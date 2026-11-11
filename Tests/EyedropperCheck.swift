import AppKit

@main
struct EyedropperCheck {
    static func expect(_ actual: NSColor?, _ expected: NSColor, _ message: String) {
        guard let actual = actual?.usingColorSpace(.deviceRGB),
              let expected = expected.usingColorSpace(.deviceRGB) else { fatalError(message) }
        for (a, b) in zip([actual.redComponent, actual.greenComponent, actual.blueComponent, actual.alphaComponent],
                          [expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent]) {
            precondition(abs(a - b) < 0.015, message)
        }
    }

    static func main() {
        _ = NSApplication.shared
        let context = ImageProcessing.context(width: 400, height: 200)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 200, y: 100, width: 200, height: 100))
        context.setFillColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 0.5).cgColor)
        context.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        let source = context.makeImage()!
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = canvas
        // Deliberately different thumbnail: sampling must use the original image.
        canvas.image = ImageProcessing.context(width: 40, height: 20)!.makeImage()!
        canvas.fullImage = source
        expect(canvas.sampledColor(at: CGPoint(x: 0, y: 0)), .red, "bottom-left pixel")
        expect(canvas.sampledColor(at: CGPoint(x: 399.9, y: 199.9)), .blue, "top-right pixel")
        expect(canvas.sampledColor(at: CGPoint(x: 50, y: 150)),
               NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 0.5), "preserve alpha")
        expect(canvas.sampledColor(at: CGPoint(x: 350, y: 50)), .clear, "transparent pixel")
        for point in [CGPoint(x: -1, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 200)] {
            precondition(canvas.sampledColor(at: point) == nil, "outside image")
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func click(_ point: CGPoint) {
            mouse(.leftMouseDown, point)
            mouse(.leftMouseUp, point)
        }
        canvas.annotationsEnabled = true
        canvas.tool = .rectangle
        var edits = 0
        canvas.annotationsChanged = { edits += 1 }
        canvas.beginColorPicking()
        click(CGPoint(x: 175, y: 75))
        expect(canvas.stroke, .blue, "fit sampling")
        expect(canvas.fill, .blue, "shape fill enabled")
        precondition(!canvas.isPickingColor && canvas.annotations.isEmpty && edits == 0)
        mouse(.leftMouseDown, CGPoint(x: 20, y: 15))
        mouse(.leftMouseDragged, CGPoint(x: 40, y: 30))
        mouse(.leftMouseUp, CGPoint(x: 40, y: 30))
        let rectangle = canvas.selected!
        expect(rectangle.fill, .blue, "new rectangle uses sampled color")
        let points = rectangle.points
        let before = edits
        canvas.beginColorPicking()
        click(CGPoint(x: 70, y: 35))
        expect(rectangle.stroke, .red, "existing rectangle border")
        expect(rectangle.fill, .red, "existing rectangle fill")
        precondition(canvas.selected === rectangle && rectangle.points == points && edits == before + 1)

        // Annotation color is included; selection decorations must not be sampled.
        rectangle.fill = .yellow
        rectangle.stroke = .yellow
        expect(canvas.sampledColor(at: CGPoint(x: 60, y: 40)), .yellow, "sample annotation")
        let flattened = NSBitmapImageRep(cgImage: canvas.flattenedImage()!)
        expect(canvas.sampledColor(at: CGPoint(x: 36, y: 26)),
               flattened.colorAt(x: 36, y: 173)!, "ignore selection outline")

        canvas.selected = nil
        canvas.tool = .text
        canvas.zoom(to: 1)
        // Pan with space held, then sample in the shifted viewport.
        let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: " ",
                                    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        canvas.beginColorPicking()
        canvas.keyDown(with: space)
        mouse(.leftMouseDown, CGPoint(x: 100, y: 50))
        mouse(.leftMouseDragged, CGPoint(x: 80, y: 30))
        mouse(.leftMouseUp, CGPoint(x: 80, y: 30))
        canvas.keyUp(with: space)
        precondition(canvas.isPickingColor)
        click(CGPoint(x: 150, y: 70))
        expect(canvas.stroke, .blue, "zoom and pan mapping")
        precondition(canvas.annotations.count == 1 && canvas.selected == nil, "sampling must not insert text")

        canvas.fitToWindow()
        canvas.zoom(to: 0.25)
        canvas.beginColorPicking()
        click(CGPoint(x: 1, y: 1))
        precondition(canvas.isPickingColor, "outside click does not sample background")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                     charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: escape)
        precondition(!canvas.isPickingColor)
        expect(canvas.stroke, .blue, "Escape preserves color")
        canvas.beginColorPicking()
        canvas.tool = .line
        precondition(!canvas.isPickingColor, "tool change cancels sampling")
        canvas.beginColorPicking()
        canvas.annotationsEnabled = false
        precondition(!canvas.isPickingColor, "closing annotations cancels sampling")
        canvas.annotationsEnabled = true
        canvas.beginColorPicking()
        canvas.fullImage = source
        precondition(!canvas.isPickingColor, "new image cancels sampling")
        print("OK: original pixels, orientation, transparency, annotations, shape fill and border, selection, zoom/pan, Escape and cancellation")
    }
}
