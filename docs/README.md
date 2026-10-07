# Screenshots

Rendered from the real UI code, not mockups. Regenerate after any UI change:

```bash
CLIPSTACK_DB=/tmp/clipstack-preview.sqlite \
CLIPSTACK_RENDER_SHOTS=./docs \
./.build/release/ClipStack
```

`CLIPSTACK_DB` points the renderer at a throwaway database seeded with generic
sample clips, so real clipboard history is never rendered or touched.

| File | Shows |
|---|---|
| `panel-dark.png` / `panel-light.png` | History, both appearances |
| `panel-favorites.png` | Favorites tab |
| `quicklook-text.png` | Editable Quick Look |
| `quicklook-image.png` | Image preview |
| `settings-*.png` | Each settings tab |

Settings tabs are rendered directly rather than through the `TabView`, because a
tab strip does not draw in an offscreen capture.
