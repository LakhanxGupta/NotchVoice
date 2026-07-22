import Foundation

/// Appends AI voice-assistant Q&A to a note in the Obsidian vault, so every
/// answer is kept in a permanent, searchable log.
enum ObsidianLogger {

    /// `…/Documents/AI/Voice Assistant Log.md` — the dedicated "AI" vault.
    private static var logFile: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
            .appendingPathComponent("AI", isDirectory: true)
            .appendingPathComponent("Voice Assistant Log.md")
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// Append one entry. Best-effort — failures are returned so the caller can
    /// surface them, but they don't block the pill/clipboard output.
    @discardableResult
    static func append(question: String, answer: String) -> Bool {
        let file = logFile
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
