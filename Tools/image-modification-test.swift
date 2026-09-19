import Foundation
import ImageIO
import CoreGraphics

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
        precondition(ImageOperation.allCases.count == 10)
        precondition(Set(ImageOperation.allCases.map(\.rawValue)).count == 10)
        precondition(ImageFormat.jpeg.fileExtension == "jpg")
        precondition(ImageFormat.png.uniformType == "public.png")
        precondition(ImageFormat.allCases.count == 22)
        precondition(ImageFormat.avif.uniformType == "public.avif")
        precondition(ImageOutputLocation.allCases.contains(.replace))
        let request = ImageModificationRequest(operation: .rotate, angle: 45)
        precondition(request.operation == .rotate && request.angle == 45)
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

        let created = directory.appendingPathComponent("fixture.png")
        makeFixture(at: created)
        var create = ImageModificationRequest(output: .alongside, format: .png)

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
        func parse(_ query: String, _ expected: ImageCommand?) {
            precondition(ImageCommandParser.parse(query) == expected, query)
        }
        parse("Convert JPG", .convert(.jpeg))
        parse("Convert to PNG", .convert(.png))
        parse(" convert image to tif ", .convert(.tiff))
        parse("CONVERT JPEG", .convert(.jpeg))
        parse("Scale1.5", .scale(1.5))
        parse("Scale 150%", .scale(1.5))
        parse("Scale image by 2.75x", .scale(2.75))
        parse("Scale .5", .scale(0.5))
        parse("Scale 1e-7", .scale(0.0000001))
        parse("Resize 1920x1080", .resize(width: 1920, height: 1080))
        parse("Resize to 800 × 600", .resize(width: 800, height: 600))
        parse("Resize 640", .resize(width: 640, height: 640))
        parse("Optimize 80%", .optimize(0.8))
        parse("Optimize 80", .optimize(0.8))
        parse("Optimize at 0.82", .optimize(0.82))
        parse("Optimize 100%", .optimize(1))
        for invalid in ["Convert", "Scale", "Resize", "Optimize", "Pad 40", "Create Image",
                        "Convert banana", "Convert JPG trailing", "Scale 0", "Scale -1",
                        "Scale NaN", "Scale inf", "Scale 1e999", "Scale 1.5oops", "Scale 1,5",
                        "Scale1.5; rm", "Resize 0x1", "Resize 1x", "Resize 1x2x3",
                        "Resize 32769x1", "Resize 1.5x2", "Optimize 101%", "Optimize 0%",
                        "Optimize 4%", "my scale 2", String(repeating: "s", count: 257)] {
            parse(invalid, nil)
        }
        for operation in ImageCommandParser.operations {
            for preset in ImageCommandParser.presets(for: operation) {
                precondition(ImageCommandParser.parse(preset.id) == preset)
                precondition(preset.operation == operation)
            }
        }
        precondition(ImageCommandParser.parse(ImageCommand.scale(1e-7).id) == .scale(1e-7))
        precondition(ImageCommandParser.parseArgument("1.375", operation: .scale) == .scale(1.375))
        precondition(ImageCommandParser.parseArgument("TIF", operation: .convert) == .convert(.tiff))
        precondition(ImageModificationEngine.writableFormats.contains(.jpeg))
        precondition(ImageModificationEngine.writableFormats.contains(.png))

        for (factor, size) in [(1.5, CGSize(width: 96, height: 72)),
                               (0.5, CGSize(width: 32, height: 24)),
                               (2.75, CGSize(width: 176, height: 132))] {
            var scale = ImageModificationRequest()
            ImageCommandParser.parse("Scale\(factor)")!.apply(to: &scale)
            let output = try! ImageModificationEngine.process(
                request: scale, inputs: [created], temporaryDirectory: directory)[0].output
            precondition(pixelSize(output) == size)
        }
        var resize = ImageModificationRequest()
        ImageCommandParser.parse("Resize 20x20")!.apply(to: &resize)
        let fitted = try! ImageModificationEngine.process(
            request: resize, inputs: [created], temporaryDirectory: directory)[0].output
        precondition(pixelSize(fitted) == CGSize(width: 20, height: 15))

        var low = ImageModificationRequest()
        ImageCommandParser.parse("Optimize 20%")!.apply(to: &low)
        let lower = try! ImageModificationEngine.process(
            request: low, inputs: [converted], temporaryDirectory: directory)[0].output
        var high = ImageModificationRequest()
        ImageCommandParser.parse("Optimize 95%")!.apply(to: &high)
        let higher = try! ImageModificationEngine.process(
            request: high, inputs: [converted], temporaryDirectory: directory)[0].output
        precondition(try! Data(contentsOf: lower).count < Data(contentsOf: higher).count)
        precondition(pixelSize(lower) == CGSize(width: 64, height: 48))
        precondition(sourceType(lower) == ImageFormat.jpeg.uniformType)
        precondition(FileManager.default.fileExists(atPath: created.path))

        var enormous = ImageModificationRequest()
        ImageCommand.scale(1e308).apply(to: &enormous)
        do {
            _ = try ImageModificationEngine.process(request: enormous, inputs: [created], temporaryDirectory: directory)
            preconditionFailure("Unbounded output was accepted")
        } catch {}
        do {
            _ = try ImageModificationEngine.process(request: resize, inputs: [], temporaryDirectory: directory)
            preconditionFailure("Missing input was accepted")
        } catch {}
        print("Image Modification: ALL PASSED")
    }

    private static func makeFixture(at url: URL) {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<48 {
            for x in 0..<64 {
                context.setFillColor(red: CGFloat((x * 31 + y * 13) % 256) / 255,
                    green: CGFloat((x * 17 + y * 47) % 256) / 255,
                    blue: CGFloat((x * 53 + y * 7) % 256) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
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
