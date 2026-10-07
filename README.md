# ClipStack

A clipboard history manager for macOS. Menu-bar only, unlimited history,
everything stored locally.

Built from scratch in Swift — no Xcode required, Command Line Tools are enough.

<img src="docs/panel-dark.png" width="380" alt="ClipStack panel">

---

## Contents

- [Install](#install)
- [Using it](#using-it)
- [Favorites](#favorites)
- [Editing a clip](#editing-a-clip)
- [Images](#images)
- [Saving a clip to a file](#saving-a-clip-to-a-file)
- [Custom icons](#custom-icons)
- [Settings](#settings)
- [Privacy](#privacy)
- [Accessibility](#accessibility)
- [Capacity](#capacity)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Project layout](#project-layout)

---

## Install

```bash
git clone https://github.com/Dhayanandh14/copy-stack.git
cd copy-stack
./tools/make-signing-cert.sh   # first time only
./build.sh install             # builds, installs to /Applications, launches
```

Then press **⌘⇧V** anywhere, or click the clipboard icon in the menu bar.

Requires macOS 13 or later. `./build.sh` alone builds `./ClipStack.app` without
installing it.

On first launch it offers to open the Accessibility settings. That permission is
needed *only* so ClipStack can press ⌘V for you — everything else works without
it. See [Accessibility](#accessibility).

### Why the certificate step exists

macOS ties Accessibility permission to an app's **code signature**. An ad-hoc
signature (`codesign --sign -`) gets a brand-new identity on every build, so
each reinstall silently invalidates the permission you granted — the System
Settings toggle stays switched on but no longer matches the installed app, and
the app keeps asking for a permission you already gave.

Signing with a fixed local certificate makes the requirement stable:

```
ad-hoc:  cdhash H"f1b4a1f5…"                 ← different every single build
signed:  identifier "local.clipstack.app"
         and certificate leaf = H"8249c907…" ← fixed
```

The certificate is local only, signs nothing but this app, and is not a
credential for any service. Remove it whenever you like:

```bash
security delete-certificate -c "ClipStack Local Signing"
```

`build.sh` warns loudly and falls back to ad-hoc if it is missing.

---

## Using it

The panel is a single column, one clip per row. Each row shows the source app's
icon (or a thumbnail, for images), a type line — `Text, 146 characters` — the
content wrapped to fit, a favorite star, and the clip's age.

Every row is the same height, and the number of text lines shown is derived from
that height, so text always truncates at a line boundary.

It follows your system appearance, or uses a palette you choose:

| Dark | Light |
|---|---|
| <img src="docs/panel-dark.png" width="330" alt="Dark appearance"> | <img src="docs/panel-light.png" width="330" alt="Light appearance"> |

**Toolbar:** **Copy** puts the clip on the clipboard and closes · **Direct
Paste** pastes it into the app you came from · **Quick Look** opens it full
size · **»** holds save, rename, delete, settings and clear.

### Keyboard

| Key | Action |
|---|---|
| `⌘⇧V` | Open ClipStack |
| `↑` `↓` | Move selection |
| `↩` | Paste selected clip |
| `⌘↩` | Paste as plain text (strips formatting) |
| `⌘1`…`⌘0` | Paste that numbered row |
| `⌘F` | Toggle favorite |
| `⌘R` | Rename — give a clip a title you can search for |
| `⌘Y` | Quick Look |
| `⌘S` | Save to file (while Quick Look is open) |
| `⇥` | Switch History ⇄ Favorites |
| `⌘⌫` | Delete clip |
| `⌘,` | Settings |
| `⎋` | Close |

Right-click any row for the same actions, plus **Save…** and, on favorites,
**Change Icon…**.

### Without opening the panel

- **⌃⌘1…0** — paste one of the 10 most recent clips
- **⌃⌥1…0** — paste one of your top 10 favorites
- **⌘⇧⌥V** — paste the most recent clip as plain text

All rebindable in Settings → Shortcuts.

---

## Favorites

Press `⌘F` or click the star to keep a clip permanently. Favorites get their own
tab, are never pruned by the history limit, and can carry
[custom icons](#custom-icons).

<img src="docs/panel-favorites.png" width="380" alt="Favorites tab">

---

## Editing a clip

Quick Look (`⌘Y`) is editable for anything that isn't an image. Type in it, then:

- **Save Changes** writes the edit back to the clip
- **Paste** saves first if you have unsaved edits, so you never paste a stale
  version

<img src="docs/quicklook-text.png" width="560" alt="Editable Quick Look">

The usual editing shortcuts all work in there — `⌘C`, `⌘V`, `⌘X`, `⌘A`, `⌘Z` and
right-click — so you can paste something in, splice two clips together, or fix a
typo before pasting.

Works the same on favorites. Edits reindex for search immediately, and the
dedupe fingerprint is recomputed so re-copying the original text later doesn't
merge into the edited row.

> A menu-bar-only app has no main menu, and macOS dispatches those shortcuts
> through menu key equivalents. ClipStack installs a hidden main menu carrying
> them; without it the editor accepts typing but nothing else.

---

## Images

Images are captured automatically and stored as PNG. Rows show a downsampled
thumbnail with the pixel dimensions; Quick Look opens the image at full size,
scaled to fit your screen.

<img src="docs/quicklook-image.png" width="500" alt="Image preview">

Thumbnails are cached by clip id so scrolling a long history stays smooth. There
is a 64 MB per-image cap (Settings → Privacy) and capture can be switched off
entirely.

---

## Saving a clip to a file

**Save…** — from Quick Look (`⌘S`), the right-click menu, or the `»` menu.

Format follows the clip: images save as PNG, rich text as RTF, plain text as
`.txt`. Names are chosen to still make sense weeks later, e.g.
`Clipboard Image 2026-10-07 at 21.52.03.png`, or the clip's title if you renamed it.

---

## Custom icons

Right-click a favorite → **Change Icon…** to give it an icon you choose, so the
clips you reach for most are recognisable at a glance. **Reset Icon** puts the
source app's icon back.

Any image works — PNG, JPEG, HEIC, TIFF, GIF, `.icns`. Whatever you pick is
downsampled to the row's icon size, so a 4000px artwork and a 32px favicon both
land looking right. The icon is stored on the clip, so it survives restarts.

Favorites only: it's for the handful of clips you keep, not the whole history.

---

## Settings

### General

<img src="docs/settings-general.png" width="470" alt="General settings">

| Setting | Default | What the default means |
|---|---|---|
| Launch at login | off | |
| Paste directly into the active app | on | Off: selecting a clip only copies it, and you press ⌘V |
| Close the panel when it loses focus | off | Panel stays up while you click into another app, so you can place the caret first, then pick a clip |
| Close the panel after pasting | off | Paste several clips in a row without reopening |
| Return keyboard focus after pasting | **on** | Typing after a paste goes to the app you pasted into, not the search box |
| Move a clip to the top when you use it | off | Clips stay in the order they were copied, so the one you just used is still where you found it |
| Check clipboard every | 0.25 s | |

Also shows whether Accessibility has been granted, with a button to fix it.

### Appearance

<img src="docs/settings-appearance.png" width="470" alt="Appearance settings">

Font size, row height (56–150), opacity, and whether to show the `⌘N` position
badges. **Everything here applies to the open panel immediately.**

**Panel size** — width and height sliders. Dragging the panel's edge updates
them, and size and position are both restored next time you open it. Position is
checked against attached displays first, so a panel left on an external monitor
doesn't reopen off-screen when you undock.

**Colors** — background, text and selection, with **Reset Colors** to restore
the stock palette. Switch custom colors off to follow the system light/dark
appearance instead. The panel picks its control appearance from the background's
brightness, so a light custom background keeps everything readable.

### Shortcuts

<img src="docs/settings-shortcuts.png" width="470" alt="Shortcut settings">

Rebind the two global hotkeys, toggle the numbered quick-paste shortcuts, and
see the full in-panel key reference. If a combination doesn't take, another app
already owns it.

### Privacy

<img src="docs/settings-privacy.png" width="470" alt="Privacy settings">

Password protection, image capture and its size cap, and per-app exclusions by
bundle identifier. See [Privacy](#privacy).

### Storage

<img src="docs/settings-storage.png" width="470" alt="Storage settings">

Type a maximum number of clips and press Return, or click **Save**. `0` means
unlimited. A warning appears *before* saving if the number would discard clips,
and invalid input is rejected rather than applied.

Also shows the clip count, favorite count and database size, with buttons to
reveal the database in Finder, clear history (keeping favorites) or delete
everything.

---

## Privacy

- **Everything stays on this Mac.** No network code, no accounts, no telemetry,
  no sync.
- **Passwords are not recorded.** Copies marked `org.nspasteboard.ConcealedType`
  — what password managers set on secrets — are skipped.
- **Per-app exclusions.** Add bundle identifiers to never record copies from
  those apps.
- **Favorites are never pruned**, whatever the history limit is set to.

Database: `~/Library/Application Support/ClipStack/history.sqlite`

---

## Accessibility

Needed only so ClipStack can press ⌘V for you. Without it, selecting a clip puts
it on the clipboard and you paste yourself — everything else works.

Grant it at System Settings → Privacy & Security → Accessibility. The panel
shows an orange banner while it's missing.

If this Mac is managed by an employer, MDM policy can block that toggle. Turn
off "Paste directly into the active app" in Settings → General and the app works
fine without the permission.

---

## Capacity

Measured, not estimated. At ~160 clips/day with a third of them screenshots:

| | Clips | Disk |
|---|---|---|
| 1 month | 4,800 | 0.17 GB |
| 1 year | 58,000 | 2.1 GB |
| 2 years | 116,000 | 4.2 GB |

Images dominate: text averages ~114 bytes, images ~113 KB. Turning off image
capture, or lowering the per-image cap, cuts growth by ~99%.

**There is no clip count at which typing in the search box stalls the UI.**

---

## How it works

macOS has no pasteboard-change notification, so `ClipboardMonitor` polls
`NSPasteboard.general.changeCount` every 0.25 s (configurable) and reads the
pasteboard only when the counter moves. It's an integer compare a few times a
second.

Storage is SQLite in WAL mode. Global hotkeys use Carbon `RegisterEventHotKey` —
the only API that gives system-wide shortcuts without Accessibility permission.
Direct paste synthesises ⌘V with `CGEvent`, which is the part that does need it.

### Search

Search stays fast at any history size, via two mechanisms that are both needed:

- A **trigram FTS5 index** over text, title and app name. Trigram specifically,
  because it is the one tokenizer that preserves substring matching — `ompose`
  still finds `docker compose`, which a word-based index would break. At 100,000
  clips this takes a query matching nothing from **169 ms to 7 ms**.
- **Search runs off the main thread**, debounced 120 ms. The index alone isn't
  enough: it is *slower* (~110 ms) when a term matches nearly every clip, because
  it gathers all matches before sorting. Running it in the background decouples
  typing from query cost entirely. Superseded searches are discarded.

Opening the panel stays synchronous — an empty query is an indexed range read,
fast at any size, and doing it inline avoids a flash of stale rows.

The index is maintained by SQLite triggers, costs ~30% extra disk, and is built
once on first launch (gated on `PRAGMA user_version`).

### Performance notes

Three things mattered more than expected:

- **App icons** were resolved through LaunchServices and the disk per row, per
  render. Cached now (`IconCache`).
- **Image bytes** were loaded by the list query, so every keystroke in the search
  box pulled every stored screenshot into memory. The list selects
  `LENGTH(blob)` only; bytes load on demand for thumbnails, Quick Look and paste.
- **Two tap gestures on one row** made SwiftUI wait out the double-click interval
  before it could resolve a single click, so every click felt ~250 ms late. One
  gesture reading `clickCount` off the live event fixed it.

---

## Troubleshooting

Turn on a plain-text log of every clipboard event and paste attempt:

```bash
defaults write local.clipstack.app debugLogging -bool true
tail -f ~/Library/Application\ Support/ClipStack/debug.log
```

It records which types were on the pasteboard, which app the copy came from, and
why a clip was skipped or a paste degraded. Turn it off with `-bool false`.

**It keeps asking for Accessibility.** Check `build.sh` isn't printing the
ad-hoc warning — see [the certificate step](#why-the-certificate-step-exists).

**Screenshots aren't captured.** Full-screen Retina screenshots can exceed the
per-image cap. Raise it in Settings → Privacy; the log says when one is dropped.

---

## Project layout

```
Sources/ClipStack/
  App.swift              menu bar, lifecycle, hotkeys, hidden main menu
  AppModel.swift         panel view model, selection, debounced async search
  ClipboardMonitor.swift changeCount polling + capture
  Store.swift            SQLite; FTS5 index, blobs loaded lazily
  Paster.swift           pasteboard writes, synthesised ⌘V, focus handback
  ClipExporter.swift     Save… (NSSavePanel, presented as a sheet)
  IconPicker.swift       custom icons for favorites
  QuickLook.swift        full-size preview, editable for text
  HotKeyCenter.swift     Carbon global hotkeys
  IconCache.swift        app icons, resolved once per bundle id
  ThumbnailCache.swift   downsampled thumbnails and custom icons
  DebugLog.swift         opt-in plain-file diagnostics
  Screenshots.swift      offscreen UI render for docs/
  Settings.swift         UserDefaults-backed preferences
  Models.swift           Clip
  Views/                 panel, rows, dotted separator, settings, hotkey recorder
tools/
  make-signing-cert.sh   one-time local signing certificate
  trigger.swift          open the panel or settings from the command line
```

`open -a ClipStack` also opens the panel.

Regenerate every screenshot in `docs/` after a UI change:

```bash
CLIPSTACK_DB=/tmp/preview.sqlite CLIPSTACK_RENDER_SHOTS=./docs ./.build/release/ClipStack
```

`CLIPSTACK_DB` points the renderer at a throwaway database seeded with sample
clips, so real clipboard history is never rendered or touched.

---

## License

None yet — default copyright applies, meaning no one else may legally reuse
this. Add a LICENSE file (MIT is the usual choice) before sharing it publicly.
