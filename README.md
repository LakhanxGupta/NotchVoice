# NotchVoice 🎙️

Built by [Lakhan Gupta](https://github.com/LakhanxGupta) for his own daily use.

Push-to-talk voice input for macOS, with a Dynamic-Island-style pill under the
notch that shows state and a live waveform following your actual voice level.
Two modes:

- **Dictation** — **hold Right Option (⌥)** and speak, then release. Your words
  are transcribed and **pasted at the cursor** (and left on the clipboard).
- **AI assistant** — **hold Right Command (⌘)** and speak, then release. Your
  words go to **Claude Code (read-only)**; the answer is **copied to the
  clipboard and appended to an Obsidian log** — the pill just confirms it landed.

Transcription is fully **on-device** with **NVIDIA Parakeet Unified 0.6B** (via the
[FluidAudio](https://github.com/FluidInference/FluidAudio) Swift package),
running on the Apple Neural Engine — private, free, and offline.

## Requirements
- **Apple Silicon** Mac, **macOS 14 (Sonoma)** or newer
- Swift 6 toolchain (`xcode-select --install`, recent Xcode)
- For AI mode: the [`claude`](https://claude.com/claude-code) CLI on your `PATH`

## Build & run
```bash
bash setup-signing.sh   # once — creates a stable signing identity (see below)
bash build.sh           # compile release, assemble + sign build/NotchVoice.app
open build/NotchVoice.app
```
A 🎙️ icon appears in the menu bar (no Dock icon, no window).

On first launch the Parakeet model (~600 MB) downloads once to
`~/Library/Application Support/FluidAudio/Models/`, then runs offline.

## Grant permissions (one time)
On first launch macOS prompts for these. If a prompt is missed, enable them in
**System Settings → Privacy & Security**:

1. **Microphone** — to capture audio.
2. **Accessibility** — to synthesize ⌘V (auto-paste) and observe the hotkeys.
   Without it, dictation falls back to clipboard-only (paste yourself with ⌘V).

## Usage
- **Dictation:** hold **Right ⌥**, speak, release → text is pasted at the cursor.
- **AI:** hold **Right ⌘**, speak, release → the answer is on your clipboard and
  in your Obsidian AI log; the pill shows "Saved to Obsidian".

The pill lingers a few seconds so you can read the result before it fades.

## Code signing (why it matters)
macOS remembers permissions per **signing identity**. Ad-hoc signing changes
identity every build, so the Accessibility grant kept resetting.
`setup-signing.sh` creates a stable self-signed certificate
("NotchVoice Self-Signed") in your login keychain; `build.sh` signs with it, so
the grant persists across rebuilds. If `codesign` prompts for the keychain,
click **"Always Allow"**.

## Notes / tweaks
- **Hotkeys:** Right Option = keyCode `61`, Right Command = keyCode `54`, in
  `Sources/NotchVoice/HotkeyManager.swift`. Right ⌘ has a short hold delay and
  cancels on any other key so ordinary ⌘ shortcuts still work.
- **AI is read-only:** Claude Code runs with Write/Edit/Bash disabled, in an
  isolated workspace — it can answer and read, but not modify or delete.
- **Obsidian log:** appended to `…/Documents/AI/Voice Assistant Log.md`.
- Transcription happens **on release** (one final result, ~100 ms warm), so
  there's no live partial text in the pill by design.

## License
[PolyForm Noncommercial 1.0.0](LICENSE.md) — free for any noncommercial use.
