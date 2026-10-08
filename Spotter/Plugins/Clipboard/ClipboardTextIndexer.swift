import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import Vision

@MainActor
final class ClipboardTextIndexer {
    private let store: ClipboardStore
    private let cacheURL: URL
    private var cache: [UUID: String] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private(set) var isEnabled = false

    init(store: ClipboardStore, directory: URL? = nil) {
        self.store = store
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1", isDirectory: true)
        cacheURL = base.appendingPathComponent("clipboard-text-index.json")
    }

    func start(enabled: Bool) {
        loadCache()
        store.onItemInserted = { [weak self] item in self?.index(item) }
        store.onItemRemoved = { [weak self] id in self?.remove(id) }
        store.onHistoryCleared = { [weak self] in self?.clear() }
        setEnabled(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard enabled else {
            tasks.values.forEach { $0.cancel() }
            tasks = [:]
            store.setSearchAnnotations([:])
            return
        }
        store.setSearchAnnotations(cache)
        for item in store.items where cache[item.id] == nil { index(item) }
    }

    private func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        guard cache.removeValue(forKey: id) != nil else { return }
        persistCache()
    }

    private func clear() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        cache = [:]
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func index(_ item: ClipboardItem) {
        guard isEnabled, cache[item.id] == nil, tasks[item.id] == nil,
            item.kind == .image || item.fileURLs.contains(where: Self.isIndexable)
        else { return }
        let id = item.id
        tasks[id] = Task { [weak self] in
            let text = await Task.detached(priority: .utility) { Self.recognizedText(in: item) }.value
            guard !Task.isCancelled, let self else { return }
            tasks[id] = nil
            guard isEnabled, let text, !text.isEmpty else { return }
            cache[id] = text
            store.setSearchAnnotation(text, for: id)
            persistCache()
        }
    }

    private nonisolated static func isIndexable(_ url: URL) -> Bool {
        ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tiff", "webp"].contains(url.pathExtension.lowercased())
    }

    private nonisolated static func recognizedText(in item: ClipboardItem) -> String? {
        var parts: [String] = []
        if let path = item.imagePath, let text = recognizeImage(URL(fileURLWithPath: path)) { parts.append(text) }
        for url in item.fileURLs.prefix(12) where isIndexable(url) {
            if url.pathExtension.lowercased() == "pdf" {
                if let text = recognizePDF(url) { parts.append(text) }
            } else if let text = recognizeImage(url) {
                parts.append(text)
            }
        }
        let result = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : String(result.prefix(200_000))
    }

    private nonisolated static func recognizeImage(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return recognize(image)
    }

    private nonisolated static func recognizePDF(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        if let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return String(text.prefix(200_000))
        }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, 24) {
            guard !Task.isCancelled, let page = document.page(at: index), let image = render(page) else { continue }
            if let text = recognize(image), !text.isEmpty { pages.append(text) }
        }
        return pages.isEmpty ? nil : pages.joined(separator: "\n")
    }

    private nonisolated static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 2_000 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private nonisolated static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) }
        }.sorted {
            if abs($0.box.midY - $1.box.midY) > 0.018 { return $0.box.midY > $1.box.midY }
            return $0.box.minX < $1.box.minX
        }
        return lines.map(\.text).joined(separator: "\n")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
            let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        cache = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    private func persistCache() {
        let raw = Dictionary(uniqueKeysWithValues: cache.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
