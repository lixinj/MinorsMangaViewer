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
    targets: [
        .executableTarget(
            name: "MinorsMangaViewer",
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
