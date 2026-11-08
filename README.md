# Screenshots

macOS menu-bar app (Tauri 2). Press Cmd+Shift+4, drag a region, then choose
**Copy to Clipboard** or **Open in Editor**. The editor lets you draw colored
rectangles and copy or save the result.

## Commands

```fish
bun install
bun run tauri dev      # run in dev mode
bun run tauri build    # build src-tauri/target/release/bundle/macos/Screenshots.app
bun run build          # frontend typecheck + build
cd src-tauri; cargo clippy -- -D warnings; cd ..
```

## Screen Recording permission

The first capture triggers the macOS Screen Recording prompt. Without it,
captures show only the wallpaper or fail. Grant it in System Settings → Privacy
& Security → Screen Recording:

- Dev mode: the permission belongs to the terminal app that runs `bun run tauri dev`.
- Built app: it belongs to `Screenshots.app`.

## Hotkey

The app listens for **Cmd+Shift+4** (`SHORTCUT` in `src-tauri/src/lib.rs`).
Disable macOS's own "Save picture of selected area as a file" shortcut in
System Settings → Keyboard → Keyboard Shortcuts → Screenshots, or it takes the
key first.

A Logitech ERGO K860 Print Screen remap (Logi Options+ keystroke
Ctrl+Opt+Cmd+R) was tried and dropped: Logi's agent posted an event but it never
reached the hotkey.

The tray menu's **Take Screenshot** runs the same flow.

## Start at Login

Toggle it in the tray menu. It creates a LaunchAgent in `~/Library/LaunchAgents/`.
Use it only with the built app (dev mode would register the dev binary), and turn
it off before moving or deleting the app.
