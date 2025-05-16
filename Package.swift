// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "spaperclip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "spaperclip", targets: ["spaperclip"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0")
    ],
    targets: [
        .executableTarget(
            name: "spaperclip",
            dependencies: ["KeyboardShortcuts"],
            path: "spaperclip",
            resources: [
                .process("Assets.xcassets"),
                .process("Preview Content"),
                .process("spaperclip.entitlements"),
            ]
        ),
        .testTarget(
            name: "spaperclipTests",
            dependencies: ["spaperclip"],
            path: "spaperclipTests"
        ),
    ]
)
