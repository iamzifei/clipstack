import AppKit
import SwiftUI
import ClipStackCore

/// Floating "sticky notes": any history entry can be popped out (⌘O) into its
/// own small always-on-top window that can be dragged, resized and kept open
/// while working in another app. Several can be open at once.
///
/// Unlike ⌘T (which pins the whole switcher), a note holds exactly one entry
/// and takes very little screen space — handy for "copy this value into five
/// form fields".
final class NoteWindowController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private var windows: [NSPanel] = []
    /// Copy-button handler (writes the entry back to the pasteboard).
    var onCopy: ((ClipItem) -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    func open(_ item: ClipItem, near anchor: NSRect?) {
        let size = NSSize(width: 320, height: item.kind == .image ? 260 : 200)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            // nonactivating: clicking the note (e.g. its Copy button) must not
            // pull focus away from the app the user is pasting into.
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let line = item.previewLine
        // Mark the cut so a clipped title doesn't read as the whole entry.
        let short = line.count > 40 ? line.prefix(40) + "…" : Substring(line)
        panel.title = "\(item.contentType.tag) · \(short)"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 200, height: 120)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: NoteView(item: item, store: store) { [weak self] in
            self?.onCopy?(item)
        })

        // Cascade new notes so several opened in a row don't stack exactly.
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var origin = anchor.map { NSPoint(x: $0.maxX - size.width - 24, y: $0.maxY - size.height - 24) }
            ?? NSPoint(x: screen.maxX - size.width - 40, y: screen.maxY - size.height - 40)
        origin.x -= CGFloat(windows.count % 6) * 24
        origin.y -= CGFloat(windows.count % 6) * 24
        panel.setFrameOrigin(origin)

        windows.append(panel)
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSPanel else { return }
        windows.removeAll { $0 === w }
    }
}

private struct NoteView: View {
    let item: ClipItem
    let store: HistoryStore
    let copy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                TypeTag(type: item.contentType)
                Spacer()
                Button(L("hint_copy"), action: copy)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let data = store.imageData(for: item), let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                Text(L("image_missing")).foregroundStyle(.secondary).padding(10)
            }
        case .text, .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let color = item.colorValue {
                        ColorSwatch(color: color, size: 40)
                    }
                    Text(String((item.plainText ?? item.fileURLs?.joined(separator: "\n") ?? "").prefix(20_000)))
                        .font(.system(size: 12, design: item.contentType == .code ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            }
        }
    }
}
