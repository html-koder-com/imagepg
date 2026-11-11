import Foundation

/// Pixel-aligned crop geometry in the canvas's bottom-left image coordinates.
struct ImageCrop {
    let imageSize: CGSize
    private(set) var rect: CGRect?
    private var start: CGPoint?
    private var original: CGRect?
    private var opposite: CGPoint?

    init(imageSize: CGSize) { self.imageSize = imageSize }

    var isDragging: Bool { start != nil }
    var handles: [CGPoint] {
        guard let rect else { return [] }
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    mutating func begin(at point: CGPoint, tolerance: CGFloat) {
        start = point
        original = nil
        opposite = nil
        if let handle = handles.enumerated().min(by: {
            hypot($0.element.x - point.x, $0.element.y - point.y) <
                hypot($1.element.x - point.x, $1.element.y - point.y)
        }), hypot(handle.element.x - point.x, handle.element.y - point.y) <= tolerance {
            opposite = handles[3 - handle.offset]
        } else if let rect, rect.contains(point) {
            original = rect
        } else {
            rect = nil
        }
    }

    mutating func drag(to point: CGPoint, square: Bool) {
        guard let start else { return }
        if let original {
            let x = max(0, min(imageSize.width - original.width, original.minX + (point.x - start.x).rounded()))
            let y = max(0, min(imageSize.height - original.height, original.minY + (point.y - start.y).rounded()))
            rect = CGRect(origin: CGPoint(x: x, y: y), size: original.size)
            return
        }
        let anchor = opposite ?? start
        var end = CGPoint(x: max(0, min(imageSize.width, point.x)).rounded(),
                          y: max(0, min(imageSize.height, point.y)).rounded())
        let origin = CGPoint(x: anchor.x.rounded(), y: anchor.y.rounded())
        if square {
            let availableX = end.x < origin.x ? origin.x : imageSize.width - origin.x
            let availableY = end.y < origin.y ? origin.y : imageSize.height - origin.y
            let side = min(max(abs(end.x - origin.x), abs(end.y - origin.y)), availableX, availableY)
            end = CGPoint(x: origin.x + (end.x < origin.x ? -side : side),
                          y: origin.y + (end.y < origin.y ? -side : side))
        }
        let candidate = CGRect(x: min(origin.x, end.x), y: min(origin.y, end.y),
                               width: abs(end.x - origin.x), height: abs(end.y - origin.y))
        rect = candidate.width >= 1 && candidate.height >= 1 ? candidate : nil
    }

    mutating func end() {
        start = nil
        original = nil
        opposite = nil
    }
}
