import Foundation

/// The switcher's "show only one type" filter, cycled with Tab / ⇧Tab.
///
/// Pure logic so it is unit-testable: the panel keeps the current selection
/// (`nil` = All) and asks this type which chips to show and where Tab goes.
public enum TypeFilter {
    /// Fixed chip order, so a type always sits in the same place.
    public static let order: [ContentType] = [.text, .url, .code, .email, .color, .image, .file]

    /// Types that actually occur, in chip order. Absent types get no chip,
    /// so cycling never lands on an empty list.
    public static func available(_ present: Set<ContentType>) -> [ContentType] {
        order.filter { present.contains($0) }
    }

    /// Next filter in the cycle All → available[0] → … → All.
    /// A `current` that is no longer available (its last entry was deleted)
    /// restarts the cycle from All.
    public static func cycle(_ current: ContentType?, available: [ContentType], step: Int) -> ContentType? {
        let options: [ContentType?] = [nil] + available.map { Optional($0) }
        let index = current.flatMap { c in options.firstIndex(where: { $0 == c }) } ?? 0
        let n = options.count
        return options[((index + step) % n + n) % n]
    }
}

/// Light / dark / follow-the-system choice for every ClipStack window.
public enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    /// Parses the stored preference; anything unknown means "follow the system".
    public init(stored: String?) {
        self = stored.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
