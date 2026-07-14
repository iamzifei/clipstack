import AppKit
import SwiftUI
import ClipStackCore

/// Borderless panel that can still take keyboard focus (Spotlight-style).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the floating switcher panel: show/hide, keyboard handling, commit.
final class SwitcherWindowController: NSObject, NSWindowDelegate {
    private let panel: KeyablePanel
    private let model: SwitcherModel
    private let store: HistoryStore
    private var keyMonitor: Any?

    init(store: HistoryStore) {
        self.store = store
        self.model = SwitcherModel(store: store)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model))

        model.onCommit = { [weak self] item in
            guard let self else { return }
            PasteboardWriter.write(item, store: self.store)
            self.hide()
        }
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.query = ""
        model.selectionIndex = 0
        model.refresh()
        centerOnMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func refreshIfVisible() {
        guard isVisible else { return }
        model.refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Returns true when the event was consumed by the switcher.
    private func handle(_ event: NSEvent) -> Bool {
        // While an IME composition is in flight (Chinese input etc.), return
        // and arrow keys belong to the input method — don't intercept them.
        if let editor = panel.fieldEditor(false, for: nil) as? NSTextView, editor.hasMarkedText() {
            return false
        }

        switch event.keyCode {
        case 53: // esc
            model.onClose?()
            return true
        case 36, 76: // return / keypad enter
            model.commitSelection()
            return true
        case 125: // down
            model.moveSelection(1)
            return true
        case 126: // up
            model.moveSelection(-1)
            return true
        default:
            break
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.keyCode == 51 { // ⌘⌫ delete entry
                model.deleteSelection()
                return true
            }
            if let chars = event.charactersIgnoringModifiers {
                if chars == "p" {
                    model.togglePinSelection()
                    return true
                }
                if let n = Int(chars), (1...9).contains(n) {
                    model.commit(atVisibleIndex: n - 1)
                    return true
                }
            }
        }
        return false
    }

    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.06
        ))
    }
}
