# Screenshots

Rendered from the real UI code, not mockups. Regenerate after any layout change:

```bash
CLIPSTACK_DB=/tmp/clipstack-preview.sqlite \
CLIPSTACK_RENDER_SHOTS=./docs \
./.build/release/ClipStack
```

`CLIPSTACK_DB` points the renderer at a throwaway database, so your real
clipboard history is never touched or shown.

Note: the Settings tab bar does not appear in these offscreen captures — AppKit's
tab control needs a real on-screen window to draw. It renders normally in the app.
