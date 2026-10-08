import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct AttachmentTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\"/></svg>"
        let source = root.appendingPathComponent("icon.svg")
        try Data(svg.utf8).write(to: source)
        let utf16 = root.appendingPathComponent("unicode.svg")
        try svg.data(using: .utf16)!.write(to: utf16)
        let bad = root.appendingPathComponent("broken.bin")
        try Data([0, 0xFF, 0, 0xFE]).write(to: bad)
        let image = root.appendingPathComponent("blank.png")
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let batch = await AIChatAttachmentReader.read([source, utf16, image, bad])
        precondition(batch.attachments.count == 3 && batch.failures.count == 1)
        precondition(batch.attachments[0].content == svg && batch.attachments[1].content == svg)
        precondition(batch.attachments[2].imageData != nil, "An image with no text remains a valid attachment")
        let encoded = try JSONEncoder().encode(batch.attachments)
        let decoded = try JSONDecoder().decode([AIChatMessage.Attachment].self, from: encoded)
        precondition(decoded == batch.attachments)
        let message = AIChatMessage(role: .user, text: "Read", attachments: [.init(name: "unsafe\nname.svg", kind: .text, content: "```\nSVG")])
        precondition(message.modelText.contains("````") && !message.modelText.contains("unsafe\nname"))
        print("PASS attachment UTF-8/UTF-16 SVG, text-free image, explicit refusal, persistence and fencing")
    }
}
