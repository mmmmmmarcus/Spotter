import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
@MainActor
struct ClipboardCaptureTests {
    static var passed = 0
    static var failed = 0

    static func check(_ condition: Bool, _ message: String) {
        if condition { passed += 1 } else { failed += 1; print("FAIL: \(message)") }
    }

    static func main() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let tiff = bitmap.representation(using: .tiff, properties: [:])!
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!

        func set(_ values: [(NSPasteboard.PasteboardType, Data)]) {
            board.clearContents()
            board.declareTypes(values.map(\.0), owner: nil)
            for (type, data) in values { board.setData(data, forType: type) }
        }
        func capture() async -> ClipboardCapture.Payload? {
            guard let snapshot = ClipboardCapture.snapshot(board) else { return nil }
            return await Task.detached { snapshot.resolve() }.value
        }
        func isImage(_ payload: ClipboardCapture.Payload?) -> Bool {
            guard case .image(let data) = payload,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
            return CGImageSourceGetType(source) as String? == UTType.png.identifier
        }
        func isText(_ payload: ClipboardCapture.Payload?, _ expected: String) -> Bool {
            if case .text(let text) = payload { return text == expected }
            return false
        }
        let label = Data("image.png".utf8)
        set([(.string, label), (.png, png)])
        check(isImage(await capture()), "PNG wins over a simultaneously advertised filename")
        set([(.tiff, tiff), (.string, label)])
        check(isImage(await capture()), "TIFF plus text resolves to PNG image data")
        set([(.string, label), (.init(UTType.jpeg.identifier), jpeg)])
        check(isImage(await capture()), "JPEG-only image representation is supported")
        set([(.png, Data("broken".utf8)), (.tiff, tiff), (.string, label)])
        check(isImage(await capture()), "invalid preferred representation falls back to a valid image")
        set([(.png, Data("broken".utf8)), (.string, label)])
        check(isText(await capture(), "image.png"), "undecodable image keeps the available text fallback")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("copied-photo.jpg")
        try jpeg.write(to: file)
        set([(.fileURL, Data(file.absoluteString.utf8)), (.string, label)])
        check(isImage(await capture()), "Finder-style single image file URL is captured as pixels")
        set([(.fileURL, Data(file.absoluteString.utf8)), (.png, Data("invalid preview".utf8)), (.string, label)])
        check(isImage(await capture()), "the copied image file wins over a Finder preview")
        set([(.fileURL, Data(folder.appendingPathComponent("gone.png").absoluteString.utf8)), (.string, label)])
        check(isText(await capture(), "image.png"), "missing files retain safe text fallback")
        set([(.URL, Data("https://example.com/image.png".utf8))])
        check(isText(await capture(), "https://example.com/image.png"), "copying an image URL stays a link and makes no network request")
        for value in ["plain text", "https://example.com", "123.45", "你好 👋"] {
            set([(.string, Data(value.utf8))])
            check(isText(await capture(), value), "ordinary text payload remains intact")
        }
        set([(.string, Data(String(repeating: "x", count: ClipboardCapture.maxTextLength + 1).utf8))])
        check(await capture() == nil, "oversized text is skipped without truncating")
        set([(.string, Data(" \n ".utf8))])
        check(await capture() == nil, "empty text is skipped")
        for marker in ClipboardCapture.sensitiveTypes.union([ClipboardCapture.internalType]) {
            set([(.png, png), (.string, label), (marker, Data())])
            check(ClipboardCapture.snapshot(board) == nil, "secret and internal markers exclude images as well as text")
        }
        set([(.png, png), (.string, label)])
        let snapshot = ClipboardCapture.snapshot(board)!
        set([(.string, Data("next copy".utf8))])
        let resolved = await Task.detached { snapshot.resolve() }.value
        check(isImage(resolved), "background resolution uses captured bytes, never a later pasteboard")
        print("\(passed)/\(passed + failed) passed")
        if failed > 0 { exit(1) }
    }
}
