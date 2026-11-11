import AppKit

@main
struct ViewportCheck {
    static func close(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        precondition(abs(actual - expected) < 0.0001, "\(message): \(actual) != \(expected)")
    }

    static func main() {
        _ = NSApplication.shared
        var viewport = ImageViewport(imageSize: CGSize(width: 4000, height: 2000),
                                     bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
        close(viewport.scale, 0.25, "fit scale")
        precondition(!viewport.canPan)
        let anchor = CGPoint(x: 350, y: 350)
        let original = viewport.imageRect
        let imagePoint = CGPoint(x: (anchor.x - original.minX) / viewport.scale,
                                 y: (anchor.y - original.minY) / viewport.scale)
        viewport.zoom(to: 1, anchor: anchor)
        close(viewport.imageRect.minX + imagePoint.x * viewport.scale, anchor.x, "zoom anchor x")
        close(viewport.imageRect.minY + imagePoint.y * viewport.scale, anchor.y, "zoom anchor y")
        viewport.pan(by: CGPoint(x: 100_000, y: -100_000))
        close(viewport.imageRect.minX, 0, "left edge")
        close(viewport.imageRect.maxY, 800, "top edge")
        viewport.pan(by: CGPoint(x: -200_000, y: 200_000))
        close(viewport.imageRect.maxX, 1000, "right edge")
        close(viewport.imageRect.minY, 0, "bottom edge")
        viewport.bounds.size = CGSize(width: 5000, height: 3000)
        viewport.constrainOffset()
        precondition(viewport.offset == .zero && !viewport.canPan)
        viewport.zoom(to: 1000, anchor: .zero)
        close(viewport.scale, 16, "maximum zoom")
        viewport.zoom(to: 0, anchor: .zero)
        close(viewport.scale, 0.01, "minimum zoom")
        viewport.fit()
        close(viewport.scale, 1, "small images are not enlarged by fit")
        viewport.bounds.size = CGSize(width: 200, height: 100)
        close(viewport.scale, 0.05, "fit follows resize")

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = canvas
        let source = ImageProcessing.context(width: 400, height: 200)!.makeImage()!
        canvas.image = ImageProcessing.context(width: 100, height: 50)!.makeImage()!
        canvas.fullImage = source
        close(canvas.viewport.scale, 0.5, "fit uses original dimensions, not thumbnail")
        canvas.zoom(to: 1)
        close(canvas.viewport.imageRect.width, 400, "100% uses original dimensions")
        var edits = 0
        canvas.annotationsChanged = { edits += 1 }
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        mouse(.leftMouseDown, 100, 50)
        mouse(.leftMouseDragged, 130, 70)
        mouse(.leftMouseUp, 130, 70)
        precondition(canvas.viewport.offset == CGPoint(x: 30, y: 20))
        precondition(edits == 0, "view changes must not mark the image edited")

        canvas.annotationsEnabled = true
        canvas.tool = .rectangle
        mouse(.leftMouseDown, 50, 30)
        mouse(.leftMouseDragged, 80, 60)
        mouse(.leftMouseUp, 80, 60)
        precondition(canvas.annotations.count == 1)
        let annotation = canvas.annotations[0]
        close(annotation.rect.minX, 120, "annotation x after zoom and pan")
        close(annotation.rect.minY, 60, "annotation y after zoom and pan")
        close(annotation.rect.width, 30, "annotation width after zoom")
        let editCount = edits
        let spaceDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, characters: " ",
                                        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        canvas.keyDown(with: spaceDown)
        mouse(.leftMouseDown, 60, 40)
        mouse(.leftMouseDragged, 80, 50)
        mouse(.leftMouseUp, 80, 50)
        precondition(canvas.viewport.offset == CGPoint(x: 50, y: 30))
        precondition(edits == editCount && annotation.rect.minX == 120, "space drag must not edit annotations")
        canvas.keyUp(with: spaceDown)
        canvas.fitToWindow()
        precondition(canvas.viewport.offset == .zero)
        mouse(.leftMouseDown, 65, 35)
        mouse(.leftMouseDragged, 75, 40)
        mouse(.leftMouseUp, 75, 40)
        close(annotation.rect.minX, 140, "selection still maps to original coordinates after fit")
        let flattened = canvas.flattenedImage()!
        precondition(flattened.width == 400 && flattened.height == 200, "export preserves full dimensions")
        canvas.annotationsEnabled = false
        let beforePan = edits
        mouse(.leftMouseDown, 100, 50)
        mouse(.leftMouseDragged, 150, 80)
        mouse(.leftMouseUp, 150, 80)
        precondition(canvas.viewport.offset == .zero && edits == beforePan, "fitted image cannot be panned")
        print("OK: zoom, limits, cursor anchor, all pan edges, resize, original dimensions, mouse dragging, annotations, space drag, fit and export")
    }
}
