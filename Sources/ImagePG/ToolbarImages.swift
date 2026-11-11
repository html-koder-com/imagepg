import AppKit

enum ToolbarImages {
    /// A rectangle with separate width/height arrows, distinct from crop corners.
    static let resize: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.appendRect(CGRect(x: 2.5, y: 3.5, width: 13, height: 11))
            func line(_ points: [CGPoint]) {
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
            }
            line([CGPoint(x: 2.5, y: 20), CGPoint(x: 15.5, y: 20)])
            line([CGPoint(x: 5, y: 17.5), CGPoint(x: 2.5, y: 20), CGPoint(x: 5, y: 22.5)])
            line([CGPoint(x: 13, y: 17.5), CGPoint(x: 15.5, y: 20), CGPoint(x: 13, y: 22.5)])
            line([CGPoint(x: 21, y: 3.5), CGPoint(x: 21, y: 14.5)])
            line([CGPoint(x: 18.5, y: 6), CGPoint(x: 21, y: 3.5), CGPoint(x: 23.5, y: 6)])
            line([CGPoint(x: 18.5, y: 12), CGPoint(x: 21, y: 14.5), CGPoint(x: 23.5, y: 12)])
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("Resize image")
        return image
    }()
}
