import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct HEICCheck {
    static func main() throws {
        precondition(ImageProcessing.canRead("heic") && ImageProcessing.canRead("HEIC"))
        precondition(ImageProcessing.canWrite("heic") && ImageProcessing.canWrite("HEIC"))
        precondition(ImageProcessing.type(for: "HEIC") == .heic)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePG-HEIC-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = ImageProcessing.context(width: 96, height: 64)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let image = context.makeImage()!

        // Model a portrait photo whose pixels are stored sideways by a camera.
        let url = directory.appendingPathComponent("portrait.HEIC")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination), "HEIC fixture encoding")

        let loaded = ImageProcessing.fullImage(at: url)!
        precondition(loaded.width == 64 && loaded.height == 96, "HEIC orientation at full resolution")
        let thumbnail = ImageProcessing.thumbnail(at: url, maximum: 32)!
        precondition(thumbnail.height == 32 && thumbnail.width < thumbnail.height, "HEIC thumbnail orientation")

        let resized = ImageProcessing.resized(loaded, width: 32, height: 48)!
        for ext in ["heic", "jpg", "png"] {
            let output = directory.appendingPathComponent("edited.\(ext)")
            precondition(ImageProcessing.save(resized, to: output, type: ext, quality: 0.8,
                                              transparency: false, background: .white), "HEIC export to \(ext)")
            let reloaded = ImageProcessing.fullImage(at: output)!
            precondition(reloaded.width == 32 && reloaded.height == 48, "HEIC export dimensions")
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
            precondition(CGImageSourceGetType(source) as String? == ImageProcessing.type(for: ext)?.identifier)
        }

        precondition(ImageProcessing.save(resized, to: url, type: "HEIC", quality: 0.9,
                                          transparency: false, background: .white), "overwrite HEIC")
        let overwritten = ImageProcessing.fullImage(at: url)!
        precondition(overwritten.width == 32 && overwritten.height == 48)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let documents = plist["CFBundleDocumentTypes"] as! [[String: Any]]
        precondition(documents.contains { ($0["CFBundleTypeExtensions"] as? [String])?.contains("heic") == true },
                     "Finder HEIC registration")
        print("OK: HEIC, velká přípona, orientace, náhled, úprava, export HEIC/JPEG/PNG, přepsání a Finder")
    }
}
