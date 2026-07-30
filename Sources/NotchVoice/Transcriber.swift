import AVFoundation
import FluidAudio

/// Wraps FluidAudio's on-device Parakeet model. An actor so the (non-Sendable)
/// model is only ever touched from one place, and the ~600 MB download that
/// happens on first use is loaded exactly once.
actor Transcriber: Transcribing {

    private let asr = UnifiedAsrManager()
    private var loadTask: Task<Void, Error>?
    private(set) var isLoaded = false

    /// Kick off (or await) the one-time model load/download. Safe to call more
    /// than once — later callers just await the first load.
    func preload() async throws {
        if isLoaded { return }
        if let loadTask {
            do {
                try await loadTask.value
                isLoaded = true
                return
            } catch {
                // A failed download shouldn't poison every future attempt —
                // drop the task so the next call retries from scratch.
                self.loadTask = nil
                throw error
            }
        }
        let task = Task { try await asr.loadModels() }
        loadTask = task
        do {
            try await task.value
            isLoaded = true
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Transcribe mono 32-bit float samples captured at `sampleRate`. Parakeet
    /// wants 16 kHz; FluidAudio resamples internally, so we just wrap the
    /// samples in a buffer at their native rate.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        try await preload()
        guard !samples.isEmpty else { return "" }

        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count))
        else {
            return ""
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        return try await asr.transcribe(buffer)
    }
}
