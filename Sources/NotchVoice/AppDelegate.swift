import AppKit

/// Coordinates the pieces. Two push-to-talk modes, both transcribed on-device
/// with Parakeet:
///   • Right Option  → dictation: your words are pasted at the cursor.
///   • Right Command → AI: your words are sent to OpenAI; the reply shows in the
///     pill, goes to the clipboard, and is logged to Obsidian.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let speech = ParakeetSpeechManager()
    private let hud = NotchHUD()

    private var isRecording = false
    private var currentMode: HotkeyManager.Mode = .dictate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireSpeech()
        wireHotkey()

        Permissions.requestMicrophone()
        // Needed to auto-insert the transcript at the cursor on release.
        Permissions.requestAccessibility()

        // Start loading/downloading the Parakeet model now so the first
        // dictation isn't cold.
        speech.warmUp()

        updateStatus(recording: false)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Right ⌥ (Option) → dictate to cursor", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hold Right ⌘ (Command) → ask AI", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchVoice", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func updateStatus(recording: Bool) {
        statusItem.button?.title = recording ? "🔴" : "🎙️"
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Hotkey

    private func wireHotkey() {
        hotkey.onPress = { [weak self] mode in self?.startDictation(mode: mode) }
        hotkey.onRelease = { [weak self] _ in self?.stopDictation() }
        hotkey.onCancel = { [weak self] _ in self?.cancelDictation() }
        hotkey.start()
    }

    // MARK: - Speech

    private func wireSpeech() {
        speech.onLevel = { [weak self] level in
            self?.hud.setLevel(level)
        }
        speech.onError = { [weak self] message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hud.flashError(message)
                self.isRecording = false
                self.updateStatus(recording: false)
            }
        }
    }

    // MARK: - Session lifecycle

    private func startDictation(mode: HotkeyManager.Mode) {
        guard !isRecording else { return }
        isRecording = true
        currentMode = mode

        hud.show(text: mode == .ai ? "Ask AI…" : "Listening…")
        updateStatus(recording: true)
        speech.start()
    }

    private func stopDictation() {
        guard isRecording else { return }
        isRecording = false
        updateStatus(recording: false)
        hud.update(text: speech.isModelReady ? "Transcribing…" : "Downloading model…")

        // Capture the mode now so the async result is routed correctly even if a
        // new session starts before transcription finishes.
        let mode = currentMode
        speech.stop { [weak self] result in
            self?.handleResult(mode: mode, result: result)
        }
    }

    private func cancelDictation() {
        guard isRecording else { return }
        isRecording = false
        updateStatus(recording: false)
        speech.cancel()
        hud.hide(after: 0.1)
    }

    private func handleResult(mode: HotkeyManager.Mode, result: Result<String, Error>) {
        switch result {
        case .failure(let error):
            hud.flashError(error.localizedDescription)
        case .success(let raw):
            let text = TranscriptCleaner.clean(raw)
            guard !text.isEmpty else {
                hud.hide(after: 0.2)
                return
            }
            switch mode {
            case .dictate:
                // Paster always sets the clipboard; it also presses ⌘V when we're
                // trusted for Accessibility, so the text lands at the cursor.
                Paster.insert(text)
                hud.showCopied(text)
            case .ai:
                handleAI(prompt: text)
            }
        }
    }

    // MARK: - AI mode

    private func handleAI(prompt: String) {
        hud.update(text: "Thinking…")
        Task {
            do {
                let answer = try await ClaudeResponder.ask(prompt)
                await MainActor.run { self.deliverAI(question: prompt, answer: answer) }
            } catch {
                await MainActor.run { self.hud.flashError(error.localizedDescription) }
            }
        }
    }

    private func deliverAI(question: String, answer: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        ObsidianLogger.append(question: question, answer: answer)
        // Pill can only show so much — the full answer is on the clipboard and
        // in Obsidian.
        let preview = answer.count > 160 ? String(answer.prefix(160)) + "…" : answer
        hud.showCopied(preview)
    }
}
