import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessing {
    static let readableExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "webp", "avif", "bmp", "gif"]
    static let writableExtensions = ["jpg", "jpeg", "png", "tiff", "heic", "webp", "avif", "bmp", "gif"]
    private static let identifiers: [String: String] = [
        "jpg": "public.jpeg", "jpeg": "public.jpeg", "png": "public.png",
        "tif": "public.tiff", "tiff": "public.tiff", "webp": "org.webmproject.webp",
        "heic": "public.heic", "avif": "public.avif", "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif"
    ]
    private static let readableTypes = Set((CGImageSourceCopyTypeIdentifiers() as [AnyObject]).compactMap { $0 as? String })
    private static let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as [AnyObject]).compactMap { $0 as? String })

    static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> CGImage? {
        let types = pasteboard.types ?? []
        let imageTypes = [NSPasteboard.PasteboardType.png, .tiff] + types.filter {
            UTType($0.rawValue)?.conforms(to: .image) == true && $0 != .png && $0 != .tiff
        }
        for type in imageTypes {
            guard let data = pasteboard.data(forType: type),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceShouldCacheImmediately: true
                ]
                if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    return image
                }
            }
            if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        }
        return NSImage(pasteboard: pasteboard)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func type(for ext: String) -> UTType? {
        guard let identifier = identifiers[ext.lowercased()] else { return nil }
        return UTType(identifier)
    }

    static func dimensions(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    static func thumbnail(at url: URL, maximum: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func fullImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, width <= 100_000, height <= 100_000,
              Double(width) * Double(height) <= 400_000_000 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func rotated(_ image: CGImage, degrees: Double) -> CGImage? {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians)), sine = abs(sin(radians))
        let width = Int(ceil(Double(image.width) * cosine + Double(image.height) * sine - 1e-8))
        let height = Int(ceil(Double(image.width) * sine + Double(image.height) * cosine - 1e-8))
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: CGFloat(radians))
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func cropped(_ image: CGImage, rect: CGRect) -> CGImage? {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy({ $0.isFinite }),
              rect.width >= 1, rect.height >= 1 else { return nil }
        let pixels = rect.integral
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard bounds.contains(pixels) else { return nil }
        // CGImage cropping starts at the top-left; the canvas starts at the bottom-left.
        return image.cropping(to: CGRect(x: pixels.minX, y: CGFloat(image.height) - pixels.maxY,
                                        width: pixels.width, height: pixels.height))
    }

    static func canvas(_ image: CGImage, width: Int, height: Int, anchor: Int,
                       background: NSColor?) -> CGImage? {
        guard let context = context(width: width, height: height) else { return nil }
        if let background = background?.usingColorSpace(.deviceRGB) {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let column = anchor % 3
        let row = anchor / 3
        let x = [0, (width - image.width) / 2, width - image.width][column]
        let y = [height - image.height, (height - image.height) / 2, 0][row]
        context.draw(image, in: CGRect(x: x, y: y, width: image.width, height: image.height))
        return context.makeImage()
    }

    static func flattened(_ image: CGImage, color: NSColor) -> CGImage? {
        guard let context = context(width: image.width, height: image.height) else { return nil }
        context.setFillColor((color.usingColorSpace(.deviceRGB) ?? .white).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    static func save(_ image: CGImage, to url: URL, type: String, quality: Double,
                     transparency: Bool, background: NSColor) -> Bool {
        guard let uti = identifiers[type.lowercased()],
              let destination = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else { return false }
        let output = transparency ? image : (flattened(image, color: background) ?? image)
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func canRead(_ ext: String) -> Bool {
        guard let identifier = identifiers[ext.lowercased()] else { return false }
        return readableTypes.contains(identifier)
    }

    static func canWrite(_ ext: String) -> Bool {
        guard let identifier = identifiers[ext.lowercased()] else { return false }
        return writableTypes.contains(identifier)
    }
}
