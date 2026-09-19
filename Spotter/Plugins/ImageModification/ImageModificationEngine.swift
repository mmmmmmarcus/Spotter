import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

enum ImageModificationEngine {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static let writableFormats: [ImageFormat] = {
        let identifiers = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
        return ImageFormat.allCases.filter { identifiers.contains($0.uniformType) }
    }()

    static func process(
        request: ImageModificationRequest, inputs: [URL], temporaryDirectory: URL,
        progress: (@Sendable (_ completed: Int, _ total: Int, _ input: URL?) -> Void)? = nil
    ) throws -> [ImageModificationResult] {
        guard !inputs.isEmpty else { throw ImageModificationFailure.noInput }
        var results: [ImageModificationResult] = []
        results.reserveCapacity(inputs.count)
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            guard let image = read(input) else {
                throw ImageModificationFailure.cannotRead(input.lastPathComponent)
            }
            let outputImage = try modify(image, request: request)
            let destination = destinationURL(request: request, input: input, temporaryDirectory: temporaryDirectory)
            let format = request.operation == .convert ? request.format : inferredFormat(from: input)
            if request.output == .replace, destination == input {
                let temporary = temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
                try write(outputImage, to: temporary, format: format, quality: request.quality)
                _ = try FileManager.default.replaceItemAt(input, withItemAt: temporary)
            } else {
                try write(outputImage, to: destination, format: format, quality: request.quality)
                if request.output == .replace { try FileManager.default.removeItem(at: input) }
            }
            results.append(ImageModificationResult(input: input, output: destination))
            progress?(index + 1, inputs.count, input)
        }
        return results
    }

    private static func read(_ url: URL) -> CIImage? {
        if let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
            return image
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    private static func modify(_ image: CIImage, request: ImageModificationRequest) throws -> CIImage {
        switch request.operation {
        case .filter:
            guard let filter = CIFilter(name: request.filterName) else { return image }
            filter.setValue(image, forKey: kCIInputImageKey)
            return filter.outputImage ?? image
        case .flipHorizontal:
            return transformed(image, CGAffineTransform(translationX: image.extent.width, y: 0).scaledBy(x: -1, y: 1))
        case .flipVertical:
            return transformed(image, CGAffineTransform(translationX: 0, y: image.extent.height).scaledBy(x: 1, y: -1))
        case .resize:
            let x = CGFloat(max(request.width, 1)) / image.extent.width
            let y = CGFloat(max(request.height, 1)) / image.extent.height
            let scaleX = request.preserveAspect ? min(x, y) : x
            let scaleY = request.preserveAspect ? min(x, y) : y
            return transformed(image, CGAffineTransform(scaleX: scaleX, y: scaleY))
        case .scale:
            let value = CGFloat(request.scale)
            try validateSize(width: image.extent.width * value, height: image.extent.height * value)
            return transformed(image, CGAffineTransform(scaleX: value, y: value))
        case .rotate:
            let radians = CGFloat(request.angle * .pi / 180)
            return transformed(image, CGAffineTransform(rotationAngle: radians))
        case .removeBackground:
            return try removeBackground(image)
        case .convert, .optimize, .stripMetadata:
            return image
        }
    }

    private static func transformed(_ image: CIImage, _ transform: CGAffineTransform) -> CIImage {
        let value = image.transformed(by: transform)
        return value.transformed(by: CGAffineTransform(translationX: -value.extent.minX, y: -value.extent.minY))
    }

    private static func removeBackground(_ image: CIImage) throws -> CIImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ImageModificationFailure.cannotRead("image")
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw ImageModificationFailure.unsupported("No foreground subject was detected.")
        }
        let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.backgroundImage = CIImage(color: .clear).cropped(to: image.extent)
        filter.maskImage = CIImage(cvPixelBuffer: mask)
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func validateSize(width: CGFloat, height: CGFloat) throws {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= 32768, height <= 32768, width * height <= 100_000_000 else {
            throw ImageModificationFailure.unsupported("The output must be at least 1 pixel per side, at most 32,768 pixels per side and no larger than 100 megapixels.")
        }
    }

    private static func write(_ image: CIImage, to url: URL, format: ImageFormat, quality: Double) throws {
        try validateSize(width: image.extent.width, height: image.extent.height)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let cgImage = context.createCGImage(image, from: image.extent),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, format.uniformType as CFString, 1, nil)
        else { throw ImageModificationFailure.cannotWrite(url.lastPathComponent) }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.05), 1)]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageModificationFailure.cannotWrite(url.lastPathComponent)
        }
    }

    private static func destinationURL(
        request: ImageModificationRequest, input: URL?, temporaryDirectory: URL
    ) -> URL {
        let format = request.operation == .convert ? request.format : input.map(inferredFormat(from:)) ?? request.format
        let stem = input?.deletingPathExtension().lastPathComponent ?? "Spotter Image"
        let suffix = request.operation == .stripMetadata ? "clean" : request.operation.rawValue
        let fileName = "\(stem)-\(suffix).\(format.fileExtension)"
        switch request.output {
        case .replace:
            guard let input else { return temporaryDirectory.appendingPathComponent(fileName) }
            if request.operation == .convert,
                inferredFormat(from: input) != request.format
            {
                return unique(input.deletingPathExtension().appendingPathExtension(format.fileExtension))
            }
            return input
        case .alongside:
            return unique((input?.deletingLastPathComponent() ?? temporaryDirectory).appendingPathComponent(fileName))
        case .desktop:
            return unique(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName))
        case .downloads:
            return unique(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName))
        case .clipboard, .preview:
            return temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
        }
    }

    private static func unique(_ proposed: URL) -> URL {
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let stem = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(stem) \(index)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent(stem + " " + UUID().uuidString).appendingPathExtension(ext)
    }

    private static func inferredFormat(from url: URL) -> ImageFormat {
        let ext = url.pathExtension.lowercased()
        if ext == "jpg" || ext == "jpeg" { return .jpeg }
        return ImageCommandParser.format(ext) ?? .png
    }


}

enum ImageFilterCatalog {
    static let available: [ImageFilterDescriptor] = {
        let categories = [
            kCICategoryBlur, kCICategoryColorAdjustment, kCICategoryColorEffect,
            kCICategoryDistortionEffect, kCICategoryHalftoneEffect, kCICategorySharpen,
            kCICategoryStylize, kCICategoryTileEffect,
        ]
        let names = Set(categories.flatMap(CIFilter.filterNames(inCategory:)))
        return names.compactMap { name in
            guard CIFilter(name: name)?.inputKeys.contains(kCIInputImageKey) == true else { return nil }
            return ImageFilterDescriptor(
                name: name, title: CIFilter.localizedName(forFilterName: name) ?? name)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }()
}
