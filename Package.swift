// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchVoice",
    platforms: [
        // FluidAudio (Parakeet on the Apple Neural Engine) requires macOS 14+;
        // speech-swift (Qwen3-ASR on MLX) requires macOS 15+.
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        // EXPERIMENT (qwen3-asr-experiment branch): Qwen3-ASR on MLX, as an
        // alternative transcription engine. Pinned exactly — this package is
        // pre-1.0 and its API moves. Remove with the branch.
        .package(url: "https://github.com/soniqo/speech-swift.git", exact: "0.0.23"),
    ],
    targets: [
        .executableTarget(
            name: "NotchVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
            ],
            path: "Sources/NotchVoice",
            // Our code stays in Swift 5 mode; FluidAudio still builds in its own
            // (Swift 6) mode. Avoids strict-concurrency errors on system globals.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
