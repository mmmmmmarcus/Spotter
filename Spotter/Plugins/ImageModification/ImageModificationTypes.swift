import Foundation

enum ImageOperation: String, CaseIterable, Identifiable, Sendable {
    case filter, convert, create, flipHorizontal, flipVertical, optimize, pad
    case removeBackground, resize, rotate, scale, stripMetadata

    var id: String { rawValue }
    var title: String {
        switch self {
        case .filter: "Apply Filter"
        case .convert: "Convert Image"
        case .create: "Create Image"
        case .flipHorizontal: "Flip Horizontally"
        case .flipVertical: "Flip Vertically"
        case .optimize: "Optimize Image"
        case .pad: "Pad Image"
        case .removeBackground: "Remove Background"
        case .resize: "Resize Image"
        case .rotate: "Rotate Image"
        case .scale: "Scale Image"
        case .stripMetadata: "Strip EXIF Metadata"
        }
    }
    var systemImage: String {
        switch self {
        case .filter: "camera.filters"
        case .convert: "arrow.triangle.2.circlepath"
        case .create: "plus.rectangle"
        case .flipHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .flipVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .optimize: "gauge.with.dots.needle.67percent"
        case .pad: "rectangle.inset.filled"
        case .removeBackground: "person.crop.rectangle.badge.minus"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .rotate: "rotate.right"
        case .scale: "aspectratio"
        case .stripMetadata: "exclamationmark.triangle"
        }
    }
}

enum ImageOutputLocation: String, CaseIterable, Identifiable, Sendable {
    case alongside, desktop, downloads, replace, clipboard, preview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .alongside: "Beside Original"
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .replace: "Replace Original"
        case .clipboard: "Clipboard"
        case .preview: "Open in Preview"
        }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, gif, tiff, jp2, atx, ktx, ktx2, astc, dds, heic, heics, avif
    case ico, bmp, icns, psd, pdf, tga, exr, pbm, pvr
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var uniformType: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .gif: "com.compuserve.gif"
        case .tiff: "public.tiff"
        case .jp2: "public.jpeg-2000"
        case .atx: "com.apple.atx"
        case .ktx: "org.khronos.ktx"
        case .ktx2: "org.khronos.ktx2"
        case .astc: "org.khronos.astc"
        case .dds: "com.microsoft.dds"
        case .heic: "public.heic"
        case .heics: "public.heics"
        case .avif: "public.avif"
        case .ico: "com.microsoft.ico"
        case .bmp: "com.microsoft.bmp"
        case .icns: "com.apple.icns"
        case .psd: "com.adobe.photoshop-image"
        case .pdf: "com.adobe.pdf"
        case .tga: "com.truevision.tga-image"
        case .exr: "com.ilm.openexr-image"
        case .pbm: "public.pbm"
        case .pvr: "public.pvr"
        }
    }
}

struct ImageFilterDescriptor: Identifiable, Hashable, Sendable {
    let name: String
    let title: String
    var id: String { name }
}

enum ImageGenerator: String, CaseIterable, Identifiable, Sendable {
    case checkerboard, constantColor, lenticularHalo, linearGradient, radialGradient
    case random, starShine, stripes, sunbeams

    var id: String { rawValue }
    var title: String {
        switch self {
        case .checkerboard: "Checkerboard"
        case .constantColor: "Constant Color"
        case .lenticularHalo: "Lenticular Halo"
        case .linearGradient: "Linear Gradient"
        case .radialGradient: "Radial Gradient"
        case .random: "Random"
        case .starShine: "Star Shine"
        case .stripes: "Stripes"
        case .sunbeams: "Sunbeams"
        }
    }
}

struct ImageModificationRequest: Sendable {
    var operation: ImageOperation = .resize
    var output: ImageOutputLocation = .alongside
    var format: ImageFormat = .png
    var filterName = "CIPhotoEffectChrome"
    var generator: ImageGenerator = .linearGradient
    var width = 1200
    var height = 800
    var preserveAspect = true
    var scale = 0.5
    var angle = 90.0
    var quality = 0.82
    var padding = 40
    var colorHex = "#00000000"
    var secondColorHex = "#4F46E5"

    static func commandDefaults(
        operation: ImageOperation, output: ImageOutputLocation, format: ImageFormat,
        hasPersistentInput: Bool
    ) -> ImageModificationRequest {
        var request = ImageModificationRequest(operation: operation, output: output, format: format)
        if output == .alongside {
            if operation == .create { request.output = .preview }
            else if !hasPersistentInput { request.output = .clipboard }
        }
        return request
    }
}

struct ImageModificationResult: Sendable {
    let input: URL?
    let output: URL
}

enum ImageModificationFailure: LocalizedError, Sendable {
    case noInput, cannotRead(String), cannotWrite(String), unsupported(String)
    var errorDescription: String? {
        switch self {
        case .noInput: "Choose at least one image."
        case .cannotRead(let name): "Could not read \(name)."
        case .cannotWrite(let name): "Could not write \(name)."
        case .unsupported(let message): message
        }
    }
}
