import AppKit

@main
struct PrintingCheck {
    static func close(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.01) {
        precondition(abs(actual - expected) <= tolerance, "\(actual) != \(expected)")
    }

    static func main() {
        _ = NSApplication.shared
        let settings = ImagePrintSettings()
        let accessory = ImagePrintAccessory(settings: settings)
        _ = accessory.view
        var revisions = 0
        let observation = accessory.observe(\.previewRevision) { _, _ in revisions += 1 }
        accessory.modePicker.selectItem(at: ImagePrintScaleMode.custom.rawValue)
        // Send actions without opening the popup's menu.
        NSApp.sendAction(accessory.modePicker.action!, to: accessory, from: accessory.modePicker)
        precondition(settings.mode == .custom && accessory.percentField.isEnabled)
        accessory.percentField.stringValue = "37,5"
        accessory.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                    object: accessory.percentField))
        precondition(settings.percent == 37.5 && revisions >= 2, "live preview must be invalidated while typing")
        withExtendedLifetime(observation) {}
        for value in ["", "0", "-1", "nan", "inf", "1001", "1e300", "abc"] {
            precondition(ImagePrintSettings.percentage(from: value) == nil, "invalid scale: \(value)")
        }
        precondition(ImagePrintSettings.percentage(from: "0,1") == 0.1)
        precondition(ImagePrintSettings.percentage(from: "1000") == 1000)
        precondition(PrintPercentageFormatter().isPartialStringValid("25,", newEditingString: nil,
                                                                   errorDescription: nil))

        let context = ImageProcessing.context(width: 400, height: 200)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 100, width: 400, height: 100))
        let source = context.makeImage()!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePG-print-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for orientation in [NSPrintInfo.PaperOrientation.portrait, .landscape] {
            for mode in ImagePrintScaleMode.allCases {
                let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                info.paperSize = CGSize(width: 595, height: 842)
                info.orientation = orientation
                info.jobDisposition = .save
                let url = directory.appendingPathComponent("\(orientation.rawValue)-\(mode.rawValue).pdf")
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
                settings.mode = mode
                settings.percent = 50
                let operation = ImagePrinting.operation(image: source, title: "Print check", printInfo: info,
                                                       settings: settings)
                operation.showsPrintPanel = false
                operation.showsProgressPanel = false
                precondition(operation.run(), "PDF print operation failed")
                let document = CGPDFDocument(url as CFURL)!
                precondition(document.numberOfPages == 1, "oversized image must not create extra pages")
                let page = document.page(at: 1)!
                let box = page.getBoxRect(.mediaBox)
                close(box.width, info.paperSize.width, tolerance: 1)
                close(box.height, info.paperSize.height, tolerance: 1)
                let raster = ImageProcessing.context(width: Int(box.width.rounded()), height: Int(box.height.rounded()))!
                raster.setFillColor(NSColor.white.cgColor)
                raster.fill(box)
                raster.drawPDFPage(page)
                let bitmap = NSBitmapImageRep(cgImage: raster.makeImage()!)
                var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.greenComponent < 0.3 {
                            minX = min(minX, x); minY = min(minY, y)
                            maxX = max(maxX, x); maxY = max(maxY, y)
                        }
                    }
                }
                let printable = box.insetBy(dx: 18, dy: 18).intersection(operation.printInfo.imageablePageBounds)
                let expected = settings.imageRect(imageSize: CGSize(width: 400, height: 200), printableRect: printable)
                    .intersection(printable)
                close(CGFloat(maxX - minX + 1), expected.width, tolerance: 2)
                close(CGFloat(maxY - minY + 1), expected.height, tolerance: 2)
                close(CGFloat(minX), expected.minX, tolerance: 2)
                // PDF source and annotations use bottom-left coordinates; verify the image isn't inverted.
                let top = bitmap.colorAt(x: (minX + maxX) / 2, y: minY + 2)!.usingColorSpace(.deviceRGB)!
                precondition(top.blueComponent > 0.8 && top.redComponent < 0.2, "printed image is inverted")
            }
        }
        print("OK: live preview KVO, scale validation, portrait/landscape PDF output, fit/fill/manual size, centering, clipping, orientation and single-page pagination")
    }
}
