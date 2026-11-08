use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::AppHandle;

/// Set while a capture or its context menu is in progress.
static BUSY: AtomicBool = AtomicBool::new(false);

/// Clears `BUSY` when dropped, so every exit path (incl. errors/panics) resets it.
struct BusyGuard;

impl Drop for BusyGuard {
    fn drop(&mut self) {
        BUSY.store(false, Ordering::SeqCst);
    }
}

/// Temp dir for captures; created if missing.
fn temp_dir() -> PathBuf {
    let dir = std::env::temp_dir().join("com.bryan.screenshots");
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("create temp dir failed: {e}");
    }
    dir
}

fn new_capture_path() -> PathBuf {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    temp_dir().join(format!("capture-{millis}.png"))
}

/// Starts the region-capture flow. No-op if one is already in progress.
pub fn start_capture(app: &AppHandle) {
    if BUSY.swap(true, Ordering::SeqCst) {
        return;
    }
    let guard = BusyGuard;
    let app = app.clone();
    let spawned = std::thread::Builder::new()
        .name("capture".into())
        .spawn(move || {
            let _guard = guard; // BUSY cleared when this thread ends
            let path = new_capture_path();
            if !run_screencapture(&path) {
                let _ = std::fs::remove_file(&path);
                return;
            }
            let (tx, rx) = std::sync::mpsc::channel();
            let app2 = app.clone();
            let path2 = path.clone();
            let result = app.run_on_main_thread(move || {
                crate::menu::show_capture_menu(&app2, path2);
                let _ = tx.send(());
            });
            if let Err(e) = result {
                eprintln!("run_on_main_thread failed: {e}");
                let _ = std::fs::remove_file(&path);
                return;
            }
            // Wait for the menu to close, then queue the cancel cleanup from
            // this (non-main) thread so it runs after any menu click.
            let _ = rx.recv();
            crate::menu::finish_capture_menu(&app, path);
        });
    if let Err(e) = spawned {
        // The closure (and guard) is dropped; BUSY is cleared.
        eprintln!("spawn capture thread failed: {e}");
    }
}

/// Runs interactive region capture. True if a non-empty file was written.
fn run_screencapture(path: &Path) -> bool {
    match Command::new("/usr/sbin/screencapture")
        .args(["-i", "-s", "-x"])
        .arg(path)
        .status()
    {
        Ok(status) if status.success() => {
            std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.len() > 0)
        }
        Ok(_) => false,
        Err(e) => {
            eprintln!("screencapture failed: {e}");
            false
        }
    }
}

/// Deletes all files in the temp dir, ignoring errors.
pub fn clean_temp_dir() {
    let Ok(entries) = std::fs::read_dir(temp_dir()) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            let _ = std::fs::remove_file(path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temp_helpers() {
        let p = new_capture_path();
        assert!(p.starts_with(temp_dir()));
        let name = p.file_name().unwrap().to_str().unwrap();
        assert!(name.starts_with("capture-") && name.ends_with(".png"));
        std::fs::write(&p, b"x").unwrap();
        clean_temp_dir();
        assert!(!p.exists());
        assert!(temp_dir().is_dir());
    }
}
