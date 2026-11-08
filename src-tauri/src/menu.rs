use std::path::{Path, PathBuf};
use std::sync::Mutex;

use tauri::menu::{Menu, MenuEvent, MenuItem};
use tauri::{AppHandle, Manager, PhysicalPosition, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_clipboard_manager::ClipboardExt;

const ANCHOR: &str = "menu-anchor";

/// Capture waiting for a context-menu choice.
#[derive(Default)]
pub struct PendingCapture(Mutex<Option<PathBuf>>);

fn take_pending(app: &AppHandle) -> Option<PathBuf> {
    app.state::<PendingCapture>().0.lock().unwrap().take()
}

/// Shows the Copy/Edit popup at the cursor. Blocks until the menu closes.
/// Must run on the main thread. Call `finish_capture_menu` afterwards.
pub fn show_capture_menu(app: &AppHandle, path: PathBuf) {
    *app.state::<PendingCapture>().0.lock().unwrap() = Some(path);
    if let Err(e) = popup(app) {
        eprintln!("context menu failed: {e}");
    }
}

/// Discards the capture if the menu was dismissed without a choice.
///
/// Menu clicks reach `on_menu_event` via the event-loop proxy queue, i.e. after
/// `popup_menu` returns. This must be called from a *non-main* thread after the
/// popup has returned: `run_on_main_thread` then posts to the same FIFO queue,
/// so the cleanup runs after any click. (On the main thread it would run
/// immediately and delete the file before the click is handled.)
pub fn finish_capture_menu(app: &AppHandle, path: PathBuf) {
    let app2 = app.clone();
    let _ = app.run_on_main_thread(move || {
        let state = app2.state::<PendingCapture>();
        let mut pending = state.0.lock().unwrap();
        if pending.as_deref() == Some(path.as_path()) {
            *pending = None;
            let _ = std::fs::remove_file(&path);
        }
        drop(pending);
        // Give focus back to the previous app unless an editor is open.
        let editor_open = app2.webview_windows().keys().any(|l| l.starts_with("editor-"));
        if !editor_open {
            let _ = app2.hide();
        }
    });
}

fn popup(app: &AppHandle) -> tauri::Result<()> {
    let copy = MenuItem::with_id(app, "copy", "Copy to Clipboard", true, None::<&str>)?;
    let edit = MenuItem::with_id(app, "edit", "Open in Editor", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&copy, &edit])?;

    // An Accessory app must be active with a focused window for the popup to
    // get keyboard input (Esc), so show and focus a 1x1 anchor at the cursor.
    let anchor = anchor_window(app)?;
    let _ = app.show(); // unhide if hidden after a previous capture
    if let Ok(pos) = app.cursor_position() {
        let _ = anchor.set_position(PhysicalPosition::new(pos.x as i32, pos.y as i32));
    }
    anchor.show()?;
    anchor.set_focus()?;
    let result = anchor.popup_menu(&menu);
    let _ = anchor.hide();
    result
}

fn anchor_window(app: &AppHandle) -> tauri::Result<WebviewWindow> {
    if let Some(w) = app.get_webview_window(ANCHOR) {
        return Ok(w);
    }
    let url = WebviewUrl::External("about:blank".parse().expect("valid url"));
    WebviewWindowBuilder::new(app, ANCHOR, url)
        .inner_size(1.0, 1.0)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .visible(false)
        .build()
}

/// Handles the context-menu items (registered via `app.on_menu_event`).
pub fn on_menu_event(app: &AppHandle, event: &MenuEvent) {
    match event.id().as_ref() {
        "copy" => {
            if let Some(path) = take_pending(app) {
                if let Err(e) = copy_file(app, &path) {
                    eprintln!("copy to clipboard failed: {e}");
                }
                let _ = std::fs::remove_file(&path);
            }
        }
        "edit" => {
            if let Some(path) = take_pending(app) {
                crate::editor::open_editor(app, path);
            }
        }
        _ => {}
    }
}

fn copy_file(app: &AppHandle, path: &Path) -> Result<(), String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    copy_png_bytes(app, &bytes)
}

/// Decodes PNG bytes and puts the image on the clipboard.
pub fn copy_png_bytes(app: &AppHandle, bytes: &[u8]) -> Result<(), String> {
    let image = tauri::image::Image::from_bytes(bytes).map_err(|e| e.to_string())?;
    app.clipboard().write_image(&image).map_err(|e| e.to_string())
}
