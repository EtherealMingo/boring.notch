//
//  OCRService.swift
//  boringNotch
//
//  Toolbox: recognize text on images with Apple Vision.
//

import AppKit
import Vision

enum OCRService {
    /// Recognize text on the given image. Runs on a background queue.
    static func recognizeText(
        in image: NSImage,
        languages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"],
        completion: @escaping (String) -> Void
    ) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion("")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                DispatchQueue.main.async { completion(text) }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("OCR failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion("") }
            }
        }
    }
}
