import AppKit
import ImageIO

@main
struct ImageProcessingCheck {
    static func main() {
        guard let context = ImageProcessing.context(width: 3, height: 2) else { fatalError("context") }
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        guard let source = context.makeImage() else { fatalError("source") }
        guard let left = ImageProcessing.rotated(source, degrees: 90), left.width == 2, left.height == 3 else { fatalError("rotate") }
        guard let right = ImageProcessing.rotated(source, degrees: -90), right.width == 2, right.height == 3 else { fatalError("rotate right") }
        guard let largeContext = ImageProcessing.context(width: 320, height: 200),
              let large = largeContext.makeImage(),
              let largeRotated = ImageProcessing.rotated(large, degrees: 90),
              largeRotated.width == 200, largeRotated.height == 320 else { fatalError("large rotate") }
        guard let resized = ImageProcessing.resized(source, width: 6, height: 4), resized.width == 6, resized.height == 4 else { fatalError("resize") }
        guard let canvas = ImageProcessing.canvas(source, width: 5, height: 4, anchor: 4, background: nil),
              canvas.width == 5, canvas.height == 4 else { fatalError("canvas") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePG-check-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let saved = ImageProcessing.save(canvas, to: temporary, type: "png", quality: 1, transparency: true, background: .white)
        let loaded = ImageProcessing.fullImage(at: temporary)
        let thumbnail = ImageProcessing.thumbnail(at: temporary, maximum: 2)
        guard saved, let loaded, loaded.width == 5, loaded.height == 4,
              let thumbnail, thumbnail.width <= 2, thumbnail.height <= 2 else {
            fatalError("save/load")
        }
        for ext in ImageProcessing.writableExtensions.filter(ImageProcessing.canWrite) {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePG-check-\(UUID().uuidString).\(ext)")
            defer { try? FileManager.default.removeItem(at: destination) }
            guard ImageProcessing.save(source, to: destination, type: ext, quality: 0.8,
                                       transparency: !["jpg", "jpeg", "bmp"].contains(ext), background: .white),
                  let reloaded = ImageProcessing.fullImage(at: destination),
                  reloaded.width == 3, reloaded.height == 2 else { fatalError("format \(ext)") }
        }
        print("OK: rotace, změna velikosti, plátno, PNG, načtení a náhled")
        print("Dostupné čtení: \(ImageProcessing.readableExtensions.sorted().filter(ImageProcessing.canRead).joined(separator: ", "))")
        print("Dostupný zápis: \(ImageProcessing.writableExtensions.filter(ImageProcessing.canWrite).joined(separator: ", "))")
    }
}
