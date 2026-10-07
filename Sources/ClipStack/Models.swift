import AppKit
import Foundation

enum ClipKind: String {
    case text
    case rtf
    case image
    case fileURL

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .rtf: return "doc.richtext"
        case .image: return "photo"
        case .fileURL: return "folder"
        }
    }
}

struct Clip: Identifiable, Hashable {
    var id: Int64
    var kind: ClipKind
    /// Plain-text representation. Used for display, search and plain-text paste.
    var text: String
    /// User-assigned title. Shown instead of `text` in the list when present.
    var title: String?
    var appName: String?
    var appBundleID: String?
    /// Size of the stored PNG/RTF payload. The bytes themselves are loaded on
    /// demand — keeping them out of the list model keeps selection snappy.
    var blobSize: Int
    var createdAt: Date
    var favorite: Bool
    var favoriteOrder: Int
    var digest: String
    /// Size of a user-chosen icon for this clip, 0 when there isn't one.
    var customIconSize: Int
    /// Hides this clip's contents in the list until it is unmarked.
    var sensitive: Bool

    /// Grey header line above each row's content, e.g. "Text, 146 characters".
    var metaLine: String {
        if sensitive { return "Hidden" }
        switch kind {
        case .text:    return "Text, \(text.count) character\(text.count == 1 ? "" : "s")"
        case .rtf:     return "Rich Text, \(text.count) character\(text.count == 1 ? "" : "s")"
        case .image:   return "Image"
        case .fileURL:
            let n = text.split(whereSeparator: \.isNewline).count
            return n == 1 ? "File" : "\(n) Files"
        }
    }

    /// A fixed-width mask, so it doesn't leak how long the content is.
    private static let mask = String(repeating: "\u{2022}", count: 10)

    /// The wrapped body text of a row. Images carry their dimensions here.
    /// A title you chose stays visible even when the clip is hidden — that's
    /// the label you find it by; it's the contents that are secret.
    var bodyText: String {
        if let title, !title.isEmpty { return title }
        if sensitive { return Clip.mask }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shown small beneath the title, when the user has renamed the clip.
    var subtitleText: String? {
        guard let title, !title.isEmpty else { return nil }
        if sensitive { return Clip.mask }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    /// What the list row shows.
    var displayLabel: String {
        if let title, !title.isEmpty { return title }
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flat.isEmpty { return kind == .image ? "Image" : "(empty)" }
        return flat
    }

    var hasBlob: Bool { blobSize > 0 }

    var hasCustomIcon: Bool { customIconSize > 0 }

    func loadBlob() -> Data? { Store.shared.blob(for: id) }

    func loadImage() -> NSImage? {
        guard kind == .image, let data = loadBlob() else { return nil }
        return NSImage(data: data)
    }

    var appIcon: NSImage? { IconCache.shared.icon(forBundleID: appBundleID) }

    /// "2m", "4h", "3d" — compact age used in the row's trailing edge.
    var age: String {
        let s = Int(Date().timeIntervalSince(createdAt))
        if s < 60 { return "\(max(s, 0))s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }
}
