import AppKit
import SwiftUI

struct ClipRowView: View {
    let clip: Clip
    let index: Int
    let selected: Bool

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings
    @State private var draftTitle: String = ""

    private var isRenaming: Bool { model.renamingID == clip.id }

    /// A selected row only gets the emphatic blue while the panel actually has
    /// the keyboard; otherwise it drops to the system's unemphasized grey.
    private var isEmphasized: Bool { selected && model.panelIsKey }

    private var accent: Color {
        if settings.useCustomColors {
            return model.panelIsKey ? settings.accentColor : settings.accentColor.opacity(0.4)
        }
        return model.panelIsKey
            ? Color(nsColor: .selectedContentBackgroundColor)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var primary: Color {
        if isEmphasized { return .white }
        return settings.useCustomColors ? settings.textColor : Color(nsColor: .labelColor)
    }

    private var muted: Color {
        if isEmphasized { return Color.white.opacity(0.75) }
        return settings.useCustomColors ? settings.textColor.opacity(0.55) : Color.secondary
    }

    /// How many whole lines of body text fit in the fixed row, after the meta
    /// line, the footer and padding have taken their share. Deriving this keeps
    /// text from being clipped through the middle of a line when rows are short.
    private var bodyLineLimit: Int {
        let lineHeight = settings.fontSize * 1.32
        let chrome = 14.0 + 12.0 + 3.0   // padding, meta line, spacing
        let available = settings.rowHeight - chrome - (clip.subtitleText != nil ? lineHeight : 0)
        return max(1, min(4, Int(available / lineHeight)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leading
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                header
                if isRenaming {
                    TextField("Title", text: $draftTitle, onCommit: {
                        model.rename(clip, to: draftTitle)
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: settings.fontSize))
                    .onAppear { draftTitle = clip.title ?? "" }
                } else {
                    // Keep a gutter on the right so text wraps before it
                    // reaches the edge, instead of crowding the star and the
                    // timestamp that sit over there.
                    Text(clip.bodyText)
                        .font(.system(size: settings.fontSize))
                        .foregroundStyle(primary)
                        .lineLimit(bodyLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 22)

                    if let subtitle = clip.subtitleText {
                        Text(subtitle)
                            .font(.system(size: settings.fontSize - 2))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .padding(.trailing, 22)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The age lives in the right gutter rather than on a row of its
            // own — a whole line of vertical space for four characters.
            .overlay(alignment: .bottomTrailing) {
                Text(clip.age)
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // Fixed, not minimum: every row is the same height regardless of how
        // long the text is or how tall the image is.
        .frame(maxWidth: .infinity, minHeight: settings.rowHeight,
               maxHeight: settings.rowHeight, alignment: .leading)
        .clipped()
        // Inset the highlight so it reads as a selected card rather than a
        // full-bleed band. The hit area stays the whole row.
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? accent : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
    }

    // MARK: Pieces

    /// Image clips preview themselves; everything else shows its source app.
    @ViewBuilder
    private var leading: some View {
        if let chosen = ThumbnailCache.shared.customIcon(for: clip) {
            // App icons arrive from macOS with depth already in the artwork —
            // a rounded squircle, a lit top edge, a shadow underneath. A flat
            // PNG next to them reads as pasted on, so the same treatment is
            // applied here: clip to the squircle, catch a highlight along the
            // edge, and float it off the background.
            Image(nsImage: chosen)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.38), radius: 2.5, x: 0, y: 1.5)
        } else if clip.kind == .image, let thumb = ThumbnailCache.shared.thumbnail(for: clip) {
            // Shown bare and aspect-correct: a wide banner stays wide, a tall
            // screenshot stays tall. A tile behind it just reads as chrome.
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // Sized against the icon slot, not the row height: letting a
                // thumbnail grow to fill a tall row made image rows tower over
                // the app icons beside them.
                .frame(maxWidth: 52, maxHeight: 54)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else if let appIcon = clip.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
        } else {
            Image(systemName: clip.kind.symbol)
                .font(.system(size: 25))
                .foregroundStyle(muted)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(settings.showNumberBadges && index < 10 ? "\u{2318}\(index == 9 ? 0 : index + 1)" : "")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(muted.opacity(0.8))
                .frame(width: 18, alignment: .leading)
            Spacer(minLength: 0)
            Text(clip.metaLine)
                .font(.system(size: 10))
                .foregroundStyle(muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.toggleFavorite(clip)
            } label: {
                Image(systemName: clip.favorite ? "star.fill" : "star")
                    .font(.system(size: 10))
                    // Filled stars follow the text colour rather than being
                    // yellow: white on dark, dark on light, white on a selected
                    // row. Yellow fought with the app icons for attention.
                    .foregroundStyle(clip.favorite ? primary : muted.opacity(0.55))
            }
            .buttonStyle(.plain)
            .frame(width: 18, alignment: .trailing)
            .help(clip.favorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

}
