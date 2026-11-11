// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Face2EmojiCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Face2EmojiCore", targets: ["Face2EmojiCore"]),
    ],
    targets: [
        .target(name: "Face2EmojiCore"),
        .testTarget(
            name: "Face2EmojiCoreTests",
            dependencies: ["Face2EmojiCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
