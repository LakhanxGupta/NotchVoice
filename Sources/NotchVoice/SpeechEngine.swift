import Foundation

/// EXPERIMENT (qwen3-asr-experiment branch).
///
/// Which transcription engine the app is currently using. Parakeet is the
/// default and the shipping path; the Qwen3-ASR variants are here to be
/// measured against it on real dictation, not because they're known better.
///
/// Delete this file (and the menu section that reads it) to revert.
enum SpeechEngine: String, CaseIterable {

    /// FluidAudio's Parakeet Unified 0.6B, int8 on the Neural Engine.
    case parakeet
    /// Qwen3-ASR 0.6B, 8-bit, MLX/GPU. The variant speech-swift recommends
    /// for 8–16 GB machines.
    case qwen06b8bit
    /// Qwen3-ASR 1.7B, 4-bit. speech-swift's own suggested fallback for
    /// machines under 24 GB ("smaller, similar quality").
    case qwen17b4bit
    /// Qwen3-ASR 1.7B, 8-bit. The accuracy pick on paper (1.32% WER on
    /// LibriSpeech test-clean), but speech-swift warns it swaps and stalls
    /// on systems below 24 GB when other apps are running.
    case qwen17b8bit

    static let `default`: SpeechEngine = .parakeet

    var title: String {
        switch self {
        case .parakeet: return "Parakeet 0.6B (ANE) — default"
        case .qwen06b8bit: return "Qwen3-ASR 0.6B 8-bit (MLX)"
        case .qwen17b4bit: return "Qwen3-ASR 1.7B 4-bit (MLX)"
        case .qwen17b8bit: return "Qwen3-ASR 1.7B 8-bit (MLX) — 24 GB+"
        }
    }

    /// HuggingFace repo for the MLX engines; `nil` for Parakeet, which
    /// FluidAudio downloads on its own.
    var modelId: String? {
        switch self {
        case .parakeet: return nil
        case .qwen06b8bit: return "aufklarer/Qwen3-ASR-0.6B-MLX-8bit"
        case .qwen17b4bit: return "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"
        case .qwen17b8bit: return "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
        }
    }

    /// Whether this engine needs MLX (and therefore `mlx.metallib`).
    var requiresMLX: Bool { modelId != nil }

    // MARK: - MLX availability

    /// MLX aborts the whole process — a C++ `abort()`, not a catchable Swift
    /// error — if it can't find `mlx.metallib`, which SwiftPM does not build.
    /// It has to be compiled with Xcode's Metal toolchain (see
    /// `scripts/build_mlx_metallib.sh` in the speech-swift checkout) and placed
    /// next to the executable. Command Line Tools alone do not ship `metal`.
    ///
    /// So: check before offering an MLX engine, rather than dying on selection.
    static let isMLXAvailable: Bool = {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = exe.deletingLastPathComponent().appendingPathComponent("mlx.metallib")
        return FileManager.default.fileExists(atPath: sibling.path)
    }()

    /// Engines that can actually run in this build.
    static var available: [SpeechEngine] {
        allCases.filter { !$0.requiresMLX || isMLXAvailable }
    }

    // MARK: - Persistence

    private static let key = "speechEngine"

    /// The engine chosen last run. Falls back to Parakeet if the stored value
    /// is unknown (e.g. after reverting this branch) *or* names an MLX engine
    /// in a build without `mlx.metallib` — otherwise a stored Qwen choice
    /// would abort the process on every launch, with no UI left to fix it.
    static var saved: SpeechEngine {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                let engine = SpeechEngine(rawValue: raw),
                !engine.requiresMLX || isMLXAvailable
            else { return .default }
            return engine
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
