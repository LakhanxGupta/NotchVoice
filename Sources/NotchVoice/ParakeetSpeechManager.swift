import Accelerate
import AVFoundation

/// Captures microphone audio while the hotkey is held, then transcribes the
/// whole utterance with on-device Parakeet on release (push-to-talk). Parakeet
/// is accurate and near-instant, so we don't stream partial words — the final
/// text lands a fraction of a second after you let go.
///
/// The audio engine is kept warm for a few seconds *after* release (not always,
/// so the mic isn't running in the background) and a short pre-roll of recent
/// audio is retained, so the next press doesn't clip the first word or two.
final class ParakeetSpeechManager {

    var onError: ((String) -> Void)?
    /// Live mic level (RMS) while holding, on the main thread.
    var onLevel: ((Float) -> Void)?
    /// Fired on the main thread once the model has finished loading/downloading.
    var onModelReady: (() -> Void)?

    /// Whether the Parakeet model has finished its one-time load/download.
    private(set) var isModelReady = false

    /// EXPERIMENT (qwen3-asr-experiment branch): the backend is injected rather
    /// than hardcoded, so Parakeet and Qwen3-ASR can be A/B'd at runtime.
    private var transcriber: any Transcribing
    private(set) var speechEngine: SpeechEngine

    private let engine = AVAudioEngine()

    // Guards the capture/pre-roll buffers, touched from the audio thread.
    private let lock = NSLock()
    private var active = false
    private var engineRunning = false

    /// Audio captured (mono, native sample rate) during the current hold.
    private var captured: [Float] = []
    private var sampleRate: Double = 16_000
    /// Recent audio kept while warm-but-idle, so a press captures words said the
    /// instant the key goes down (covers mic start latency).
    private var preRoll: [Float] = []
    private var preRollCap = 0

    private let idleTail: TimeInterval = 6
    private var idleStop: DispatchWorkItem?

    // MARK: - Lifecycle

    init(engine: SpeechEngine = .saved) {
        self.speechEngine = engine
        self.transcriber = Self.makeTranscriber(for: engine)
    }

    private static func makeTranscriber(for engine: SpeechEngine) -> any Transcribing {
        guard let modelId = engine.modelId else { return Transcriber() }
        return QwenTranscriber(modelId: modelId)
    }

    /// EXPERIMENT: swap the transcription backend at runtime. Frees the old
    /// Qwen weights first — two 0.6B+ models resident at once is something a
    /// 16 GB machine notices — then warms the new one.
    func setEngine(_ engine: SpeechEngine) {
        guard engine != speechEngine else { return }
        let previous = transcriber
        Task { await (previous as? QwenTranscriber)?.unload() }

        speechEngine = engine
        SpeechEngine.saved = engine
        transcriber = Self.makeTranscriber(for: engine)
        isModelReady = false
        warmUp()
    }

    /// Begin loading the model at launch so the first dictation isn't cold.
    func warmUp() {
        // Capture both, so a load that finishes after the user switched engines
        // doesn't report the wrong backend as ready.
        let loading = transcriber
        let engineAtStart = speechEngine
        Task { [weak self] in
            guard let self else { return }
            do {
                try await loading.preload()
                await MainActor.run {
                    guard self.speechEngine == engineAtStart else { return }
                    self.isModelReady = true
                    self.onModelReady?()
                }
            } catch {
                await MainActor.run {
                    self.onError?("Model load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Session

    func start() {
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micAuth == .authorized else {
            onError?("Mic permission needed → Privacy › Microphone")
            return
        }
        idleStop?.cancel()
        guard ensureEngineRunning() else { return }

        lock.lock()
        // Seed the capture with the pre-roll so the opening words aren't clipped.
        captured = preRoll
        preRoll.removeAll(keepingCapacity: true)
        active = true
        lock.unlock()
    }

    /// Stop capturing and transcribe. The completion runs on the main thread
    /// with the transcript (empty if the clip was too short) or an error. Taking
    /// a per-call completion — rather than a shared callback — keeps each
    /// session's result tied to the mode it was started in, even if a new
    /// session begins before this one's async transcription finishes.
    func stop(completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        active = false
        let samples = captured
        captured = []
        let rate = sampleRate
        lock.unlock()

        scheduleIdleStop()

        guard samples.count > Int(rate * 0.2) else {
            // Too short to be speech — just close out empty.
            completion(.success(""))
            return
        }

        let backend = transcriber
        let engineUsed = speechEngine
        Task {
            let started = Date()
            do {
                let text = try await backend.transcribe(samples: samples, sampleRate: rate)
                // EXPERIMENT: record real-world latency per engine.
                EngineLog.record(
                    engine: engineUsed,
                    audioSeconds: Double(samples.count) / rate,
                    transcribeSeconds: Date().timeIntervalSince(started),
                    transcript: text)
                await MainActor.run { completion(.success(text)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Abandon the current capture without transcribing (the hold turned out to
    /// be a shortcut chord, not dictation).
    func cancel() {
        lock.lock()
        active = false
        captured = []
        lock.unlock()
        scheduleIdleStop()
    }

    // MARK: - Engine

    private func ensureEngineRunning() -> Bool {
        if engineRunning { return true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("No mic input (check input device)")
            return false
        }
        sampleRate = format.sampleRate
        preRollCap = Int(format.sampleRate * 0.7)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onError?("Audio engine failed: \(error.localizedDescription)")
            return false
        }
        engineRunning = true
        return true
    }

    /// Real-time audio callback: append mono samples to the capture (or pre-roll)
    /// and emit the level.
    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }

        lock.lock()
        if active {
            // Bound memory on a pathologically long / stuck hold (~2 min cap).
            if captured.count < Int(sampleRate * 120) {
                captured.append(contentsOf: UnsafeBufferPointer(start: channel, count: n))
            }
            lock.unlock()
            // RMS for the waveform (SIMD, so it's cheap on the audio thread).
            var rms: Float = 0
            vDSP_rmsqv(channel, 1, &rms, vDSP_Length(n))
            DispatchQueue.main.async { self.onLevel?(rms) }
        } else {
            preRoll.append(contentsOf: UnsafeBufferPointer(start: channel, count: n))
            if preRoll.count > preRollCap {
                preRoll.removeFirst(preRoll.count - preRollCap)
            }
            lock.unlock()
        }
    }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopEngine() }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTail, execute: work)
    }

    private func stopEngine() {
        lock.lock()
        active = false
        preRoll.removeAll(keepingCapacity: false)
        lock.unlock()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        engineRunning = false
    }
}
