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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "spaperclip",
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
