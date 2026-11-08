mod capture;

use tauri::menu::{CheckMenuItem, Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::App;
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

/// Global hotkey that starts a capture. Logi Options+ maps the ERGO K860 Print
/// Screen key to Ctrl+Opt+Cmd + HID key 0x15. Hotkeys match the physical key, so
/// this is `KeyR` (QWERTY position) even though Colemak-DH types "P" there.
const SHORTCUT: &str = "Control+Alt+Super+KeyR";

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

fn setup_tray(app: &App) -> tauri::Result<()> {
    let autostart_on = app.autolaunch().is_enabled().unwrap_or_else(|e| {
        eprintln!("autostart is_enabled failed: {e}");
        false
    });

    let take = MenuItem::with_id(app, "take", "Take Screenshot", true, None::<&str>)?;
    let login = CheckMenuItem::with_id(
        app,
        "login",
        "Start at Login",
        true,
        autostart_on,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&take, &login, &quit])?;

    let mut tray = TrayIconBuilder::with_id("main")
        .tooltip("Screenshots")
        .menu(&menu)
        .show_menu_on_left_click(true);
    if let Some(icon) = app.default_window_icon() {
        // The app icon is full-color, so it is not used as a template image.
        tray = tray.icon(icon.clone());
    }

    tray.on_menu_event(move |app, event| match event.id().as_ref() {
        "take" => capture::start_capture(app),
        "login" => {
            // macOS toggles the check state before the event fires.
            let want = login.is_checked().unwrap_or(false);
            let manager = app.autolaunch();
            let result = if want {
                manager.enable()
            } else {
                manager.disable()
            };
            if let Err(e) = result {
                eprintln!("autostart toggle failed: {e}");
                let actual = manager.is_enabled().unwrap_or(false);
                let _ = login.set_checked(actual);
            }
        }
        "quit" => {
            capture::clean_temp_dir();
            app.exit(0);
        }
        _ => {}
    })
    .build(app)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        capture::start_capture(app);
                    }
                })
                .build(),
        )
        .setup(|app| {
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            capture::clean_temp_dir();
            setup_tray(app)?;
            // Keep running without the hotkey if registration fails; the tray still works.
            if let Err(e) = app.global_shortcut().register(SHORTCUT) {
                eprintln!("failed to register shortcut {SHORTCUT}: {e}");
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![greet])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
