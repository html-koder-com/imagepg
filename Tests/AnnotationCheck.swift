import AppKit

@main
struct AnnotationCheck {
    static func main() {
        _ = NSApplication.shared
        guard let baseContext = ImageProcessing.context(width: 100, height: 100) else { fatalError("context") }
        baseContext.setFillColor(NSColor.white.cgColor)
        baseContext.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        guard let base = baseContext.makeImage() else { fatalError("base image") }

        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        canvas.image = base
        canvas.fullImage = base
        let rectangle = Annotation(tool: .rectangle, point: CGPoint(x: 20, y: 20),
                                   stroke: .red, width: 2, fill: .red,
                                   startArrow: .none, endArrow: .none,
                                   text: "", fontName: "Helvetica", fontSize: 20)
        rectangle.points[1] = CGPoint(x: 80, y: 80)
        canvas.annotations = [rectangle]
        guard rectangle.contains(CGPoint(x: 20, y: 50), tolerance: 3),
              !rectangle.contains(CGPoint(x: 5, y: 5), tolerance: 3),
              let flattened = canvas.flattenedImage() else { fatalError("annotation geometry") }

        let bitmap = NSBitmapImageRep(cgImage: flattened)
        guard let center = bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB),
              let outside = bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB),
              center.redComponent > 0.9, center.greenComponent < 0.1,
              outside.redComponent > 0.9, outside.greenComponent > 0.9 else {
            fatalError("flattened pixels")
        }

        let line = Annotation(tool: .line, point: CGPoint(x: 20, y: 50),
                              stroke: .red, width: 2, fill: nil,
                              startArrow: .filled, endArrow: .filled,
                              text: "", fontName: "Helvetica", fontSize: 20,
                              arrowLength: 24)
        line.points[1] = CGPoint(x: 80, y: 50)
        canvas.annotations = [line]
        guard let lineImage = canvas.flattenedImage() else { fatalError("line image") }
        let lineBitmap = NSBitmapImageRep(cgImage: lineImage)
        for x in [36, 64] {
            let arrowPixels = (52...58).compactMap { y in
                lineBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            }
            guard arrowPixels.contains(where: { $0.redComponent > 0.8 && $0.greenComponent < 0.4 }) else {
                fatalError("arrow at x=\(x)")
            }
        }

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePG-annotation-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }
        guard ImageProcessing.save(lineImage, to: destination, type: "png", quality: 1,
                                   transparency: true, background: .white),
              let reloaded = ImageProcessing.fullImage(at: destination),
              reloaded.width == 100, reloaded.height == 100 else { fatalError("saved annotation") }
        let savedBitmap = NSBitmapImageRep(cgImage: reloaded)
        for x in [36, 64] {
            guard (52...58).contains(where: { y in
                guard let color = savedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.redComponent > 0.8 && color.greenComponent < 0.4
            }) else { fatalError("saved arrow at x=\(x)") }
        }
        print("OK: výběr objektu, obě šipky, sloučení v plném rozlišení, uložení PNG")
    }
}
