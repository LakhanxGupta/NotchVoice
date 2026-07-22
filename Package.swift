// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchVoice",
    platforms: [
        // FluidAudio (Parakeet on the Apple Neural Engine) requires macOS 14+.
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "NotchVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/NotchVoice",
            // Our code stays in Swift 5 mode; FluidAudio still builds in its own
            // (Swift 6) mode. Avoids strict-concurrency errors on system globals.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
