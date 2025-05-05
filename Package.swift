// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "spaperclip",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "spaperclip", targets: ["spaperclip"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "spaperclip",
            path: "spaperclip"
        )
    ]
)
