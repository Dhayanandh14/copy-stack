import AppKit
import UniformTypeIdentifiers

/// Saves a clip to a file the user picks — the natural companion to Quick Look
/// when the clip is a screenshot you want to keep.
enum ClipExporter {
    static func save(_ clip: Clip) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName(for: clip)
        panel.allowedContentTypes = [contentType(for: clip)]
        panel.message = "Save this clip"

        DebugLog.write("SAVE opening dialog for clip \(clip.id) (\(clip.kind.rawValue))")
        NSApp.activate(ignoringOtherApps: true)

        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                DebugLog.write("SAVE cancelled")
                return
            }
            do {
                try data(for: clip).write(to: url, options: .atomic)
                DebugLog.write("SAVED clip \(clip.id) -> \(url.path)")
            } catch {
                present(error: error, url: url)
            }
        }

        // Our panel and the Quick Look window both sit at .floating level, so a
        // plain save dialog opens *behind* them and looks like nothing happened.
        // Hanging it off the visible window as a sheet keeps it in front.
        if let parent = QuickLook.currentWindow ?? PanelController.shared.hostWindow {
            DebugLog.write("SAVE presenting as sheet on \(parent.title.isEmpty ? "panel" : parent.title)")
            panel.beginSheetModal(for: parent, completionHandler: complete)
        } else {
            panel.level = .modalPanel
            panel.begin(completionHandler: complete)
        }
    }

    // MARK: Pieces

    private static func data(for clip: Clip) throws -> Data {
        switch clip.kind {
        case .image, .rtf:
            guard let blob = clip.loadBlob() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return blob
        case .text, .fileURL:
            return Data(clip.text.utf8)
        }
    }

    private static func contentType(for clip: Clip) -> UTType {
        switch clip.kind {
        case .image: return .png
        case .rtf: return .rtf
        case .text, .fileURL: return .plainText
        }
    }

    /// A name that's recognisable in a Downloads folder six weeks later.
    private static func suggestedName(for clip: Clip) -> String {
        let stamp = stampFormatter.string(from: clip.createdAt)
        let ext: String
        switch clip.kind {
        case .image: ext = "png"
        case .rtf: ext = "rtf"
        case .text, .fileURL: ext = "txt"
        }

        if let title = clip.title, !title.isEmpty {
            return "\(sanitize(title)).\(ext)"
        }
        if clip.kind == .image {
            return "Clipboard Image \(stamp).\(ext)"
        }
        let snippet = sanitize(String(clip.text.prefix(40)))
        return snippet.isEmpty ? "Clipboard \(stamp).\(ext)" : "\(snippet).\(ext)"
    }

    private static func sanitize(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return String(collapsed.unicodeScalars.filter { !illegal.contains($0) }).prefix(60).description
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    private static func present(error: Error, url: URL) {
        DebugLog.write("SAVE FAILED \(url.path): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.messageText = "Couldn't save the clip"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
