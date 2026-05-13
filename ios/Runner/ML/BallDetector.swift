import CoreML
import CoreMedia
import Foundation
import Vision

/// Runs the ball-detection model against a single frame, returning at most
/// one best-confidence detection.
///
/// Implementation choice: we call CoreML directly via `VNCoreMLRequest`
/// rather than using the `ultralytics_yolo` Flutter plugin. The plugin
/// would invoke detection from Dart over its own platform channels, which
/// would bypass `PipelineRunner` and split orchestration across two
/// boundaries. Keeping detection in Swift lets the runner own the entire
/// per-frame flow.
///
/// Model bundling: place a YOLO11n .mlpackage (exported from Apple's model
/// gallery or via ultralytics) at `ios/Runner/Models/YOLO11n.mlpackage`
/// and add it to the Runner target in Xcode. Xcode will compile it to
/// `.mlmodelc` at build time and bundle it. If the model is missing the
/// detector logs and returns nil for every frame — the rest of the
/// pipeline continues to run.
protocol BallDetecting {
    func detect(in frame: PipelineFrame) async throws -> BallDetection?
}

final class BallDetector: BallDetecting {
    init(
        confidenceThreshold: Double,
        modelName: String = "YOLO11n",
        targetLabel: String = "sports ball"
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.modelName = modelName
        self.targetLabel = targetLabel
    }

    private let confidenceThreshold: Double
    private let modelName: String
    private let targetLabel: String

    private var visionModel: VNCoreMLModel?
    private var modelLoadAttempted = false

    func detect(in frame: PipelineFrame) async throws -> BallDetection? {
        guard let visionModel = loadModelIfNeeded() else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let detection = Self.bestDetection(
                    in: request.results,
                    frame: frame,
                    targetLabel: self.targetLabel,
                    confidenceThreshold: self.confidenceThreshold
                )
                continuation.resume(returning: detection)
            }
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(
                cvPixelBuffer: frame.pixelBuffer,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func loadModelIfNeeded() -> VNCoreMLModel? {
        if let visionModel { return visionModel }
        if modelLoadAttempted { return nil }
        modelLoadAttempted = true

        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        var modelURL: URL?
        for ext in extensions {
            if let url = Bundle.main.url(forResource: modelName, withExtension: ext) {
                modelURL = url
                break
            }
        }
        guard let url = modelURL else {
            NSLog("BallDetector: model '%@' not bundled — detection disabled.", modelName)
            return nil
        }

        do {
            let mlModel = try MLModel(contentsOf: url)
            let model = try VNCoreMLModel(for: mlModel)
            visionModel = model
            return model
        } catch {
            NSLog(
                "BallDetector: failed to load '%@': %@",
                modelName,
                String(describing: error)
            )
            return nil
        }
    }

    private static func bestDetection(
        in results: [Any]?,
        frame: PipelineFrame,
        targetLabel: String,
        confidenceThreshold: Double
    ) -> BallDetection? {
        guard let observations = results as? [VNRecognizedObjectObservation] else {
            return nil
        }

        let candidates = observations.filter { observation in
            guard let label = observation.labels.first?.identifier else { return false }
            return label.caseInsensitiveCompare(targetLabel) == .orderedSame
                && Double(observation.confidence) >= confidenceThreshold
        }
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        let width = CGFloat(CVPixelBufferGetWidth(frame.pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(frame.pixelBuffer))
        let bbox = best.boundingBox
        // Vision normalises with origin at bottom-left; flip to top-left
        // image coords for downstream consumers (touch attribution, UI overlay).
        let originX = bbox.origin.x * width
        let originY = (1.0 - bbox.origin.y - bbox.size.height) * height
        let boundingBox = CGRect(
            x: originX,
            y: originY,
            width: bbox.size.width * width,
            height: bbox.size.height * height
        )

        let timestampMs = Int(
            CMTimeGetSeconds(frame.presentationTime) * 1000
        )
        return BallDetection(
            frameIndex: frame.frameIndex,
            timestampMs: timestampMs,
            boundingBox: boundingBox,
            confidence: Double(best.confidence)
        )
    }
}
