import AppKit

@main
struct CropCheck {
    static func color(_ image: CGImage, x: Int = 0, y: Int = 0, equals expected: NSColor) {
        let actual = NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        let expected = expected.usingColorSpace(.deviceRGB)!
        for (a, b) in zip([actual.redComponent, actual.greenComponent, actual.blueComponent, actual.alphaComponent],
                          [expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent]) {
            precondition(abs(a - b) < 0.015, "crop pixel color / alpha")
        }
    }

    static func main() {
        _ = NSApplication.shared
        let context = ImageProcessing.context(width: 400, height: 200)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 200, y: 100, width: 200, height: 100))
        let translucent = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 0.5)
        context.setFillColor(translucent.cgColor)
        context.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        let source = context.makeImage()!
        let bottom = ImageProcessing.cropped(source, rect: CGRect(x: 20, y: 10, width: 40, height: 30))!
        precondition(bottom.width == 40 && bottom.height == 30)
        color(bottom, equals: .red)
        color(ImageProcessing.cropped(source, rect: CGRect(x: 250, y: 150, width: 1, height: 1))!, equals: .blue)
        color(ImageProcessing.cropped(source, rect: CGRect(x: 20, y: 150, width: 30, height: 20))!, equals: translucent)
        color(ImageProcessing.cropped(source, rect: CGRect(x: 250, y: 20, width: 30, height: 20))!, equals: .clear)
        let crossing = ImageProcessing.cropped(source, rect: CGRect(x: 190, y: 90, width: 20, height: 20))!
        color(crossing, x: 15, y: 5, equals: .blue)
        color(crossing, x: 5, y: 15, equals: .red)
        for invalid in [CGRect.zero, CGRect(x: -1, y: 0, width: 2, height: 2),
                        CGRect(x: 399, y: 199, width: 2, height: 2),
                        CGRect(x: CGFloat.nan, y: 0, width: 2, height: 2)] {
            precondition(ImageProcessing.cropped(source, rect: invalid) == nil)
        }

        var selection = ImageCrop(imageSize: CGSize(width: 400, height: 200))
        selection.begin(at: CGPoint(x: 300, y: 160), tolerance: 7)
        selection.drag(to: CGPoint(x: 50, y: 20), square: false)
        selection.end()
        precondition(selection.rect == CGRect(x: 50, y: 20, width: 250, height: 140), "reverse drag")
        selection.begin(at: CGPoint(x: 150, y: 80), tolerance: 7)
        selection.drag(to: CGPoint(x: 1000, y: -1000), square: false)
        selection.end()
        precondition(selection.rect == CGRect(x: 150, y: 0, width: 250, height: 140), "move clamps without resizing")
        selection.begin(at: CGPoint(x: 150, y: 140), tolerance: 7)
        selection.drag(to: CGPoint(x: 250, y: 80), square: false)
        selection.end()
        precondition(selection.rect == CGRect(x: 250, y: 0, width: 150, height: 80), "corner resize")
        selection.begin(at: CGPoint(x: 50, y: 150), tolerance: 7)
        selection.drag(to: CGPoint(x: 500, y: -100), square: true)
        selection.end()
        precondition(selection.rect == CGRect(x: 50, y: 0, width: 150, height: 150), "square stays inside image")

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = canvas
        canvas.image = ImageProcessing.context(width: 40, height: 20)!.makeImage()!
        canvas.fullImage = source
        let annotation = Annotation(tool: .rectangle, point: CGPoint(x: 40, y: 20), stroke: .yellow,
                                    width: 2, fill: .yellow, startArrow: .none, endArrow: .none,
                                    text: "", fontName: "Helvetica", fontSize: 20)
        annotation.points[1] = CGPoint(x: 80, y: 60)
        canvas.annotations = [annotation]
        canvas.selected = annotation
        var edits = 0
        var applied: CGRect?
        canvas.annotationsChanged = { edits += 1 }
        canvas.cropRequested = { applied = $0 }
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, shift: Bool = false) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y),
                                          modifierFlags: shift ? [.shift] : [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func key(_ code: UInt16, _ text: String, up: Bool = false) {
            let event = NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: text, charactersIgnoringModifiers: text,
                                        isARepeat: false, keyCode: code)!
            if up { canvas.keyUp(with: event) } else { canvas.keyDown(with: event) }
        }
        canvas.beginCrop()
        precondition(canvas.selected == nil && edits == 0)
        canvas.applyCrop()
        precondition(applied == nil, "empty crop cannot apply")
        mouse(.leftMouseDown, 10, 10)
        mouse(.leftMouseUp, 10, 10)
        precondition(canvas.cropSelection?.rect == nil, "click alone makes no crop")
        mouse(.leftMouseDown, 10, 10)
        mouse(.leftMouseDragged, 60, 40)
        canvas.applyCrop()
        precondition(applied == nil, "drag must finish before apply")
        mouse(.leftMouseUp, 60, 40)
        precondition(canvas.cropSelection?.rect == CGRect(x: 20, y: 20, width: 100, height: 60), "fit uses full resolution")
        let flattenedCrop = ImageProcessing.cropped(canvas.flattenedImage()!, rect: canvas.cropSelection!.rect!)!
        color(flattenedCrop, x: 40, y: 40, equals: .yellow)
        key(36, "\r")
        precondition(applied == canvas.cropSelection?.rect)
        key(53, "\u{1b}")
        precondition(!canvas.isCropping && edits == 0 && canvas.annotations.count == 1, "cancel preserves source / annotations")

        canvas.zoom(to: 1)
        canvas.beginCrop()
        key(49, " ")
        mouse(.leftMouseDown, 100, 50)
        mouse(.leftMouseDragged, 130, 70)
        mouse(.leftMouseUp, 130, 70)
        key(49, " ", up: true)
        precondition(canvas.viewport.offset == CGPoint(x: 30, y: 20) && canvas.cropSelection?.rect == nil)
        mouse(.leftMouseDown, 50, 30)
        mouse(.leftMouseDragged, 90, 50, shift: true)
        mouse(.leftMouseUp, 90, 50)
        precondition(canvas.cropSelection?.rect == CGRect(x: 120, y: 60, width: 40, height: 40), "zoom/pan/square mapping")
        canvas.fullImage = source
        precondition(!canvas.isCropping && edits == 0, "new image cancels crop")
        precondition(ToolbarImages.resize.isTemplate)
        precondition(NSImage(systemSymbolName: "crop", accessibilityDescription: nil) != nil)
        precondition(NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil) != nil)
        print("OK: crop pixels, orientation, alpha, bounds, move, handles, square, zoom/pan, apply/cancel, annotations and icons")
    }

}
