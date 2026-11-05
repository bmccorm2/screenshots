"""Open a temporary editor from the background; verify focus without clicking.
No screen capture, clipboard changes, login items, or global shortcuts.
"""
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/Screenshots.swift").read_text()
startup = '''        buildMenu()
        registerShortcuts()
        if !UserDefaults.standard.bool(forKey: "ConfiguredLogin") {
            enableLogin()
        }'''
assert source.count(startup) == 1
# Replace only startup in a temporary build; exercise the real presentation code.
replacement = '''        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let context = CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 2400,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
            self.showEditor(image: context.makeImage()!)
            self.editor!.window!.title = "Screenshots — temporary focus check"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let success = NSApp.isActive && self.editor!.window!.isKeyWindow && self.editor!.window!.firstResponder === self.editor!.canvas
                let result = "active=\\(NSApp.isActive) key=\\(self.editor!.window!.isKeyWindow) canvas=\\(self.editor!.window!.firstResponder === self.editor!.canvas) PASS=\\(success)"
                try! result.write(toFile: "RESULT_PATH", atomically: true, encoding: .utf8)
                self.editor!.close()
                NSApp.terminate(nil)
            }
        }'''
with tempfile.TemporaryDirectory(prefix="screenshots-focus-") as directory:
    folder = Path(directory)
    app = folder / "FocusCheck.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    result = folder / "result.txt"
    swift = folder / "FocusCheck.swift"
    swift.write_text(source.replace(startup, replacement.replace("RESULT_PATH", str(result))))
    info = plistlib.loads((root / "Info.plist").read_bytes())
    info["CFBundleIdentifier"] = "local.bryan.screenshots.focus-check"
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["xcrun", "swiftc", str(swift), "-O", "-assert-config", "Debug", "-swift-version", "5",
                    "-framework", "AppKit", "-framework", "Carbon", "-framework", "ServiceManagement",
                    "-o", str(app / "Contents/MacOS/Screenshots")], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["open", "-g", "-n", "-W", str(app)], check=True, timeout=15)
    text = result.read_text()
    print(text)
    assert "PASS=true" in text
