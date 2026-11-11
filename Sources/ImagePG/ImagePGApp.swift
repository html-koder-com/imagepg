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
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        bounds.fill()
        guard let image else {
            let message = "Přetáhněte obrázek sem, stiskněte ⌘O nebo ⌘V"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = message.size(withAttributes: attributes)
            message.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                     y: (bounds.height - size.height) / 2), withAttributes: attributes)
            return
        }
        guard let rect = imageRect else { return }
        // Only tile the visible region: a highly zoomed image can be enormous.
        let visible = rect.intersection(bounds)
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
            let box = selected.rect.insetBy(dx: -4 / imageScale, dy: -4 / imageScale)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1 / imageScale)
            context.setLineDash(phase: 0, lengths: [5 / imageScale, 3 / imageScale])
            context.stroke(box)
            context.setLineDash(phase: 0, lengths: [])
            for handle in selected.handles {
                let size = 8 / imageScale
                let square = CGRect(x: handle.x - size / 2, y: handle.y - size / 2, width: size, height: size)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(square)
                context.stroke(square)
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
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.drawPath(using: .eoFill)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        for fraction: CGFloat in [1 / 3, 2 / 3] {
            context.move(to: CGPoint(x: box.minX + box.width * fraction, y: box.minY))
            context.addLine(to: CGPoint(x: box.minX + box.width * fraction, y: box.maxY))
            context.move(to: CGPoint(x: box.minX, y: box.minY + box.height * fraction))
            context.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * fraction))
        }
        context.strokePath()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(box)
        context.restoreGState()
        for handle in selection.handles {
            let point = CGPoint(x: imageRect.minX + handle.x * scale, y: imageRect.minY + handle.y * scale)
            let square = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            square.fill()
            NSColor.black.withAlphaComponent(0.65).setStroke()
            NSBezierPath(rect: square).stroke()
        }
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
    private var status: NSTextField!
    private var cropBar: NSStackView!
    private var cropBarHeight: NSLayoutConstraint!
    private var cropLabel: NSTextField!
    private var cropApplyButton: NSButton!
    private var annotationPanel: NSScrollView!
    private var panelWidth: NSLayoutConstraint!
    private var toolPicker: NSPopUpButton!
    private var strokeWell: NSColorWell!
    private var eyedropperButton: NSButton!
    private var fillWell: NSColorWell!
    private var transparentFill: NSButton!
    private var widthField: NSTextField!
    private var widthSlider: NSSlider!
    private var widthPreview: LineWidthPreviewView!
    private var startPicker: NSPopUpButton!
    private var endPicker: NSPopUpButton!
    private var fontPicker: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var textField: NSTextField!
    private var annotationHint: NSTextField!
    private var strokeGroup: NSStackView!
    private var widthGroup: NSStackView!
    private var fillGroup: NSStackView!
    private var arrowGroup: NSStackView!
    private var fontGroup: NSStackView!
    private var updatingAnnotationControls = false
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
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
        if let pendingOpenURL {
            self.pendingOpenURL = nil
            open(pendingOpenURL)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isProcessing else { showError("Počkejte, až se dokončí úprava obrázku."); return .terminateCancel }
        return confirmDiscardOrSave() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            let url = URL(fileURLWithPath: first)
            if window == nil {
                pendingOpenURL = url
            } else {
                open(url)
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isProcessing else { showError("Počkejte, až se dokončí úprava obrázku."); return false }
        guard confirmDiscardOrSave() else { return false }
        // Closing the last window also terminates the app; avoid asking twice after Discard.
        isDirty = false
        return true
    }

    private func makeWindow() {
        window = ImagePGWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.pasteImage = { [weak self] in self?.pasteImage(nil) }
        window.title = "ImagePG"
        window.center()
        window.setFrameAutosaveName("ImagePG.MainWindow")
        window.delegate = self
        window.minSize = NSSize(width: 650, height: 440)
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        canvas = ImageCanvasView(frame: .zero)
        canvas.translatesAutoresizingMaskIntoConstraints = false
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
        status = NSTextField(labelWithString: "Žádný obrázek")
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(canvas)
        content.addSubview(annotationPanel)
        content.addSubview(status)
        content.addSubview(cropBar)
        panelWidth = annotationPanel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: annotationPanel.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: cropBar.topAnchor),
            cropBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            cropBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            cropBar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            cropBarHeight,
            annotationPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            annotationPanel.topAnchor.constraint(equalTo: content.topAnchor),
            annotationPanel.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            panelWidth,
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -7),
            status.heightAnchor.constraint(equalToConstant: 18)
        ])
        canvas.viewportChanged = { [weak self] in self?.updateUI() }
        canvas.cropChanged = { [weak self] in self?.updateCropControls() }
        canvas.cropRequested = { [weak self] rect in self?.performCrop(rect) }
        let toolbar = NSToolbar(identifier: "ImagePG.MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        updateUI()
    }

    private func makeCropBar() {
        cropBar = NSStackView()
        cropBar.orientation = .horizontal
        cropBar.alignment = .centerY
        cropBar.spacing = 10
        cropBar.translatesAutoresizingMaskIntoConstraints = false
        cropBar.isHidden = true
        cropBarHeight = cropBar.heightAnchor.constraint(equalToConstant: 0)
        cropLabel = NSTextField(labelWithString: "Tažením vyznačte výřez")
        cropLabel.font = .systemFont(ofSize: 12)
        cropLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cropLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cropLabel.lineBreakMode = .byTruncatingTail
        cropLabel.toolTip = "Tažením vyznačíte výřez. Uvnitř ho přesunete, rohy změníte velikost. Shift drží čtverec; mezerník umožňuje posun obrázku."
        let cancel = NSButton(title: "Zrušit (Esc)", target: self, action: #selector(cancelCrop(_:)))
        cropApplyButton = NSButton(title: "Oříznout (↵)", target: self, action: #selector(applyCrop(_:)))
        cropApplyButton.bezelColor = .controlAccentColor
        [cropLabel, cancel, cropApplyButton].forEach { cropBar.addArrangedSubview($0) }
    }

    private func updateCropControls() {
        cropBar.isHidden = !canvas.isCropping
        cropBarHeight.constant = canvas.isCropping ? 38 : 0
        if let rect = canvas.cropSelection?.rect {
            cropLabel.stringValue = "Výřez: \(Int(rect.width)) × \(Int(rect.height)) px"
        } else {
            cropLabel.stringValue = "Tažením vyznačte výřez • Shift: čtverec"
        }
        cropApplyButton.isEnabled = canvas.cropSelection?.rect != nil && canvas.cropSelection?.isDragging != true
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
        annotationPanel = NSScrollView()
        annotationPanel.translatesAutoresizingMaskIntoConstraints = false
        annotationPanel.hasVerticalScroller = true
        annotationPanel.drawsBackground = true
        annotationPanel.isHidden = true
        let stack = AnnotationPanelStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        func label(_ title: String) -> NSTextField {
            let field = NSTextField(labelWithString: title)
            field.font = .systemFont(ofSize: 11, weight: .medium)
            field.textColor = .secondaryLabelColor
            return field
        }
        func group(_ title: String) -> NSStackView {
            let section = NSStackView()
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = 4
            section.addArrangedSubview(label(title))
            stack.addArrangedSubview(section)
            return section
        }
        func add(_ view: NSView, to section: NSStackView, width: CGFloat = 218) {
            view.translatesAutoresizingMaskIntoConstraints = false
            section.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let title = NSTextField(labelWithString: "Anotace")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(title)
        let toolGroup = group("Nástroj")
        toolPicker = NSPopUpButton()
        toolPicker.addItems(withTitles: AnnotationTool.allCases.map(\.title))
        toolPicker.target = self; toolPicker.action = #selector(annotationToolChanged(_:))
        add(toolPicker, to: toolGroup)

        strokeGroup = group("Barva čáry / textu")
        strokeWell = NSColorWell()
        strokeWell.color = canvas.stroke
        strokeWell.target = self; strokeWell.action = #selector(annotationStyleChanged(_:))
        add(strokeWell, to: strokeGroup)
        eyedropperButton = NSButton(title: "Kapátko z obrázku", target: self, action: #selector(toggleColorPicking(_:)))
        eyedropperButton.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Kapátko")
        eyedropperButton.imagePosition = .imageLeading
        eyedropperButton.toolTip = "Kliknutím do obrázku naberete barvu. U obdélníku a elipsy se nastaví výplň i obrys. Esc výběr zruší."
        add(eyedropperButton, to: strokeGroup)

        widthGroup = group("Tloušťka čáry (px)")
        let widthRow = NSStackView()
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 8
        widthSlider = NSSlider(value: 4, minValue: 0.5, maxValue: 50,
                               target: self, action: #selector(annotationWidthSliderChanged(_:)))
        widthSlider.isContinuous = true
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 152).isActive = true
        widthField = NSTextField(string: "4")
        widthField.delegate = self
        widthField.alignment = .right
        widthField.translatesAutoresizingMaskIntoConstraints = false
        widthField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        widthRow.addArrangedSubview(widthSlider)
        widthRow.addArrangedSubview(widthField)
        add(widthRow, to: widthGroup)
        widthPreview = LineWidthPreviewView()
        widthPreview.color = canvas.stroke
        widthPreview.translatesAutoresizingMaskIntoConstraints = false
        widthPreview.heightAnchor.constraint(equalToConstant: 36).isActive = true
        add(widthPreview, to: widthGroup)

        fillGroup = group("Výplň")
        transparentFill = NSButton(checkboxWithTitle: "Průhledná výplň", target: self,
                                   action: #selector(annotationStyleChanged(_:)))
        transparentFill.state = .on
        add(transparentFill, to: fillGroup)
        fillGroup.addArrangedSubview(label("Barva výplně"))
        fillWell = NSColorWell()
        fillWell.color = .systemYellow
        fillWell.isEnabled = false
        fillWell.target = self; fillWell.action = #selector(annotationStyleChanged(_:))
        add(fillWell, to: fillGroup)

        arrowGroup = group("Začátek čáry")
        startPicker = NSPopUpButton()
        startPicker.addItems(withTitles: ArrowStyle.allCases.map(\.title))
        startPicker.target = self; startPicker.action = #selector(annotationStyleChanged(_:))
        add(startPicker, to: arrowGroup)
        arrowGroup.addArrangedSubview(label("Konec čáry"))
        endPicker = NSPopUpButton()
        endPicker.addItems(withTitles: ArrowStyle.allCases.map(\.title))
        endPicker.target = self; endPicker.action = #selector(annotationStyleChanged(_:))
        add(endPicker, to: arrowGroup)

        fontGroup = group("Rodina písma")
        fontPicker = NSPopUpButton()
        fontPicker.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPicker.selectItem(withTitle: "Helvetica")
        fontPicker.target = self; fontPicker.action = #selector(annotationStyleChanged(_:))
        add(fontPicker, to: fontGroup)
        fontGroup.addArrangedSubview(label("Velikost písma (px)"))
        fontSizeField = NSTextField(string: "32")
        fontSizeField.delegate = self
        add(fontSizeField, to: fontGroup)
        fontGroup.addArrangedSubview(label("Text"))
        textField = NSTextField(string: "Text")
        textField.delegate = self
        add(textField, to: fontGroup)
        annotationHint = NSTextField(wrappingLabelWithString: "Tažením vytvoříte objekt, kliknutím ho vyberete. Úchyty mění tvar. Shift drží kruh nebo čtverec. Delete smaže výběr.")
        annotationHint.font = .systemFont(ofSize: 11)
        annotationHint.textColor = .secondaryLabelColor
        annotationHint.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(annotationHint)
        annotationHint.widthAnchor.constraint(equalToConstant: 218).isActive = true
        annotationPanel.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: annotationPanel.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: annotationPanel.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: annotationPanel.contentView.topAnchor)
        ])
        updateAnnotationControlsVisibility()
    }

    @objc private func toggleAnnotations(_ sender: Any?) {
        guard !canvas.isCropping, !isProcessing else { return }
        let showing = annotationPanel.isHidden
        annotationPanel.isHidden = !showing
        canvas.annotationsEnabled = showing
        panelWidth.constant = showing ? 250 : 0
        if showing { syncAnnotationControls() }
    }

    @objc private func annotationToolChanged(_ sender: Any?) {
        canvas.tool = AnnotationTool(rawValue: toolPicker.indexOfSelectedItem) ?? .select
        canvas.selected = nil
        updateAnnotationControlsVisibility()
    }

    @objc private func annotationStyleChanged(_ sender: Any?) { applyAnnotationControls() }

    @objc private func toggleColorPicking(_ sender: Any?) {
        if canvas.isPickingColor { canvas.cancelColorPicking() }
        else {
            strokeWell.deactivate()
            fillWell.deactivate()
            canvas.beginColorPicking()
        }
    }

    @objc private func annotationWidthSliderChanged(_ sender: Any?) {
        widthField.stringValue = String(format: "%.1f", widthSlider.doubleValue)
        applyAnnotationControls()
    }

    func controlTextDidEndEditing(_ obj: Notification) { applyAnnotationControls() }

    private func updateAnnotationControlsVisibility() {
        let active = canvas.selected?.tool ?? canvas.tool
        strokeGroup.isHidden = active == .select
        widthGroup.isHidden = active == .select || active == .text
        fillGroup.isHidden = active != .ellipse && active != .rectangle
        arrowGroup.isHidden = active != .line
        fontGroup.isHidden = active != .text
        eyedropperButton.title = canvas.isPickingColor ? "Zrušit kapátko (Esc)" : "Kapátko z obrázku"
        annotationHint.stringValue = canvas.isPickingColor
            ? "Klikněte na barvu v obrázku. U obdélníku a elipsy kapátko nastaví výplň i obrys. Esc výběr zruší."
            : active == .text
            ? "Kliknutím vložíte text. Vybraný text lze přetáhnout nebo upravit v panelu. Delete ho smaže."
            : "Tažením vytvoříte objekt, kliknutím ho vyberete. Úchyty mění tvar. Shift drží kruh nebo čtverec. Delete smaže výběr."
    }

    private func applyAnnotationControls() {
        guard !updatingAnnotationControls else { return }
        canvas.stroke = strokeWell.color
        canvas.lineWidth = max(0.5, min(500, CGFloat(Double(widthField.stringValue) ?? 4)))
        widthField.stringValue = String(format: "%.1f", canvas.lineWidth)
        widthSlider.doubleValue = min(50, Double(canvas.lineWidth))
        widthPreview.lineWidth = canvas.lineWidth
        widthPreview.color = canvas.stroke
        canvas.fill = transparentFill.state == .on ? nil : fillWell.color
        fillWell.isEnabled = transparentFill.state != .on
        canvas.startArrow = ArrowStyle(rawValue: startPicker.indexOfSelectedItem) ?? .none
        canvas.endArrow = ArrowStyle(rawValue: endPicker.indexOfSelectedItem) ?? .none
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
    }

    private func syncAnnotationControls() {
        guard toolPicker != nil else { return }
        updatingAnnotationControls = true
        defer { updatingAnnotationControls = false }
        let item = canvas.selected
        strokeWell.color = item?.stroke ?? canvas.stroke
        widthField.stringValue = String(format: "%.1f", item?.width ?? canvas.lineWidth)
        widthSlider.doubleValue = min(50, Double(item?.width ?? canvas.lineWidth))
        widthPreview.lineWidth = item?.width ?? canvas.lineWidth
        widthPreview.color = item?.stroke ?? canvas.stroke
        let selectedFill = item == nil ? canvas.fill : item?.fill
        transparentFill.state = selectedFill == nil ? .on : .off
        fillWell.color = selectedFill ?? .systemYellow
        fillWell.isEnabled = transparentFill.state != .on
        startPicker.selectItem(at: (item?.startArrow ?? canvas.startArrow).rawValue)
        endPicker.selectItem(at: (item?.endArrow ?? canvas.endArrow).rawValue)
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
        appMenu.addItem(withTitle: "O aplikaci ImagePG", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ukončit ImagePG", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(title: "Soubor", action: nil, keyEquivalent: "")
        main.addItem(fileItem)
        let file = NSMenu(title: "Soubor")
        fileItem.submenu = file
        menu(file, "Otevřít…", #selector(openDialog(_:)), "o")
        menu(file, "Uložit", #selector(save(_:)), "s")
        let saveAs = menu(file, "Uložit jako…", #selector(saveAs(_:)), "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        menu(file, "Tisk…", #selector(printImage(_:)), "p")
        let controlPrint = menu(file, "Tisk…", #selector(printImage(_:)), "p")
        controlPrint.keyEquivalentModifierMask = [.control]
        controlPrint.isHidden = true
        controlPrint.allowsKeyEquivalentWhenHidden = true
        let editItem = NSMenuItem(title: "Úpravy", action: nil, keyEquivalent: "")
        main.addItem(editItem)
        let edit = NSMenu(title: "Úpravy")
        editItem.submenu = edit
        edit.addItem(withTitle: "Vložit obrázek ze schránky", action: #selector(ImagePGWindow.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        menu(edit, "Otočit doleva o 90°", #selector(rotateLeft(_:)), "")
        menu(edit, "Otočit doprava o 90°", #selector(rotateRight(_:)), "")
        menu(edit, "Otočit o úhel…", #selector(rotateAngle(_:)), "")
        edit.addItem(.separator())
        menu(edit, "Změnit velikost obrázku…", #selector(resize(_:)), "r")
        menu(edit, "Oříznout / výřez", #selector(toggleCrop(_:)), "k")
        menu(edit, "Použít ořez", #selector(applyCrop(_:)), "")
        menu(edit, "Zrušit ořez", #selector(cancelCrop(_:)), "")
        let canvasSize = menu(edit, "Velikost plátna…", #selector(changeCanvas(_:)), "p")
        canvasSize.keyEquivalentModifierMask = [.command, .shift]
        let viewItem = NSMenuItem(title: "Zobrazení", action: nil, keyEquivalent: "")
        main.addItem(viewItem)
        let view = NSMenu(title: "Zobrazení")
        viewItem.submenu = view
        menu(view, "Přiblížit", #selector(zoomIn(_:)), "+")
        let zoomInAlias = menu(view, "Přiblížit", #selector(zoomIn(_:)), "=")
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        menu(view, "Oddálit", #selector(zoomOut(_:)), "-")
        menu(view, "Přizpůsobit oknu", #selector(fitImage(_:)), "0")
        menu(view, "Skutečná velikost (100 %)", #selector(actualSize(_:)), "1")
        view.addItem(.separator())
        menu(view, "Předchozí obrázek", #selector(previousImage(_:)), "")
        menu(view, "Další obrázek", #selector(nextImage(_:)), "")
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
        ["open", "save", "previous", "next", "left", "right", "resize", "crop", "canvas", "annotate", "zoomOut", "zoomIn", "fit", "actual"].map { NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let definitions: [String: (String, String, Selector)] = [
            "zoomOut": ("Oddálit (⌘−)", "minus.magnifyingglass", #selector(zoomOut(_:))),
            "zoomIn": ("Přiblížit (⌘+)", "plus.magnifyingglass", #selector(zoomIn(_:))),
            "fit": ("Přizpůsobit oknu (⌘0)", "arrow.down.right.and.arrow.up.left", #selector(fitImage(_:))),
            "actual": ("Skutečná velikost — 100 % (⌘1)", "1.magnifyingglass", #selector(actualSize(_:))),
            "open": ("Otevřít", "folder", #selector(openDialog(_:))),
            "save": ("Uložit", "square.and.arrow.down", #selector(save(_:))),
            "previous": ("Předchozí", "chevron.left", #selector(previousImage(_:))),
            "next": ("Další", "chevron.right", #selector(nextImage(_:))),
            "left": ("Otočit vlevo", "rotate.left", #selector(rotateLeft(_:))),
            "right": ("Otočit vpravo", "rotate.right", #selector(rotateRight(_:))),
            "resize": ("Změnit velikost obrázku (⌘R)", "", #selector(resize(_:))),
            "crop": ("Oříznout / výřez (⌘K)", "crop", #selector(toggleCrop(_:))),
            "canvas": ("Velikost plátna (⇧⌘P)", "rectangle.dashed", #selector(changeCanvas(_:))),
            "annotate": ("Anotace", "pencil.tip", #selector(toggleAnnotations(_:)))
        ]
        guard let definition = definitions[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = definition.0
        item.paletteLabel = definition.0
        item.toolTip = definition.0
        item.image = identifier.rawValue == "resize" ? ToolbarImages.resize :
            NSImage(systemSymbolName: definition.1, accessibilityDescription: definition.0)
        item.target = self
        item.action = definition.2
        toolbarItems[identifier] = item
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let name = item.itemIdentifier.rawValue
        if name == "open" { return !isProcessing }
        if name == "previous" || name == "next" {
            return folderImages.count > 1 && !isProcessing && !canvas.isCropping
        }
        let availableDuringCrop = ["crop", "zoomOut", "zoomIn", "fit", "actual"].contains(name)
        return image != nil && !isProcessing && (!canvas.isCropping || availableDuringCrop)
    }

    private func updateUI(_ message: String? = nil) {
        if let url = imageURL {
            window.title = url.lastPathComponent + (isDirty ? " •" : "") + " — ImagePG"
            let size = image.map { "\($0.width) × \($0.height) px" } ?? "Načítání…"
            let position = folderImages.firstIndex(of: url).map { "  •  \($0 + 1) / \(folderImages.count)" } ?? ""
            status.stringValue = message ?? "\(size)\(position)  •  \(url.deletingLastPathComponent().path)"
        } else if let image {
            window.title = "Obrázek ze schránky" + (isDirty ? " •" : "") + " — ImagePG"
            status.stringValue = message ?? "\(image.width) × \(image.height) px  •  obrázek ze schránky"
        } else {
            window.title = "ImagePG"
            status.stringValue = "Žádný obrázek"
        }
        if image != nil, message == nil {
            status.stringValue += String(format: "  •  %.0f %%", canvas.viewport.scale * 100)
        }
        for (identifier, item) in toolbarItems {
            item.isEnabled = validateToolbarItem(item)
            if identifier.rawValue == "crop" {
                item.toolTip = canvas.isCropping ? "Zrušit ořez (Esc)" : "Oříznout / výřez (⌘K)"
            }
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
        alert.messageText = "Uložit změny v obrázku?"
        alert.informativeText = imageURL?.lastPathComponent ?? "Obrázek ze schránky"
        alert.addButton(withTitle: "Uložit")
        alert.addButton(withTitle: "Zahodit změny")
        alert.addButton(withTitle: "Zrušit")
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
        panel.title = "Otevřít obrázek"
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
            showError("Ve schránce není obrázek, který lze otevřít.")
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
        guard ImageProcessing.canRead(url.pathExtension) else { showError("Tento formát obrázku není v systému podporován."); return }
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
        updateUI("Načítání \(url.lastPathComponent)…")
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
                    self.showError("Obrázek se nepodařilo načíst.")
                    self.updateUI("Načtení selhalo: \(url.lastPathComponent)")
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
            showError("Anotace se nepodařilo sloučit s obrázkem.")
            return
        }
        let hadAnnotations = !canvas.annotations.isEmpty
        isProcessing = true
        updateUI("Zpracování obrázku…")
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
                    self.showError("Úpravu se nepodařilo provést. Obrázek může být příliš velký.")
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
            showError("Obrázek s anotacemi se nepodařilo připravit k tisku.")
            return
        }
        ImagePrinting.run(image: rendered, title: imageURL?.lastPathComponent ?? "Obrázek ze schránky")
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
            showError("Obrázek se nepodařilo uložit.")
            return false
        }
        finishSave(rendered, destination: url)
        updateUI("Uloženo: \(url.lastPathComponent)")
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
            showError("Obrázek se nepodařilo uložit.")
            return false
        }
        imageURL = destination
        finishSave(rendered, destination: destination)
        folderImages = [destination]
        scanFolder(for: destination, generation: loadGeneration)
        updateUI("Uloženo: \(destination.lastPathComponent)")
        return true
    }
}
