import AppKit
import Carbon
import ServiceManagement

func selectionRect(from start: CGPoint, to end: CGPoint, inside bounds: CGRect) -> CGRect {
    CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
}

func loadScreenshot(at file: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
    // Decode now: the editor outlives both the image source and its temporary file.
    return CGImageSourceCreateImageAtIndex(source, 0,
                                          [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

func annotatedImage(_ image: CGImage, boxes: [CGRect]) -> CGImage? {
    guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(6)
    for box in boxes {
        let inset = box.insetBy(dx: 3, dy: 3)
        let radius = min(12, min(inset.width, inset.height) / 2)
        context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
    }
    return context.makeImage()
}

func copyImage(_ image: CGImage) -> Bool {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let png = representation.representation(using: .png, properties: [:]),
          let tiff = representation.tiffRepresentation else { return false }
    let item = NSPasteboardItem()
    item.setData(png, forType: .png)
    item.setData(tiff, forType: .tiff)
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.writeObjects([item])
}

final class Canvas: NSView {
    let image: CGImage
    var boxes: [CGRect] = []
    var dragStart: CGPoint?
    var pendingBox: CGRect?
    var didChange: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel("Screenshot. Drag to draw a red rounded rectangle. Command Z undoes the last rectangle.")
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    var imageRect: CGRect {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        return CGPoint(x: (point.x - rect.minX) * CGFloat(image.width) / rect.width,
                       y: (point.y - rect.minY) * CGFloat(image.height) / rect.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: imageRect)
        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        let scale = imageRect.width / CGFloat(image.width)
        context.scaleBy(x: scale, y: scale)
        context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(6)
        for box in boxes + (pendingBox.map { [$0] } ?? []) {
            let inset = box.insetBy(dx: 3, dy: 3)
            guard inset.width > 0, inset.height > 0 else { continue }
            let radius = min(12, min(inset.width, inset.height) / 2)
            context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        }
        context.restoreGState()
    }
    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        dragStart = imagePoint(event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        pendingBox = selectionRect(from: start, to: imagePoint(event),
                                   inside: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        if let box = pendingBox, box.width >= 8, box.height >= 8 { boxes.append(box) }
        dragStart = nil
        pendingBox = nil
        needsDisplay = true
        didChange?()
    }
    @objc func undo(_ sender: Any?) {
        guard !boxes.isEmpty else { return }
        boxes.removeLast()
        needsDisplay = true
        didChange?()
    }
}

final class Editor: NSWindowController {
    let canvas: Canvas
    let status = NSTextField(labelWithString: "Drag to draw a red box · ⌘Z undo · ⌘C copy")

    init(image: CGImage) {
        canvas = Canvas(image: image)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let scale = min(1, min((available.width - 100) / CGFloat(image.width),
                              (available.height - 160) / CGFloat(image.height)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: max(440, CGFloat(image.width) * scale),
                                                  height: max(240, CGFloat(image.height) * scale + 44)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Screenshots — Editor"
        window.minSize = NSSize(width: 360, height: 240)
        window.isReleasedWhenClosed = false
        window.level = .floating
        let root = window.contentView!
        let cancel = NSButton(title: "Cancel", target: window, action: #selector(NSWindow.performClose(_:)))
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        cancel.translatesAutoresizingMaskIntoConstraints = false
        let copy = NSButton(title: "Copy Image", target: self, action: #selector(copyScreenshot))
        copy.keyEquivalent = "c"
        copy.keyEquivalentModifierMask = .command
        canvas.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        copy.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addSubview(canvas)
        root.addSubview(status)
        root.addSubview(cancel)
        root.addSubview(copy)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -44),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12),
            cancel.trailingAnchor.constraint(equalTo: copy.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            copy.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        canvas.didChange = { [weak self] in
            self?.status.stringValue = "Drag to draw a red box · ⌘Z undo · ⌘C copy"
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    @objc func copyScreenshot(_ sender: Any?) {
        guard let image = annotatedImage(canvas.image, boxes: canvas.boxes), copyImage(image) else {
            showError("Couldn't copy the screenshot", detail: "Please try again.")
            return
        }
        status.stringValue = "Copied — ready to paste"
    }
}

func showError(_ title: String, detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    var captureProcess: Process?
    var captureDirectory: URL?
    var editor: Editor?
    var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        registerShortcuts()
        if !UserDefaults.standard.bool(forKey: "ConfiguredLogin") {
            enableLogin()
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard NSApp.modalWindow == nil, let editor, let window = editor.window, window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor.canvas)
    }
    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        appMenu.addItem(withTitle: "Quit Screenshots", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        fileMenu.addItem(withTitle: "Close Editor", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)
        editMenu.addItem(withTitle: "Undo Box", action: #selector(Canvas.undo(_:)), keyEquivalent: "z")
        let copy = editMenu.addItem(withTitle: "Copy Image", action: #selector(Editor.copyScreenshot(_:)), keyEquivalent: "c")
        // The window controller is reached through the responder chain.
        copy.target = nil
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Screenshots")
        let menu = NSMenu()
        let direct = menu.addItem(withTitle: "Capture to Clipboard", action: #selector(captureClipboard), keyEquivalent: "4")
        direct.keyEquivalentModifierMask = [.command, .shift]
        direct.target = self
        let edit = menu.addItem(withTitle: "Capture to Editor", action: #selector(captureEditor), keyEquivalent: "5")
        edit.keyEquivalentModifierMask = [.command, .shift]
        edit.target = self
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        updateLoginState()
        let setup = menu.addItem(withTitle: "Setup Instructions…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenshots", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    func registerShortcuts() {
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            app.capture(edit: id.id == 2)
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))],
           Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard result == noErr else {
            showError("Couldn't enable global shortcuts", detail: "Use the menu-bar capture actions instead.")
            return
        }
        for (key, id) in [(UInt32(kVK_ANSI_4), UInt32(1)), (UInt32(kVK_ANSI_5), UInt32(2))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(cmdKey | shiftKey),
                                            EventHotKeyID(signature: 0x534E4150, id: id),
                                            GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeys.append(ref) }
            else {
                showError("Shortcut ⌘⇧\(id == 1 ? "4" : "5") is unavailable",
                          detail: "Disable the matching macOS shortcut in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, then quit and reopen this app. Menu-bar capture still works.")
            }
        }
    }
    func showEditor(image: CGImage) {
        editor?.close()
        editor = Editor(image: image)
        editor?.window?.makeKeyAndOrderFront(nil)
        editor?.window?.makeFirstResponder(editor?.canvas)
        // Activation is asynchronous; finish the focus handoff in applicationDidBecomeActive.
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func captureClipboard() { capture(edit: false) }
    @objc func captureEditor() { capture(edit: true) }
    func capture(edit: Bool) {
        guard captureProcess == nil else { NSSound.beep(); return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            showError("Allow screen recording", detail: "Enable Screenshots in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app. Your clipboard has not been changed.")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let file = directory.appendingPathComponent("capture.png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    defer {
                        try? FileManager.default.removeItem(at: directory)
                        self?.captureDirectory = nil
                    }
                    guard let self else { return }
                    self.captureProcess = nil
                    // Escape produces no file; preserve the clipboard and existing editor.
                    guard FileManager.default.fileExists(atPath: file.path) else { return }
                    guard process.terminationStatus == 0,
                          let image = loadScreenshot(at: file) else {
                        showError("Couldn't read the screenshot", detail: "Please try again. Your clipboard has not been changed.")
                        return
                    }
                    if edit {
                        self.showEditor(image: image)
                    } else if !copyImage(image) {
                        showError("Couldn't copy the screenshot", detail: "Please try again.")
                    }
                }
            }
            captureProcess = process
            captureDirectory = directory
            try process.run()
        } catch {
            captureProcess = nil
            captureDirectory = nil
            try? FileManager.default.removeItem(at: directory)
            showError("Couldn't start capture", detail: error.localizedDescription)
        }
    }
    func updateLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    func enableLogin() {
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "ConfiguredLogin")
            if SMAppService.mainApp.status == .requiresApproval {
                showError("Approve launch at login", detail: "Enable Screenshots in System Settings → General → Login Items & Extensions.")
            }
        } catch {
            showError("Couldn't enable launch at login", detail: "Move Screenshots.app into Applications and reopen it. \(error.localizedDescription)")
        }
        updateLoginState()
    }
    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            do { try SMAppService.mainApp.unregister() }
            catch { showError("Couldn't disable launch at login", detail: error.localizedDescription) }
            updateLoginState()
        } else if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else { enableLogin() }
    }
    @objc func showSetup() {
        showError("Screenshots setup", detail: "1. Keep Screenshots.app in Applications.\n2. Disable the macOS ⌘⇧4 and ⌘⇧5 shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots. Other screenshot shortcuts can stay enabled.\n3. Allow Screenshots under Privacy & Security → Screen & System Audio Recording.\n\n⌘⇧4: select and copy.\n⌘⇧5: select and edit.\nEditor: drag red boxes, ⌘Z undo, ⌘C copy.\nEscape cancels capture.")
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let process = captureProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        if let directory = captureDirectory { try? FileManager.default.removeItem(at: directory) }
        for key in hotKeys { UnregisterEventHotKey(key) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

func selfTest() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    assert(selectionRect(from: CGPoint(x: 180, y: 80), to: CGPoint(x: 20, y: 10), inside: bounds)
           == CGRect(x: 20, y: 10, width: 160, height: 70))
    assert(selectionRect(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 300, y: -20), inside: bounds)
           == CGRect(x: 20, y: 0, width: 180, height: 10))
    let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 800,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(bounds)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    let image = context.makeImage()!
    let result = annotatedImage(image, boxes: [CGRect(x: 20, y: 10, width: 100, height: 60)])!
    assert(result.width == 200 && result.height == 100)
    let bitmap = NSBitmapImageRep(cgImage: result)
    var red = 0
    for y in 0..<100 {
        for x in 0..<200 {
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if color.redComponent > 0.9 && color.greenComponent < 0.3 && color.blueComponent < 0.1 { red += 1 }
        }
    }
    assert(red > 500 && red < 2000, "Expected a red outline, not a filled box")
    let center = bitmap.colorAt(x: 70, y: 60)!.usingColorSpace(.deviceRGB)!
    assert(center.greenComponent > 0.9, "Box interior must remain unfilled")
    let plain = annotatedImage(image, boxes: [])!
    assert(NSBitmapImageRep(cgImage: plain).colorAt(x: 30, y: 30)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.9)
    // Bitmap rows run top-down; the box's lower edge is at image-space y=10.
    let bottomEdge = bitmap.colorAt(x: 70, y: 87)!.usingColorSpace(.deviceRGB)!
    assert(bottomEdge.redComponent > 0.9 && bottomEdge.greenComponent < 0.3,
           "Export must preserve the editor's bottom-up coordinates")
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("screenshots-test-\(UUID().uuidString).png")
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: fixture)
    let loadedImage = autoreleasepool { loadScreenshot(at: fixture)! }
    try! FileManager.default.removeItem(at: fixture)
    let editor = Editor(image: loadedImage)
    editor.window!.contentView!.layoutSubtreeIfNeeded()
    assert(editor.window!.level == .floating, "Editor must appear above normal app windows")
    let cancel = editor.window!.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }!
    assert(cancel.target as? NSWindow === editor.window && cancel.action == #selector(NSWindow.performClose(_:)))
    assert(cancel.keyEquivalent == "\u{1b}" && cancel.keyEquivalentModifierMask.isEmpty)
    let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 440, pixelsHigh: 196,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
    editor.canvas.draw(editor.canvas.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let previewCenter = preview.colorAt(x: 220, y: 98)!.usingColorSpace(.deviceRGB)!
    assert(previewCenter.redComponent > 0.9 && previewCenter.greenComponent > 0.9 && previewCenter.blueComponent > 0.9,
           "Editor must display the captured pixels after the temporary PNG is deleted")
    assert(editor.canvas.imageRect.width > 0 && editor.canvas.imageRect.height > 0)
    let imageRect = editor.canvas.imageRect
    let previewBlue = preview.colorAt(x: Int(imageRect.minX + 6 * imageRect.width / 200),
                                      y: Int(CGFloat(preview.pixelsHigh) - imageRect.minY - 4 * imageRect.height / 100))!.usingColorSpace(.deviceRGB)!
    assert(previewBlue.blueComponent > 0.9 && previewBlue.redComponent < 0.3,
           "Preview must show the image content in the correct orientation, not just a blank background")
    let export = annotatedImage(loadedImage, boxes: [CGRect(x: 20, y: 10, width: 100, height: 60)])!
    let exportBitmap = NSBitmapImageRep(cgImage: export)
    assert(exportBitmap.colorAt(x: 6, y: 96)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9,
           "Copied image must retain screenshot content after source release and file deletion")
    assert(exportBitmap.representation(using: .png, properties: [:]) != nil && exportBitmap.tiffRepresentation != nil)
    editor.canvas.boxes = [CGRect(x: 20, y: 10, width: 100, height: 60)]
    editor.canvas.undo(nil)
    assert(editor.canvas.boxes.isEmpty)
    editor.canvas.undo(nil)
    assert(editor.canvas.boxes.isEmpty)
    assert(editor.window!.canBecomeKey, "Editor must accept keyboard focus")
    assert(editor.window!.makeFirstResponder(editor.canvas))
    assert(editor.window!.firstResponder === editor.canvas)
    var responder: NSResponder? = editor.canvas
    while let current = responder, !current.responds(to: #selector(Editor.copyScreenshot(_:))) {
        responder = current.nextResponder
    }
    assert(responder as? Editor === editor,
           "Command C must reach the editor through the responder chain")
    print("PASS: selection geometry, clamping, image dimensions, rounded outline, unfilled interior, export orientation, editor preview and copy after image-source release and PNG deletion, undo, Command C routing")
}

if CommandLine.arguments.contains("--self-test") {
    selfTest()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
