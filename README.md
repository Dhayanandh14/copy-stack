# ClipStack

A clipboard history manager for macOS. Menu-bar only, unlimited history, local SQLite storage.
Built from scratch — no Xcode required, Command Line Tools are enough.

![ClipStack panel](docs/panel-light.png)

<sub>Dark mode: [docs/panel-dark.png](docs/panel-dark.png) · Settings: [docs/settings-light.png](docs/settings-light.png)</sub>

## Build & install

First time only — create the local signing certificate:

```bash
./tools/make-signing-cert.sh
```

Then:

```bash
./build.sh            # builds ./ClipStack.app
./build.sh install    # builds, copies to /Applications, launches it
```

### Why the certificate matters

macOS ties Accessibility permission to an app's **code signature**. An ad-hoc
signature (`codesign --sign -`) gets a brand-new identity on every build, so
each reinstall silently invalidates the permission you granted — the System
Settings toggle stays switched on but no longer matches the installed app, and
the app keeps asking for a permission you already gave.

Signing with a fixed local certificate makes the requirement stable:

```
ad-hoc:  cdhash H"f1b4a1f5…"                    # different every build
signed:  identifier "local.clipstack.app"
         and certificate leaf = H"8249c907…"    # fixed
```

The certificate is local only, signs nothing but this app, and is not a
credential for any service. Remove it whenever you like:

```bash
security delete-certificate -c "ClipStack Local Signing"
```

`build.sh` warns loudly and falls back to ad-hoc if it is missing.

## Using it

Press **⌘⇧V** anywhere, or click the clipboard icon in the menu bar.

| Key | Action |
|---|---|
| `↑` `↓` | Move selection |
| `↩` | Paste selected clip |
| `⌘↩` | Paste as plain text (strips formatting) |
| `⌘1`…`⌘0` | Paste that numbered row |
| `⌘F` | Toggle favorite |
| `⌘R` | Rename clip (give it a title you can search for) |
| `⌘Y` | Quick Look — full-size preview of the selected clip |
| `⌘S` | Save the clip to a file (while Quick Look is open) |
| right-click | Paste, save, favorite, rename, change icon, delete |
| `⇥` | Switch History ⇄ Favorites |
| `⌘⌫` | Delete clip |
| `⎋` | Close |

System-wide, without opening the panel:

- **⌃⌘1…0** — paste one of the 10 most recent clips
- **⌃⌥1…0** — paste one of your top 10 favorites
- **⌘⇧⌥V** — paste the most recent clip as plain text

All rebindable in Settings → Shortcuts.

## The panel

A narrow column, one clip per row. Each row shows its source app's icon (or a
thumbnail, for images), a type line — `Text, 146 characters` / `Image` — the
content wrapped to three lines, a favorite star, and the clip's age.

Toolbar across the top: **Copy** puts the clip on the clipboard and closes,
**Direct Paste** pastes it into the app you came from, **Quick Look** opens it
full size. The `»` menu holds rename, delete, settings and clear.

## Images

Images are captured automatically and stored as PNG. Rows show a downsampled
thumbnail with the pixel dimensions; Quick Look opens the image at full size,
scaled to fit your screen. Thumbnails are cached by clip id so scrolling a long
history stays smooth.

Images dominate database size, so there's an 8 MB per-image cap (adjustable in
Settings → Privacy) and capture can be switched off entirely.

## Saving clips

**Save…** writes a clip to a file you pick — useful for keeping a screenshot
you pasted earlier. Available from Quick Look (`⌘S`), by right-clicking a row,
and from the `»` menu.

Format follows the clip: images save as PNG, rich text as RTF, plain text as
`.txt`. Filenames are chosen to still make sense later, e.g.
`Clipboard Image 2026-09-24 at 21.52.03.png`, or the clip's title if you renamed it.

## Custom icons for favorites

Right-click any favorite → **Change Icon…** to give it an icon you choose, so
the clips you reach for most are recognisable at a glance. **Reset Icon** puts
the source app's icon back.

Any image works — PNG, JPEG, HEIC, TIFF, GIF, `.icns`. Whatever you pick is
downsampled to the row's icon size, so a 4000px artwork and a 32px favicon both
land looking right. The icon is stored on the clip itself, so it survives
restarts.

Favorites only: it's for the handful of clips you keep, not the whole history.

## Behaviour toggles

Settings → General, all three chosen so the panel behaves like a tool you keep
open rather than a menu that vanishes:

| Setting | Default | What the default gives you |
|---|---|---|
| Close the panel when it loses focus | off | Panel stays up while you click into another app, so you can place the caret first, then pick a clip |
| Close the panel after pasting | off | Paste several clips in a row without reopening |
| Return keyboard focus after pasting | **on** | Typing after a paste goes to the app you pasted into, not the search box |

## Panel size and position

Both persist. Drag the panel's edge, or use the Width/Height sliders in
Settings → Appearance — they drive the same stored values. Position is checked
against attached displays on restore, so a panel left on an external monitor
does not reopen off-screen when you undock.

## Search

Search stays fast no matter how large the history gets, via two mechanisms:

- A **trigram FTS5 index** over text, title and app name. Trigram specifically,
  because it is the one tokenizer that keeps substring matching — `ompose`
  still finds `docker compose`, which a word-based index would break. At
  100,000 clips this takes a query that matched nothing from 169ms to 7ms.
- **Search runs off the main thread**, debounced 120ms. The index alone isn't
  enough: it is *slower* (~110ms) when a term matches nearly every clip,
  because it gathers all matches before sorting. Running it in the background
  means typing is never coupled to query cost. Superseded searches are
  discarded, so only the newest result is applied.

Opening the panel stays synchronous — an empty query is an indexed range read,
fast at any size, and doing it inline avoids a flash of stale rows.

The index is maintained by SQLite triggers, costs roughly 30% extra disk, and is
built once on first launch (gated on `PRAGMA user_version`).

## Capacity

Measured, not estimated. At ~160 clips/day with a third of them screenshots:

| | Clips | Disk |
|---|---|---|
| 1 month | 4,800 | 0.17 GB |
| 1 year | 58,000 | 2.1 GB |
| 2 years | 116,000 | 4.2 GB |

Images dominate: text averages ~114 bytes, images ~113 KB. Turning off image
capture, or lowering the per-image cap, cuts growth by ~99%. There is no clip
count at which typing in the search box stalls the UI.

## Troubleshooting

Turn on a plain-text log of every clipboard event and paste attempt:

```bash
defaults write local.clipstack.app debugLogging -bool true
tail -f ~/Library/Application\ Support/ClipStack/debug.log
```

It records what types were on the pasteboard, which app the copy came from, and
why a clip was skipped or a paste degraded. Turn it off with `-bool false`.

## Accessibility permission

Only needed so ClipStack can press ⌘V for you. Without it everything else works
— selecting a clip puts it on the clipboard and you paste yourself. Grant it at
System Settings → Privacy & Security → Accessibility.

If this Mac is managed by your employer, MDM policy can block that toggle. Turn
off "Paste directly into the active app" in Settings → General and the app works
fine without the permission.

## Privacy

- Everything stays on this Mac. No network code, no accounts, no sync.
- Copies marked `org.nspasteboard.ConcealedType` (what password managers set on
  secrets) are never recorded. Toggle in Settings → Privacy.
- Exclude specific apps by bundle ID in Settings → Privacy.
- Database: `~/Library/Application Support/ClipStack/history.sqlite`

## Storage

History defaults to **unlimited**. Favorites are never pruned regardless of the
limit. Settings → Storage shows the row count and file size, and can clear
history (keeping favorites) or wipe everything.

Rough scale: plain-text clips average well under 1 KB, so 100,000 of them is
around 50 MB. Images dominate size — capped at 8 MB each by default, and
capture can be turned off entirely.

## How it works

macOS has no pasteboard-change notification, so `ClipboardMonitor` polls
`NSPasteboard.general.changeCount` every 0.25 s (configurable) and reads the
pasteboard only when the counter moves. Storage is SQLite in WAL mode. Global
hotkeys use Carbon `RegisterEventHotKey`, the only API that gives system-wide
shortcuts without Accessibility permission. Direct paste synthesises ⌘V with
`CGEvent`, which is the part that needs the permission.

## Layout

```
Sources/ClipStack/
  App.swift              menu bar, lifecycle, hotkey binding, remote triggers
  AppModel.swift         panel view model, selection, clip actions
  ClipboardMonitor.swift changeCount polling + capture
  Store.swift            SQLite; blobs loaded lazily, never in the list query
  Paster.swift           pasteboard writes, synthesised ⌘V, focus handback
  ClipExporter.swift     Save… (NSSavePanel, presented as a sheet)
  QuickLook.swift        full-size preview window
  HotKeyCenter.swift     Carbon global hotkeys
  IconCache.swift        app icons, resolved once per bundle id
  ThumbnailCache.swift   downsampled image thumbnails, by clip id
  DebugLog.swift         opt-in plain-file diagnostics
  Screenshots.swift      offscreen UI render for docs/
  Settings.swift         UserDefaults-backed preferences
  Models.swift           Clip
  IconPicker.swift       custom icons for favorites
  Views/                 panel, rows, settings, hotkey recorder
tools/
  make-signing-cert.sh   one-time local signing certificate
  trigger.swift          open the panel or settings from the CLI
```

### Performance notes

Two things that mattered more than expected:

- **App icons** were resolved through LaunchServices per row, per render.
  Cached now (`IconCache`).
- **Image bytes** were loaded by the list query, so every keystroke in the
  search box pulled every stored screenshot into memory. The list now selects
  `LENGTH(blob)` only; bytes load on demand for thumbnails, Quick Look and paste.

Row layout is fixed-height so every row lines up. The number of body text lines
is derived from the row height rather than hardcoded, so text truncates at a
line boundary instead of being cut through the middle when rows are short.

A subtler one: attaching both a single-tap and double-tap gesture to a row made
SwiftUI wait out the double-click interval before it could resolve a single
click, so every click felt ~250 ms late. One gesture reading `clickCount` off
the live event fixed it.
