fn main() {
    // Declaring the app commands makes them permission-gated (see capabilities/default.json).
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&["get_capture", "copy_png", "save_png"]),
    ))
    .expect("failed to run tauri-build");
}
