import AppKit
import SwiftUI
import ClipStackCore

/// Borderless panel that can still take keyboard focus (Spotlight-style).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the floating switcher panel: show/hide, keyboard handling, commit,
/// plus the ⌘K transform menu, ⌘O notes and the hold-⌘ ring presentation.
final class SwitcherWindowController: NSObject, NSWindowDelegate {
    private let panel: KeyablePanel
    private let model: SwitcherModel
    private let store: HistoryStore
    private let notes: NoteWindowController
    private var keyMonitor: Any?
    /// True while the ⌘K menu is tracking. NSMenu runs its own loop but our
    /// local key monitor still sees ↑↓↩ — without this flag ↩ would commit
    /// the list row instead of choosing the menu item.
    private var isShowingMenu = false
    /// The app that was frontmost when the panel opened — where an
    /// auto-paste goes. The panel is non-activating, so this is normally
    /// still the frontmost app; we re-activate it anyway to be safe.
    private var previousApp: NSRunningApplication?
    /// Ring bookkeeping: the app ⌘V was pressed in, whether an entry was
    /// deleted during the ring, and whether a keep-on-top panel was on
    /// screen before the ring borrowed it.
    private var ringTarget: NSRunningApplication?
    private var ringDeleted = false
    private var panelWasPinnedBeforeRing = false
    /// Called after an item was written back to the pasteboard (UI feedback).
    var onCopied: ((ClipItem) -> Void)?
    /// Called when a transform could not produce anything (e.g. OCR found no text).
    var onNotice: ((String) -> Void)?

    init(store: HistoryStore) {
        self.store = store
        self.model = SwitcherModel(store: store)
        self.notes = NoteWindowController(store: store)
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: SwitcherView.panelSize),
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

        model.onCommit = { [weak self] item in self?.deliver(item) }
        model.onCommitMerged = { [weak self] text in self?.deliverNewText(text) }
        model.onClose = { [weak self] in self?.hide() }
        // Keep `previousApp` current even while a keep-on-top panel sits
        // unfocused: the user may move between apps before clicking a row.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.previousApp = app
        }
        notes.onCopy = { [weak self] item in
            // A note's Copy button never auto-pastes: the user clicked it, so
            // the target app is not focused and ⌘V would land in the wrong place.
            PasteboardWriter.write(item, store: store)
            self?.onCopied?(item)
        }
    }

    var isVisible: Bool { panel.isVisible }
    /// True while the panel itself has keyboard focus (e.g. typing a search):
    /// the ⌘V ring must then leave ⌘V alone so pasting into the search works.
    var hasKeyFocus: Bool { panel.isKeyWindow }

    private var autoPasteEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.autoPaste) }

    /// Hotkey entry point. While keeping the panel on top it may be visible but
    /// unfocused (the user is typing elsewhere); in that case the hotkey brings
    /// focus back rather than dismissing what the user asked to keep around.
    func toggle() {
        if !isVisible {
            show()
        } else if model.keepOnTop && !panel.isKeyWindow {
            rememberFrontmostApp()
            panel.makeKeyAndOrderFront(nil)
        } else {
            hide()
        }
    }

    func show() {
        rememberFrontmostApp()
        model.ringMode = false
        model.query = ""
        model.typeFilter = nil
        model.marked = []
        model.selectionIndex = 0
        model.refresh()
        centerOnMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        model.ringMode = false
        panel.orderOut(nil)
    }

    func refreshIfVisible() {
        guard isVisible else { return }
        model.refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep-on-top means "survive losing focus" — that is the whole feature.
        guard !model.keepOnTop, !model.ringMode else { return }
        hide()
    }

    private func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
    }

    // MARK: delivering a choice

    /// Writes `item` to the pasteboard and, when auto-paste is on, pastes it
    /// into the app the panel was opened over.
    private func deliver(_ item: ClipItem) {
        PasteboardWriter.write(item, store: store)
        let paste = autoPasteEnabled && Accessibility.isTrusted()
        // In keep-on-top mode the panel is being used as a reference sheet
        // while working in another app, so copying must not dismiss it.
        if !model.keepOnTop { hide() }
        // No known target (nothing was frontmost, or it quit): skip the
        // paste rather than let ⌘V land in ClipStack's own search field.
        if paste, let app = previousApp { Paster.paste(into: app) }
        onCopied?(item)
    }

    /// Transform / merge results become a brand-new history entry.
    private func deliverNewText(_ text: String) {
        let item = ClipItem.text(text)
        store.add(item)
        deliver(item)
    }

    // MARK: ⌘V ring (hold ⌘, tap V)

    /// The ring panel is shown WITHOUT taking key focus, so the app being
    /// pasted into stays focused the whole time and receives the final ⌘V.
    func ringBegin() {
        ringTarget = NSWorkspace.shared.frontmostApplication
        ringDeleted = false
        panelWasPinnedBeforeRing = isVisible && model.keepOnTop
        rememberFrontmostApp()
        removeKeyMonitor()
        model.ringMode = true
        model.query = ""
        model.typeFilter = nil
        model.marked = []
        model.refresh()
        // The first tap highlights the newest entry (the current clipboard),
        // so a quick ⌘V-and-release still pastes exactly what ⌘V always did.
        model.selectionIndex = 0
        if !panelWasPinnedBeforeRing { centerOnMouseScreen() }
        panel.orderFrontRegardless()
    }

    func ringStep(_ delta: Int) {
        guard model.ringMode else { return }
        let count = model.filtered.count
        guard count > 0 else { return }
        // Wraps around, so holding ⌘ and tapping V keeps cycling.
        model.selectionIndex = ((model.selectionIndex + delta) % count + count) % count
    }

    func ringDelete() {
        guard model.ringMode else { return }
        ringDeleted = true
        model.deleteSelection()
    }

    func ringCancel() {
        guard model.ringMode else { return }
        endRing()
    }

    /// `immediate`: post the ⌘V synchronously (a held-back key is about to
    /// be replayed and must land after the paste); otherwise wait a beat for
    /// the ⌘ release to settle.
    func ringCommit(immediate: Bool = false) {
        guard model.ringMode else { return }
        let target = ringTarget
        let item = model.selected
        // Back on the first row with nothing deleted = the plain ⌘V case,
        // even if the user cycled all the way round.
        let untouched = model.selectionIndex == 0 && !ringDeleted
        endRing()
        // ⌘V then ⌘Tab: the paste was meant for the app the ring started in,
        // not whatever is frontmost now — drop it rather than guess.
        guard let target, NSWorkspace.shared.frontmostApplication == target else { return }
        if !untouched {
            guard let item else { return }
            PasteboardWriter.write(item, store: store)
            onCopied?(item)
        }
        // When untouched the pasteboard is left exactly as the source app
        // wrote it (native formats, password-manager content we never
        // recorded) and the paste is simply replayed.
        if immediate {
            Paster.postCommandV()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.postCommandV() }
        }
    }

    /// Leaves ring mode: a keep-on-top panel that was on screen before goes
    /// back to being the normal reference sheet; otherwise the panel hides.
    private func endRing() {
        if panelWasPinnedBeforeRing {
            model.ringMode = false
            model.refresh()
        } else {
            hide()
        }
        panelWasPinnedBeforeRing = false
        ringTarget = nil
    }

    // MARK: ⌘K transforms

    private func showTransformMenu() {
        guard let item = model.selected else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ action: @escaping () -> Void) {
            let mi = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            let target = MenuAction(action)
            mi.target = target
            mi.representedObject = target // keep the closure alive with the item
            menu.addItem(mi)
        }

        switch item.kind {
        case .text:
            let text = item.plainText ?? ""
            let colors = ColorTransform.alternatives(for: text)
            for c in colors {
                add(String(format: L("tf_copy_as"), c)) { [weak self] in self?.deliverNewText(c) }
            }
            // A colour only needs its other notations; "lowercase" or
            // "URL-encode" on "#4F8EF7" is noise.
            for t in colors.isEmpty ? TextTransform.available(for: text) : [] {
                add(L(t.titleKey)) { [weak self] in
                    if let out = t.apply(text) { self?.deliverNewText(out) }
                }
            }
        case .image:
            add(L("tf_ocr")) { [weak self] in self?.runOCR(on: item) }
        case .file:
            if let paths = item.fileURLs, !paths.isEmpty {
                add(L("tf_copy_paths")) { [weak self] in self?.deliverNewText(paths.joined(separator: "\n")) }
                add(L("tf_copy_names")) { [weak self] in
                    self?.deliverNewText(paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n"))
                }
            }
        }

        if menu.items.isEmpty {
            let none = NSMenuItem(title: L("tf_none"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }

        guard let view = panel.contentView else { return }
        // Pop up over the preview pane's top-left corner (list is 320pt wide).
        // NSHostingView is flipped (origin top-left), so measure from the top.
        // 84 = search bar + type-filter chip row, so the menu opens on the
        // preview header instead of covering the chips.
        let fromTop: CGFloat = 84
        let point = NSPoint(x: 332, y: view.isFlipped ? fromTop : view.bounds.height - fromTop)
        // Positioning on the first item also pre-selects it, so ⌘K then ↩
        // runs the top transform without an extra ↓.
        isShowingMenu = true
        menu.popUp(positioning: menu.items.first, at: point, in: view)
        isShowingMenu = false
    }

    private func runOCR(on item: ClipItem) {
        guard let png = store.imageData(for: item) else { return }
        OCR.recognizeText(in: png) { [weak self] text in
            guard let self else { return }
            if let text {
                self.deliverNewText(text)
            } else {
                self.onNotice?(L("ocr_no_text"))
            }
        }
    }

    // MARK: ⌘O notes

    private func openNoteForSelection() {
        guard let item = model.selected else { return }
        notes.open(item, near: panel.frame)
        if !model.keepOnTop { hide() }
    }

    // MARK: keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, !self.isShowingMenu else { return event }
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
        case 53: // esc: first clears marks, then the type filter, then closes
            if !model.marked.isEmpty {
                model.marked = []
            } else if model.typeFilter != nil {
                model.typeFilter = nil
            } else {
                model.onClose?()
            }
            return true
        case 36, 76: // return / keypad enter
            model.commitSelection()
            return true
        case 125: // down
            model.moveSelection(1)
            return true
        case 48: // tab / ⇧tab: next / previous type filter (the search field
                 // is the only focusable control, so Tab has nothing else to do)
            let back = event.modifierFlags.contains(.shift)
            model.cycleTypeFilter(back ? -1 : 1)
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
                switch chars {
                case "p":
                    model.togglePinSelection()
                    return true
                case "t":
                    model.keepOnTop.toggle()
                    return true
                case "k":
                    showTransformMenu()
                    return true
                case "m":
                    model.toggleMarkSelection()
                    return true
                case "o":
                    openNoteForSelection()
                    return true
                default:
                    break
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

/// Bridges a Swift closure to NSMenuItem's target/action.
private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}
