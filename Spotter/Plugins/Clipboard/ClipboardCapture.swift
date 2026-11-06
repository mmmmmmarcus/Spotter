import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ClipboardCapture {
    static let internalType = NSPasteboard.PasteboardType("com.spotter.internal")
    static let maxTextLength = 32_000
    static let filePreviewMaxPixel = 1024
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive"),
    ]

    enum Payload: Sendable {
        case image(Data)
        case text(String)
        case files([URL], preview: Data?)
    }

    struct Snapshot: Sendable {
        let images: [Data]
        let imageFile: URL?
        let text: String?
        var fileURLs: [URL] = []

        func resolve() -> Payload? {
            if let imageFile, let data = try? Data(contentsOf: imageFile),
               let png = ClipboardCapture.png(data: data) { return .image(png) }
            // An image file Spotter cannot read (a privacy-protected folder, Universal Clipboard's container) keeps the pasteboard's own preview, so the row never depends on a later grant.
            if !fileURLs.isEmpty {
                return .files(fileURLs, preview: imageFile == nil ? nil : images.lazy.compactMap(ClipboardCapture.preview).first)
            }
            for data in images {
                if let png = ClipboardCapture.png(data: data) { return .image(png) }
            }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= ClipboardCapture.maxTextLength else { return nil }
            return .text(text)
        }
    }

    @MainActor
    static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot? {
        let change = pasteboard.changeCount
        let types = pasteboard.types ?? []
        guard !types.contains(internalType), Set(types).isDisjoint(with: sensitiveTypes) else { return nil }
        let supported = Set(CGImageSourceCopyTypeIdentifiers() as! [String])
        let others = types.filter { supported.contains($0.rawValue) && $0 != .png && $0 != .tiff }
        let imageTypes = ([NSPasteboard.PasteboardType.png, .tiff] + others).filter { types.contains($0) }
        let images = imageTypes.compactMap { pasteboard.data(forType: $0) }
        var urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty, let paths = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            urls = paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        }
        urls = urls.filter { $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") }
        let imageFile = urls.count == 1 && UTType(filenameExtension: urls[0].pathExtension)?.conforms(to: .image) == true ? urls[0] : nil
        let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
        // A promised representation can replace the pasteboard while being requested; never combine different copies.
        guard pasteboard.changeCount == change else { return nil }
        return Snapshot(images: images, imageFile: imageFile, text: text, fileURLs: urls)
    }

    @MainActor
    static func writeFiles(_ urls: [URL], to pasteboard: NSPasteboard) -> Bool {
        guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
            && FileManager.default.fileExists(atPath: $0.path) }) else { return false }
        let entries = urls.map { url in
            let entry = NSPasteboardItem()
            entry.setString(url.absoluteString, forType: .fileURL)
            entry.setData(Data(), forType: internalType)
            return entry
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(entries)
    }

    // The largest representation wins: icon families list their smallest size first.
    private static func preview(data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let index = (0..<CGImageSourceGetCount(source)).max { pixelWidth(source, $0) < pixelWidth(source, $1) } ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: filePreviewMaxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        return encodePNG(image)
    }

    private static func pixelWidth(_ source: CGImageSource, _ index: Int) -> Int {
        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func png(data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        if CGImageSourceGetType(source) as String? == UTType.png.identifier { return data }
        return encodePNG(image)
    }
}
