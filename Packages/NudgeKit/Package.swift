// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NudgeKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NudgeCore", targets: ["NudgeCore"]),
        .library(name: "NudgeUI", targets: ["NudgeUI"]),
    ],
    targets: [
        .target(name: "NudgeCore"),
        .target(name: "NudgeUI", dependencies: ["NudgeCore"]),
        .executableTarget(name: "NudgeGallery", dependencies: ["NudgeCore", "NudgeUI"]),
        .testTarget(
            name: "NudgeCoreTests",
            dependencies: ["NudgeCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "NudgeUITests", dependencies: ["NudgeUI"]),
    ]
)
