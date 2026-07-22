import Foundation

/// Appends AI voice-assistant Q&A to a Markdown note, so every answer is kept in
/// a permanent, searchable log.
///
/// The destination is read from a local, gitignored config file so no personal
/// path lives in the repo:
///   `~/Library/Application Support/NotchVoice/obsidian-log-path.txt`
/// containing the full path to the log file (e.g. an Obsidian vault note). If
/// the config is absent, logging is simply skipped.
enum ObsidianLogger {

    /// Reads the log destination from the local config file. Returns nil if unset.
    private static var logFile: URL? {
        let config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchVoice", isDirectory: true)
            .appendingPathComponent("obsidian-log-path.txt")
        guard let raw = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// Append one entry. Best-effort — returns false (rather than throwing) if no
    /// destination is configured or the write fails; logging never blocks output.
    @discardableResult
    static func append(question: String, answer: String) -> Bool {
        guard let file = logFile else { return false }
        let entry = """

        ## \(timestamp.string(from: Date()))
        **Q:** \(question)

        \(answer)

        ---

        """

        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
            } else {
                // File doesn't exist yet — create it with a heading.
                let header = "# NotchVoice — AI Voice Assistant Log\n"
                try (header + entry).write(to: file, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            return false
        }
    }
}
