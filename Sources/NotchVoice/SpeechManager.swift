import AVFoundation
import Speech

/// Streams microphone audio into `SFSpeechRecognizer` and emits the running
/// transcript. Prefers on-device recognition for privacy / offline use.
final class SpeechManager {

    /// Called on an arbitrary queue with the full transcript so far and whether
    /// this is the final result for the current session.
    var onTranscript: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    /// Live mic level (RMS, roughly 0…0.3 for speech), on the main thread.
    var onLevel: ((Float) -> Void)?

    private let locale = Locale(identifier: "en-US")

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        // Verify the two permissions we depend on and report the exact problem.
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        guard speechAuth == .authorized else {
            onError?("Speech permission needed → Privacy › Speech Recognition")
            return
        }
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micAuth == .authorized else {
            onError?("Mic permission needed → Privacy › Microphone")
            return
        }

        // Fresh recognizer each session keeps state clean.
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            onError?("Speech recognizer unavailable")
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A 0-sample-rate/0-channel format means the mic isn't actually available.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("No mic input (check input device)")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            if let channel = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += channel[i] * channel[i] }
                let rms = (n > 0) ? (sum / Float(n)).squareRoot() : 0
                DispatchQueue.main.async { self.onLevel?(rms) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            cleanup()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onTranscript?(result.bestTranscription.formattedString, result.isFinal)
            }
            if let error {
                let desc = error.localizedDescription
                if desc.localizedCaseInsensitiveContains("dictation") {
                    self.onError?("Turn on Dictation: Settings › Keyboard")
                } else if (result?.bestTranscription.formattedString ?? "").isEmpty {
                    self.onError?("Speech error: \(desc)")
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.cleanup()
            }
        }
    }

    func stop() {
        // Ending audio flushes the recognizer, which then delivers `isFinal`.
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
    }

    private func cleanup() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        task = nil
        request = nil
    }
}
