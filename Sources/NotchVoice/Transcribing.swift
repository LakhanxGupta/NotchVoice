/// EXPERIMENT (qwen3-asr-experiment branch).
///
/// The one thing `ParakeetSpeechManager` needs from a transcription backend,
/// so Parakeet and Qwen3-ASR are interchangeable. Both implementations are
/// actors: the underlying models aren't `Sendable`, and this keeps each one
/// pinned to a single isolation domain.
protocol Transcribing: Actor {
    /// Load (downloading first if needed) the model. Idempotent — callers may
    /// invoke it repeatedly and should just await the first load.
    func preload() async throws

    /// Transcribe mono 32-bit float samples captured at `sampleRate`.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String
}
