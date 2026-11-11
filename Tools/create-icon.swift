import AppKit
import ImageIO

// Render the icon from native shapes so the source stays easy to regenerate.
// Design: crop-corner brackets framing a landscape (viewer + editor) on an indigo tile.
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot create icon canvas")
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor
}
func gradient(_ colors: [CGColor], _ points: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
    let value = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: points)!
    ctx.drawLinearGradient(value, start: start, end: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Tile with the macOS icon grid proportions (824 pt body inside a 1024 canvas).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(10, 8, 40, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(88, 101, 242))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
gradient([rgb(88, 101, 242), rgb(142, 77, 240)], [0, 1], CGPoint(x: 100, y: 924), CGPoint(x: 924, y: 100))
// Soft top light.
gradient([rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)], [0, 0.45], CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 100))
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(255, 255, 255, 0.18))
ctx.setLineWidth(3)
ctx.strokePath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(20, 10, 60, 0.28))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

// Crop brackets.
ctx.setStrokeColor(rgb(255, 255, 255))
ctx.setLineWidth(58)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
for corner in [[(262, 624), (262, 762), (400, 762)], [(624, 762), (762, 762), (762, 624)],
               [(762, 400), (762, 262), (624, 262)], [(400, 262), (262, 262), (262, 400)]] {
    ctx.move(to: CGPoint(x: corner[0].0, y: corner[0].1))
    for point in corner.dropFirst() { ctx.addLine(to: CGPoint(x: point.0, y: point.1)) }
}
ctx.strokePath()

// Sun.
ctx.setFillColor(rgb(255, 199, 95))
ctx.fillEllipse(in: CGRect(x: 598 - 62, y: 604 - 62, width: 124, height: 124))

// Mountains.
let mountains = CGMutablePath()
mountains.move(to: CGPoint(x: 352, y: 352))
mountains.addLine(to: CGPoint(x: 470, y: 524))
mountains.addQuadCurve(to: CGPoint(x: 498, y: 524), control: CGPoint(x: 484, y: 544))
mountains.addLine(to: CGPoint(x: 560, y: 434))
mountains.addLine(to: CGPoint(x: 596, y: 479))
mountains.addQuadCurve(to: CGPoint(x: 624, y: 479), control: CGPoint(x: 610, y: 496))
mountains.addLine(to: CGPoint(x: 690, y: 352))
mountains.closeSubpath()
ctx.saveGState()
ctx.addPath(mountains)
ctx.clip()
gradient([rgb(255, 255, 255), rgb(228, 226, 255)], [0, 1], CGPoint(x: 512, y: 544), CGPoint(x: 512, y: 352))
ctx.restoreGState()

ctx.endTransparencyLayer()
ctx.restoreGState()

guard let output = CommandLine.arguments.dropFirst().first,
      let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                         "public.png" as CFString, 1, nil) else {
    fatalError("Cannot create icon image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write icon") }
