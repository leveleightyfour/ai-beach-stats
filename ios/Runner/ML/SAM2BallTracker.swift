import CoreImage
import CoreMedia
import CoreML
import Foundation

/// SAM 2-based ball tracker. Drop-in replacement for `VisionBallTracker`
/// behind the `BallTracking` protocol.
///
/// ## Architecture
///
/// SAM 2 inference is a 3-stage chain (same shape across Apple's
/// published CoreML port and the upstream Meta models):
///
///   1. **Image encoder** — runs once per frame on the source image,
///      produces multi-scale Hiera feature maps. Most of the per-frame
///      cost lives here.
///   2. **Prompt encoder** — encodes the box/point/mask prompt for
///      *what to segment*. Cheap.
///   3. **Mask decoder** — combines image features + prompt embedding
///      to produce a segmentation mask.
///
/// For our pipeline we prompt with the previous frame's bbox centre
/// (point prompt). The first commit of this class is structural only —
/// `predict()` is a stub that logs and returns nil. The next commit
/// wires the real inference once we've seen the actual model
/// input/output tensor shapes (logged on first model load — see
/// `describeModel`).
///
/// ## Sourcing the models
///
/// Apple publishes CoreML ports of SAM 2.1 on Hugging Face. Current
/// defaults are the Tiny FLOAT16 variant filenames:
///
///   - `SAM2_1TinyImageEncoderFLOAT16.mlpackage`
///   - `SAM2_1TinyPromptEncoderFLOAT16.mlpackage`
///   - `SAM2_1TinyMaskDecoderFLOAT16.mlpackage`
///
/// Drop all three into `ios/Runner/Models/` and add each to the Runner
/// target in Xcode (Action: Reference files in place, ✅ Runner target).
/// To use Small / Base+ / Large variants, change the names passed to
/// `init` (or rename the files to match the defaults).
///
/// Performance heads-up: Tiny image encoder runs at ~30-80ms per frame
/// on iPad M4, so the 145s test clip at 15Hz sampling = ~2,400 frames =
/// ~1-2 minutes processing. Larger variants ramp to 10× that.
final class SAM2BallTracker: BallTracking {
    init(
        imageEncoderName: String = "SAM2_1TinyImageEncoderFLOAT16",
        promptEncoderName: String = "SAM2_1TinyPromptEncoderFLOAT16",
        maskDecoderName: String = "SAM2_1TinyMaskDecoderFLOAT16",
        maxSessionFrames: Int = 60
    ) {
        self.imageEncoderName = imageEncoderName
        self.promptEncoderName = promptEncoderName
        self.maskDecoderName = maskDecoderName
        self.maxSessionFrames = maxSessionFrames
    }

    private let imageEncoderName: String
    private let promptEncoderName: String
    private let maskDecoderName: String
    private let maxSessionFrames: Int

    private var imageEncoder: MLModel?
    private var promptEncoder: MLModel?
    private var maskDecoder: MLModel?
    private var modelLoadAttempted = false

    private var sessionActive = false
    private var sessionFrameCount = 0
    private var lastBoundingBox: CGRect?
    private let ciContext = CIContext()

    private static let inputSide = 1024
    private static let maskSide = 256
    private static let minScore: Float = 0.5
    private static let minBboxSide: CGFloat = 5
    private static let maxBboxSide: CGFloat = 200

    var isAvailable: Bool {
        loadModelsIfNeeded()
        return imageEncoder != nil
            && promptEncoder != nil
            && maskDecoder != nil
    }

    var isSessionActive: Bool { sessionActive }

    func startSession(
        initialFrame: PipelineFrame,
        initialDetection: BallDetection
    ) {
        guard isAvailable else { return }
        lastBoundingBox = initialDetection.boundingBox
        sessionActive = true
        sessionFrameCount = 0
        print("[SAM2BallTracker] session started anchorFrame=\(initialFrame.frameIndex)")
    }

    func predict(in frame: PipelineFrame) async throws -> BallDetection? {
        guard sessionActive, let lastBbox = lastBoundingBox else { return nil }
        guard let encoder = imageEncoder,
              let prompter = promptEncoder,
              let decoder = maskDecoder
        else {
            endSession()
            return nil
        }

        if sessionFrameCount >= maxSessionFrames {
            print("[SAM2BallTracker] session capped at \(maxSessionFrames) frames; ending")
            endSession()
            return nil
        }

        do {
            // --- 1. Letterbox source frame to 1024x1024 ---
            let srcW = CGFloat(CVPixelBufferGetWidth(frame.pixelBuffer))
            let srcH = CGFloat(CVPixelBufferGetHeight(frame.pixelBuffer))
            let side = CGFloat(Self.inputSide)
            let scale = side / max(srcW, srcH)
            let scaledW = srcW * scale
            let scaledH = srcH * scale
            let padX = (side - scaledW) / 2
            let padY = (side - scaledH) / 2

            guard let resized = letterboxToSquare(
                source: frame.pixelBuffer,
                scale: scale,
                padX: padX,
                padY: padY
            ) else {
                endSession()
                return nil
            }

            // --- 2. Image encoder ---
            let encOut = try await encoder.prediction(
                from: try MLDictionaryFeatureProvider(dictionary: [
                    "image": MLFeatureValue(pixelBuffer: resized),
                ])
            )
            guard
                let imgEmbed = encOut.featureValue(for: "image_embedding")?.multiArrayValue,
                let featsS0 = encOut.featureValue(for: "feats_s0")?.multiArrayValue,
                let featsS1 = encOut.featureValue(for: "feats_s1")?.multiArrayValue
            else {
                endSession()
                return nil
            }

            // --- 3. Prompt encoder: bbox centre as positive point ---
            // Apple's port takes point coordinates in pixel space of the
            // 1024x1024 input (not normalised). Map the prior bbox centre
            // from source pixels into that space via the letterbox transform.
            let inputX = Float(lastBbox.midX * scale + padX)
            let inputY = Float(lastBbox.midY * scale + padY)

            let points = try MLMultiArray(shape: [1, 1, 2], dataType: .float16)
            points[[0, 0, 0] as [NSNumber]] = NSNumber(value: inputX)
            points[[0, 0, 1] as [NSNumber]] = NSNumber(value: inputY)
            let labels = try MLMultiArray(shape: [1, 1], dataType: .float16)
            labels[[0, 0] as [NSNumber]] = NSNumber(value: Float(1))

            let promptOut = try await prompter.prediction(
                from: try MLDictionaryFeatureProvider(dictionary: [
                    "points": MLFeatureValue(multiArray: points),
                    "labels": MLFeatureValue(multiArray: labels),
                ])
            )
            guard
                let sparse = promptOut.featureValue(for: "sparse_embeddings")?.multiArrayValue,
                let dense = promptOut.featureValue(for: "dense_embeddings")?.multiArrayValue
            else {
                endSession()
                return nil
            }

            // --- 4. Mask decoder ---
            let decOut = try await decoder.prediction(
                from: try MLDictionaryFeatureProvider(dictionary: [
                    "feats_s0": MLFeatureValue(multiArray: featsS0),
                    "feats_s1": MLFeatureValue(multiArray: featsS1),
                    "image_embedding": MLFeatureValue(multiArray: imgEmbed),
                    "sparse_embedding": MLFeatureValue(multiArray: sparse),
                    "dense_embedding": MLFeatureValue(multiArray: dense),
                ])
            )
            guard
                let masks = decOut.featureValue(for: "low_res_masks")?.multiArrayValue,
                let scores = decOut.featureValue(for: "scores")?.multiArrayValue
            else {
                endSession()
                return nil
            }

            // --- 5. Pick best mask candidate ---
            var bestScore: Float = -.infinity
            var bestIdx = 0
            for i in 0..<3 {
                let s = scores[[0, i] as [NSNumber]].floatValue
                if s > bestScore {
                    bestScore = s
                    bestIdx = i
                }
            }
            if bestScore < Self.minScore {
                if sessionFrameCount == 0 {
                    print("[SAM2BallTracker] no confident mask (score=\(bestScore)) on first predict; ending")
                }
                endSession()
                return nil
            }

            // --- 6. Bbox of the selected mask (logits > 0 = foreground) ---
            var minX = Int.max
            var minY = Int.max
            var maxX = -1
            var maxY = -1
            var pixelCount = 0
            for my in 0..<Self.maskSide {
                for mx in 0..<Self.maskSide {
                    let val = masks[[0, bestIdx, my, mx] as [NSNumber]].floatValue
                    if val > 0 {
                        if mx < minX { minX = mx }
                        if my < minY { minY = my }
                        if mx > maxX { maxX = mx }
                        if my > maxY { maxY = my }
                        pixelCount += 1
                    }
                }
            }
            guard pixelCount > 0 else {
                endSession()
                return nil
            }

            // --- 7. Mask coords (256x256) -> 1024 input space -> source pixels ---
            let maskScale = side / CGFloat(Self.maskSide)
            let x1Src = (CGFloat(minX) * maskScale - padX) / scale
            let y1Src = (CGFloat(minY) * maskScale - padY) / scale
            let x2Src = (CGFloat(maxX + 1) * maskScale - padX) / scale
            let y2Src = (CGFloat(maxY + 1) * maskScale - padY) / scale
            let newBbox = CGRect(
                x: x1Src,
                y: y1Src,
                width: x2Src - x1Src,
                height: y2Src - y1Src
            )

            // --- 8. Plausibility checks ---
            if newBbox.width < Self.minBboxSide
                || newBbox.height < Self.minBboxSide
                || newBbox.width > Self.maxBboxSide
                || newBbox.height > Self.maxBboxSide
            {
                endSession()
                return nil
            }

            lastBoundingBox = newBbox
            sessionFrameCount += 1

            let timestampMs = Int(
                CMTimeGetSeconds(frame.presentationTime) * 1000
            )
            return BallDetection(
                frameIndex: frame.frameIndex,
                timestampMs: timestampMs,
                boundingBox: newBbox,
                confidence: Double(bestScore)
            )
        } catch {
            print("[SAM2BallTracker] inference error at frame \(frame.frameIndex): \(error)")
            endSession()
            return nil
        }
    }

    /// Scale + letterbox the source pixel buffer to a 1024x1024 BGRA buffer
    /// suitable as input to the SAM 2 image encoder.
    private func letterboxToSquare(
        source: CVPixelBuffer,
        scale: CGFloat,
        padX: CGFloat,
        padY: CGFloat
    ) -> CVPixelBuffer? {
        let side = Self.inputSide
        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            side,
            side,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let dest = output else { return nil }

        var image = CIImage(cvPixelBuffer: source)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))
        let canvas = CIImage(color: .black)
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        image = image.composited(over: canvas)
        ciContext.render(image, to: dest)
        return dest
    }

    func endSession() {
        if sessionActive {
            print("[SAM2BallTracker] session ended after \(sessionFrameCount) frames")
        }
        sessionActive = false
        sessionFrameCount = 0
        lastBoundingBox = nil
    }

    private func loadModelsIfNeeded() {
        if imageEncoder != nil && promptEncoder != nil && maskDecoder != nil {
            return
        }
        if modelLoadAttempted { return }
        modelLoadAttempted = true

        let candidateExtensions = ["mlmodelc", "mlpackage", "mlmodel"]

        func find(_ name: String) -> URL? {
            for ext in candidateExtensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
            return nil
        }

        guard let encURL = find(imageEncoderName) else {
            print("[SAM2BallTracker] '\(imageEncoderName)' not bundled — disabled.")
            return
        }
        guard let promptURL = find(promptEncoderName) else {
            print("[SAM2BallTracker] '\(promptEncoderName)' not bundled — disabled.")
            return
        }
        guard let decURL = find(maskDecoderName) else {
            print("[SAM2BallTracker] '\(maskDecoderName)' not bundled — disabled.")
            return
        }

        print("[SAM2BallTracker] resolved bundle URLs:")
        print("  encoder: \(encURL.lastPathComponent)")
        print("  prompt : \(promptURL.lastPathComponent)")
        print("  decoder: \(decURL.lastPathComponent)")
        print("[SAM2BallTracker] loading models (first run may take a minute for ANE compilation)…")

        do {
            let t0 = Date()
            print("[SAM2BallTracker] loading image encoder…")
            let encoder = try MLModel(contentsOf: encURL)
            print("[SAM2BallTracker] image encoder loaded in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")

            let t1 = Date()
            print("[SAM2BallTracker] loading prompt encoder…")
            let prompter = try MLModel(contentsOf: promptURL)
            print("[SAM2BallTracker] prompt encoder loaded in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")

            let t2 = Date()
            print("[SAM2BallTracker] loading mask decoder…")
            let decoder = try MLModel(contentsOf: decURL)
            print("[SAM2BallTracker] mask decoder loaded in \(String(format: "%.1f", Date().timeIntervalSince(t2)))s")

            imageEncoder = encoder
            promptEncoder = prompter
            maskDecoder = decoder
            print("[SAM2BallTracker] all three models loaded; ready (predict still stubbed)")
            Self.describeModel(encoder, label: "ImageEncoder")
            Self.describeModel(prompter, label: "PromptEncoder")
            Self.describeModel(decoder, label: "MaskDecoder")
        } catch {
            print("[SAM2BallTracker] model load failed: \(error)")
            imageEncoder = nil
            promptEncoder = nil
            maskDecoder = nil
        }
    }

    /// Logs the input + output names, types, and (where available)
    /// tensor shapes for a freshly-loaded MLModel. Used once on first
    /// load so we can see Apple's actual generated tensor schema
    /// before wiring inference in commit 2.
    private static func describeModel(_ model: MLModel, label: String) {
        let desc = model.modelDescription
        print("[SAM2BallTracker] --- \(label) inputs ---")
        for (key, feature) in desc.inputDescriptionsByName {
            print("  - \(key): \(describe(feature))")
        }
        print("[SAM2BallTracker] --- \(label) outputs ---")
        for (key, feature) in desc.outputDescriptionsByName {
            print("  - \(key): \(describe(feature))")
        }
    }

    private static func describe(_ feature: MLFeatureDescription) -> String {
        var parts: [String] = ["type=\(feature.type.rawValue)"]
        if let mac = feature.multiArrayConstraint {
            let shape = mac.shape.map(\.intValue)
            parts.append("shape=\(shape)")
            parts.append("dataType=\(mac.dataType.rawValue)")
        }
        if let ic = feature.imageConstraint {
            parts.append("image=\(ic.pixelsWide)x\(ic.pixelsHigh)")
        }
        return parts.joined(separator: " ")
    }
}
