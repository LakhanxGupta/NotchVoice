// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchVoice",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "NotchVoice",
            path: "Sources/NotchVoice"
        )
    ]
)
