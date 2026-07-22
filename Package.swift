// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Sparkle: macOS auto-update framework. Ships as a binary XCFramework
        // via SPM; build.sh copies Sparkle.framework into the .app bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure-Foundation core: models + persistent history store.
        // Kept AppKit-free so it can be unit-tested headlessly.
        .target(name: "ClipStackCore"),
        // The menu-bar app itself (AppKit + SwiftUI + Carbon hotkey).
        .executableTarget(
            name: "ClipStack",
            dependencies: [
                "ClipStackCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // So the runtime finds Sparkle.framework in Contents/Frameworks
            // once build.sh has copied it there. -Xlinker passes -rpath through
            // the Swift driver to the actual linker.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        // All unit tests live in this single folder.
        .testTarget(
            name: "ClipStackTests",
            dependencies: ["ClipStackCore"]
        ),
    ]
)
