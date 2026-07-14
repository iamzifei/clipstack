// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure-Foundation core: models + persistent history store.
        // Kept AppKit-free so it can be unit-tested headlessly.
        .target(name: "ClipStackCore"),
        // The menu-bar app itself (AppKit + SwiftUI + Carbon hotkey).
        .executableTarget(
            name: "ClipStack",
            dependencies: ["ClipStackCore"]
        ),
        // All unit tests live in this single folder.
        .testTarget(
            name: "ClipStackTests",
            dependencies: ["ClipStackCore"]
        ),
    ]
)
