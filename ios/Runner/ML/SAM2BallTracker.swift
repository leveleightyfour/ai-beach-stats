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
        guard sessionActive, lastBoundingBox != nil else { return nil }
        guard imageEncoder != nil,
              promptEncoder != nil,
              maskDecoder != nil
        else {
            endSession()
            return nil
        }

        if sessionFrameCount >= maxSessionFrames {
            print("[SAM2BallTracker] session capped at \(maxSessionFrames) frames; ending")
            endSession()
            return nil
        }

        // TODO(commit 2): orchestrate the inference chain:
        //
        //   1. Image encoder: feed frame.pixelBuffer (resized/normalised
        //      to the encoder's expected input — typically 1024x1024)
        //      and read the feature-map outputs.
        //   2. Prompt encoder: feed the centre of lastBoundingBox as a
        //      point prompt (or the bbox itself as a box prompt — TBD
        //      once we see the prompt-encoder input schema).
        //   3. Mask decoder: combine encoder features + prompt
        //      embeddings, read mask + score.
        //   4. If score below threshold or mask empty/improbably-sized,
        //      end session and return nil.
        //   5. Else compute bbox of mask, update lastBoundingBox,
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

        do {
            let encoder = try MLModel(contentsOf: encURL)
            let prompter = try MLModel(contentsOf: promptURL)
            let decoder = try MLModel(contentsOf: decURL)
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
