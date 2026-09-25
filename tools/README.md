# trigger

Opens ClipStack's panel or settings from the command line, without the menu bar.

```bash
swiftc -O trigger.swift -o clipstack-trigger
./clipstack-trigger            # open the panel
./clipstack-trigger settings   # open settings
```

It posts a distributed notification (`local.clipstack.openPanel` /
`local.clipstack.openSettings`) that the running app listens for. Useful for
scripting, and for reaching the app when a hotkey is taken by something else.

`open -a ClipStack` also opens the panel now.
