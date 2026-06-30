// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MinorsMangaViewer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "MinorsMangaViewer",
            targets: ["MinorsMangaViewer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/mtgto/Unrar.swift.git", from: "0.3.0")
    ],
    targets: [
        .executableTarget(
            name: "MinorsMangaViewer",
            dependencies: [
                "ZIPFoundation",
                .product(name: "Unrar", package: "Unrar.swift")
            ],
            path: "Sources/MinorsMangaViewer",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/blank_page.jpg")
            ]
        ),
        .testTarget(
            name: "MinorsMangaViewerTests",
            dependencies: ["MinorsMangaViewer"],
            path: "Tests/MinorsMangaViewerTests"
        ),
    ]
)
