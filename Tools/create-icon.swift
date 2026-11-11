import AppKit
import ImageIO

// Render the icon from native shapes so the source stays easy to regenerate.
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
func round(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}
func gradient(_ colors: [CGColor], _ points: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
    let value = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: points)!
    ctx.drawLinearGradient(value, start: start, end: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func polygon(_ points: [CGPoint], _ color: CGColor) {
    let path = CGMutablePath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    fill(path, color)
}

let tile = CGRect(x: 48, y: 48, width: 928, height: 928)
ctx.saveGState()
ctx.addPath(round(tile, 205))
ctx.clip()
gradient([rgb(48, 79, 134), rgb(13, 35, 73), rgb(9, 29, 55)], [0, 0.55, 1],
         CGPoint(x: 150, y: 980), CGPoint(x: 900, y: 70))
ctx.setStrokeColor(rgb(167, 211, 244, 0.18))
ctx.setLineWidth(5)
ctx.addPath(round(CGRect(x: 51, y: 51, width: 922, height: 922), 202))
ctx.strokePath()
ctx.restoreGState()

// A second print gives the icon a gallery silhouette.
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -0.11)
ctx.translateBy(x: -512, y: -512)
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 38, color: rgb(0, 10, 27, 0.38))
fill(round(CGRect(x: 191, y: 203, width: 648, height: 648), 62), rgb(172, 214, 228))
ctx.restoreGState()

ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 42, color: rgb(0, 10, 27, 0.42))
fill(round(CGRect(x: 156, y: 181, width: 696, height: 696), 68), rgb(251, 252, 249))
ctx.setShadow(offset: .zero, blur: 0)

let photo = CGRect(x: 203, y: 228, width: 602, height: 602)
ctx.saveGState()
ctx.addPath(round(photo, 25))
ctx.clip()
gradient([rgb(101, 208, 228), rgb(35, 141, 188), rgb(25, 89, 150)], [0, 0.58, 1],
         CGPoint(x: 300, y: 830), CGPoint(x: 760, y: 230))
ctx.setFillColor(rgb(255, 196, 98))
ctx.fillEllipse(in: CGRect(x: 601, y: 599, width: 145, height: 145))
polygon([CGPoint(x: 203, y: 228), CGPoint(x: 203, y: 372),
         CGPoint(x: 402, y: 602), CGPoint(x: 620, y: 228)], rgb(25, 152, 168))
polygon([CGPoint(x: 278, y: 228), CGPoint(x: 568, y: 570),
         CGPoint(x: 805, y: 294), CGPoint(x: 805, y: 228)], rgb(13, 89, 129))
ctx.restoreGState()

// The loupe signals that ImagePG is an image viewer.
let center = CGPoint(x: 681, y: 350)
let radius: CGFloat = 139
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 25, color: rgb(1, 17, 38, 0.38))
ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(242, 249, 250))
ctx.setLineWidth(59)
ctx.move(to: CGPoint(x: 783, y: 248))
ctx.addLine(to: CGPoint(x: 865, y: 166))
ctx.strokePath()
ctx.setFillColor(rgb(17, 67, 99))
ctx.fillEllipse(in: CGRect(x: center.x - radius - 25, y: center.y - radius - 25,
                            width: 2 * (radius + 25), height: 2 * (radius + 25)))
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                          width: 2 * radius, height: 2 * radius))
ctx.clip()
gradient([rgb(96, 211, 229), rgb(31, 137, 183)], [0, 1],
         CGPoint(x: 570, y: 490), CGPoint(x: 770, y: 215))
polygon([CGPoint(x: 520, y: 212), CGPoint(x: 644, y: 440),
         CGPoint(x: 840, y: 212)], rgb(13, 98, 137))
ctx.restoreGState()
ctx.setStrokeColor(rgb(250, 253, 249))
ctx.setLineWidth(24)
ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                              width: 2 * radius, height: 2 * radius))
ctx.setStrokeColor(rgb(255, 255, 255, 0.38))
ctx.setLineWidth(9)
ctx.addArc(center: center, radius: radius - 19, startAngle: 1.65, endAngle: 2.65, clockwise: false)
ctx.strokePath()

guard let output = CommandLine.arguments.dropFirst().first,
      let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                         "public.png" as CFString, 1, nil) else {
    fatalError("Cannot create icon image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write icon") }
