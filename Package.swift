// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecipeCanvas",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RecipeCanvas",
            path: "Sources/RecipeCanvas",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RecipeCanvasTests",
            dependencies: ["RecipeCanvas"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
