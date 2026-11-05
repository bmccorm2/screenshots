# Screenshot app plan

## Goal
An installable, lightweight native macOS app with two capture modes:

1. **Capture → Clipboard:** drag to select a screen region; copy the screenshot directly to the macOS clipboard.
2. **Capture → Editor:** drag to select a screen region; open the screenshot in a small editor; drag to draw red rounded-rectangle outlines; press **⌘C** to copy the image with the outlines baked in.

## Proposed defaults
- Native Swift/AppKit app; no web runtime or third-party dependencies.
- Menu-bar app with two capture actions and Quit.
- Global keyboard shortcuts: **⌘⇧4** for clipboard capture; **⌘⇧5** for capture into the editor. Disable the conflicting macOS screenshot shortcuts manually.
- Use macOS's built-in region-selection interface if it works reliably from the app.
- Escape cancels capture without changing the clipboard.
- Editor supports multiple red rounded rectangles and ⌘Z to undo the last one.
- Fixed red color, outline thickness, and corner radius; no styling settings.
- Captures stay local; no uploads, accounts, or screenshot history.
- Launch automatically at login using macOS's login-item service.
- Provide a locally signed `.app` bundle for this Apple Silicon Mac, plus reproducible build instructions.

## Tasks
- [x] Inspect the project folder and current Mac environment (empty project; Apple Silicon).
- [x] Confirm shortcuts, launch behavior, and whether installation is just for this Mac.
- [x] Verify available Swift/macOS build tools (Swift 6.4 and macOS SDK installed).
- [x] Verify screen-capture permissions interactively (user confirmed direct capture works).
- [x] Build the menu-bar app and both capture entry points.
- [x] Implement region capture, cancellation, and useful permission/error guidance.
- [x] Implement direct clipboard capture without opening the editor.
- [x] Build the small editor with red rounded-rectangle drawing, undo, and ⌘C.
- [x] Ensure clipboard output includes annotations at the screenshot's original resolution.
- [x] Add automated checks for selection/clamping, outline rendering, resolution, orientation, editor layout, undo, and ⌘C routing.
- [x] Switch the editor preview to direct Core Graphics rendering (this alone did not fix the blank image).
- [x] Reproduce the actual bug: lazy image decoding after the image source is released and the capture file deleted.
- [x] Decode captured pixels immediately before cleanup; test both preview and export after source release/file deletion. Confirm the corrected regression fails without the fix.
- [x] Enable self-test assertions in optimized builds and correct color-profile/focus assumptions in existing checks.
- [x] Confirm the preview fix with a real editor capture on the user's Mac (user confirmed).
- [x] Add Cancel/Escape and standard ⌘W editor closing without changing the clipboard.
- [x] Open the editor above normal app windows.
- [x] Finish the keyboard-focus handoff after app activation; verify a real background launch becomes active with the editor as key window and canvas as first responder (Tests/focus-check.py).
- [ ] Test capture, cancellation, permissions, shortcuts, Retina scaling, and multiple monitors where available.
- [x] Package the installable app and document installation and use in README.md.
- [x] Compile successfully, pass self-checks, validate Info.plist, and verify the local code signature.
- [ ] Confirm automatic startup at the next login after installation.

## Acceptance checks
- Direct mode: select a region, then paste the image into another app.
- Editor mode: select a region, draw one or more red rounded boxes, press ⌘C, then paste the annotated image into another app.
- Undo removes the last box; copying does not include editor controls.
- Canceling capture leaves the previous clipboard contents untouched.
- Failures do not replace the clipboard with an empty image.

## Out of scope
Screenshot history, cloud sync, text/arrows, cropping after capture, configurable drawing styles, and an App Store release.

## Distribution / permissions
Screen capture may require approval in System Settings → Privacy & Security → Screen & System Audio Recording. Local packaging does not imply Apple notarization; distribution to other Macs may require signing/notarization to avoid Gatekeeper warnings.
