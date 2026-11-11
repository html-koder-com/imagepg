import AppKit
import UniformTypeIdentifiers

final class FieldSync: NSObject, NSTextFieldDelegate {
    var changed: ((NSTextField) -> Void)?
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField { changed?(field) }
    }
}

final class DialogAction: NSObject {
    var action: (() -> Void)?
    @objc func invoke(_ sender: Any?) { action?() }
}

enum EditorDialogs {
    static func label(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        return label
    }

    static func field(_ value: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.stringValue = value
        field.alignment = .right
        return field
    }

    static func resize(width: Int, height: Int) -> (Int, Int)? {
        let alert = NSAlert()
        alert.messageText = "Změnit velikost obrázku"
        alert.informativeText = "Poměr stran zůstane zachován."
        alert.addButton(withTitle: "Změnit velikost")
        alert.addButton(withTitle: "Zrušit")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 124))
        let widthField = field("\(width)", frame: NSRect(x: 100, y: 88, width: 115, height: 24))
        let heightField = field("\(height)", frame: NSRect(x: 100, y: 52, width: 115, height: 24))
        let percentField = field("100", frame: NSRect(x: 100, y: 16, width: 115, height: 24))
        for (text, y) in [("Šířka (px)", 91.0), ("Výška (px)", 55.0), ("Velikost (%)", 19.0)] {
            view.addSubview(label(text, frame: NSRect(x: 0, y: y, width: 96, height: 20)))
        }
        [widthField, heightField, percentField].forEach(view.addSubview)
        let sync = FieldSync()
        var updating = false
        sync.changed = { changed in
            guard !updating else { return }
            updating = true
            defer { updating = false }
            if changed === widthField, let value = Int(widthField.stringValue), value > 0 {
                heightField.integerValue = max(1, Int((Double(value) * Double(height) / Double(width)).rounded()))
                percentField.stringValue = String(format: "%.1f", Double(value) * 100 / Double(width))
            } else if changed === heightField, let value = Int(heightField.stringValue), value > 0 {
                widthField.integerValue = max(1, Int((Double(value) * Double(width) / Double(height)).rounded()))
                percentField.stringValue = String(format: "%.1f", Double(value) * 100 / Double(height))
            } else if changed === percentField,
                      let value = Double(percentField.stringValue.replacingOccurrences(of: ",", with: ".")), value > 0 {
                widthField.integerValue = max(1, Int((Double(width) * value / 100).rounded()))
                heightField.integerValue = max(1, Int((Double(height) * value / 100).rounded()))
            }
        }
        [widthField, heightField, percentField].forEach { $0.delegate = sync }
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn,
              let newWidth = Int(widthField.stringValue), let newHeight = Int(heightField.stringValue),
              newWidth > 0, newHeight > 0 else { return nil }
        return (newWidth, newHeight)
    }

    static func canvas(width: Int, height: Int) -> (Int, Int, Int, NSColor?)? {
        let alert = NSAlert()
        alert.messageText = "Velikost plátna"
        alert.informativeText = "Při zmenšení se obrázek ořízne, při zvětšení se doplní pozadí."
        alert.addButton(withTitle: "Použít")
        alert.addButton(withTitle: "Zrušit")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 178))
        let widthField = field("\(width)", frame: NSRect(x: 130, y: 145, width: 115, height: 24))
        let heightField = field("\(height)", frame: NSRect(x: 130, y: 113, width: 115, height: 24))
        view.addSubview(label("Šířka (px)", frame: NSRect(x: 0, y: 148, width: 120, height: 20)))
        view.addSubview(label("Výška (px)", frame: NSRect(x: 0, y: 116, width: 120, height: 20)))
        view.addSubview(widthField); view.addSubview(heightField)
        let anchor = NSPopUpButton(frame: NSRect(x: 130, y: 77, width: 200, height: 27))
        anchor.addItems(withTitles: ["Vlevo nahoře", "Nahoře", "Vpravo nahoře", "Vlevo", "Uprostřed", "Vpravo", "Vlevo dole", "Dole", "Vpravo dole"])
        anchor.selectItem(at: 4)
        view.addSubview(label("Ukotvení", frame: NSRect(x: 0, y: 80, width: 120, height: 20)))
        view.addSubview(anchor)
        let transparent = NSButton(checkboxWithTitle: "Průhledné pozadí", target: nil, action: nil)
        transparent.frame = NSRect(x: 0, y: 44, width: 220, height: 24)
        transparent.state = .on
        view.addSubview(transparent)
        let colorWell = NSColorWell(frame: NSRect(x: 130, y: 5, width: 70, height: 28))
        colorWell.color = .white
        colorWell.isEnabled = false
        let action = DialogAction()
        action.action = { colorWell.isEnabled = transparent.state != .on }
        transparent.target = action; transparent.action = #selector(DialogAction.invoke(_:))
        view.addSubview(label("Barva pozadí", frame: NSRect(x: 0, y: 9, width: 120, height: 20)))
        view.addSubview(colorWell)
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn,
              let newWidth = Int(widthField.stringValue), let newHeight = Int(heightField.stringValue),
              newWidth > 0, newHeight > 0 else { return nil }
        return (newWidth, newHeight, anchor.indexOfSelectedItem, transparent.state == .on ? nil : colorWell.color)
    }

    static func angle(preview: CGImage) -> Double? {
        let alert = NSAlert()
        alert.messageText = "Otočit o libovolný úhel"
        alert.informativeText = "Kladné hodnoty otáčejí doleva."
        alert.addButton(withTitle: "Otočit")
        alert.addButton(withTitle: "Zrušit")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 330))
        let imageView = NSImageView(frame: NSRect(x: 55, y: 71, width: 310, height: 250))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)
        let slider = NSSlider(value: 0, minValue: -180, maxValue: 180,
                              target: nil, action: nil)
        slider.frame = NSRect(x: 0, y: 37, width: 310, height: 24)
        slider.isContinuous = true
        let valueField = field("0", frame: NSRect(x: 325, y: 37, width: 60, height: 24))
        let scale = min(1, 700 / Double(max(preview.width, preview.height)))
        let previewImage = scale == 1 ? preview :
            (ImageProcessing.resized(preview,
                width: max(1, Int((Double(preview.width) * scale).rounded())),
                height: max(1, Int((Double(preview.height) * scale).rounded()))) ?? preview)
        func updatePreview(_ angle: Double) {
            guard let rotated = ImageProcessing.rotated(previewImage, degrees: angle) else { return }
            imageView.image = NSImage(cgImage: rotated, size: NSSize(width: rotated.width, height: rotated.height))
        }
        updatePreview(0)
        let sliderAction = DialogAction()
        sliderAction.action = {
            valueField.integerValue = Int(slider.doubleValue.rounded())
            updatePreview(slider.doubleValue)
        }
        slider.target = sliderAction; slider.action = #selector(DialogAction.invoke(_:))
        let fieldAction = DialogAction()
        fieldAction.action = {
            if let angle = Double(valueField.stringValue.replacingOccurrences(of: ",", with: ".")) {
                slider.doubleValue = max(-180, min(180, angle))
                updatePreview(angle)
            }
        }
        valueField.target = fieldAction; valueField.action = #selector(DialogAction.invoke(_:))
        view.addSubview(slider); view.addSubview(valueField)
        view.addSubview(label("°", frame: NSRect(x: 390, y: 39, width: 20, height: 20)))
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn,
              let result = Double(valueField.stringValue.replacingOccurrences(of: ",", with: ".")),
              result.isFinite, abs(result) <= 3600 else { return nil }
        return result
    }

    static func saveAs(defaultURL: URL?, panel: NSSavePanel = NSSavePanel()) -> (URL, String, Double, Bool, NSColor)? {
        let available = ImageProcessing.writableExtensions.filter(ImageProcessing.canWrite)
        guard !available.isEmpty else { return nil }
        panel.title = "Uložit obrázek jako"
        panel.directoryURL = defaultURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        let suggestedType = defaultURL?.pathExtension.lowercased() ?? "png"
        let initialType = available.contains(suggestedType) ? suggestedType : available[0]
        panel.nameFieldStringValue = (defaultURL?.deletingPathExtension().lastPathComponent ?? "Obrázek") + "." + initialType
        panel.allowedContentTypes = [ImageProcessing.type(for: initialType)!]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 112))
        let format = NSPopUpButton(frame: NSRect(x: 125, y: 80, width: 190, height: 26))
        format.addItems(withTitles: available.map { $0.uppercased() })
        format.selectItem(at: available.firstIndex(of: initialType) ?? 0)
        let quality = NSSlider(value: 0.9, minValue: 0.01, maxValue: 1, target: nil, action: nil)
        quality.frame = NSRect(x: 125, y: 52, width: 190, height: 22)
        let transparency = NSButton(checkboxWithTitle: "Zachovat průhlednost", target: nil, action: nil)
        transparency.frame = NSRect(x: 125, y: 24, width: 205, height: 22)
        transparency.state = .on
        let background = NSColorWell(frame: NSRect(x: 125, y: 0, width: 70, height: 24))
        background.color = .white
        view.addSubview(label("Formát", frame: NSRect(x: 0, y: 83, width: 110, height: 20)))
        view.addSubview(label("Kvalita komprese", frame: NSRect(x: 0, y: 53, width: 120, height: 20)))
        view.addSubview(format); view.addSubview(quality); view.addSubview(transparency); view.addSubview(background)
        let formatAction = DialogAction()
        formatAction.action = {
            let selected = available[format.indexOfSelectedItem]
            let current = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.allowedContentTypes = [ImageProcessing.type(for: selected)!]
            panel.nameFieldStringValue = current + "." + selected
            let supportsAlpha = !["jpg", "bmp"].contains(selected)
            transparency.isEnabled = supportsAlpha
            transparency.state = supportsAlpha ? .on : .off
            quality.isEnabled = ["jpg", "heic", "webp", "avif"].contains(selected)
        }
        format.target = formatAction; format.action = #selector(DialogAction.invoke(_:))
        formatAction.action?()
        panel.accessoryView = view
        // NSControl does not retain its target. Keep format changes working for the
        // entire modal session, including in optimized builds.
        let response = withExtendedLifetime(formatAction) { panel.runModal() }
        guard response == .OK, let url = panel.url else { return nil }
        let selected = available[format.indexOfSelectedItem]
        let destination = url.pathExtension.lowercased() == selected
            ? url : url.deletingPathExtension().appendingPathExtension(selected)
        if destination != url && FileManager.default.fileExists(atPath: destination.path) {
            let alert = NSAlert()
            alert.messageText = "Soubor již existuje"
            alert.informativeText = "Chcete nahradit soubor \(destination.lastPathComponent)?"
            alert.addButton(withTitle: "Nahradit")
            alert.addButton(withTitle: "Zrušit")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        }
        return (destination, selected, quality.doubleValue,
                transparency.state == .on, background.color)
    }
}
