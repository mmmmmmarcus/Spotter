import CoreGraphics
import Vision

/// Reads text out of captured pixels with Vision. On-device and offline: no network, no new
/// permission — it sees exactly the pixels the existing Screen Recording grant already covers.
enum ScreenshotTextRecognizer {
    /// `nonisolated` and taking only a `CGImage`, so the caller can run it off the main actor and
    /// get back a plain `String`.
    nonisolated static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Chinese must lead: auto-detection and an English-first list both misread the Chinese in mixed lines ("你好世界" → "1547Ш").
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let fragments = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map {
                ScreenshotTextLayout.Fragment(string: $0.string, box: observation.boundingBox)
            }
        }
        return ScreenshotTextLayout.text(from: fragments)
    }
}
