import AppKit

/// Coordinates the pieces: hold hotkey -> transcribe speech -> show live text in
/// the notch pill -> copy the final transcript to the clipboard.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let speech = SpeechManager()
    private let hud = NotchHUD()

    private var isRecording = false
    private var sessionFinalized = false
    private var lastTranscript = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireSpeech()
        wireHotkey()

        Permissions.requestMicrophone()
        Permissions.requestSpeech()

        updateStatus(recording: false)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Right ⌥ (Option) to dictate", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Text appears in the notch & is copied", action: nil, keyEquivalent: ""))
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
        hotkey.onPress = { [weak self] in self?.startDictation() }
        hotkey.onRelease = { [weak self] in self?.stopDictation() }
        hotkey.start()
    }

    // MARK: - Speech

    private func wireSpeech() {
        speech.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async { self?.handleTranscript(text, isFinal: isFinal) }
        }
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

    private func startDictation() {
        guard !isRecording else { return }
        isRecording = true
        sessionFinalized = false
        lastTranscript = ""

        hud.show(text: "Listening…")
        updateStatus(recording: true)
        speech.start()
    }

    private func stopDictation() {
        guard isRecording else { return }
        isRecording = false
        updateStatus(recording: false)
        speech.stop()

        // Guarantee the pill closes/copies even if a final result never arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.finishSession()
        }
    }

    private func handleTranscript(_ full: String, isFinal: Bool) {
        lastTranscript = full
        hud.update(text: full.isEmpty ? "Listening…" : full)
        if isFinal { finishSession() }
    }

    /// Copy the transcript to the clipboard and collapse the pill. Safe to call
    /// more than once (from the final result and/or the release fallback).
    private func finishSession() {
        guard !sessionFinalized else { return }
        sessionFinalized = true
        let text = lastTranscript
        if text.isEmpty {
            hud.hide(after: 0.2)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            hud.showCopied(text)
        }
    }
}
