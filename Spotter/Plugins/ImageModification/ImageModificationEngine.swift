import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

enum ImageModificationEngine {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func process(
        request: ImageModificationRequest, inputs: [URL], temporaryDirectory: URL,
        progress: (@Sendable (_ completed: Int, _ total: Int, _ input: URL?) -> Void)? = nil
    ) throws -> [ImageModificationResult] {
        if request.operation == .create {
            let image = try create(request)
            let destination = destinationURL(request: request, input: nil, temporaryDirectory: temporaryDirectory)
            try write(image, to: destination, format: request.format, quality: request.quality)
            progress?(1, 1, nil)
            return [ImageModificationResult(input: nil, output: destination)]
        }
        guard !inputs.isEmpty else { throw ImageModificationFailure.noInput }
        var results: [ImageModificationResult] = []
        results.reserveCapacity(inputs.count)
        for (index, input) in inputs.enumerated() {
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
            let value = CGFloat(max(request.scale, 0.01))
            return transformed(image, CGAffineTransform(scaleX: value, y: value))
        case .rotate:
            let radians = CGFloat(request.angle * .pi / 180)
            return transformed(image, CGAffineTransform(rotationAngle: radians))
        case .pad:
            let amount = CGFloat(max(request.padding, 0))
            let background = CIImage(color: color(request.colorHex))
                .cropped(to: CGRect(x: 0, y: 0, width: image.extent.width + amount * 2, height: image.extent.height + amount * 2))
            return image.transformed(by: CGAffineTransform(translationX: amount - image.extent.minX, y: amount - image.extent.minY)).composited(over: background)
        case .removeBackground:
            return try removeBackground(image)
        case .convert, .optimize, .stripMetadata:
            return image
        case .create:
            return try create(request)
        }
    }

    private static func transformed(_ image: CIImage, _ transform: CGAffineTransform) -> CIImage {
        let value = image.transformed(by: transform)
        return value.transformed(by: CGAffineTransform(translationX: -value.extent.minX, y: -value.extent.minY))
    }

    private static func create(_ request: ImageModificationRequest) throws -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: max(request.width, 1), height: max(request.height, 1))
        let filterName: String
        switch request.generator {
        case .checkerboard: filterName = "CICheckerboardGenerator"
        case .constantColor: filterName = "CIConstantColorGenerator"
        case .lenticularHalo: filterName = "CILenticularHaloGenerator"
        case .linearGradient: filterName = "CILinearGradient"
        case .radialGradient: filterName = "CIRadialGradient"
        case .random: filterName = "CIRandomGenerator"
        case .starShine: filterName = "CIStarShineGenerator"
        case .stripes: filterName = "CIStripesGenerator"
        case .sunbeams: filterName = "CISunbeamsGenerator"
        }
        guard let filter = CIFilter(name: filterName) else {
            throw ImageModificationFailure.unsupported("The selected generator is unavailable.")
        }
        let first = color(request.colorHex)
        let second = color(request.secondColorHex)
        let center = CIVector(x: rect.midX, y: rect.midY)
        for key in filter.inputKeys {
            switch key {
            case "inputColor", "inputColor0": filter.setValue(first, forKey: key)
            case "inputColor1": filter.setValue(second, forKey: key)
            case "inputCenter": filter.setValue(center, forKey: key)
            case "inputPoint0": filter.setValue(CIVector(x: rect.minX, y: rect.minY), forKey: key)
            case "inputPoint1": filter.setValue(CIVector(x: rect.maxX, y: rect.maxY), forKey: key)
            case "inputRadius0": filter.setValue(0, forKey: key)
            case "inputRadius1", "inputRadius": filter.setValue(min(rect.width, rect.height) / 2, forKey: key)
            case "inputWidth": filter.setValue(max(min(rect.width, rect.height) / 8, 4), forKey: key)
            default: break
            }
        }
        guard let output = filter.outputImage else { throw ImageModificationFailure.unsupported("Could not create the image.") }
        return output.cropped(to: rect)
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

    private static func write(_ image: CIImage, to url: URL, format: ImageFormat, quality: Double) throws {
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
        let format = request.operation == .convert || request.operation == .create ? request.format : input.map(inferredFormat(from:)) ?? request.format
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
        return ImageFormat(rawValue: ext) ?? .png
    }

    private static func color(_ hex: String) -> CIColor {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let scanner = Scanner(string: value)
        var number: UInt64 = 0
        scanner.scanHexInt64(&number)
        let red, green, blue, alpha: CGFloat
        if value.count == 8 {
            red = CGFloat((number >> 24) & 0xff) / 255
            green = CGFloat((number >> 16) & 0xff) / 255
            blue = CGFloat((number >> 8) & 0xff) / 255
            alpha = CGFloat(number & 0xff) / 255
        } else {
            red = CGFloat((number >> 16) & 0xff) / 255
            green = CGFloat((number >> 8) & 0xff) / 255
            blue = CGFloat(number & 0xff) / 255
            alpha = 1
        }
        return CIColor(red: red, green: green, blue: blue, alpha: alpha)
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
