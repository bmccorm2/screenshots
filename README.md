# Screenshots

A small native macOS menu-bar app for this Apple Silicon Mac. No dependencies, accounts, uploads, or screenshot history.

## Install

1. Open `dist` in Finder and drag **Screenshots.app** into **Applications**. If using `dist/Screenshots.zip`, unzip it first.
2. In **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**, disable the built-in shortcuts using **⌘⇧4** and **⌘⇧5** (selected-area capture and screenshot/recording options). This app uses those keys. Other screenshot shortcuts can stay enabled.
3. Open **Screenshots** from Applications. Look for the viewfinder icon in the menu bar; there is no Dock icon.
4. The app registers itself to launch at login. If macOS asks for approval, enable it in **System Settings → General → Login Items & Extensions**.
5. Try a capture. Grant access under **System Settings → Privacy & Security → Screen & System Audio Recording** when prompted. Quit and reopen Screenshots after changing permission.

This build is locally/ad-hoc signed, not Apple-notarized. It's intended for your Mac, not general distribution. Rebuilding may require granting screen-recording permission again.

## Use

| Action | Shortcut |
| --- | --- |
| Select a region and copy directly to the clipboard | **⌘⇧4** |
| Select a region and open the editor | **⌘⇧5** |
| Cancel region selection | **Escape** |
| Copy the annotated image in the editor | **⌘C** |
| Undo the last box in the editor | **⌘Z** |
| Close the editor without copying | **⌘W**, **Escape**, or **Cancel** |

In the editor, drag over the image to draw a red rounded-rectangle outline. Draw as many boxes as you need. The image fits the window; copies retain the original pixel dimensions. The **Copy Image** button does the same thing as ⌘C. Copying leaves the editor open. The editor floats above normal app windows and receives keyboard focus when opened. Cancel/⌘W/Escape close only the editor and leave the clipboard unchanged.

Both capture actions are also available from the menu-bar icon. If shortcut registration fails, disable the conflicting shortcuts and restart the app.

The clipboard includes PNG and TIFF representations for compatibility with apps that accept pasted images. Capturing into the editor does not change the clipboard until you copy. Canceling leaves the clipboard untouched.

A new editor capture replaces the previous editor image and its boxes. There is no save/history feature. Capture uses a private temporary directory, removed after loading the image or quitting normally; a forced termination/crash can leave a temporary file behind.

To disable automatic startup, uncheck **Launch at Login** in the app's menu. To uninstall, disable startup, quit, then delete the app from Applications.

## Build and checks

Requires Apple's Command Line Tools. From this folder:

```fish
./build.sh
```

Builds `dist/Screenshots.app`, signs it locally, and runs assertion-based checks for selection/clamping, red rounded-outline rendering, original resolution, annotation orientation, editor preview and exported image content after image-source release and temporary-file deletion, undo, and the ⌘C responder chain. Assertions are explicitly enabled even in the optimized build. Tests do not change the clipboard, register login items, or request capture permission.

To rerun checks:

```fish
./dist/Screenshots.app/Contents/MacOS/Screenshots --self-test
```

To test actual background-to-editor activation (briefly opens a test window and takes keyboard focus):

```fish
python3 Tests/focus-check.py
```

This checks app activation, key-window status, and canvas keyboard focus without capturing the screen, changing the clipboard, or registering shortcuts/login items.

Interactive checks still needed: real region selection and cancellation, permission approval, pasting into another app, global shortcuts, Retina/multiple-monitor capture, and login startup.
