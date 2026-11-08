# Screenshots: macOS region-capture app (Tauri 2)

## Goal
Build a macOS menu-bar app. When you press Print Screen, you select a region of the screen. A native context menu then offers **Copy to Clipboard** or **Open in Editor**. The editor lets you draw colored rectangles on the screenshot, then copy or save the result.

## Context
- Project dir: `/Users/bryan/src/screenshots-tauri` (currently empty, not a git repo yet).
- Machine: macOS 27, Rust 1.99, bun 1.3, Node 26. The Tauri CLI is not installed globally. Use `@tauri-apps/cli` as a dev dependency.
- User shell is fish. Give any commands for the user in fish syntax.
- Commands (after scaffolding):
  - Dev: `bun run tauri dev`
  - Build: `bun run tauri build`
  - Frontend typecheck/build: `bun run build`
  - Rust: `cd src-tauri; cargo check; cargo clippy -- -D warnings`
- The user's keyboard is a Logitech ERGO. Its Print Screen key is expected to send **F13** on macOS. This must be confirmed (task 6).

## Decisions
- Stack: Tauri 2 + Rust backend. Frontend is **vanilla TypeScript + Vite** (no React or other framework). Package manager is **bun**.
- App name `Screenshots`, bundle identifier `com.bryan.screenshots`.
- macOS only. Do not add Windows or Linux code paths.
- **Menu-bar (tray) app only**: no Dock icon (`ActivationPolicy::Accessory`) and no window at launch. The tray menu has `Take Screenshot` (same flow as the hotkey, useful for testing), `Start at Login` (checkbox), and `Quit`.
- **Start at login**: off by default. Toggle it with the tray `Start at Login` checkbox via `tauri-plugin-autostart` (`MacosLauncher::LaunchAgent`, no extra launch args). The checkbox state is read from `autolaunch().is_enabled()` at startup; the OS LaunchAgent is the source of truth, with no separate settings file.
- **Global hotkey F13**, active even when another app is focused. Define it in one constant (`SHORTCUT` in `src-tauri/src/lib.rs`). There is no settings UI. React only to `ShortcutState::Pressed`, not to release.
- **Capture** uses the macOS CLI: `/usr/sbin/screencapture -i -s -x <tmpfile>.png`
  - `-i -s` = interactive **region (mouse drag) selection only**. `-x` = no sound.
  - If the user presses Esc, the file is not created. Treat that as a cancel and do nothing else.
  - Temp files go in `std::env::temp_dir()/com.bryan.screenshots/`, named `capture-<unix_millis>.png`.
- Ignore the hotkey while a capture or context menu is already in progress (`AtomicBool` guard).
- **Context menu** after a successful capture: a native macOS popup menu at the mouse cursor with two items, `Copy to Clipboard` and `Open in Editor`. Esc or clicking outside dismisses it and discards the screenshot.
- **Copy to Clipboard** puts the PNG image (not a file path) on the clipboard, then deletes the temp file.
- **Open in Editor** opens a new editor window that shows the screenshot. Multiple editor windows may be open at once, each with a unique label `editor-<unix_millis>`.
- **Editor features**:
  - Draw rectangles by mouse drag (outline only, no fill). Shift does not constrain to a square.
  - Colors (6 swatches): red `#FF3B30` (default), orange `#FF9500`, yellow `#FFCC00`, green `#34C759`, blue `#007AFF`, black `#000000`.
  - Line widths (3 options): 2, 4 (default), 8 **points**. Stroke width in image pixels = points × `window.devicePixelRatio`, so lines look the same thickness on Retina screens.
  - Changing color or width affects only rectangles drawn afterwards.
  - Rectangles cannot be moved, resized, or deleted individually. **Undo** (Cmd+Z and a button) removes the last rectangle. There is no redo.
  - **Copy** button and Cmd+C: put the flattened image (screenshot + rectangles), at full native resolution, on the clipboard.
  - **Save…** button and Cmd+S: open the native macOS save dialog with default name `Screenshot <YYYY-MM-DD> at <HH.MM.SS>.png`, then write a PNG.
  - Closing the window discards unsaved edits without asking.
- Screenshots are only written to a permanent location when the user clicks Save. Temp files are deleted once consumed (copied, or loaded into the editor). Leftovers in the temp dir are deleted at app startup and quit.
- Plugins allowed: `tauri-plugin-global-shortcut`, `tauri-plugin-clipboard-manager`, `tauri-plugin-dialog`, `tauri-plugin-autostart`. Tauri features: `tray-icon`, `image-png`. Do not add other crates or npm packages unless strictly required. If you must, note why in this file.

## Tasks
Tick each checkbox in this file as you complete it.

- [x] 1. **Scaffold** in the existing dir: `bunx create-tauri-app@latest . --template vanilla-ts --manager bun --identifier com.bryan.screenshots --yes`. If the flags differ, scaffold an equivalent vanilla-ts + bun Tauri 2 project. Set the product name to `Screenshots`. Run `git init` and add a sensible `.gitignore` (`node_modules`, `dist`, `src-tauri/target`). Confirm `bun run tauri dev` launches.
- [ ] 2. **Remove the default window**: delete the `windows` entry in `src-tauri/tauri.conf.json` so nothing opens at launch. In `setup`, call `app.set_activation_policy(tauri::ActivationPolicy::Accessory)`. Keep `index.html` as the editor page (or rename it to `editor.html` and update the Vite config accordingly).
- [ ] 3. **Tray**: in `src-tauri/src/lib.rs` `setup`, build a `TrayIconBuilder` using the app icon (template icon if possible). Its menu has:
  - `Take Screenshot` → `start_capture(app)`.
  - `Start at Login` (`CheckMenuItem`, initial checked = `app.autolaunch().is_enabled()`) → call `enable()` or `disable()` to match the new state. On error, log to stderr and reset the checkbox to the actual `is_enabled()` value.
  - `Quit` → clean the temp dir, then `app.exit(0)`.

  Register `tauri-plugin-autostart` with `MacosLauncher::LaunchAgent` and `None` args.
- [ ] 4. **Temp dir helpers** (`src-tauri/src/capture.rs`): `fn temp_dir() -> PathBuf` (creates the dir if missing), `fn new_capture_path() -> PathBuf`, and `fn clean_temp_dir()` (deletes all files in it, ignoring errors). Call `clean_temp_dir()` at startup.
- [ ] 5. **Capture** (`capture.rs`): implement `pub fn start_capture(app: &AppHandle)`:
  - Return immediately if the `BUSY: AtomicBool` guard is already set. Otherwise set it.
  - On a background thread (`std::thread::spawn` or `tauri::async_runtime::spawn_blocking`), run `screencapture -i -s -x <path>` and wait for it.
  - If the exit status is not success, or the file is missing or empty, clear `BUSY` and return.
  - Otherwise call `app.run_on_main_thread(...)` to show the context menu (task 7) for that path.
  - Clear `BUSY` after the menu closes. Make sure every path clears it, including errors.
- [ ] 6. **Global shortcut**: register `tauri-plugin-global-shortcut` with `SHORTCUT = "F13"`. On `Pressed`, call `start_capture`. If registration fails, log to stderr and keep running so the tray still works. **Before moving on, have the user confirm the hotkey:** run `bun run tauri dev` with a temporary `eprintln!("shortcut fired")` and ask them to press Print Screen on the Logitech ERGO. If it doesn't fire:
  - Check whether Logi Options+ maps that key to a macOS screenshot action. If so, ask the user to set it to the default keystroke or F13.
  - If the key sends something other than F13, ask the user what Logi Options+ or Karabiner-EventViewer shows, update `SHORTCUT`, and record the final key in this file's Decisions.
  - Remove the temporary log afterwards.
- [ ] 7. **Context menu** (`src-tauri/src/menu.rs`): implement `pub fn show_capture_menu(app: &AppHandle, path: PathBuf)`:
  - Build a `Menu` with two `MenuItem`s (ids `copy`, `edit`). Store `path` in managed state (`Mutex<Option<PathBuf>>`, "pending capture").
  - A popup menu needs a window. Use a reusable anchor window with label `menu-anchor`: 1×1 px, `decorations(false)`, `transparent(true)`, `always_on_top(true)`, `skip_taskbar(true)`, not resizable, created once and reused. Move it to `app.cursor_position()`, show it, `set_focus()` it, then call `window.popup_menu(&menu)`. Hide the anchor afterwards. If a hidden anchor works, prefer keeping it hidden.
  - Handle menu events (`app.on_menu_event` or the menu's handler):
    - `copy` → take the pending path, read the PNG, `tauri::image::Image::from_bytes`, `app.clipboard().write_image(&image)`, delete the file.
    - `edit` → take the pending path, then `open_editor(app, path)` (task 8).
  - If the menu closes without a choice (Esc or outside click), delete the pending file and clear the state. On macOS, `popup_menu` returns after the menu closes. Make sure the cancel cleanup doesn't race a selected item's event: only delete if the state is still `Some` after event handling, or defer the check with a short `run_on_main_thread` hop. Pick whichever approach works reliably and add a comment explaining it.
- [ ] 8. **Open editor** (`src-tauri/src/editor.rs`): implement `open_editor(app, path)`:
  - Read the PNG bytes into a managed `Mutex<HashMap<String, Vec<u8>>>` keyed by the new window label `editor-<unix_millis>`, then delete the temp file.
  - Read the image dimensions (decode the PNG header via `tauri::image::Image::from_bytes`). Create a `WebviewWindow` on the editor page with title `Screenshot`. Size: image pixels ÷ the monitor scale factor, plus the toolbar height, clamped to 90% of the current monitor. Center it, `set_focus()`.
  - When the window is destroyed, remove its entry from the map.
- [ ] 9. **Rust commands** (register in `invoke_handler`):
  - `get_capture(window: WebviewWindow) -> tauri::ipc::Response`: returns the raw PNG bytes for `window.label()`, or an error string if missing.
  - `copy_png(app, bytes: Vec<u8>) -> Result<(), String>`: puts the PNG on the clipboard as an image. Accept the body as raw bytes (`tauri::ipc::Request` with an `InvokeBody::Raw` body) to avoid JSON-encoding large arrays.
  - `save_png(path: String, bytes: Vec<u8>) -> Result<(), String>`: writes the file. Raw body as above; pass the path as a header or as a separate small arg, whichever is simplest and correct.
  - Add capability permissions for the plugins and commands to `src-tauri/capabilities/default.json`, scoped to windows `editor-*`.
- [ ] 10. **Editor UI** (`index.html`, `src/main.ts`, `src/styles.css`):
  - Top toolbar: 6 color swatches (the selected one is visibly highlighted), 3 width buttons (each shows a line of that thickness; the selected one is highlighted), Undo, Copy, Save…. Below it, the image area.
  - On load: `invoke('get_capture')` → `Blob` → `createImageBitmap`. Use a `<canvas>` whose **internal size equals the image's native pixel size**, displayed with CSS scaled to fit the area while keeping the aspect ratio (no upscaling past 1 CSS px per image px ÷ DPR).
  - State: `rects: {x, y, w, h, color, widthPx}[]` in image-pixel coordinates. Convert pointer events to image coordinates with `canvas.getBoundingClientRect()` and the canvas/CSS size ratio. Normalize negative width/height. Use pointer capture so dragging outside the canvas still works. Ignore rectangles smaller than 3×3 image px.
  - Redraw = draw the image, then every rectangle, then the live drag preview.
  - Keyboard: Cmd+Z → undo, Cmd+C → copy, Cmd+S → save.
  - Copy: `canvas.toBlob('image/png')` → bytes → `copy_png`. Show a brief "Copied" toast (~1 s).
  - Save: `save()` from `@tauri-apps/plugin-dialog` with the default filename from Decisions and a `png` filter. If cancelled, do nothing. Otherwise call `save_png`, then show a brief "Saved" toast.
  - Show errors in the same toast area, in red.
- [ ] 11. **Permissions note**: the first capture triggers the macOS Screen Recording permission prompt. In dev mode the permission belongs to the terminal app; in the built app it belongs to `Screenshots.app`. Add a short `README.md` covering run/build commands, this permission, and the Logitech key setup from task 6.
- [ ] 12. **Lint and build**: `bun run build`, `cargo clippy -- -D warnings`, and `bun run tauri build` must all pass. Fix any warnings.

## Acceptance criteria
- `bun run build`, `cargo clippy -- -D warnings` (in `src-tauri`), and `bun run tauri build` succeed.
- Launching the app shows a tray icon and no Dock icon or window.
- Pressing Print Screen on the Logitech ERGO (confirmed by the user) starts region selection. The tray's `Take Screenshot` does the same.
- Pressing Esc during selection: nothing else happens. Pressing the hotkey again works.
- After selecting a region, a native menu with `Copy to Clipboard` and `Open in Editor` appears at the cursor.
- `Copy to Clipboard` → pasting into Preview (File → New from Clipboard) shows the region at full resolution.
- Dismissing the menu with Esc leaves no file in the temp dir.
- `Open in Editor` opens a window showing the screenshot, sized to fit the screen.
- Drawing rectangles works with all 6 colors and 3 widths, and they look crisp on a Retina display. Undo removes the latest one.
- Copy in the editor → pasting shows the screenshot with the rectangles at full resolution.
- Save… writes a PNG that opens in Preview with the rectangles.
- Two editor windows can be open at the same time and work independently.
- With the **built** app: checking `Start at Login` creates a LaunchAgent plist in `~/Library/LaunchAgents/`. After logging out and back in, the tray icon appears. Unchecking removes the plist. The checkbox reflects the real state after restarting the app.
- After using all flows and quitting, `$TMPDIR/com.bryan.screenshots/` is empty.

## Out of scope
- Full-screen or window capture modes, delay timers, multi-monitor special handling (beyond what `screencapture -i` does natively).
- Other annotation tools (arrows, text, blur, highlight, crop), moving or resizing rectangles, redo.
- Settings UI, configurable hotkey, auto-update, code signing or notarization.
- Windows or Linux support, tests beyond lint and build (there is no automated UI testing).

## Notes / risks
- **Popup menu from an Accessory app**: the menu may not appear or may not take keyboard input unless the app is active and a window is focused. That's why the anchor window is shown and focused first. If it still fails, try `app.show()` (activates the app on macOS) before `popup_menu`.
- **Thread safety**: menu popups and window creation must run on the main thread (`run_on_main_thread`). `screencapture` must **not** run on the main thread, because it blocks.
- **Global shortcut events** fire on both press and release; handle only `Pressed`.
- **Missing permission**: without Screen Recording permission, `screencapture` may return only the wallpaper, or fail. Don't try to detect this; the README explains it.
- **Logitech Print Screen key**: Logi Options+ may intercept the key and trigger macOS's own screenshot tool. Resolve this with the user in task 6; do not guess.
- **Autostart in dev mode** registers the dev binary path. Test `Start at Login` only with the built `.app` (run it from `src-tauri/target/release/bundle/macos/`, ideally after copying it to `/Applications`). Disable the option before deleting or moving the app.
- **Large IPC payloads**: Retina screenshots can be tens of MB. Use raw-byte IPC (`tauri::ipc::Response` and raw request bodies), not JSON number arrays.
