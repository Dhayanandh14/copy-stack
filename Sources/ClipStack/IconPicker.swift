import AppKit
import UniformTypeIdentifiers

/// Lets a favorite carry an icon you choose, instead of the source app's.
/// Whatever you pick is downsampled to the row's icon size, so a 4000px
/// artwork and a 32px favicon both land looking right.
enum IconPicker {
    /// 48pt slot on a Retina display, with headroom if the row grows.
    private static let storedPixelSize: CGFloat = 128

    static func choose(for clip: Clip, completion: @escaping () -> Void) {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        open.canChooseDirectories = false
        open.canChooseFiles = true
        open.message = "Choose an icon for this favorite"
        open.prompt = "Use Icon"

        NSApp.activate(ignoringOtherApps: true)

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = open.url else { return }
            guard let png = downsample(url) else {
                report("That file couldn't be read as an image.")
                return
            }
            Store.shared.setCustomIcon(id: clip.id, png)
            ThumbnailCache.shared.dropCustomIcon(id: clip.id)
            DebugLog.write("ICON set for clip \(clip.id) from \(url.lastPathComponent) (\(png.count)b)")
            completion()
        }

        // Same layering trap as the save dialog: our panel floats, so a plain
        // open dialog would sit behind it.
        if let parent = PanelController.shared.hostWindow {
            open.beginSheetModal(for: parent, completionHandler: handle)
        } else {
            open.level = .modalPanel
            open.begin(completionHandler: handle)
        }
    }

    static func clear(for clip: Clip) {
        Store.shared.setCustomIcon(id: clip.id, nil)
        ThumbnailCache.shared.dropCustomIcon(id: clip.id)
        DebugLog.write("ICON cleared for clip \(clip.id)")
    }

    /// ImageIO handles every format the picker accepts — PNG, JPEG, HEIC, TIFF,
    /// GIF, even .icns — and applies EXIF orientation while resizing.
    private static func downsample(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: storedPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private static func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't use that icon"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
