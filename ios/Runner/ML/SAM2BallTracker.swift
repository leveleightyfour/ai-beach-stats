import CoreMedia
import CoreML
import Foundation
import Vision

/// SAM 2-based ball tracker. Drop-in replacement for `VisionBallTracker`
/// behind the same `BallTracking` protocol.
///
/// ## Sourcing the model
///
/// Apple publishes CoreML ports of SAM 2 on Hugging Face. Tiny is the
/// only size that fits our per-frame budget on iPad (~30-80ms encoder
/// pass on Neural Engine; larger sizes balloon to 200ms+):
///
/// - https://huggingface.co/apple/coreml-sam2-tiny
/// - Download the image-encoder and mask-decoder packages.
/// - Rename to `SAM2ImageEncoder.mlpackage` and `SAM2MaskDecoder.mlpackage`
///   (or change the filenames in `loadModelsIfNeeded()` below).
/// - Drop both into `ios/Runner/Models/` and add to the Runner target
///   in Xcode (Action: Reference files in place, ✅ Runner target).
///
/// ## Implementation status (commit 1 of 2)
///
/// The class loads the model files and exposes the `BallTracking` API,
/// but `predict()` is currently a stub. The actual Hiera encoder pass,
/// prompt encoding, memory bank propagation, and mask decoding go in
/// the next commit — I need to inspect Apple's actual generated .mlpackage
/// inputs/outputs to get tensor shapes right. Until then, if the SAM 2
/// model is bundled this tracker logs and returns nil from predict
/// (effectively disabling tracking and falling back to detector-per-frame).
/// `MLPipelineCoordinator.pickBallTracker()` only selects this tracker
/// when both `.mlpackage` files are in the bundle; otherwise the
/// existing `VisionBallTracker` is used.
final class SAM2BallTracker: BallTracking {
    init(
        encoderName: String = "SAM2ImageEncoder",
        decoderName: String = "SAM2MaskDecoder",
        maxSessionFrames: Int = 60
    ) {
        self.encoderName = encoderName
        self.decoderName = decoderName
        self.maxSessionFrames = maxSessionFrames
    }

    private let encoderName: String
    private let decoderName: String
    private let maxSessionFrames: Int

    private var imageEncoder: MLModel?
    private var maskDecoder: MLModel?
    private var modelLoadAttempted = false

    private var sessionActive = false
    private var sessionFrameCount = 0
    private var lastBoundingBox: CGRect?

    var isAvailable: Bool {
        loadModelsIfNeeded()
        return imageEncoder != nil && maskDecoder != nil
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
        guard sessionActive, lastBoundingBox != nil else { return nil }
        guard imageEncoder != nil, maskDecoder != nil else {
            endSession()
            return nil
        }

        if sessionFrameCount >= maxSessionFrames {
            print("[SAM2BallTracker] session capped at \(maxSessionFrames) frames; ending")
            endSession()
            return nil
        }

        // TODO(commit 2): orchestrate the SAM 2 inference chain:
        //
        //   1. Run image encoder on `frame.pixelBuffer` to produce
        //      multi-scale Hiera feature maps (size depends on encoder
        //      variant — usually 256×256 features at multiple scales).
        //   2. Construct the prompt embedding from `lastBoundingBox`
        //      (point prompt at bbox centre is the simplest workable
        //      choice; box prompt is more accurate but requires the
        //      box-prompt input pipeline in the .mlpackage).
        //   3. Optionally apply memory attention from the prior frame's
        //      decoded features (the temporal-tracking part). Skipping
        //      this for a first pass would still give us a per-frame
        //      "find the ball near here" — already better than Vision's
        //      correlation drift.
        //   4. Run mask decoder to produce a segmentation mask.
        //   5. Compute bbox = bounding box of mask above some
        //      confidence threshold. Reject if mask is empty or area is
        //      out of plausible-ball-size range.
        //   6. Update `lastBoundingBox`, increment `sessionFrameCount`,
        //      return BallDetection.

        print("[SAM2BallTracker] predict() not yet implemented; ending session at frame \(frame.frameIndex)")
        endSession()
        return nil
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
        if imageEncoder != nil && maskDecoder != nil { return }
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

        guard let encoderURL = find(encoderName) else {
            print("[SAM2BallTracker] '\(encoderName)' not bundled — disabled.")
            return
        }
        guard let decoderURL = find(decoderName) else {
            print("[SAM2BallTracker] '\(decoderName)' not bundled — disabled.")
            return
        }

        do {
            imageEncoder = try MLModel(contentsOf: encoderURL)
            maskDecoder = try MLModel(contentsOf: decoderURL)
            print("[SAM2BallTracker] models loaded; ready (predict still stubbed)")
        } catch {
            print("[SAM2BallTracker] model load failed: \(error)")
            imageEncoder = nil
            maskDecoder = nil
        }
    }
}
