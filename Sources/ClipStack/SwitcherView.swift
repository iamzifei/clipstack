import SwiftUI
import ClipStackCore

/// The floating switcher: search bar on top, history list on the left,
/// full-fidelity preview on the right.
struct SwitcherView: View {
    /// Shared with the window controller so the panel frame matches.
    static let panelSize = CGSize(width: 980, height: 480)

    @ObservedObject var model: SwitcherModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                listPane
                    .frame(width: 320)
                Divider()
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: SwitcherView.panelSize.width, height: SwitcherView.panelSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.revision) { _ in
            if !searchFocused { searchFocused = true }
        }
    }

    // MARK: pieces

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("search_placeholder"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
            Text(String(format: L("items_count"), model.filtered.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var listPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { pair in
                        row(item: pair.element, index: pair.offset)
                            .id(pair.element.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.commit(atVisibleIndex: pair.offset) }
                            .onTapGesture {
                                // ⌘-click marks for merge (like Finder's
                                // multi-select); a plain click just selects.
                                if NSEvent.modifierFlags.contains(.command) {
                                    model.toggleMark(id: pair.element.id)
                                }
                                model.selectionIndex = pair.offset
                            }
                    }
                }
                .padding(6)
            }
            // With "Show scroll bars: Always" (any mouse attached) the legacy
            // scroller draws an opaque white track between the list and the
            // preview. The list is keyboard-driven and shows its item count,
            // so the bar adds nothing; wheel/trackpad scrolling still works.
            .scrollIndicators(.never)
            .onChange(of: model.selectionIndex) { _ in
                if let id = model.selected?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func row(item: ClipItem, index: Int) -> some View {
        let isSelected = index == model.selectionIndex
        let type = item.contentType
        let markNumber = model.markNumber(of: item.id)
        return HStack(spacing: 8) {
            if let markNumber {
                // Marked for merge: the badge shows the paste order.
                Text("\(markNumber)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.accentColor, in: Circle())
            } else if let color = item.colorValue {
                ColorSwatch(color: color, size: 14)
                    .frame(width: 16)
            } else {
                Image(systemName: icon(for: type))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewLine)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TypeTag(type: type)
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                    }
                    Text(Self.relative(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.22)
                : (markNumber != nil ? Color.accentColor.opacity(0.08) : Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    @ViewBuilder
    private var previewPane: some View {
        if let item = model.selected {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // The tag already names the kind; a separate "Text" label
                    // next to it only repeated it.
                    TypeTag(type: item.contentType)
                    Text(ByteFormat.string(item.byteSize))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Self.full(item.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let app = item.sourceApp {
                        Text(String(format: L("from_app"), app))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.pinned {
                        Label(L("pinned"), systemImage: "pin.fill").font(.system(size: 10))
                    }
                }
                Divider()
                previewBody(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(12)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(model.query.isEmpty ? L("empty_history") : String(format: L("no_match"), model.query))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func previewBody(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                if let color = item.colorValue {
                    // Colour entries: a big swatch plus every notation, so
                    // the value can be checked at a glance before pasting.
                    HStack(alignment: .top, spacing: 12) {
                        ColorSwatch(color: color, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach([color.hexString, color.rgbString, color.hslString], id: \.self) {
                                Text($0).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)
                }
                Text(String((item.plainText ?? "").prefix(20_000)))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image:
            if let data = model.store.imageData(for: item), let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L("image_missing")).foregroundStyle(.secondary)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileURLs ?? [], id: \.self) { path in
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.ringMode {
                // Hold-⌘ ring: only these keys mean anything right now.
                hint("V", L("hint_ring_next"))
                hint("⇧V", L("hint_ring_prev"))
                hint("⌫", L("hint_delete"))
                hint("esc", L("hint_close"))
                Text(L("hint_ring_release"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            } else {
                standardHints
            }
            Spacer()
            Text("ClipStack \(appVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var standardHints: some View {
            hint("↩", model.marked.isEmpty ? L("hint_copy")
                 : String(format: L("hint_copy_marked"), model.marked.count),
                 active: !model.marked.isEmpty)
            hint("⌘1–9", L("hint_quick"))
            hint("⌘K", L("hint_transform"))
            hint("⌘M", L("hint_mark"))
            hint("⌘O", L("hint_note"))
            hint("⌘P", L("hint_pin"))
            // Highlighted while on, so the current mode is readable at a glance
            // even when the panel sits unfocused over another app.
            hint("⌘T", L("hint_keep_on_top"), active: model.keepOnTop)
            hint("⌘⌫", L("hint_delete"))
            // Global hotkey (fires even while the panel is focused); shows the
            // user's current binding so a rebind stays in sync.
            hint(clearAllKey, L("hint_clear_all"))
            hint("esc", L("hint_close"))
    }

    private var clearAllKey: String {
        let combo = HotKeys.clearAllCombo
        return KeyMap.displayString(keyCode: combo.code, carbonModifiers: UInt32(combo.mods))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func hint(_ key: String, _ label: String, active: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    active ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
        }
        // Never wrap a hint onto two lines; the footer is one tight row.
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: helpers

    private func icon(for type: ContentType) -> String {
        switch type {
        case .text: return "doc.text"
        case .url: return "link"
        case .email: return "envelope"
        case .color: return "paintpalette"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func relative(_ date: Date) -> String {
        if date.timeIntervalSinceNow > -60 { return L("just_now") }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func full(_ date: Date) -> String {
        fullFormatter.string(from: date)
    }
}

/// Small uppercase pill naming the entry's content type (URL / CODE / …).
struct TypeTag: View {
    let type: ContentType

    var body: some View {
        Text(type.tag)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .kerning(0.4)
            // Solid pill + white text: a tinted-text-on-faint-tint tag
            // washed out to unreadable when the translucent panel sat over
            // a dark window in light mode.
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(tint, in: RoundedRectangle(cornerRadius: 3))
    }

    /// One hue per type so rows can be scanned by colour alone.
    private var tint: Color {
        switch type {
        case .url: return .blue
        case .email: return .teal
        case .color: return .pink
        case .code: return .purple
        case .image: return .orange
        case .file: return .brown
        case .text: return Color(nsColor: .systemGray)
        }
    }
}

/// Rounded square filled with a parsed clipboard colour. A checkerboard sits
/// underneath so translucent colours read as translucent.
struct ColorSwatch: View {
    let color: ColorValue
    let size: CGFloat

    var body: some View {
        ZStack {
            Checkerboard().fill(Color.gray.opacity(0.35))
            Rectangle().fill(Color(
                .sRGB,
                red: Double(color.red) / 255,
                green: Double(color.green) / 255,
                blue: Double(color.blue) / 255,
                opacity: color.alpha
            ))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

private struct Checkerboard: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cell = max(3, rect.width / 6)
        var y: CGFloat = 0, row = 0
        while y < rect.height {
            var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
            while x < rect.width {
                p.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                x += cell * 2
            }
            y += cell
            row += 1
        }
        return p
    }
}
