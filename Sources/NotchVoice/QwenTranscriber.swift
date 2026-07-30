import Foundation
import Qwen3ASR

/// EXPERIMENT (qwen3-asr-experiment branch).
///
/// Wraps speech-swift's Qwen3-ASR (MLX, so the GPU rather than the Neural
/// Engine). Deliberately mirrors `Transcriber`'s shape — same one-time load
/// with retry-on-failure, same `transcribe` signature — so the two are
/// swappable behind `Transcribing`.
///
/// Unlike Parakeet this is an encoder + autoregressive LLM decoder, which
/// means two things worth knowing: first inference pays for Metal shader
/// compilation (hence the dummy pass in `preload`), and latency scales with
/// the number of words spoken rather than just the audio length.
actor QwenTranscriber: Transcribing {

    private let modelId: String
    private var model: Qwen3ASRModel?
    private var loadTask: Task<Qwen3ASRModel, Error>?

    init(modelId: String) {
        self.modelId = modelId
    }

    /// Download + load the weights once, then run a throwaway inference to
    /// force Metal shader compilation. Without that second step the first real
    /// dictation eats a multi-second compile that the weight load alone
    /// doesn't cover.
    func preload() async throws {
        _ = try await loadedModel()
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let model = try await loadedModel()
        // Qwen's feature extractor resamples internally, so the mic's native
        // rate goes straight in — no WAV file, no ffmpeg hop.
        return model.transcribe(
            audio: samples,
            sampleRate: Int(sampleRate),
            language: "en")
    }

    // MARK: - Loading

    private func loadedModel() async throws -> Qwen3ASRModel {
        if let model { return model }
        if let loadTask {
            do {
                let model = try await loadTask.value
                self.model = model
                return model
            } catch {
                // A failed download shouldn't poison every future attempt.
                self.loadTask = nil
                throw error
            }
        }

        let id = modelId
        let task = Task { () throws -> Qwen3ASRModel in
            let model = try await Qwen3ASRModel.fromPretrained(modelId: id)
            // Half a second of silence: cheap, and it compiles the shaders.
            _ = model.transcribe(audio: [Float](repeating: 0, count: 8_000), sampleRate: 16_000)
            return model
        }
        loadTask = task
        do {
            let model = try await task.value
            self.model = model
            return model
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Free the weights when switching away from this engine — otherwise two
    /// models sit resident, which a 16 GB machine notices.
    func unload() {
        model?.unload()
        model = nil
        loadTask = nil
    }
}
