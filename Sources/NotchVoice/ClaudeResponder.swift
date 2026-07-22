import Foundation

/// Tiny thread-safe flag: the watchdog (one queue) sets it, the reader (another)
/// checks it after the process exits.
private final class TimeoutFlag {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

/// Sends a spoken prompt to Claude Code's CLI in headless mode (`claude -p`) and
/// returns its reply. Used by the AI hotkey. No API key needed — it uses your
/// existing Claude Code authentication.
enum ClaudeResponder {

    enum ClaudeError: LocalizedError {
        case notFound
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "Claude Code CLI not found (is `claude` installed?)"
            case .timedOut: return "Claude Code timed out"
            case .failed(let msg): return msg.isEmpty ? "Claude Code failed" : msg
            }
        }
    }

    private static let timeout: TimeInterval = 120

    /// The voice session is read-only: it can read files and answer, but must not
    /// edit, create, or delete anything. We deny every mutating tool (and Bash,
    /// which could delete via `rm`).
    private static let disallowedTools = "Write,Edit,NotebookEdit,Bash"

    static func ask(_ prompt: String) async throws -> String {
        guard let claude = resolvePath() else { throw ClaudeError.notFound }
        let workspace = ensureWorkspace()

        return try await withCheckedThrowingContinuation { continuation in
            // Run off the cooperative pool — this blocks on process I/O.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claude)
                // `--disallowed-tools` is variadic and would swallow the prompt,
                // so it must come first with `-p` and the prompt strictly last.
                process.arguments = [
                    "--disallowed-tools", disallowedTools,
                    "-p",
                    "Respond concisely.\n\n\(prompt)",
                ]
                process.currentDirectoryURL = workspace

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Kill it if it runs away (agentic sessions can hang).
                let didTimeOut = TimeoutFlag()
                let watchdog = DispatchWorkItem {
                    if process.isRunning {
                        didTimeOut.set()
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                // Read stdout/stderr to EOF so a large reply can't fill the pipe
                // buffer and deadlock the child.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                let timedOut = didTimeOut.value

                let out = String(decoding: outData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else if timedOut {
                    continuation.resume(throwing: ClaudeError.timedOut)
                } else {
                    let err = String(decoding: errData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ClaudeError.failed(err.isEmpty ? out : err))
                }
            }
        }
    }

    /// Full path to the `claude` binary. A Finder-launched app has a minimal
    /// PATH (no Homebrew), so check the usual spots, then fall back to a login
    /// shell that has the user's real PATH.
    private static func resolvePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        try? shell.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// A dedicated empty folder so Claude Code doesn't see (or act on) unrelated
    /// project files.
    private static func ensureWorkspace() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchVoice", isDirectory: true)
            .appendingPathComponent("claude-workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
