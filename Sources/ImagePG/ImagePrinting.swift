import AppKit

enum ImagePrintScaleMode: Int, CaseIterable {
    case fit, fill, custom

    var title: String {
        switch self {
        case .fit: return L("Fit to page")
        case .fill: return L("Fill page (crop)")
        case .custom: return L("Custom scale")
        }
    }
}

final class ImagePrintSettings {
    var mode: ImagePrintScaleMode = .fit
    var percent: Double = 100

    static func percentage(from text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (0.1...1000).contains(value) else { return nil }
        return value
    }

    func imageRect(imageSize: CGSize, printableRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, !printableRect.isEmpty else { return .zero }
        let widthScale = printableRect.width / imageSize.width
        let heightScale = printableRect.height / imageSize.height
        let scale: CGFloat
        switch mode {
        case .fit: scale = min(widthScale, heightScale)
        case .fill: scale = max(widthScale, heightScale)
        case .custom: scale = CGFloat(percent / 100)
        }
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: printableRect.midX - size.width / 2, y: printableRect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// A single paper-sized view shared by the system's live preview and actual output.
/// Scaling is applied here only; AppKit's separate scaling control is hidden.
final class ImagePrintView: NSView {
    let image: CGImage
    let settings: ImagePrintSettings
    let initialPrintInfo: NSPrintInfo
    private let documentTitle: String

    init(image: CGImage, settings: ImagePrintSettings, printInfo: NSPrintInfo, title: String) {
        self.image = image
        self.settings = settings
        initialPrintInfo = printInfo
        documentTitle = title
        super.init(frame: CGRect(origin: .zero, size: printInfo.paperSize))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var printJobTitle: String { documentTitle }

    // NSPrintOperation copies its print info. Always read the live operation's copy.
    private var printInfo: NSPrintInfo { NSPrintOperation.current?.printInfo ?? initialPrintInfo }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        frame.size = printInfo.paperSize
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        CGRect(origin: .zero, size: printInfo.paperSize)
    }

    override func locationOfPrintRect(_ rect: NSRect) -> NSPoint { .zero }

    override func draw(_ dirtyRect: NSRect) {
        let page = CGRect(origin: .zero, size: printInfo.paperSize)
        NSColor.white.setFill()
        page.fill()
        // Leave at least 6.35 mm around the image and respect the printer's hardware margins.
        let printable = page.insetBy(dx: 18, dy: 18).intersection(printInfo.imageablePageBounds)
        guard !printable.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let imageRect = settings.imageRect(imageSize: CGSize(width: image.width, height: image.height),
                                           printableRect: printable)
        context.saveGState()
        context.clip(to: printable)
        context.interpolationQuality = .high
        context.draw(image, in: imageRect)
        context.restoreGState()
    }
}

final class PrintPercentageFormatter: Formatter {
    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        // Keep unfinished input (such as "25,") intact until editing ends.
        true
    }

    override func string(for obj: Any?) -> String? {
        guard let number = obj as? NSNumber else { return nil }
        return number.stringValue
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard let value = ImagePrintSettings.percentage(from: string) else {
            error?.pointee = L("Enter a scale from 0.1 to 1000 %.") as NSString
            return false
        }
        obj?.pointee = NSNumber(value: value)
        return true
    }
}

final class ImagePrintAccessory: NSViewController, NSPrintPanelAccessorizing, NSTextFieldDelegate {
    let settings: ImagePrintSettings
    private(set) var modePicker: NSPopUpButton!
    private(set) var percentField: NSTextField!
    @objc dynamic private(set) var previewRevision = 0

    init(settings: ImagePrintSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        title = L("Image size")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 370, height: 152))
        content.addSubview(EditorDialogs.label(L("Size"), frame: CGRect(x: 0, y: 119, width: 96, height: 20)))
        modePicker = NSPopUpButton(frame: CGRect(x: 100, y: 114, width: 270, height: 28))
        modePicker.addItems(withTitles: ImagePrintScaleMode.allCases.map(\.title))
        modePicker.selectItem(at: settings.mode.rawValue)
        modePicker.target = self
        modePicker.action = #selector(modeChanged(_:))
        modePicker.setAccessibilityLabel(L("Image size fitting"))
        content.addSubview(modePicker)
        content.addSubview(EditorDialogs.label(L("Scale"), frame: CGRect(x: 0, y: 79, width: 96, height: 20)))
        percentField = EditorDialogs.field(String(settings.percent), frame: CGRect(x: 104, y: 76, width: 90, height: 24))
        percentField.formatter = PrintPercentageFormatter()
        percentField.delegate = self
        percentField.target = self
        percentField.action = #selector(percentChanged(_:))
        percentField.isEnabled = settings.mode == .custom
        percentField.setAccessibilityLabel(L("Custom scale in percent"))
        content.addSubview(percentField)
        content.addSubview(EditorDialogs.label("%", frame: CGRect(x: 202, y: 79, width: 30, height: 20)))
        let note = NSTextField(wrappingLabelWithString:
            L("100 % = 1 pixel per printer point (72 dpi).\nPrints on one page; overflow is cropped. Range 0.1–1000 %."))
        note.frame = CGRect(x: 0, y: 0, width: 370, height: 60)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        content.addSubview(note)
        view = content
    }

    @objc private func modeChanged(_ sender: Any?) {
        guard let mode = ImagePrintScaleMode(rawValue: modePicker.indexOfSelectedItem) else { return }
        settings.mode = mode
        percentField.isEnabled = mode == .custom
        invalidatePreview()
    }

    @objc private func percentChanged(_ sender: Any?) { updatePercentage() }
    func controlTextDidChange(_ notification: Notification) { updatePercentage() }

    private func updatePercentage() {
        let text = percentField.currentEditor()?.string ?? percentField.stringValue
        guard let value = ImagePrintSettings.percentage(from: text),
              settings.percent != value else { return }
        settings.percent = value
        invalidatePreview()
    }

    private func invalidatePreview() {
        willChangeValue(forKey: "localizedSummaryItems")
        previewRevision += 1
        didChangeValue(forKey: "localizedSummaryItems")
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> { ["previewRevision"] }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        let summary = settings.mode == .custom ? "\(settings.percent) %" : settings.mode.title
        return [[.itemName: L("Image size"), .itemDescription: summary]]
    }
}

enum ImagePrinting {
    static func run(image: CGImage, title: String) {
        operation(image: image, title: title).run()
    }

    static func operation(image: CGImage, title: String, printInfo: NSPrintInfo = .shared,
                          settings: ImagePrintSettings = ImagePrintSettings()) -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        info.scalingFactor = 1
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let view = ImagePrintView(image: image, settings: settings, printInfo: info, title: title)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        let panel = operation.printPanel
        panel.options.formUnion([.showsPaperSize, .showsOrientation, .showsPreview])
        panel.options.subtract([.showsScaling, .showsPageSetupAccessory])
        panel.addAccessoryController(ImagePrintAccessory(settings: settings))
        return operation
    }
}
