import AppKit

/// Localized UI string. Keys are English; translations live in Resources/<lang>.lproj/Localizable.strings.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string, e.g. `L("Saved: %@", name)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

/// Visual constants and small reusable views for the dark, minimal interface.
enum Theme {
    static let canvas = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.086, alpha: 1)
    static let panel = NSColor(srgbRed: 0.122, green: 0.122, blue: 0.137, alpha: 1)
    static let hairline = NSColor(white: 1, alpha: 0.08)
    static let swatches: [(NSColor, String)] = [
        (.systemRed, L("Red")), (.systemOrange, L("Orange")), (.systemYellow, L("Yellow")), (.systemGreen, L("Green")),
        (.systemBlue, L("Blue")), (.systemPurple, L("Purple")), (.white, L("White")), (.black, L("Black"))
    ]

    static func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text.uppercased())
        field.font = .systemFont(ofSize: 10.5, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        return field
    }

    /// Key hint in the style "Esc", rendered dimmer than the button title.
    static func buttonTitle(_ title: String, key: String, color: NSColor = .labelColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color
        ])
        result.append(NSAttributedString(string: "  " + key, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: color.withAlphaComponent(0.6)
        ]))
        return result
    }

    static func symbol(_ name: String, _ description: String, size: CGFloat = 15) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }

    static func isSame(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.01 && abs(x.greenComponent - y.greenComponent) < 0.01 &&
            abs(x.blueComponent - y.blueComponent) < 0.01 && abs(x.alphaComponent - y.alphaComponent) < 0.01
    }

    /// Template images for the line-end picker. `mirrored` draws the line start (tip on the left).
    static func arrowImage(_ style: ArrowStyle, mirrored: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 14), flipped: false) { rect in
            let transform = NSAffineTransform()
            if mirrored {
                transform.translateX(by: rect.width, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
                transform.concat()
            }
            NSColor.black.set()
            let tip: CGFloat = 23, y: CGFloat = 7
            let stem: CGFloat
            switch style {
            case .none: stem = tip
            case .filled: stem = 16
            case .open: stem = 22
            case .circle: stem = 16
            case .diamond: stem = 14
            }
            let line = NSBezierPath()
            line.lineWidth = 1.7
            line.lineCapStyle = .round
            line.move(to: CGPoint(x: 3, y: y))
            line.line(to: CGPoint(x: stem, y: y))
            line.stroke()
            switch style {
            case .none: break
            case .filled:
                let head = NSBezierPath()
                head.move(to: CGPoint(x: 15, y: 2.5)); head.line(to: CGPoint(x: tip, y: y)); head.line(to: CGPoint(x: 15, y: 11.5))
                head.close(); head.fill()
            case .open:
                let head = NSBezierPath()
                head.lineWidth = 1.7; head.lineCapStyle = .round; head.lineJoinStyle = .round
                head.move(to: CGPoint(x: 16.5, y: 2.5)); head.line(to: CGPoint(x: tip - 0.5, y: y)); head.line(to: CGPoint(x: 16.5, y: 11.5))
                head.stroke()
            case .circle:
                NSBezierPath(ovalIn: CGRect(x: 16, y: 3.5, width: 7, height: 7)).fill()
            case .diamond:
                let head = NSBezierPath()
                head.move(to: CGPoint(x: 13.5, y: y)); head.line(to: CGPoint(x: 18.25, y: 2.25))
                head.line(to: CGPoint(x: tip, y: y)); head.line(to: CGPoint(x: 18.25, y: 11.75)); head.close(); head.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = style.title
        return image
    }
}

/// Translucent rounded "glass" container used for the status pill and the crop bar.
final class HUDView: NSVisualEffectView {
    let stack = NSStackView()

    init(radius: CGFloat) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func pin(insets: NSEdgeInsets) {
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
    }

    // The pill floats over the photo; let clicks outside its controls reach the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self || view === stack || view is NSTextField && !(view as! NSTextField).isEditable ? nil : view
    }
}

/// Round colour swatch for the annotation palette.
final class SwatchButton: NSButton {
    let color: NSColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: NSColor, name: String, target: AnyObject?, action: Selector) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        toolTip = name
        setAccessibilityLabel(name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let inner = bounds.insetBy(dx: 3, dy: 3)
        if isChosen {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        color.setFill()
        let dot = NSBezierPath(ovalIn: inner)
        dot.fill()
        NSColor(white: 1, alpha: 0.2).setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }
}

/// Empty-window call to action. Lives inside the canvas so file drops still reach it.
final class EmptyStateView: NSView {
    init(open: NSButton, paste: NSButton) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let title = NSTextField(labelWithString: L("Drop an image here"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: L("JPEG, PNG, HEIC, WebP, TIFF, GIF and more"))
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [open, paste])
        buttons.spacing = 10
        let stack = NSStackView(views: [icon, title, subtitle, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(22, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 520),
            heightAnchor.constraint(equalToConstant: 380),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 22, yRadius: 22)
        NSColor(white: 1, alpha: 0.015).setFill()
        path.fill()
        path.lineWidth = 1.5
        path.setLineDash([6, 5], count: 2, phase: 0)
        NSColor(white: 1, alpha: 0.14).setStroke()
        path.stroke()
    }
}
