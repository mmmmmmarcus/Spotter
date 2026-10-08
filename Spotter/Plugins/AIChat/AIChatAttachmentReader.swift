import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

enum AIChatAttachmentReader {
    private static let totalCharacterLimit = 120_000
    private static let attachmentCharacterLimit = 60_000

    static func read(_ urls: [URL]) async -> [AIChatMessage.Attachment] {
        await Task.detached(priority: .userInitiated) {
            var remaining = totalCharacterLimit
            var attachments: [AIChatMessage.Attachment] = []
            for url in urls.prefix(10) where remaining > 0 {
                guard let attachment = readOne(url, characterLimit: min(attachmentCharacterLimit, remaining)) else { continue }
                attachments.append(attachment)
                remaining -= attachment.content.count
            }
            return attachments
        }.value
    }

    private nonisolated static func readOne(_ url: URL, characterLimit: Int) -> AIChatMessage.Attachment? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), size <= 32 * 1024 * 1024 else {
            return nil
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            var text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                text = (0..<min(document.pageCount, 12)).compactMap { index -> String? in
                    guard let page = document.page(at: index), let image = render(page) else { return nil }
                    return recognize(image)
                }.joined(separator: "\n")
            }
            guard !text.isEmpty else { return nil }
            return .init(name: url.lastPathComponent, kind: .pdf, content: String(text.prefix(characterLimit)))
        }
        if ["png", "jpg", "jpeg", "heic", "heif", "tiff", "webp"].contains(ext) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                let text = recognize(image), !text.isEmpty else { return nil }
            return .init(name: url.lastPathComponent, kind: .image, content: String(text.prefix(characterLimit)))
        }
        guard let data = try? Data(contentsOf: url), data.count <= 2 * 1024 * 1024,
            let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return .init(name: url.lastPathComponent, kind: .text, content: String(text.prefix(characterLimit)))
    }

    private nonisolated static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private nonisolated static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 2_000 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width,
            height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
