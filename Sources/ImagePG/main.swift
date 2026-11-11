import AppKit

let application = NSApplication.shared
let delegate = ImagePGAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)

// Set the Dock icon explicitly. The bundle resource is used for the .app; the
// source-tree fallback also covers development launches with `swift run`.
let sourceIcon = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/ImagePG.png")
let iconURLs = [Bundle.main.url(forResource: "ImagePG", withExtension: "png"), sourceIcon]
for case let url? in iconURLs {
    if let icon = NSImage(contentsOf: url) {
        application.applicationIconImage = icon
        break
    }
}

application.run()
