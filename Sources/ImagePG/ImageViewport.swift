import Foundation

/// Shared geometry for drawing, annotation hit testing, zooming and panning.
struct ImageViewport {
    var imageSize: CGSize = .zero
    var bounds: CGRect = .zero
    private(set) var explicitScale: CGFloat?
    private(set) var offset: CGPoint = .zero

    var fitScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / imageSize.width, bounds.height / imageSize.height, 1)
    }
    var scale: CGFloat { explicitScale ?? fitScale }
    var minimumScale: CGFloat { min(0.01, fitScale) }
    let maximumScale: CGFloat = 16
    var imageRect: CGRect {
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2 + offset.x,
                      y: bounds.midY - size.height / 2 + offset.y,
                      width: size.width, height: size.height)
    }
    var canPan: Bool { imageRect.width > bounds.width || imageRect.height > bounds.height }

    mutating func fit() {
        explicitScale = nil
        offset = .zero
    }

    mutating func zoom(to requestedScale: CGFloat, anchor: CGPoint) {
        guard requestedScale.isFinite, imageSize.width > 0, imageSize.height > 0 else { return }
        let oldRect = imageRect
        let oldScale = scale
        explicitScale = max(minimumScale, min(maximumScale, requestedScale))
        let ratio = scale / oldScale
        offset = CGPoint(x: anchor.x - (anchor.x - oldRect.minX) * ratio - bounds.midX + imageSize.width * scale / 2,
                         y: anchor.y - (anchor.y - oldRect.minY) * ratio - bounds.midY + imageSize.height * scale / 2)
        constrainOffset()
    }

    mutating func pan(by delta: CGPoint) {
        offset.x += delta.x
        offset.y += delta.y
        constrainOffset()
    }

    mutating func constrainOffset() {
        let limitX = max(0, (imageSize.width * scale - bounds.width) / 2)
        let limitY = max(0, (imageSize.height * scale - bounds.height) / 2)
        offset.x = max(-limitX, min(limitX, offset.x))
        offset.y = max(-limitY, min(limitY, offset.y))
    }
}
