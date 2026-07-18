// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Violetta",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Violetta",
            targets: ["Violetta"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "12.8.0")
    ],
    targets: [
        .target(
            name: "Violetta",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke")
            ]
        ),
    ]
)
