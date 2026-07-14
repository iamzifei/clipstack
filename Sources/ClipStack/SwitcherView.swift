import SwiftUI
import ClipStackCore

/// The floating switcher: search bar on top, history list on the left,
/// full-fidelity preview on the right.
struct SwitcherView: View {
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
        .frame(width: 780, height: 460)
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
                            .onTapGesture { model.selectionIndex = pair.offset }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectionIndex) { _ in
                if let id = model.selected?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func row(item: ClipItem, index: Int) -> some View {
        let isSelected = index == model.selectionIndex
        return HStack(spacing: 8) {
            Image(systemName: icon(for: item.kind))
                .frame(width: 16)
                .foregroundStyle(isSelected ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewLine)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                HStack(spacing: 6) {
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
            isSelected ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    @ViewBuilder
    private var previewPane: some View {
        if let item = model.selected {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(kindLabel(item.kind))
                        .font(.system(size: 11, weight: .semibold))
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
        HStack(spacing: 14) {
            hint("↩", L("hint_copy"))
            hint("⌘1–9", L("hint_quick"))
            hint("⌘P", L("hint_pin"))
            hint("⌘⌫", L("hint_delete"))
            hint("esc", L("hint_close"))
            Spacer()
            Text("ClipStack")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: helpers

    private func icon(for kind: ClipKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    private func kindLabel(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return L("kind_text")
        case .image: return L("kind_image")
        case .file: return L("kind_file")
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
