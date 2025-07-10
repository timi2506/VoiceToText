// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "VoiceToText",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "VoiceToText",
            targets: ["VoiceToText"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VoiceToText",
            dependencies: [],
            path: "Sources/VoiceToText",
            resources: []
        )
    ]
)