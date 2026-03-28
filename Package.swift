// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TinyPDF",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Packages/TinyKit"),
    ],
    targets: [
        .executableTarget(
            name: "TinyPDF",
            dependencies: ["TinyKit"],
            path: "Sources/TinyPDF",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
