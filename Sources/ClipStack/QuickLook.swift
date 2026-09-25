import AppKit
import SwiftUI

/// A floating preview of one clip at full size — images at their real
/// dimensions (scaled to fit the screen), text scrollable and selectable.
enum QuickLook {
    private static var window: NSWindow?

    /// The open preview window, if any — a save sheet should hang off it.
    static var currentWindow: NSWindow? { window?.isVisible == true ? window : nil }

    static func show(_ clip: Clip) {
        close()

        let view = QuickLookView(clip: clip)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = clip.metaLine
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.setContentSize(preferredSize(for: clip))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
    }

    /// Fit the image's real size to the screen, leaving a margin.
    private static func preferredSize(for clip: Clip) -> NSSize {
        guard clip.kind == .image, let blob = clip.loadBlob(),
              let rep = NSBitmapImageRep(data: blob)
        else { return NSSize(width: 640, height: 460) }

        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let maxW = visible.width * 0.7, maxH = visible.height * 0.8
        var w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = min(1, min(maxW / w, maxH / h))
        w *= scale; h *= scale
        return NSSize(width: max(280, w), height: max(200, h + 28))
    }
}

private struct QuickLookView: View {
    let clip: Clip
    @State private var loaded: NSImage?
    @State private var draft: String = ""
    @State private var savedFlash = false

    private var isEditable: Bool { clip.kind != .image }
    private var hasEdits: Bool { isEditable && draft != clip.text }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if clip.kind == .image, let image = loaded {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Editable in place: Quick Look doubles as the scratch pad
                    // for fixing a typo before pasting.
                    TextEditor(text: $draft)
                        .font(.system(size: 13, design: clip.kind == .fileURL ? .monospaced : .default))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                if clip.kind == .image, loaded == nil { loaded = clip.loadImage() }
                if draft.isEmpty { draft = clip.text }
            }

            Divider()
            HStack(spacing: 10) {
                if savedFlash {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else if hasEdits {
                    Label("Edited", systemImage: "pencil.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else {
                    if let appName = clip.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save to File\u{2026}") { ClipExporter.save(clip) }
                if isEditable {
                    Button("Save Changes") { commit() }
                        .disabled(!hasEdits)
                }
                Button("Paste") {
                    if hasEdits { commit() }
                    QuickLook.close()
                    AppModel.shared.activate(latestClip())
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Writes the edit back to the clip and refreshes the list behind us.
    private func commit() {
        let text = draft
        Store.shared.updateText(id: clip.id, text)
        AppModel.shared.reload()
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { savedFlash = false }
        }
    }

    /// Pasting after an edit must use the edited text, not the stale copy this
    /// view was handed when it opened.
    private func latestClip() -> Clip {
        var updated = clip
        updated.text = draft
        return updated
    }
}
