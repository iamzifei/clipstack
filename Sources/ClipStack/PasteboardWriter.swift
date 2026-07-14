import AppKit
import ClipStackCore

/// Writes a history entry back to the general pasteboard, restoring every
/// flavor we captured (plain + RTF + HTML for text, PNG + TIFF for images,
/// real file URLs for files).
enum PasteboardWriter {
    static func write(_ item: ClipItem, store: HistoryStore) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text:
            var types: [NSPasteboard.PasteboardType] = [.string]
            if item.rtfData != nil { types.append(.rtf) }
            if item.htmlData != nil { types.append(.html) }
            types.append(ClipboardMonitor.selfMarker)
            pb.declareTypes(types, owner: nil)
            pb.setString(item.plainText ?? "", forType: .string)
            if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            if let html = item.htmlData { pb.setData(html, forType: .html) }
            pb.setData(Data(), forType: ClipboardMonitor.selfMarker)

        case .image:
            guard let png = store.imageData(for: item) else { return }
            pb.declareTypes([.png, .tiff, ClipboardMonitor.selfMarker], owner: nil)
            pb.setData(png, forType: .png)
            if let rep = NSBitmapImageRep(data: png), let tiff = rep.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            pb.setData(Data(), forType: ClipboardMonitor.selfMarker)

        case .file:
            let urls = (item.fileURLs ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return }
            pb.writeObjects(urls)
            pb.addTypes([ClipboardMonitor.selfMarker], owner: nil)
            pb.setData(Data(), forType: ClipboardMonitor.selfMarker)
        }

        // The monitor ignores our marker, so bump the entry to the front here.
        store.promoteIfExists(hash: item.contentHash)
    }
}
