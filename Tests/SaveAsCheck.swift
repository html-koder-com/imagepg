import AppKit

// Exercise the real accessory controls without opening the system file browser.
final class CheckingSavePanel: NSSavePanel {
    var checked = false

    override func runModal() -> NSApplication.ModalResponse {
        let available = ImageProcessing.writableExtensions.filter(ImageProcessing.canWrite)
        let format = accessoryView!.subviews.compactMap { $0 as? NSPopUpButton }.first!
        precondition(format.target != nil, "Format action must survive until the modal session")
        for name in ["Rodinná fotka.v2.png", "Vlastní název.png"] {
            nameFieldStringValue = name
            let stem = (name as NSString).deletingPathExtension
            for (index, ext) in available.enumerated() {
                format.selectItem(at: index)
                precondition(NSApp.sendAction(format.action!, to: format.target, from: format))
                precondition(nameFieldStringValue == stem + "." + ext,
                             "Filename must immediately match format \(ext): \(nameFieldStringValue)")
                precondition(allowedContentTypes == [ImageProcessing.type(for: ext)!])
            }
        }
        checked = true
        return .cancel
    }
}

@main
struct SaveAsCheck {
    static func main() {
        _ = NSApplication.shared
        let panel = CheckingSavePanel()
        let result = EditorDialogs.saveAs(defaultURL: URL(fileURLWithPath: "/tmp/Rodinná fotka.v2.png"), panel: panel)
        precondition(panel.checked && result == nil, "Cancellation must return no destination")
        print("OK: immediate filename extension updates for all writable formats, custom names, multiple dots and cancellation")
    }
}
