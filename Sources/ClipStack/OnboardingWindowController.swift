import AppKit
import SwiftUI
import ClipStackCore

/// One line of the guide: the keys to press and what they do.
struct GuideRow: Identifiable {
    let id = UUID()
    let keys: [String]
    let text: String
}

/// One page of the welcome guide.
struct GuidePage {
    let icon: String   // SF Symbol name
    let title: String
    let body: String
    let rows: [GuideRow]
    /// Screenshot of the feature (Resources/Guide/guide-N.jpg), nil when
    /// running unbundled.
    var image: NSImage? = nil
}

final class OnboardingModel: ObservableObject {
    @Published var page = 0
}

/// First-run welcome guide: six short pages, each naming the keys for one
/// group of features. Shown once per `Onboarding.currentVersion`, and
/// reopenable from the menu-bar menu ("Welcome Guide…").
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// "Try it" on the last page: close the guide and open the panel.
    var onOpenPanel: (() -> Void)?

    private let model = OnboardingModel()
    private var window: NSWindow?
    private var keyMonitor: Any?

    /// Called at launch: shows the guide only if this version hasn't been seen.
    func showIfNeeded() {
        let seen = UserDefaults.standard.integer(forKey: PrefKey.onboardingSeen)
        guard Onboarding.shouldShow(seenVersion: seen) else { return }
        show()
    }

    func show() {
        // Already open (menu clicked again): just bring it forward, keep the page.
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Marked as seen as soon as it is shown: closing it early is a clear
        // "not now", and it stays one click away in the menu.
        UserDefaults.standard.set(Onboarding.currentVersion, forKey: PrefKey.onboardingSeen)
        model.page = 0

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = L("ob_window_title")
            w.isReleasedWhenClosed = false
            // Open on whatever Space the user is on (e.g. a full-screen app),
            // not on the desktop Space the app happened to launch into.
            w.collectionBehavior.insert(.moveToActiveSpace)
            w.delegate = self
            window = w
        }
        // Rebuilt every time so the pages show the user's current hotkeys.
        window?.contentView = NSHostingView(rootView: OnboardingView(
            model: model,
            pages: Self.pages(),
            onFinish: { [weak self] in self?.finish() },
            onClose: { [weak self] in self?.window?.close() }
        ))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    private func finish() {
        window?.close()
        // Let the guide window go away before the panel takes the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onOpenPanel?()
        }
    }

    // ← / → page, Return = next (or "try it" on the last page), esc closes.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            switch event.keyCode {
            case 123: self.model.page = Onboarding.page(self.model.page, step: -1)
            case 124: self.model.page = Onboarding.page(self.model.page, step: 1)
            case 36, 76:
                if self.model.page == Onboarding.pageCount - 1 { self.finish() }
                else { self.model.page = Onboarding.page(self.model.page, step: 1) }
            case 53: window.close()
            default: return event
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: content

    private static func display(_ combo: (code: Int, mods: Int)) -> String {
        KeyMap.displayString(keyCode: combo.code, carbonModifiers: UInt32(combo.mods))
    }

    /// Bundled screenshot for page `n` (1-based). The panel shots are taken
    /// with demo data in dark mode, the same ones the website uses.
    private static func screenshot(_ n: Int) -> NSImage? {
        Bundle.main.url(forResource: "guide-\(n)", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))
    }

    static func pages() -> [GuidePage] {
        let open = display(HotKeys.switcherCombo)
        let settings = display(HotKeys.settingsCombo)
        let pages: [GuidePage] = [
            GuidePage(icon: "doc.on.clipboard", title: L("ob_title_1"),
                      body: String(format: L("ob_body_1"), open),
                      rows: [GuideRow(keys: [open], text: L("ob_row_open"))]),
            GuidePage(icon: "magnifyingglass", title: L("ob_title_2"), body: L("ob_body_2"),
                      rows: [GuideRow(keys: ["↑", "↓"], text: L("ob_row_move")),
                             GuideRow(keys: ["↩"], text: L("ob_row_copy")),
                             GuideRow(keys: ["⌘", "1–9"], text: L("ob_row_quick")),
                             GuideRow(keys: ["esc"], text: L("ob_row_close"))]),
            GuidePage(icon: "tag", title: L("ob_title_3"), body: L("ob_body_3"),
                      rows: [GuideRow(keys: ["⇥"], text: L("ob_row_next_type")),
                             GuideRow(keys: ["⇧", "⇥"], text: L("ob_row_prev_type"))]),
            GuidePage(icon: "wand.and.stars", title: L("ob_title_4"), body: L("ob_body_4"),
                      rows: [GuideRow(keys: ["⌘", "K"], text: L("ob_row_transform"))]),
            GuidePage(icon: "square.stack.3d.up", title: L("ob_title_5"), body: L("ob_body_5"),
                      rows: [GuideRow(keys: ["⌘", "P"], text: L("ob_row_pin")),
                             GuideRow(keys: ["⌘", "M"], text: L("ob_row_merge")),
                             GuideRow(keys: ["⌘", "O"], text: L("ob_row_note")),
                             GuideRow(keys: ["⌘", "T"], text: L("ob_row_ontop"))]),
            GuidePage(icon: "gearshape", title: L("ob_title_6"), body: L("ob_body_6"),
                      rows: [GuideRow(keys: [settings], text: L("ob_row_settings"))]),
        ]
        return pages.enumerated().map { i, page in
            var page = page
            page.image = screenshot(i + 1)
            return page
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let pages: [GuidePage]
    let onFinish: () -> Void
    let onClose: () -> Void

    private var isLast: Bool { model.page == pages.count - 1 }

    var body: some View {
        let page = pages[min(model.page, pages.count - 1)]
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if let image = page.image {
                    // Fixed-height frame so the text below doesn't jump
                    // between pages; shorter shots sit centred in it.
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.imageHeight)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                }
                HStack(spacing: 10) {
                    Image(systemName: page.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(page.title)
                        .font(.system(size: 22, weight: .bold))
                }
                Text(page.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(page.rows) { row in
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                ForEach(row.keys, id: \.self) { KeyCap(text: $0) }
                            }
                            .frame(minWidth: 86, alignment: .leading)
                            Text(row.text)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Divider()
            HStack {
                if !isLast {
                    Button(L("ob_skip"), action: onClose)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Page dots: also clickable.
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == model.page ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: 7, height: 7)
                            .onTapGesture { model.page = i }
                    }
                }
                Spacer()
                if model.page > 0 {
                    Button(L("ob_back")) { model.page = Onboarding.page(model.page, step: -1) }
                }
                if isLast {
                    Button(L("ob_try"), action: onFinish)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("ob_next")) { model.page = Onboarding.page(model.page, step: 1) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// 576 pt of content width (640 − 2×32) at the panel shots' 2:1 ratio.
    static let imageHeight: CGFloat = 287
    static let size = CGSize(width: 640, height: 600)
}

/// A keyboard key drawn as a small rounded cap.
private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 26)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}
