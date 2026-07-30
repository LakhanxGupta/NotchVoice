import Foundation

/// EXPERIMENT (qwen3-asr-experiment branch).
///
/// Appends one CSV row per transcription so the engines can be compared on
/// real dictation instead of on someone else's benchmark corpus. Published
/// WER/RTFx numbers come from audiobook narration; this records what actually
/// happens when *you* talk.
///
/// `~/Library/Application Support/NotchVoice/engine-timings.csv`
enum EngineLog {

    private static let queue = DispatchQueue(label: "com.lakhan.notchvoice.enginelog")

    private static var url: URL? {
        guard
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("NotchVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engine-timings.csv")
    }

    /// `timestamp,engine,audio_seconds,transcribe_seconds,xrt,chars,transcript`
    static func record(
        engine: SpeechEngine,
        audioSeconds: Double,
        transcribeSeconds: Double,
        transcript: String
    ) {
        guard let url else { return }
        let xrt = transcribeSeconds > 0 ? audioSeconds / transcribeSeconds : 0
        // Quote the transcript and escape inner quotes — dictation contains commas.
        let escaped = transcript.replacingOccurrences(of: "\"", with: "\"\"")
        let row = String(
            format: "%@,%@,%.3f,%.3f,%.1f,%d,\"%@\"\n",
            ISO8601DateFormatter().string(from: Date()),
            engine.rawValue,
            audioSeconds,
            transcribeSeconds,
            xrt,
            transcript.count,
            escaped)

        queue.async {
            let header = "timestamp,engine,audio_seconds,transcribe_seconds,xrt,chars,transcript\n"
            if !FileManager.default.fileExists(atPath: url.path) {
                try? Data(header.utf8).write(to: url)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(row.utf8))
        }
    }
}
