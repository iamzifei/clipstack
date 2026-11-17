import AppKit
import Vision

/// On-device text recognition for image entries (⌘K → "Extract text").
///
/// Uses Apple's Vision framework, which runs entirely locally and needs no
/// permission. Recognition happens on a background queue; the completion
/// handler is delivered on the main queue.
enum OCR {
    static func recognizeText(in pngData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = recognizeSync(pngData)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func recognizeSync(_ data: Data) -> String? {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Let Vision pick the language per image, but list the ones this
        // app's users actually copy so mixed Chinese/English screenshots work.
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"]
        do {
            try VNImageRequestHandler(cgImage: cg).perform([request])
        } catch {
            NSLog("ClipStack OCR failed: \(error)")
            return nil
        }
        // Observations come back roughly top-to-bottom; keep one per line.
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
