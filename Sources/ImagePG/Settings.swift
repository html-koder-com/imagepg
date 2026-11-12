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
        window.center()
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeGeneralPane() -> NSView {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 170))
        let label = NSTextField(labelWithString: L("Language") + ":")
        label.alignment = .right
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
        restartNote = NSTextField(wrappingLabelWithString: L("The new language is used after ImagePG restarts."))
        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .secondaryLabelColor
        restartButton = NSButton(title: L("Restart Now"), target: self, action: #selector(restartNow(_:)))
        restartButton.bezelColor = .controlAccentColor
        restartButton.keyEquivalent = "\r"
        for view in [label, languagePicker!, restartNote!, restartButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 170),
            label.firstBaselineAnchor.constraint(equalTo: languagePicker.firstBaselineAnchor),
            languagePicker.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            languagePicker.topAnchor.constraint(equalTo: pane.topAnchor, constant: 28),
            languagePicker.widthAnchor.constraint(equalToConstant: 220),
            restartNote.leadingAnchor.constraint(equalTo: languagePicker.leadingAnchor, constant: 3),
            restartNote.topAnchor.constraint(equalTo: languagePicker.bottomAnchor, constant: 8),
            restartNote.widthAnchor.constraint(equalToConstant: 290),
            restartButton.leadingAnchor.constraint(equalTo: languagePicker.leadingAnchor),
            restartButton.topAnchor.constraint(equalTo: restartNote.bottomAnchor, constant: 12)
        ])
        return pane
    }

    private func update() {
        let changed = AppSettings.language != launchLanguage
        restartNote.isHidden = !changed
        restartButton.isHidden = !changed
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
