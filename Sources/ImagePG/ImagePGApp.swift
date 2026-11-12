import AppKit
import UniformTypeIdentifiers

final class ImagePGWindow: NSWindow {
    var pasteImage: (() -> Void)?

    @objc func paste(_ sender: Any?) { pasteImage?() }
}

final class ImageCanvasView: NSView {
    var image: CGImage? { didSet { refreshViewport() } }
    var fullImage: CGImage? { didSet { cancelCrop(); cancelColorPicking(); refreshViewport() } }
    private(set) var viewport = ImageViewport()
    var viewportChanged: (() -> Void)?
    /// Space kept around a fitted photo (the app sets it; checks use the bare canvas).
    var fitPadding: CGFloat {
        get { viewport.fitPadding }
        set { viewport.fitPadding = newValue; refreshViewport() }
    }
    var annotationsEnabled = false { didSet { if !annotationsEnabled { cancelColorPicking() }; invalidateCursor() } }
    private var panLast: CGPoint?
    private var spaceHeld = false
    var annotations: [Annotation] = [] { didSet { needsDisplay = true; annotationsChanged?() } }
    var selected: Annotation? { didSet { needsDisplay = true; selectionChanged?(selected) } }
    var tool: AnnotationTool = .select { didSet { cancelColorPicking(); invalidateCursor() } }
    private(set) var isPickingColor = false
    var colorPickingChanged: (() -> Void)?
    var colorPicked: (() -> Void)?
    var stroke: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var fill: NSColor? = nil
    var startArrow: ArrowStyle = .none
    var endArrow: ArrowStyle = .none
    var annotationText = "Text"
    var fontName = "Helvetica"
    var fontSize: CGFloat = 32
    var annotationsChanged: (() -> Void)?
    var selectionChanged: ((Annotation?) -> Void)?
    var openFile: ((URL) -> Void)?
    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var draggingHandle: Int?
    private var pendingTool: AnnotationTool?
    private var creating = false
    private(set) var cropSelection: ImageCrop?
    var isCropping: Bool { cropSelection != nil }
    var cropChanged: (() -> Void)?
    var cropRequested: ((CGRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvas.setFill()
        bounds.fill()
        guard let image else { return }
        guard let rect = imageRect else { return }
        // Only tile the visible region: a highly zoomed image can be enormous.
        let visible = rect.intersection(bounds)
        if !visible.isEmpty, let context = NSGraphicsContext.current?.cgContext {
            // Lift the photo off the canvas with a soft shadow.
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                              color: NSColor.black.withAlphaComponent(0.55).cgColor)
            NSColor.black.setFill()
            visible.fill()
            context.restoreGState()
        }
        let tile: CGFloat = 14
        NSColor(calibratedWhite: 0.8, alpha: 1).setFill()
        visible.fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        if !visible.isEmpty {
            for row in Int(floor(visible.minY / tile))..<Int(ceil(visible.maxY / tile)) {
                for column in Int(floor(visible.minX / tile))..<Int(ceil(visible.maxX / tile)) where (row + column).isMultiple(of: 2) {
                    CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                           width: tile, height: tile).intersection(visible).fill()
                }
            }
        }
        // Switch to the original as soon as the preview would lose detail on this display.
        let backingScale = window?.backingScaleFactor ?? 1
        let rendered = rect.width * backingScale > CGFloat(image.width) ? (fullImage ?? image) : image
        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        NSGraphicsContext.current?.cgContext.draw(rendered, in: rect)
        drawAnnotations(in: rect)
        drawCrop(in: rect)
    }

    private func drawAnnotations(in rect: CGRect) {
        guard let fullImage, !annotations.isEmpty else { return }
        let context = NSGraphicsContext.current!.cgContext
        let imageScaleX = rect.width / CGFloat(fullImage.width)
        let imageScaleY = rect.height / CGFloat(fullImage.height)
        let imageScale = min(imageScaleX, imageScaleY)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: imageScaleX, y: imageScaleY)
        for annotation in annotations { annotation.draw(in: context) }
        if let selected {
            context.saveGState()
            let box = selected.rect.insetBy(dx: -5 / imageScale, dy: -5 / imageScale)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.25 / imageScale)
            if selected.tool != .line { context.stroke(box) }
            for handle in selected.handles {
                let size = 10 / imageScale
                let dot = CGRect(x: handle.x - size / 2, y: handle.y - size / 2, width: size, height: size)
                context.setShadow(offset: CGSize(width: 0, height: -1 / imageScale), blur: 3 / imageScale,
                                  color: NSColor.black.withAlphaComponent(0.5).cgColor)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: dot)
                context.setShadow(offset: .zero, blur: 0)
                context.setLineWidth(1.5 / imageScale)
                context.strokeEllipse(in: dot)
            }
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawCrop(in imageRect: CGRect) {
        guard let selection = cropSelection, let rect = selection.rect else { return }
        let scale = viewport.scale
        let box = CGRect(x: imageRect.minX + rect.minX * scale,
                         y: imageRect.minY + rect.minY * scale,
                         width: rect.width * scale, height: rect.height * scale)
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.clip(to: imageRect.intersection(bounds))
        context.addRect(imageRect)
        context.addRect(box)
        context.setFillColor(NSColor.black.withAlphaComponent(0.62).cgColor)
        context.drawPath(using: .eoFill)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        for fraction: CGFloat in [1 / 3, 2 / 3] {
            context.move(to: CGPoint(x: box.minX + box.width * fraction, y: box.minY))
            context.addLine(to: CGPoint(x: box.minX + box.width * fraction, y: box.maxY))
            context.move(to: CGPoint(x: box.minX, y: box.minY + box.height * fraction))
            context.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * fraction))
        }
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.stroke(box)
        context.restoreGState()
        // Corner brackets instead of square handles; hit areas stay at the corners.
        let arm = min(22, box.width / 2, box.height / 2)
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(4)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        for handle in selection.handles {
            let point = CGPoint(x: imageRect.minX + handle.x * scale, y: imageRect.minY + handle.y * scale)
            let dx: CGFloat = point.x <= box.midX ? 1 : -1
            let dy: CGFloat = point.y <= box.midY ? 1 : -1
            context.move(to: CGPoint(x: point.x, y: point.y + arm * dy))
            context.addLine(to: point)
            context.addLine(to: CGPoint(x: point.x + arm * dx, y: point.y))
        }
        context.strokePath()
        context.restoreGState()
        drawBadge("\(Int(rect.width)) × \(Int(rect.height)) px", below: box)
    }

    /// Small dark label under (or, without room, inside) a selection.
    private func drawBadge(_ text: String, below box: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var badge = CGRect(x: box.midX - size.width / 2 - 9, y: box.minY - size.height - 18,
                           width: size.width + 18, height: size.height + 8)
        if badge.minY < 64 { badge.origin.y = box.minY + 10 }
        let path = NSBezierPath(roundedRect: badge, xRadius: 7, yRadius: 7)
        NSColor(white: 0.08, alpha: 0.85).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.15).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        text.draw(at: CGPoint(x: badge.minX + 9, y: badge.minY + 4), withAttributes: attributes)
    }

    func beginCrop() {
        guard let fullImage else { return }
        cancelColorPicking()
        selected = nil
        cropSelection = ImageCrop(imageSize: CGSize(width: fullImage.width, height: fullImage.height))
        window?.makeFirstResponder(self)
        cropDidChange()
    }

    func cancelCrop() {
        guard isCropping else { return }
        cropSelection = nil
        cropDidChange()
    }

    func applyCrop() {
        guard let selection = cropSelection, !selection.isDragging, let rect = selection.rect else { return }
        cropRequested?(rect)
    }

    private func cropDidChange() {
        needsDisplay = true
        invalidateCursor()
        cropChanged?()
    }

    private var imageRect: CGRect? {
        guard image != nil, viewport.imageSize.width > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        return viewport.imageRect
    }

    private func refreshViewport() {
        let source = fullImage ?? image
        viewport.imageSize = source.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        viewport.bounds = bounds
        viewport.constrainOffset()
        needsDisplay = true
        invalidateCursor()
        viewportChanged?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshViewport()
    }

    func fitToWindow() {
        viewport.fit()
        refreshViewport()
    }

    func zoom(to scale: CGFloat, anchor: CGPoint? = nil) {
        guard fullImage != nil, panLast == nil, dragStart == nil, cropSelection?.isDragging != true else { return }
        viewport.zoom(to: scale, anchor: anchor ?? CGPoint(x: bounds.midX, y: bounds.midY))
        refreshViewport()
    }

    func zoom(by factor: CGFloat, anchor: CGPoint? = nil) {
        zoom(to: viewport.scale * factor, anchor: anchor)
    }

    override func magnify(with event: NSEvent) {
        zoom(by: max(0.1, 1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
        zoom(by: exp(max(-1, min(1, event.scrollingDeltaY * sensitivity))),
             anchor: convert(event.locationInWindow, from: nil))
    }

    private func invalidateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        guard let rect = imageRect else { return }
        if (isPickingColor || isCropping) && !spaceHeld {
            addCursorRect(rect.intersection(bounds), cursor: .crosshair)
            return
        }
        guard viewport.canPan,
              !annotationsEnabled || tool == .select || spaceHeld else { return }
        addCursorRect(rect.intersection(bounds), cursor: panLast == nil ? .openHand : .closedHand)
    }

    private func beginPan(with event: NSEvent) {
        guard viewport.canPan else { return }
        panLast = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
        invalidateCursor()
    }

    private func imagePoint(_ event: NSEvent, clamped: Bool = false) -> CGPoint? {
        guard let rect = imageRect, let fullImage else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard clamped || rect.contains(point) else { return nil }
        return CGPoint(x: max(0, min(CGFloat(fullImage.width), (point.x - rect.minX) * CGFloat(fullImage.width) / rect.width)),
                       y: max(0, min(CGFloat(fullImage.height), (point.y - rect.minY) * CGFloat(fullImage.height) / rect.height)))
    }

    private var hitTolerance: CGFloat {
        guard let rect = imageRect, let fullImage else { return 8 }
        return 7 * CGFloat(fullImage.width) / rect.width
    }

    private func makeAnnotation(_ kind: AnnotationTool, at point: CGPoint) -> Annotation? {
        guard let rect = imageRect, let fullImage else { return nil }
        let extent = max(CGFloat(fullImage.width) / rect.width, CGFloat(fullImage.height) / rect.height)
        return Annotation(tool: kind, point: point, stroke: stroke, width: lineWidth,
                          fill: fill, startArrow: startArrow, endArrow: endArrow,
                          text: annotationText, fontName: fontName, fontSize: fontSize,
                          arrowLength: 20 * extent)
    }

    func beginColorPicking() {
        guard !isCropping, annotationsEnabled, fullImage != nil, (selected?.tool ?? tool) != .select else { return }
        window?.makeFirstResponder(self)
        isPickingColor = true
        invalidateCursor()
        colorPickingChanged?()
    }

    func cancelColorPicking() {
        guard isPickingColor else { return }
        isPickingColor = false
        invalidateCursor()
        colorPickingChanged?()
    }

    private func pickColor(at point: CGPoint) {
        guard let color = sampledColor(at: point) else { return }
        let active = selected?.tool ?? tool
        stroke = color
        if active == .rectangle || active == .ellipse { fill = color }
        if let selected {
            selected.stroke = color
            if active == .rectangle || active == .ellipse { selected.fill = color }
            needsDisplay = true
            annotationsChanged?()
        }
        cancelColorPicking()
        colorPicked?()
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = imagePoint(event), fullImage != nil else { return }
        window?.makeFirstResponder(self)
        if isCropping && !spaceHeld {
            cropSelection?.begin(at: point, tolerance: hitTolerance)
            cropDidChange()
            return
        }
        if !annotationsEnabled || spaceHeld {
            beginPan(with: event)
            return
        }
        if isPickingColor {
            pickColor(at: point)
            return
        }
        dragStart = point
        dragLast = point
        creating = false
        draggingHandle = nil
        pendingTool = nil
        if let selected, let index = selected.handles.firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) <= hitTolerance }) {
            draggingHandle = index
            return
        }
        if let hit = annotations.reversed().first(where: { $0.contains(point, tolerance: hitTolerance) }) {
            selected = hit
            return
        }
        selected = nil
        guard tool != .select else {
            dragStart = nil
            dragLast = nil
            beginPan(with: event)
            return
        }
        if tool == .text {
            guard let annotation = makeAnnotation(.text, at: point) else { return }
            annotations.append(annotation)
            selected = annotation
            return
        }
        pendingTool = tool
    }

    override func mouseDragged(with event: NSEvent) {
        if let last = panLast {
            let point = convert(event.locationInWindow, from: nil)
            viewport.pan(by: CGPoint(x: point.x - last.x, y: point.y - last.y))
            panLast = point
            needsDisplay = true
            return
        }
        if isCropping, let point = imagePoint(event, clamped: true) {
            cropSelection?.drag(to: point, square: event.modifierFlags.contains(.shift))
            cropDidChange()
            return
        }
        guard let start = dragStart, let last = dragLast,
              let point = imagePoint(event, clamped: true) else { return }
        if let pendingTool {
            guard hypot(point.x - start.x, point.y - start.y) >= hitTolerance / 2 else { return }
            guard let annotation = makeAnnotation(pendingTool, at: start) else { return }
            if pendingTool == .pen { annotation.points = [start] }
            annotations.append(annotation)
            selected = annotation
            creating = true
            self.pendingTool = nil
        }
        guard let selected else { return }
        if creating {
            if selected.tool == .pen { selected.points.append(point) }
            else {
                var end = point
                if event.modifierFlags.contains(.shift), selected.tool == .rectangle || selected.tool == .ellipse {
                    let length = max(abs(point.x - start.x), abs(point.y - start.y))
                    end = CGPoint(x: start.x + (point.x < start.x ? -length : length),
                                  y: start.y + (point.y < start.y ? -length : length))
                }
                selected.points[1] = end
            }
        } else if let handle = draggingHandle {
            if selected.tool == .line { selected.points[handle] = point }
            else if selected.tool == .rectangle || selected.tool == .ellipse {
                let opposite = selected.handles[3 - handle]
                var end = point
                if event.modifierFlags.contains(.shift) {
                    let length = max(abs(point.x - opposite.x), abs(point.y - opposite.y))
                    end = CGPoint(x: opposite.x + (point.x < opposite.x ? -length : length),
                                  y: opposite.y + (point.y < opposite.y ? -length : length))
                }
                selected.points = [opposite, end]
            }
        } else {
            selected.move(by: CGPoint(x: point.x - last.x, y: point.y - last.y))
        }
        dragLast = point
        needsDisplay = true
        annotationsChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        if cropSelection?.isDragging == true {
            cropSelection?.end()
            cropDidChange()
        }
        panLast = nil
        invalidateCursor()
        dragStart = nil
        dragLast = nil
        draggingHandle = nil
        pendingTool = nil
        creating = false
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && isCropping {
            cancelCrop()
        } else if (event.keyCode == 36 || event.keyCode == 76) && isCropping {
            applyCrop()
        } else if isCropping && (event.keyCode == 51 || event.keyCode == 117) {
            return
        } else if event.keyCode == 53 && isPickingColor {
            cancelColorPicking()
        } else if event.keyCode == 49 {
            spaceHeld = true
            invalidateCursor()
        } else if event.keyCode == 51 || event.keyCode == 117 {
            if let selected {
                annotations.removeAll { $0 === selected }
                self.selected = nil
            }
        } else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            invalidateCursor()
        } else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        cropSelection?.end()
        cancelColorPicking()
        spaceHeld = false
        panLast = nil
        dragStart = nil
        dragLast = nil
        pendingTool = nil
        draggingHandle = nil
        creating = false
        invalidateCursor()
        return super.resignFirstResponder()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL?,
              ImageProcessing.canRead(url.pathExtension) else { return [] }
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL?,
              ImageProcessing.canRead(url.pathExtension) else { return false }
        openFile?(url)
        return true
    }
}

final class ImagePGAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSTextFieldDelegate, NSMenuItemValidation {
    private var window: ImagePGWindow!
    private var canvas: ImageCanvasView!
    private var statusHUD: HUDView!
    private var status: NSTextField!
    private var cropBar: HUDView!
    private var cropLabel: NSTextField!
    private var cropApplyButton: NSButton!
    private var emptyState: EmptyStateView!
    private var annotationPanel: NSScrollView!
    private var panelEdge: NSView!
    private var panelWidth: NSLayoutConstraint!
    private var toolSegments: NSSegmentedControl!
    private var toolNameLabel: NSTextField!
    private var swatches: [SwatchButton] = []
    private var strokeTitle: NSTextField!
    private var strokeWell: NSColorWell!
    private var eyedropperButton: NSButton!
    private var fillWell: NSColorWell!
    private var fillMode: NSSegmentedControl!
    private var widthField: NSTextField!
    private var widthSlider: NSSlider!
    private var widthPreview: LineWidthPreviewView!
    private var startSegments: NSSegmentedControl!
    private var endSegments: NSSegmentedControl!
    private var fontPicker: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var textField: NSTextField!
    private var annotationHint: NSTextField!
    private var textGroup: NSStackView!
    private var strokeGroup: NSStackView!
    private var widthGroup: NSStackView!
    private var fillGroup: NSStackView!
    private var arrowGroup: NSStackView!
    private var fontGroup: NSStackView!
    private var updatingAnnotationControls = false
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var modesGroup: NSToolbarItemGroup!
    private var zoomLabel: NSTextField!
    private var imageURL: URL?
    private var image: CGImage?
    private var preview: CGImage?
    private var folderImages: [URL] = []
    private var isDirty = false
    private var isProcessing = false
    private var loadGeneration = 0
    private let loadQueue = OperationQueue()
    private let prefetchQueue = OperationQueue()
    private let folderQueue = OperationQueue()
    private let previewCache = NSCache<NSString, NSImage>()
    private var keyMonitor: Any?
    private var pendingOpenURL: URL?
    /// Building the window can spin the run loop; files that arrive meanwhile wait for launch to finish.
    private var didFinishLaunching = false
    private var settingsController: SettingsWindowController?
    private var relaunchOnQuit = false
    static let repositoryURL = URL(string: "https://github.com/html-koder-com/imagepg")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadQueue.maxConcurrentOperationCount = 1
        loadQueue.qualityOfService = .userInitiated
        prefetchQueue.maxConcurrentOperationCount = 2
        prefetchQueue.qualityOfService = .utility
        folderQueue.maxConcurrentOperationCount = 1
        folderQueue.qualityOfService = .userInitiated
        previewCache.countLimit = 8
        makeWindow()
        makeMenu()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow, !(self.window.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            switch event.keyCode {
            case 123: self.previousImage(nil); return nil
            case 124: self.nextImage(nil); return nil
            default: break
            }
            if let text = event.charactersIgnoringModifiers?.lowercased() {
                if text == "l" { self.rotateLeft(nil); return nil }
                if text == "r" { self.rotateRight(nil); return nil }
            }
            return event
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        didFinishLaunching = true
        if let pendingOpenURL {
            self.pendingOpenURL = nil
            open(pendingOpenURL)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        // Settings → Restart Now: start a fresh instance once this one has really decided to quit.
        if relaunchOnQuit, Bundle.main.bundleURL.pathExtension == "app" {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-n", Bundle.main.bundlePath]
            try? open.run()
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.restart = { [weak self] in
                guard let self else { return }
                self.relaunchOnQuit = true
                NSApp.terminate(nil)
                // Quitting can be cancelled (unsaved changes); then do not relaunch later.
                self.relaunchOnQuit = false
            }
            settingsController = controller
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: 11)
        let credits = NSMutableAttributedString(string: L("Free and open source (MIT License)") + "\n", attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph
        ])
        credits.append(NSAttributedString(string: L("ImagePG on GitHub"), attributes: [
            .font: font, .link: Self.repositoryURL, .paragraphStyle: paragraph
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isProcessing else { showError(L("Please wait until the image edit finishes.")); return .terminateCancel }
        return confirmDiscardOrSave() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            let url = URL(fileURLWithPath: first)
            if !didFinishLaunching {
                pendingOpenURL = url
            } else {
                open(url)
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isProcessing else { showError(L("Please wait until the image edit finishes.")); return false }
        guard confirmDiscardOrSave() else { return false }
        // Closing the last window also terminates the app; avoid asking twice after Discard.
        isDirty = false
        return true
    }

    private func makeWindow() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        window = ImagePGWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.pasteImage = { [weak self] in self?.pasteImage(nil) }
        window.title = "ImagePG"
        window.backgroundColor = Theme.canvas
        window.center()
        window.setFrameAutosaveName("ImagePG.MainWindow")
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 480)
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.canvas.cgColor
        window.contentView = content
        canvas = ImageCanvasView(frame: .zero)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.fitPadding = 44
        canvas.openFile = { [weak self] url in self?.open(url) }
        canvas.annotationsChanged = { [weak self] in
            self?.isDirty = true
            self?.updateUI()
        }
        canvas.selectionChanged = { [weak self] _ in self?.syncAnnotationControls() }
        canvas.colorPickingChanged = { [weak self] in self?.updateAnnotationControlsVisibility() }
        canvas.colorPicked = { [weak self] in self?.syncAnnotationControls() }
        makeAnnotationPanel()
        makeCropBar()
        makeStatus()
        makeEmptyState()
        panelEdge = NSView()
        panelEdge.wantsLayer = true
        panelEdge.layer?.backgroundColor = NSColor.black.cgColor
        panelEdge.translatesAutoresizingMaskIntoConstraints = false
        panelEdge.isHidden = true
        content.addSubview(canvas)
        content.addSubview(annotationPanel)
        content.addSubview(panelEdge)
        content.addSubview(statusHUD)
        content.addSubview(cropBar)
        panelWidth = annotationPanel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: annotationPanel.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            annotationPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            annotationPanel.topAnchor.constraint(equalTo: content.topAnchor),
            annotationPanel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panelWidth,
            panelEdge.trailingAnchor.constraint(equalTo: annotationPanel.leadingAnchor),
            panelEdge.topAnchor.constraint(equalTo: content.topAnchor),
            panelEdge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panelEdge.widthAnchor.constraint(equalToConstant: 1),
            statusHUD.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            statusHUD.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -14),
            statusHUD.heightAnchor.constraint(equalToConstant: 30),
            statusHUD.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -32),
            cropBar.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            cropBar.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -14),
            cropBar.heightAnchor.constraint(equalToConstant: 44),
            cropBar.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -32),
            emptyState.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: canvas.centerYAnchor)
        ])
        canvas.viewportChanged = { [weak self] in self?.updateUI() }
        canvas.cropChanged = { [weak self] in self?.updateCropControls() }
        canvas.cropRequested = { [weak self] rect in self?.performCrop(rect) }
        let toolbar = NSToolbar(identifier: "ImagePG.MainToolbar.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        updateUI()
    }

    private func makeStatus() {
        statusHUD = HUDView(radius: 15)
        status = NSTextField(labelWithString: "")
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusHUD.stack.addArrangedSubview(status)
        statusHUD.pin(insets: NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
    }

    /// First part reads as the headline, the rest as quieter metadata.
    private func statusText(_ parts: [String]) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "   ·   ", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
            }
            result.append(NSAttributedString(string: part, attributes: [
                .font: index == 0 ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium) : font,
                .foregroundColor: index == 0 ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]))
        }
        return result
    }

    private func makeEmptyState() {
        let open = NSButton(title: L("Open…"), target: self, action: #selector(openDialog(_:)))
        open.attributedTitle = Theme.buttonTitle(L("Open…"), key: "⌘O", color: .white)
        open.image = Theme.symbol("folder", L("Open"), size: 13)
        open.imagePosition = .imageLeading
        open.bezelColor = .controlAccentColor
        open.controlSize = .large
        let paste = NSButton(title: L("Paste from clipboard"), target: self, action: #selector(pasteFromButton(_:)))
        paste.attributedTitle = Theme.buttonTitle(L("Paste from clipboard"), key: "⌘V")
        paste.controlSize = .large
        emptyState = EmptyStateView(open: open, paste: paste)
        canvas.addSubview(emptyState)
    }

    @objc private func pasteFromButton(_ sender: Any?) { pasteImage(nil) }

    private func makeCropBar() {
        cropBar = HUDView(radius: 14)
        cropBar.isHidden = true
        let title = NSTextField(labelWithString: L("Crop mode"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        cropLabel = NSTextField(labelWithString: L("Drag to select an area"))
        cropLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        cropLabel.textColor = .secondaryLabelColor
        cropLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cropLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cropLabel.lineBreakMode = .byTruncatingTail
        cropLabel.toolTip = L("Drag to select the area to keep. Drag inside to move it, drag the corners to resize. Shift keeps a square; hold Space to pan the image.")
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelCrop(_:)))
        cancel.attributedTitle = Theme.buttonTitle(L("Cancel"), key: "Esc")
        cropApplyButton = NSButton(title: L("Crop"), target: self, action: #selector(applyCrop(_:)))
        cropApplyButton.image = Theme.symbol("crop", L("Crop"), size: 12)
        cropApplyButton.imagePosition = .imageLeading
        cropApplyButton.bezelColor = .controlAccentColor
        [title, cropLabel, cancel, cropApplyButton].forEach { cropBar.stack.addArrangedSubview($0) }
        cropBar.stack.setCustomSpacing(18, after: cropLabel)
        cropBar.stack.setCustomSpacing(8, after: cancel)
        cropBar.pin(insets: NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 7))
    }

    private func updateCropControls() {
        cropBar.isHidden = !canvas.isCropping
        if let rect = canvas.cropSelection?.rect {
            cropLabel.stringValue = L("Selection %d × %d px", Int(rect.width), Int(rect.height)) + "   ·   " + L("Shift keeps a square")
        } else {
            cropLabel.stringValue = L("Drag to select an area") + "   ·   " + L("Shift keeps a square")
        }
        let enabled = canvas.cropSelection?.rect != nil && canvas.cropSelection?.isDragging != true
        cropApplyButton.isEnabled = enabled
        cropApplyButton.attributedTitle = Theme.buttonTitle(L("Crop"), key: "↵", color: enabled ? .white : .tertiaryLabelColor)
        updateUI()
    }

    @objc private func toggleCrop(_ sender: Any?) {
        guard image != nil, !isProcessing else { return }
        if canvas.isCropping { canvas.cancelCrop(); return }
        commitCurrentEditing()
        if canvas.annotationsEnabled { toggleAnnotations(nil) }
        canvas.beginCrop()
    }

    @objc private func cancelCrop(_ sender: Any?) { canvas.cancelCrop() }
    @objc private func applyCrop(_ sender: Any?) { canvas.applyCrop() }

    private func performCrop(_ rect: CGRect) {
        guard let image, !isProcessing else { return }
        canvas.cancelCrop()
        guard rect != CGRect(x: 0, y: 0, width: image.width, height: image.height) else { return }
        edit(fitResult: true) { ImageProcessing.cropped($0, rect: rect) }
    }

    private func makeAnnotationPanel() {
        let contentWidth: CGFloat = 248
        annotationPanel = NSScrollView()
        annotationPanel.translatesAutoresizingMaskIntoConstraints = false
        annotationPanel.hasVerticalScroller = true
        annotationPanel.autohidesScrollers = true
        annotationPanel.borderType = .noBorder
        annotationPanel.drawsBackground = true
        annotationPanel.backgroundColor = Theme.panel
        annotationPanel.isHidden = true
        let stack = AnnotationPanelStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        func section(_ title: String?) -> (NSStackView, NSTextField?) {
            let section = NSStackView()
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = 10
            section.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
            let line = NSBox()
            line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            section.addArrangedSubview(line)
            line.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            section.setCustomSpacing(14, after: line)
            var label: NSTextField?
            if let title {
                label = Theme.sectionTitle(title)
                section.addArrangedSubview(label!)
            }
            stack.addArrangedSubview(section)
            return (section, label)
        }
        func sized(_ view: NSView, _ width: CGFloat) -> NSView {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
            return view
        }
        func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = spacing
            return row
        }
        func label(_ text: String, width: CGFloat? = nil) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 12)
            field.textColor = .secondaryLabelColor
            if let width { _ = sized(field, width) }
            return field
        }

        let title = NSTextField(labelWithString: L("Annotations"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(12, after: title)
        let symbols = ["cursorarrow", "scribble.variable", "line.diagonal", "oval", "rectangle", "textformat"]
        let images = zip(symbols, AnnotationTool.allCases).map { Theme.symbol($0.0, $0.1.title, size: 14) ?? NSImage() }
        toolSegments = NSSegmentedControl(images: images, trackingMode: .selectOne,
                                          target: self, action: #selector(annotationToolChanged(_:)))
        toolSegments.segmentDistribution = .fillEqually
        toolSegments.controlSize = .large
        for (index, tool) in AnnotationTool.allCases.enumerated() { toolSegments.setToolTip(tool.title, forSegment: index) }
        toolSegments.selectedSegment = 0
        stack.addArrangedSubview(sized(toolSegments, contentWidth))
        stack.setCustomSpacing(8, after: toolSegments)
        toolNameLabel = label(L("Tool: %@", AnnotationTool.select.title))
        toolNameLabel.font = .systemFont(ofSize: 11)
        toolNameLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(toolNameLabel)
        stack.setCustomSpacing(14, after: toolNameLabel)

        (textGroup, _) = section(L("Text"))
        textField = NSTextField(string: "Text")
        textField.placeholderString = L("Annotation text")
        textField.delegate = self
        textGroup.addArrangedSubview(sized(textField, contentWidth))

        let stroke = section(L("Color"))
        strokeGroup = stroke.0
        strokeTitle = stroke.1
        swatches = Theme.swatches.map { SwatchButton(color: $0.0, name: $0.1, target: self, action: #selector(swatchChosen(_:))) }
        strokeGroup.addArrangedSubview(row(swatches, spacing: 6))
        strokeWell = NSColorWell(style: .minimal)
        strokeWell.color = canvas.stroke
        strokeWell.target = self; strokeWell.action = #selector(annotationStyleChanged(_:))
        strokeWell.toolTip = L("Custom color")
        eyedropperButton = NSButton(image: Theme.symbol("eyedropper", L("Eyedropper"), size: 13) ?? NSImage(),
                                    target: self, action: #selector(toggleColorPicking(_:)))
        eyedropperButton.setButtonType(.pushOnPushOff)
        eyedropperButton.toolTip = L("Eyedropper – click the image to pick a color. For rectangles and ellipses it sets both fill and outline. Esc cancels.")
        strokeGroup.addArrangedSubview(row([sized(strokeWell, 52), eyedropperButton, label(L("Custom color"))]))

        (widthGroup, _) = section(L("Width"))
        widthSlider = NSSlider(value: 4, minValue: 0.5, maxValue: 50,
                               target: self, action: #selector(annotationWidthSliderChanged(_:)))
        widthSlider.isContinuous = true
        widthField = NSTextField(string: "4")
        widthField.delegate = self
        widthField.alignment = .right
        widthGroup.addArrangedSubview(row([sized(widthSlider, 152), sized(widthField, 56), label("px")]))
        widthPreview = LineWidthPreviewView()
        widthPreview.color = canvas.stroke
        widthPreview.translatesAutoresizingMaskIntoConstraints = false
        widthPreview.heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthGroup.addArrangedSubview(sized(widthPreview, contentWidth))

        (fillGroup, _) = section(L("Fill"))
        fillMode = NSSegmentedControl(labels: [L("None"), L("Color")], trackingMode: .selectOne,
                                      target: self, action: #selector(annotationStyleChanged(_:)))
        fillMode.segmentDistribution = .fillEqually
        fillMode.selectedSegment = 0
        fillWell = NSColorWell(style: .minimal)
        fillWell.color = .systemYellow
        fillWell.isEnabled = false
        fillWell.target = self; fillWell.action = #selector(annotationStyleChanged(_:))
        fillGroup.addArrangedSubview(row([sized(fillMode, 150), sized(fillWell, 52)]))
        fillGroup.addArrangedSubview(sized(Theme.caption(L("Pick the surrounding color with the eyedropper – fill and outline both use it, so you can cover part of the image.")), contentWidth))

        (arrowGroup, _) = section(L("Line ends"))
        startSegments = NSSegmentedControl(images: ArrowStyle.allCases.map { Theme.arrowImage($0, mirrored: true) },
                                           trackingMode: .selectOne, target: self, action: #selector(annotationStyleChanged(_:)))
        endSegments = NSSegmentedControl(images: ArrowStyle.allCases.map { Theme.arrowImage($0, mirrored: false) },
                                         trackingMode: .selectOne, target: self, action: #selector(annotationStyleChanged(_:)))
        for control in [startSegments!, endSegments!] {
            control.segmentDistribution = .fillEqually
            control.selectedSegment = 0
            for style in ArrowStyle.allCases { control.setToolTip(style.title, forSegment: style.rawValue) }
        }
        arrowGroup.addArrangedSubview(row([label(L("Start"), width: 72), sized(startSegments, contentWidth - 80)]))
        arrowGroup.addArrangedSubview(row([label(L("End"), width: 72), sized(endSegments, contentWidth - 80)]))

        (fontGroup, _) = section(L("Font"))
        fontPicker = NSPopUpButton()
        fontPicker.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPicker.selectItem(withTitle: "Helvetica")
        fontPicker.target = self; fontPicker.action = #selector(annotationStyleChanged(_:))
        fontGroup.addArrangedSubview(sized(fontPicker, contentWidth))
        fontSizeField = NSTextField(string: "32")
        fontSizeField.delegate = self
        fontSizeField.alignment = .right
        fontGroup.addArrangedSubview(row([label(L("Size"), width: 72), sized(fontSizeField, 64), label("px")]))

        let (hintGroup, _) = section(nil)
        annotationHint = Theme.caption("")
        hintGroup.addArrangedSubview(sized(annotationHint, contentWidth))

        annotationPanel.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: annotationPanel.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: annotationPanel.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: annotationPanel.contentView.topAnchor)
        ])
        updateAnnotationControlsVisibility()
    }

    @objc private func toggleAnnotations(_ sender: Any?) {
        guard !canvas.isCropping, !isProcessing else { updateUI(); return }
        let showing = annotationPanel.isHidden
        annotationPanel.isHidden = !showing
        panelEdge.isHidden = !showing
        canvas.annotationsEnabled = showing
        panelWidth.constant = showing ? 280 : 0
        if showing { syncAnnotationControls() }
        window.contentView?.layoutSubtreeIfNeeded()
        updateUI()
    }

    @objc private func annotationToolChanged(_ sender: Any?) {
        canvas.tool = AnnotationTool(rawValue: toolSegments.selectedSegment) ?? .select
        canvas.selected = nil
        updateAnnotationControlsVisibility()
    }

    @objc private func annotationStyleChanged(_ sender: Any?) { applyAnnotationControls() }

    @objc private func swatchChosen(_ sender: SwatchButton) {
        strokeWell.color = sender.color
        applyAnnotationControls()
    }

    @objc private func toggleColorPicking(_ sender: Any?) {
        if canvas.isPickingColor { canvas.cancelColorPicking() }
        else {
            strokeWell.deactivate()
            fillWell.deactivate()
            canvas.beginColorPicking()
        }
        updateAnnotationControlsVisibility()
    }

    @objc private func annotationWidthSliderChanged(_ sender: Any?) {
        widthField.stringValue = String(format: "%.1f", widthSlider.doubleValue)
        applyAnnotationControls()
    }

    func controlTextDidEndEditing(_ obj: Notification) { applyAnnotationControls() }

    private func updateSwatchSelection() {
        for swatch in swatches { swatch.isChosen = Theme.isSame(swatch.color, strokeWell.color) }
    }

    private func updateAnnotationControlsVisibility() {
        let active = canvas.selected?.tool ?? canvas.tool
        toolNameLabel.stringValue = canvas.selected != nil ? L("Selected object: %@", active.title) : L("Tool: %@", canvas.tool.title)
        textGroup.isHidden = active != .text
        strokeGroup.isHidden = active == .select
        let strokeName = active == .text ? L("Text color") : (active == .rectangle || active == .ellipse) ? L("Outline") : L("Color")
        strokeTitle?.stringValue = strokeName.uppercased()
        widthGroup.isHidden = active == .select || active == .text
        fillGroup.isHidden = active != .ellipse && active != .rectangle
        arrowGroup.isHidden = active != .line
        fontGroup.isHidden = active != .text
        eyedropperButton.state = canvas.isPickingColor ? .on : .off
        eyedropperButton.contentTintColor = canvas.isPickingColor ? .controlAccentColor : nil
        annotationHint.stringValue = canvas.isPickingColor
            ? L("Click a color in the image. For rectangles and ellipses the eyedropper sets both fill and outline. Esc cancels.")
            : active == .text
            ? L("Click to place text. Drag selected text to move it or edit it in the panel. Delete removes it.")
            : L("Drag to create an object, click to select it. Handles change its shape. Shift keeps a circle or square. Delete removes the selection. Hold Space to pan the image.")
        updateSwatchSelection()
    }

    private func applyAnnotationControls() {
        guard !updatingAnnotationControls else { return }
        canvas.stroke = strokeWell.color
        canvas.lineWidth = max(0.5, min(500, CGFloat(Double(widthField.stringValue) ?? 4)))
        widthField.stringValue = String(format: "%.1f", canvas.lineWidth)
        widthSlider.doubleValue = min(50, Double(canvas.lineWidth))
        widthPreview.lineWidth = canvas.lineWidth
        widthPreview.color = canvas.stroke
        canvas.fill = fillMode.selectedSegment == 0 ? nil : fillWell.color
        fillWell.isEnabled = fillMode.selectedSegment == 1
        canvas.startArrow = ArrowStyle(rawValue: startSegments.selectedSegment) ?? .none
        canvas.endArrow = ArrowStyle(rawValue: endSegments.selectedSegment) ?? .none
        canvas.fontName = fontPicker.titleOfSelectedItem ?? "Helvetica"
        canvas.fontSize = max(1, min(1000, CGFloat(Double(fontSizeField.stringValue) ?? 32)))
        canvas.annotationText = textField.stringValue
        if let selected = canvas.selected {
            selected.stroke = canvas.stroke
            selected.width = canvas.lineWidth
            selected.fill = canvas.fill
            selected.startArrow = canvas.startArrow
            selected.endArrow = canvas.endArrow
            selected.fontName = canvas.fontName
            selected.fontSize = canvas.fontSize
            selected.text = canvas.annotationText
            canvas.needsDisplay = true
            canvas.annotationsChanged?()
        }
        updateSwatchSelection()
    }

    private func syncAnnotationControls() {
        guard toolSegments != nil else { return }
        updatingAnnotationControls = true
        defer { updatingAnnotationControls = false }
        let item = canvas.selected
        strokeWell.color = item?.stroke ?? canvas.stroke
        widthField.stringValue = String(format: "%.1f", item?.width ?? canvas.lineWidth)
        widthSlider.doubleValue = min(50, Double(item?.width ?? canvas.lineWidth))
        widthPreview.lineWidth = item?.width ?? canvas.lineWidth
        widthPreview.color = item?.stroke ?? canvas.stroke
        let selectedFill = item == nil ? canvas.fill : item?.fill
        fillMode.selectedSegment = selectedFill == nil ? 0 : 1
        fillWell.color = selectedFill ?? .systemYellow
        fillWell.isEnabled = selectedFill != nil
        startSegments.selectedSegment = (item?.startArrow ?? canvas.startArrow).rawValue
        endSegments.selectedSegment = (item?.endArrow ?? canvas.endArrow).rawValue
        fontPicker.selectItem(withTitle: item?.fontName ?? canvas.fontName)
        fontSizeField.stringValue = String(format: "%.0f", item?.fontSize ?? canvas.fontSize)
        textField.stringValue = item?.text ?? canvas.annotationText
        updateAnnotationControlsVisibility()
    }

    private func makeMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        menu(appMenu, L("About ImagePG"), #selector(showAbout(_:)), "")
        appMenu.addItem(.separator())
        menu(appMenu, L("Settings…"), #selector(showSettings(_:)), ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit ImagePG"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(title: L("File"), action: nil, keyEquivalent: "")
        main.addItem(fileItem)
        let file = NSMenu(title: L("File"))
        fileItem.submenu = file
        menu(file, L("Open…"), #selector(openDialog(_:)), "o")
        menu(file, L("Save"), #selector(save(_:)), "s")
        let saveAs = menu(file, L("Save As…"), #selector(saveAs(_:)), "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        menu(file, L("Print…"), #selector(printImage(_:)), "p")
        let controlPrint = menu(file, L("Print…"), #selector(printImage(_:)), "p")
        controlPrint.keyEquivalentModifierMask = [.control]
        controlPrint.isHidden = true
        controlPrint.allowsKeyEquivalentWhenHidden = true
        let editItem = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        main.addItem(editItem)
        let edit = NSMenu(title: L("Edit"))
        editItem.submenu = edit
        edit.addItem(withTitle: L("Paste Image from Clipboard"), action: #selector(ImagePGWindow.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        menu(edit, L("Rotate Left 90°"), #selector(rotateLeft(_:)), "")
        menu(edit, L("Rotate Right 90°"), #selector(rotateRight(_:)), "")
        menu(edit, L("Rotate by Angle…"), #selector(rotateAngle(_:)), "")
        edit.addItem(.separator())
        menu(edit, L("Resize Image…"), #selector(resize(_:)), "r")
        menu(edit, L("Crop / Selection"), #selector(toggleCrop(_:)), "k")
        menu(edit, L("Apply Crop"), #selector(applyCrop(_:)), "")
        menu(edit, L("Cancel Crop"), #selector(cancelCrop(_:)), "")
        let canvasSize = menu(edit, L("Canvas Size…"), #selector(changeCanvas(_:)), "p")
        canvasSize.keyEquivalentModifierMask = [.command, .shift]
        let viewItem = NSMenuItem(title: L("View"), action: nil, keyEquivalent: "")
        main.addItem(viewItem)
        let view = NSMenu(title: L("View"))
        viewItem.submenu = view
        menu(view, L("Zoom In"), #selector(zoomIn(_:)), "+")
        let zoomInAlias = menu(view, L("Zoom In"), #selector(zoomIn(_:)), "=")
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        menu(view, L("Zoom Out"), #selector(zoomOut(_:)), "-")
        menu(view, L("Fit to Window"), #selector(fitImage(_:)), "0")
        menu(view, L("Actual Size (100 %)"), #selector(actualSize(_:)), "1")
        view.addItem(.separator())
        menu(view, L("Previous Image"), #selector(previousImage(_:)), "")
        menu(view, L("Next Image"), #selector(nextImage(_:)), "")
    }

    @discardableResult
    private func menu(_ parent: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        parent.addItem(item)
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("navigation"), .flexibleSpace, .init("rotate"), .init("transform"), .init("modes"),
         .flexibleSpace, .init("zoomLabel"), .init("zoom"), .init("open"), .init("save")]
    }

    private func makeItem(_ name: String, _ label: String, _ symbol: String, _ action: Selector,
                          image: NSImage? = nil) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .init(name))
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = image ?? NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.autovalidates = false
        toolbarItems[item.itemIdentifier] = item
        return item
    }

    private func makeGroup(_ name: String, _ label: String, _ items: [NSToolbarItem]) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: .init(name))
        group.label = label
        group.paletteLabel = label
        group.subitems = items
        group.autovalidates = false
        return group
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier.rawValue {
        case "navigation":
            return makeGroup("navigation", L("Browse"), [
                makeItem("previous", L("Previous (←)"), "chevron.left", #selector(previousImage(_:))),
                makeItem("next", L("Next (→)"), "chevron.right", #selector(nextImage(_:)))])
        case "rotate":
            return makeGroup("rotate", L("Rotate"), [
                makeItem("left", L("Rotate left (L)"), "rotate.left", #selector(rotateLeft(_:))),
                makeItem("right", L("Rotate right (R)"), "rotate.right", #selector(rotateRight(_:)))])
        case "transform":
            return makeGroup("transform", L("Dimensions"), [
                makeItem("resize", L("Resize image (⌘R)"), "", #selector(resize(_:)), image: ToolbarImages.resize),
                makeItem("canvas", L("Canvas size (⇧⌘P)"), "rectangle.dashed", #selector(changeCanvas(_:)))])
        case "modes":
            let labels = [L("Crop (⌘K)"), L("Annotations")]
            let images = [NSImage(systemSymbolName: "crop", accessibilityDescription: labels[0]) ?? NSImage(),
                          NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: labels[1]) ?? NSImage()]
            let group = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .selectAny,
                                           labels: labels, target: self, action: #selector(modeChanged(_:)))
            group.label = L("Mode")
            group.paletteLabel = L("Mode")
            group.controlRepresentation = .expanded
            group.autovalidates = false
            for (index, item) in group.subitems.enumerated() { item.toolTip = labels[index] }
            modesGroup = group
            return group
        case "zoomLabel":
            zoomLabel = NSTextField(labelWithString: "—")
            zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            zoomLabel.alignment = .center
            zoomLabel.translatesAutoresizingMaskIntoConstraints = false
            zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
            let label = NSToolbarItem(itemIdentifier: .init("zoomLabel"))
            label.view = zoomLabel
            label.label = L("Zoom")
            label.toolTip = L("Current zoom")
            return label
        case "zoom":
            return makeGroup("zoom", L("Zoom"), [
                makeItem("zoomOut", L("Zoom out (⌘−)"), "minus", #selector(zoomOut(_:))),
                makeItem("zoomIn", L("Zoom in (⌘+)"), "plus", #selector(zoomIn(_:))),
                makeItem("fit", L("Fit to window (⌘0)"), "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", #selector(fitImage(_:))),
                makeItem("actual", L("Actual size — 100 % (⌘1)"), "1.magnifyingglass", #selector(actualSize(_:)))])
        case "open":
            return makeItem("open", L("Open (⌘O)"), "folder", #selector(openDialog(_:)))
        case "save":
            let item = makeItem("save", L("Save (⌘S)"), "square.and.arrow.down", #selector(save(_:)))
            if #available(macOS 26.0, *) {
                item.style = .prominent
                item.backgroundTintColor = .controlAccentColor
            }
            return item
        default:
            return nil
        }
    }

    @objc private func modeChanged(_ sender: Any?) {
        guard let modesGroup else { return }
        if modesGroup.isSelected(at: 0) != canvas.isCropping { toggleCrop(nil) }
        else if modesGroup.isSelected(at: 1) != canvas.annotationsEnabled { toggleAnnotations(nil) }
        updateUI()
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let name = item.itemIdentifier.rawValue
        if name == "open" { return !isProcessing }
        if name == "previous" || name == "next" {
            return folderImages.count > 1 && !isProcessing && !canvas.isCropping
        }
        let availableDuringCrop = ["zoomOut", "zoomIn", "fit", "actual"].contains(name)
        return image != nil && !isProcessing && (!canvas.isCropping || availableDuringCrop)
    }

    private func updateUI(_ message: String? = nil) {
        var parts: [String] = []
        if let url = imageURL {
            window.title = url.lastPathComponent
            let position = folderImages.firstIndex(of: url).map { L("%d of %d", $0 + 1, folderImages.count) + "  ·  " } ?? ""
            window.subtitle = position + url.deletingLastPathComponent().lastPathComponent
            parts = [image.map { "\($0.width) × \($0.height) px" } ?? L("Loading…"), url.pathExtension.uppercased()]
        } else if let image {
            window.title = L("Image from clipboard")
            window.subtitle = L("Not saved")
            parts = ["\(image.width) × \(image.height) px", L("from clipboard")]
        } else {
            window.title = "ImagePG"
            window.subtitle = L("No image")
        }
        window.isDocumentEdited = isDirty
        let zoom = String(format: "%.0f %%", canvas.viewport.scale * 100)
        if image != nil { parts.append(zoom) }
        status.attributedStringValue = statusText(message.map { [$0] } ?? parts)
        statusHUD.isHidden = canvas.isCropping || (message == nil && parts.isEmpty)
        emptyState.isHidden = image != nil || imageURL != nil
        zoomLabel?.stringValue = image != nil ? zoom : "—"
        zoomLabel?.textColor = image != nil ? .labelColor : .tertiaryLabelColor
        for (identifier, item) in toolbarItems {
            item.isEnabled = validateToolbarItem(item)
            if identifier.rawValue == "save" { item.isEnabled = image != nil && !isProcessing && !canvas.isCropping }
        }
        if let modesGroup {
            let available = image != nil && !isProcessing
            modesGroup.isEnabled = available
            modesGroup.subitems.forEach { $0.isEnabled = available }
            modesGroup.setSelected(canvas.isCropping, at: 0)
            modesGroup.setSelected(canvas.annotationsEnabled, at: 1)
            modesGroup.subitems.first?.toolTip = canvas.isCropping ? L("Cancel crop (Esc)") : L("Crop (⌘K)")
        }
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ImagePG"
        alert.informativeText = text
        alert.runModal()
    }

    private func confirmDiscardOrSave() -> Bool {
        canvas.cancelCrop()
        commitCurrentEditing()
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = L("Save changes to the image?")
        alert.informativeText = imageURL?.lastPathComponent ?? L("Image from clipboard")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Discard Changes"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func commitCurrentEditing() {
        if window.firstResponder is NSTextView { window.makeFirstResponder(canvas) }
    }

    @objc private func openDialog(_ sender: Any?) {
        guard !isProcessing else { return }
        let panel = NSOpenPanel()
        panel.title = L("Open image")
        panel.allowedContentTypes = ImageProcessing.readableExtensions.compactMap { ImageProcessing.canRead($0) ? ImageProcessing.type(for: $0) : nil }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }

    private func pasteImage(_ sender: Any?) {
        guard !isProcessing else { return }
        guard let image = ImageProcessing.imageFromPasteboard(.general) else {
            showError(L("The clipboard does not contain an image that can be opened."))
            return
        }
        guard confirmDiscardOrSave() else { return }
        loadGeneration += 1
        loadQueue.cancelAllOperations()
        folderQueue.cancelAllOperations()
        prefetchQueue.cancelAllOperations()
        imageURL = nil
        self.image = image
        let scale = min(1, 2200 / Double(max(image.width, image.height)))
        preview = scale == 1 ? image : ImageProcessing.resized(image,
            width: max(1, Int((Double(image.width) * scale).rounded())),
            height: max(1, Int((Double(image.height) * scale).rounded())))
        folderImages = []
        canvas.fitToWindow()
        canvas.fullImage = image
        canvas.image = preview ?? image
        canvas.annotations = []
        canvas.selected = nil
        isDirty = true
        updateUI()
    }

    private func open(_ url: URL, alreadyConfirmed: Bool = false) {
        guard ImageProcessing.canRead(url.pathExtension) else { showError(L("This image format is not supported on this system.")); return }
        guard !isProcessing, alreadyConfirmed || confirmDiscardOrSave() else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loadQueue.cancelAllOperations()
        imageURL = url
        image = nil
        preview = nil
        canvas.image = nil
        canvas.fullImage = nil
        canvas.fitToWindow()
        canvas.annotations = []
        canvas.selected = nil
        isDirty = false
        folderImages = [url]
        scanFolder(for: url, generation: generation)
        updateUI(L("Loading %@…", url.lastPathComponent))
        let cacheKey = url.path as NSString
        if let cached = previewCache.object(forKey: cacheKey)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            preview = cached
            canvas.image = cached
        }
        loadQueue.addOperation { [weak self] in
            guard let self else { return }
            if self.previewCache.object(forKey: cacheKey) == nil,
               let thumbnail = ImageProcessing.thumbnail(at: url, maximum: 2200) {
                self.previewCache.setObject(NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height)), forKey: cacheKey)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.preview = thumbnail
                    self.canvas.image = thumbnail
                }
            }
            guard let full = ImageProcessing.fullImage(at: url) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.showError(L("The image could not be loaded."))
                    self.updateUI(L("Loading failed: %@", url.lastPathComponent))
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.image = full
                self.canvas.fullImage = full
                self.canvas.image = self.preview ?? full
                self.updateUI()
                self.prefetchNeighbors()
            }
        }
    }

    private func scanFolder(for url: URL, generation: Int) {
        folderQueue.cancelAllOperations()
        folderQueue.addOperation { [weak self] in
            let folder = url.deletingLastPathComponent()
            let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            var images = files.filter { ImageProcessing.canRead($0.pathExtension) }.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            if !images.contains(url) { images.append(url) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation, self.imageURL == url else { return }
                self.folderImages = images
                self.updateUI()
                self.prefetchNeighbors()
            }
        }
    }

    private func prefetchNeighbors() {
        guard let url = imageURL, let index = folderImages.firstIndex(of: url), folderImages.count > 1 else { return }
        prefetchQueue.cancelAllOperations()
        let count = folderImages.count
        for offset in [-1, 1] {
            let next = folderImages[(index + offset + count) % count]
            let key = next.path as NSString
            guard previewCache.object(forKey: key) == nil else { continue }
            prefetchQueue.addOperation { [weak self] in
                guard let self, let thumb = ImageProcessing.thumbnail(at: next, maximum: 2200) else { return }
                self.previewCache.setObject(NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height)), forKey: key)
            }
        }
    }

    private func navigate(_ offset: Int) {
        guard !isProcessing, !canvas.isCropping, let url = imageURL, let index = folderImages.firstIndex(of: url), folderImages.count > 1 else { return }
        let destination = folderImages[(index + offset + folderImages.count) % folderImages.count]
        guard confirmDiscardOrSave() else { return }
        open(destination, alreadyConfirmed: true)
    }
    @objc private func zoomIn(_ sender: Any?) { canvas.zoom(by: 1.25) }
    @objc private func zoomOut(_ sender: Any?) { canvas.zoom(by: 1 / 1.25) }
    @objc private func fitImage(_ sender: Any?) { canvas.fitToWindow() }
    @objc private func actualSize(_ sender: Any?) { canvas.zoom(to: 1) }

    @objc private func previousImage(_ sender: Any?) { navigate(-1) }
    @objc private func nextImage(_ sender: Any?) { navigate(1) }

    private func edit(fitResult: Bool = false, _ action: @escaping (CGImage) -> CGImage?) {
        guard let current = image, !isProcessing, !canvas.isCropping else { return }
        guard let source = canvas.annotations.isEmpty ? current : canvas.flattenedImage() else {
            showError(L("The annotations could not be merged into the image."))
            return
        }
        let hadAnnotations = !canvas.annotations.isEmpty
        isProcessing = true
        updateUI(L("Processing image…"))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = action(source)
            let nextPreview: CGImage? = result.flatMap { edited in
                let scale = min(1, 2200 / Double(max(edited.width, edited.height)))
                if scale == 1 { return edited }
                return ImageProcessing.resized(edited,
                    width: max(1, Int((Double(edited.width) * scale).rounded())),
                    height: max(1, Int((Double(edited.height) * scale).rounded())))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                if let result {
                    self.image = result
                    self.canvas.fullImage = result
                    self.preview = nextPreview
                    self.canvas.image = nextPreview ?? result
                    if fitResult { self.canvas.fitToWindow() }
                    if hadAnnotations {
                        self.canvas.annotations = []
                        self.canvas.selected = nil
                    }
                    self.isDirty = true
                    self.updateUI()
                } else {
                    self.showError(L("The edit could not be applied. The image may be too large."))
                    self.updateUI()
                }
            }
        }
    }

    @objc private func rotateLeft(_ sender: Any?) { edit { ImageProcessing.rotated($0, degrees: 90) } }
    @objc private func rotateRight(_ sender: Any?) { edit { ImageProcessing.rotated($0, degrees: -90) } }
    @objc private func rotateAngle(_ sender: Any?) {
        guard let source = image, !isProcessing, !canvas.isCropping else { return }
        let sample = preview ?? source
        guard let angle = EditorDialogs.angle(preview: sample), angle != 0 else { return }
        edit { ImageProcessing.rotated($0, degrees: angle) }
    }
    @objc private func resize(_ sender: Any?) {
        guard let source = image, !isProcessing, !canvas.isCropping,
              let (width, height) = EditorDialogs.resize(width: source.width, height: source.height) else { return }
        if width == source.width && height == source.height { return }
        edit { ImageProcessing.resized($0, width: width, height: height) }
    }
    @objc private func changeCanvas(_ sender: Any?) {
        guard let source = image, !isProcessing, !canvas.isCropping,
              let (width, height, anchor, background) = EditorDialogs.canvas(width: source.width, height: source.height) else { return }
        edit { ImageProcessing.canvas($0, width: width, height: height, anchor: anchor, background: background) }
    }

    @objc private func save(_ sender: Any?) { _ = saveCurrent() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleCrop(_:)) {
            menuItem.state = canvas.isCropping ? .on : .off
            return image != nil && !isProcessing
        }
        if menuItem.action == #selector(applyCrop(_:)) {
            return !isProcessing && canvas.cropSelection?.rect != nil && canvas.cropSelection?.isDragging != true
        }
        if menuItem.action == #selector(cancelCrop(_:)) { return canvas.isCropping }
        let editActions = [#selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(rotateAngle(_:)),
                           #selector(resize(_:)), #selector(changeCanvas(_:)), #selector(save(_:)), #selector(saveAs(_:))]
        if let action = menuItem.action, editActions.contains(action) {
            return image != nil && !isProcessing && !canvas.isCropping
        }
        if menuItem.action == #selector(printImage(_:)) {
            return image != nil && !isProcessing && !canvas.isCropping && window.attachedSheet == nil
        }
        return true
    }

    @objc private func printImage(_ sender: Any?) {
        guard let image, !isProcessing, !canvas.isCropping, window.attachedSheet == nil else { return }
        commitCurrentEditing()
        guard let rendered = canvas.annotations.isEmpty ? image : canvas.flattenedImage() else {
            showError(L("The image with annotations could not be prepared for printing."))
            return
        }
        ImagePrinting.run(image: rendered, title: imageURL?.lastPathComponent ?? L("Image from clipboard"))
    }
    private func finishSave(_ rendered: CGImage, destination: URL) {
        image = rendered
        canvas.fullImage = rendered
        canvas.annotations = []
        canvas.selected = nil
        let scale = min(1, 2200 / Double(max(rendered.width, rendered.height)))
        preview = scale == 1 ? rendered : ImageProcessing.resized(rendered,
            width: max(1, Int((Double(rendered.width) * scale).rounded())),
            height: max(1, Int((Double(rendered.height) * scale).rounded())))
        canvas.image = preview ?? rendered
        previewCache.removeObject(forKey: destination.path as NSString)
        isDirty = false
    }

    private func saveCurrent() -> Bool {
        commitCurrentEditing()
        guard let image, !isProcessing, !canvas.isCropping else { return false }
        guard let url = imageURL else { return saveAsCurrent() }
        let ext = url.pathExtension.lowercased()
        guard ImageProcessing.canWrite(ext) else {
            return saveAsCurrent()
        }
        let alpha = !["jpg", "jpeg", "bmp"].contains(ext)
        guard let rendered = canvas.annotations.isEmpty ? image : canvas.flattenedImage(),
              ImageProcessing.save(rendered, to: url, type: ext, quality: 0.9, transparency: alpha, background: .white) else {
            showError(L("The image could not be saved."))
            return false
        }
        finishSave(rendered, destination: url)
        updateUI(L("Saved: %@", url.lastPathComponent))
        return true
    }

    @objc private func saveAs(_ sender: Any?) { _ = saveAsCurrent() }

    private func saveAsCurrent() -> Bool {
        commitCurrentEditing()
        guard let image, !isProcessing, !canvas.isCropping,
              let (destination, type, quality, transparency, background) = EditorDialogs.saveAs(defaultURL: imageURL) else { return false }
        guard let rendered = canvas.annotations.isEmpty ? image : canvas.flattenedImage(),
              ImageProcessing.save(rendered, to: destination, type: type, quality: quality,
                                   transparency: transparency, background: background) else {
            showError(L("The image could not be saved."))
            return false
        }
        imageURL = destination
        finishSave(rendered, destination: destination)
        folderImages = [destination]
        scanFolder(for: destination, generation: loadGeneration)
        updateUI(L("Saved: %@", destination.lastPathComponent))
        return true
    }
}
