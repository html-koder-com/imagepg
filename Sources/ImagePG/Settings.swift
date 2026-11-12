import AppKit

/// App preferences stored in the app's own defaults domain.
enum AppSettings {
    /// Languages the app ships, shown by their own names so anyone can find theirs.
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("cs", "Čeština"), ("sk", "Slovenčina"), ("de", "Deutsch"),
        ("fr", "Français"), ("pl", "Polski"), ("hu", "Magyar")
    ]

    /// The language chosen in Settings, or nil to follow macOS.
    static var language: String? {
        get {
            let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String]
            return stored?.first.flatMap { code in languages.first { code.hasPrefix($0.code) }?.code }
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: "AppleLanguages") }
            else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        }
    }
}

/// Preferences window: a toolbar of panes (only "General" for now) above a simple form.
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let general = NSToolbarItem.Identifier("general")
    private let launchLanguage = AppSettings.language
    private var languagePicker: NSPopUpButton!
    private var restartNote: NSTextField!
    private var restartButton: NSButton!
    private var updatesCheckbox: NSButton!
    private var grid: NSGridView!
    var restart: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 170),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Settings")
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "ImagePG.Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = general
        window.contentView = makeGeneralPane()
        update()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeGeneralPane() -> NSView {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        languagePicker = NSPopUpButton()
        languagePicker.addItem(withTitle: L("Same as system"))
        languagePicker.menu?.addItem(.separator())
        for language in AppSettings.languages {
            languagePicker.addItem(withTitle: language.name)
            languagePicker.lastItem?.representedObject = language.code
        }
        if let current = AppSettings.language,
           let index = languagePicker.itemArray.firstIndex(where: { $0.representedObject as? String == current }) {
            languagePicker.selectItem(at: index)
        } else {
            languagePicker.selectItem(at: 0)
        }
        languagePicker.target = self
        languagePicker.action = #selector(languageChanged(_:))
        languagePicker.translatesAutoresizingMaskIntoConstraints = false
        languagePicker.widthAnchor.constraint(equalToConstant: 220).isActive = true
        restartNote = NSTextField(wrappingLabelWithString: L("The new language is used after ImagePG restarts."))
        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .secondaryLabelColor
        restartNote.preferredMaxLayoutWidth = 280
        restartButton = NSButton(title: L("Restart Now"), target: self, action: #selector(restartNow(_:)))
        restartButton.bezelColor = .controlAccentColor
        restartButton.keyEquivalent = "\r"
        let restartStack = NSStackView(views: [restartNote, restartButton])
        restartStack.orientation = .vertical
        restartStack.alignment = .leading
        restartStack.spacing = 10
        updatesCheckbox = NSButton(checkboxWithTitle: L("Check for updates at launch"), target: self,
                                   action: #selector(updatesChanged(_:)))
        updatesCheckbox.state = UpdateChecker.checksAtLaunch ? .on : .off

        grid = NSGridView(views: [
            [label(L("Language") + ":"), languagePicker],
            [NSGridCell.emptyContentView, restartStack],
            [label(L("Updates") + ":"), updatesCheckbox]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 150
        grid.rowAlignment = .firstBaseline
        grid.row(at: 2).topPadding = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        let pane = NSView()
        pane.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: pane.trailingAnchor, constant: -30),
            grid.topAnchor.constraint(equalTo: pane.topAnchor, constant: 26),
            grid.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -26),
            pane.widthAnchor.constraint(equalToConstant: 500)
        ])
        return pane
    }

    @objc private func updatesChanged(_ sender: Any?) {
        UpdateChecker.checksAtLaunch = updatesCheckbox.state == .on
    }

    private func update() {
        grid.row(at: 1).isHidden = AppSettings.language == launchLanguage
        window?.layoutIfNeeded()
        if let window, let pane = window.contentView {
            // Let the window grow or shrink with the restart hint.
            let size = pane.fittingSize
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
    }

    @objc private func languageChanged(_ sender: Any?) {
        AppSettings.language = languagePicker.selectedItem?.representedObject as? String
        update()
    }

    @objc private func restartNow(_ sender: Any?) { restart?() }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [general] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [general] }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [general] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L("General")
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("General"))
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
    @objc private func selectPane(_ sender: Any?) {}
}
