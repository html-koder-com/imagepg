import AppKit

final class AnnotationPanelStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class LineWidthPreviewView: NSView {
    var lineWidth: CGFloat = 4 { didSet { needsDisplay = true } }
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let context = NSGraphicsContext.current!.cgContext
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineWidth(min(max(0.5, lineWidth), bounds.height - 6))
        context.move(to: CGPoint(x: 13, y: bounds.midY))
        context.addLine(to: CGPoint(x: bounds.maxX - 13, y: bounds.midY))
        context.strokePath()
    }
}

enum AnnotationTool: Int, CaseIterable {
    case select, pen, line, ellipse, rectangle, text

    var title: String {
        switch self {
        case .select: return L("Select")
        case .pen: return L("Pen")
        case .line: return L("Line")
        case .ellipse: return L("Ellipse")
        case .rectangle: return L("Rectangle")
        case .text: return L("Text")
        }
    }
}

enum ArrowStyle: Int, CaseIterable {
    case none, filled, open, circle, diamond

    var title: String {
        switch self {
        case .none: return L("No arrow")
        case .filled: return L("Filled arrow")
        case .open: return L("Open arrow")
        case .circle: return L("Circle")
        case .diamond: return L("Diamond")
        }
    }
}

final class Annotation {
    let tool: AnnotationTool
    var points: [CGPoint]
    var stroke: NSColor
    var width: CGFloat
    var fill: NSColor?
    var startArrow: ArrowStyle
    var endArrow: ArrowStyle
    var arrowLength: CGFloat
    var text: String
    var fontName: String
    var fontSize: CGFloat

    init(tool: AnnotationTool, point: CGPoint, stroke: NSColor, width: CGFloat,
         fill: NSColor?, startArrow: ArrowStyle, endArrow: ArrowStyle,
         text: String, fontName: String, fontSize: CGFloat, arrowLength: CGFloat = 18) {
        self.tool = tool
        self.points = [point, point]
        self.stroke = stroke
        self.width = width
        self.fill = fill
        self.startArrow = startArrow
        self.endArrow = endArrow
        self.arrowLength = arrowLength
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
    }

    var font: NSFont { NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize) }
    var textSize: CGSize {
        let measured = (text.isEmpty ? "Text" : text as NSString).boundingRect(
            with: CGSize(width: 100_000, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]).size
        return CGSize(width: max(12, ceil(measured.width) + 4), height: max(fontSize, ceil(measured.height) + 4))
    }
    var rect: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text { return CGRect(origin: first, size: textSize) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                      width: (xs.max() ?? first.x) - (xs.min() ?? first.x),
                      height: (ys.max() ?? first.y) - (ys.min() ?? first.y))
    }
    var handles: [CGPoint] {
        switch tool {
        case .line: return Array(points.prefix(2))
        case .ellipse, .rectangle:
            let r = rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
                    CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)]
        default: return []
        }
    }

    func move(by delta: CGPoint) {
        points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
    }

    func draw(in context: CGContext) {
        guard let first = points.first else { return }
        context.saveGState()
        context.setLineWidth(max(0.5, width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(stroke.cgColor)
        switch tool {
        case .select: break
        case .pen:
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            if points.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
            context.strokePath()
        case .line:
            guard points.count > 1 else { break }
            context.move(to: first)
            context.addLine(to: points[1])
            context.strokePath()
            drawArrow(startArrow, tip: first, other: points[1], in: context)
            drawArrow(endArrow, tip: points[1], other: first, in: context)
        case .ellipse, .rectangle:
            let shape = rect
            if tool == .ellipse { context.addEllipse(in: shape) }
            else { context.addRect(shape) }
            if let fill {
                context.setFillColor(fill.cgColor)
                context.drawPath(using: .fillStroke)
            } else { context.strokePath() }
        case .text:
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: stroke]
            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
        context.restoreGState()
    }

    private func drawArrow(_ style: ArrowStyle, tip: CGPoint, other: CGPoint, in context: CGContext) {
        guard style != .none else { return }
        let dx = tip.x - other.x, dy = tip.y - other.y
        let distance = hypot(dx, dy)
        guard distance > 0.01 else { return }
        let ux = dx / distance, uy = dy / distance
        let length = min(max(arrowLength, width * 5), max(8, distance * 0.45))
        let half = length * 0.43
        let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
        let left = CGPoint(x: base.x - uy * half, y: base.y + ux * half)
        let right = CGPoint(x: base.x + uy * half, y: base.y - ux * half)
        context.beginPath()
        switch style {
        case .none: break
        case .filled, .open:
            context.move(to: left); context.addLine(to: tip); context.addLine(to: right)
            if style == .filled {
                context.closePath(); context.setFillColor(stroke.cgColor); context.fillPath()
            } else { context.strokePath() }
        case .circle:
            context.addEllipse(in: CGRect(x: tip.x - half, y: tip.y - half, width: half * 2, height: half * 2))
            context.setFillColor(stroke.cgColor); context.fillPath()
        case .diamond:
            let far = CGPoint(x: tip.x - ux * length * 1.5, y: tip.y - uy * length * 1.5)
            context.move(to: tip); context.addLine(to: left); context.addLine(to: far)
            context.addLine(to: right); context.closePath()
            context.setFillColor(stroke.cgColor); context.fillPath()
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if tool == .text { return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if tool == .rectangle || tool == .ellipse {
            let r = rect.insetBy(dx: -tolerance, dy: -tolerance)
            if !r.contains(point) { return false }
            if fill != nil { return true }
            if tool == .rectangle {
                return abs(point.x - rect.minX) <= tolerance || abs(point.x - rect.maxX) <= tolerance ||
                       abs(point.y - rect.minY) <= tolerance || abs(point.y - rect.maxY) <= tolerance
            }
            let rx = max(rect.width / 2, 0.1), ry = max(rect.height / 2, 0.1)
            let d = hypot((point.x - rect.midX) / rx, (point.y - rect.midY) / ry)
            return abs(d - 1) <= tolerance / min(rx, ry)
        }
        for pair in zip(points, points.dropFirst()) {
            let a = pair.0, b = pair.1
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / max(dx * dx + dy * dy, 0.001)))
            if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance { return true }
        }
        return points.count == 1 && hypot(point.x - points[0].x, point.y - points[0].y) <= tolerance
    }
}

extension ImageCanvasView {
    /// Samples one original-resolution pixel, including annotations but excluding selection handles.
    /// Canvas coordinates have their origin at the bottom left, just like the export context.
    func sampledColor(at point: CGPoint) -> NSColor? {
        guard let source = fullImage, point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0,
              point.x < CGFloat(source.width), point.y < CGFloat(source.height),
              let context = ImageProcessing.context(width: 1, height: 1) else { return nil }
        context.interpolationQuality = .none
        context.translateBy(x: -floor(point.x), y: -floor(point.y))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in annotations { annotation.draw(in: context) }
        NSGraphicsContext.restoreGraphicsState()
        guard let pixel = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: pixel).colorAt(x: 0, y: 0)
    }

    func flattenedImage() -> CGImage? {
        guard let source = fullImage, let context = ImageProcessing.context(width: source.width, height: source.height) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for annotation in annotations { annotation.draw(in: context) }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
