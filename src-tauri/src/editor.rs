use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::ipc::{InvokeBody, Request, Response};
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};

/// Must match the toolbar height in `src/styles.css`.
const TOOLBAR_HEIGHT: f64 = 44.0;
/// Enough width for the toolbar.
const MIN_WIDTH: f64 = 740.0;
const MIN_HEIGHT: f64 = 200.0;

/// PNG bytes per editor window label.
#[derive(Default)]
pub struct Captures(Mutex<HashMap<String, Vec<u8>>>);

/// Opens a new editor window for the capture at `path`. Consumes the file.
pub fn open_editor(app: &AppHandle, path: PathBuf) {
    let bytes = std::fs::read(&path);
    let _ = std::fs::remove_file(&path);
    let bytes = match bytes {
        Ok(b) => b,
        Err(e) => return eprintln!("read capture failed: {e}"),
    };
    if let Err(e) = create_window(app, bytes) {
        eprintln!("open editor failed: {e}");
    }
}

fn create_window(app: &AppHandle, bytes: Vec<u8>) -> tauri::Result<()> {
    let image = tauri::image::Image::from_bytes(&bytes)?;
    let (img_w, img_h) = (image.width() as f64, image.height() as f64);
    drop(image);

    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let (scale, max_w, max_h) = match &monitor {
        Some(m) => {
            let s = m.scale_factor();
            let size = m.size().to_logical::<f64>(s);
            (s, size.width * 0.9, size.height * 0.9)
        }
        None => (2.0, 1600.0, 1000.0),
    };
    let width = (img_w / scale).max(MIN_WIDTH).min(max_w);
    let height = (img_h / scale + TOOLBAR_HEIGHT).max(MIN_HEIGHT).min(max_h);

    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let mut label = format!("editor-{millis}");
    while app.get_webview_window(&label).is_some() {
        label.push('x');
    }

    let captures = app.state::<Captures>();
    captures.0.lock().unwrap().insert(label.clone(), bytes);

    let built = WebviewWindowBuilder::new(app, &label, WebviewUrl::App("index.html".into()))
        .title("Screenshot")
        .inner_size(width, height)
        .min_inner_size(MIN_WIDTH, MIN_HEIGHT)
        .center()
        .visible(false)
        .build();
    let window = match built {
        Ok(w) => w,
        Err(e) => {
            captures.0.lock().unwrap().remove(&label);
            return Err(e);
        }
    };

    let app2 = app.clone();
    let label2 = label.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::Destroyed = event {
            app2.state::<Captures>().0.lock().unwrap().remove(&label2);
        }
    });

    let _ = app.show(); // unhide if the app was hidden after a previous capture
    window.show()?;
    window.set_focus()
}

#[tauri::command]
pub async fn get_capture(window: WebviewWindow) -> Result<Response, String> {
    let captures = window.state::<Captures>();
    let map = captures.0.lock().unwrap();
    map.get(window.label())
        .map(|b| Response::new(b.clone()))
        .ok_or_else(|| "capture not found".into())
}

fn raw_body<'a>(request: &'a Request<'_>) -> Result<&'a [u8], String> {
    match request.body() {
        InvokeBody::Raw(b) => Ok(b),
        InvokeBody::Json(_) => Err("expected raw PNG body".into()),
    }
}

#[tauri::command]
pub async fn copy_png(app: AppHandle, request: Request<'_>) -> Result<(), String> {
    crate::menu::copy_png_bytes(&app, raw_body(&request)?)
}

/// Body: PNG bytes. Header `path`: target path, percent-encoded
/// (`encodeURIComponent`), since header values must be ASCII.
#[tauri::command]
pub async fn save_png(request: Request<'_>) -> Result<(), String> {
    let path = request
        .headers()
        .get("path")
        .and_then(|v| v.to_str().ok())
        .ok_or("missing path header")?;
    let path = percent_decode(path)?;
    std::fs::write(&path, raw_body(&request)?).map_err(|e| format!("{path}: {e}"))
}

fn percent_decode(s: &str) -> Result<String, String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s.get(i + 1..i + 3).ok_or("bad path encoding")?;
            out.push(u8::from_str_radix(hex, 16).map_err(|_| "bad path encoding")?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).map_err(|_| "path is not UTF-8".into())
}

#[cfg(test)]
mod tests {
    #[test]
    fn percent_decode() {
        assert_eq!(
            super::percent_decode("%2FUsers%2Fb%2FScreenshot%20%C3%A9.png").unwrap(),
            "/Users/b/Screenshot é.png"
        );
        assert!(super::percent_decode("%2").is_err());
    }
}
