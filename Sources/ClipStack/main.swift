import AppKit

// Menu-bar-only app: no Dock icon, no main window (LSUIElement in Info.plist
// covers the bundled build; the activation policy covers `swift run`).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
