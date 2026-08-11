import Foundation
import ImageIO

private final class ImageProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Int, Int, String)] = []

    func append(_ value: (Int, Int, String)) {
        lock.withLock { values.append(value) }
    }

    var snapshots: [(Int, Int, String)] { lock.withLock { values } }
}

@main
struct ImageModificationTests {
    static func main() {
        precondition(ImageOperation.allCases.count == 12)
        precondition(Set(ImageOperation.allCases.map(\.rawValue)).count == 12)
        precondition(ImageFormat.jpeg.fileExtension == "jpg")
        precondition(ImageFormat.png.uniformType == "public.png")
        precondition(ImageFormat.allCases.count == 22)
        precondition(ImageFormat.avif.uniformType == "public.avif")
        precondition(ImageOutputLocation.allCases.contains(.replace))
        let request = ImageModificationRequest(operation: .rotate, angle: 45)
        precondition(request.operation == .rotate && request.angle == 45)
        precondition(ImageModificationRequest.commandDefaults(
            operation: .create, output: .alongside, format: .png,
            hasPersistentInput: false).output == .preview)
        precondition(ImageModificationRequest.commandDefaults(
            operation: .resize, output: .alongside, format: .png,
            hasPersistentInput: false).output == .clipboard)
        precondition(ImageModificationRequest.commandDefaults(
            operation: .resize, output: .alongside, format: .png,
            hasPersistentInput: true).output == .alongside)
        precondition(ImageModificationRequest.commandDefaults(
            operation: .convert, output: .alongside, format: .avif,
            hasPersistentInput: true).format == .avif)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-image-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var create = ImageModificationRequest(
            operation: .create, output: .alongside, format: .png, width: 64, height: 48,
            colorHex: "#FF0000", secondColorHex: "#0000FF")
        let created = try! ImageModificationEngine.process(
            request: create, inputs: [], temporaryDirectory: directory)[0].output
        precondition(pixelSize(created) == CGSize(width: 64, height: 48))
        for generator in ImageGenerator.allCases {
            create.generator = generator
            let generated = try! ImageModificationEngine.process(
                request: create, inputs: [], temporaryDirectory: directory)[0].output
            precondition(pixelSize(generated) == CGSize(width: 64, height: 48))
        }

        precondition(ImageFilterCatalog.available.count > 20)
        precondition(ImageFilterCatalog.available.contains { $0.name == "CIPhotoEffectChrome" })

        create.operation = .resize
        create.width = 32
        create.height = 32
        create.preserveAspect = true
        let resized = try! ImageModificationEngine.process(
            request: create, inputs: [created], temporaryDirectory: directory)[0].output
        precondition(pixelSize(resized) == CGSize(width: 32, height: 24))

        create.operation = .convert
        create.format = .jpeg
        let progress = ImageProgressRecorder()
        let converted = try! ImageModificationEngine.process(
            request: create, inputs: [created], temporaryDirectory: directory
        ) { completed, total, input in
            progress.append((completed, total, input?.lastPathComponent ?? ""))
        }[0].output
        precondition(converted.pathExtension == ImageFormat.jpeg.fileExtension)
        precondition(sourceType(converted) == ImageFormat.jpeg.uniformType)
        let snapshots = progress.snapshots
        precondition(snapshots.count == 1)
        precondition(snapshots[0].0 == 1 && snapshots[0].1 == 1)
        precondition(snapshots[0].2 == created.lastPathComponent)
        print("Image Modification: ALL PASSED")
    }

    private static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func sourceType(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }
}
