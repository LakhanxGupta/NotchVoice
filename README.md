# NotchVoice 🎙️

Built by [Lakhan Gupta](https://github.com/LakhanxGupta) for his own daily use.

Push-to-talk dictation for macOS. **Hold the Right Option (⌥) key and speak** —
your words appear live in a Dynamic-Island-style pill under the notch, with a
waveform that follows your actual voice level. On release the transcript is
**copied to your clipboard**, so you can paste it anywhere with ⌘V (Safari,
YouTube search, chat fields, notes, etc.).

Speech is transcribed **on-device** with Apple's Speech framework — private, free,
and works offline. No Accessibility permission required.

## Requirements
- macOS 13 (Ventura) or newer
- Xcode command-line tools / Swift toolchain (`xcode-select --install`)
- **Dictation enabled**: System Settings → Keyboard → Dictation → On.
  (Apple's on-device speech recognizer refuses to run otherwise, even with
  Microphone/Speech Recognition permissions granted.)

## Build & run
```bash
bash build.sh
open build/NotchVoice.app
```
A 🎙️ icon appears in the menu bar.

## Grant permissions (one time)
On first launch macOS will prompt for these. If a prompt is missed, enable them
manually in **System Settings → Privacy & Security**:

1. **Microphone** — to hear you.
2. **Speech Recognition** — to transcribe.

That's it — no Accessibility permission needed.

## Usage
1. **Hold Right Option (⌥)** and speak — text streams into the pill under the notch.
2. **Release** to stop — the transcript is now on your clipboard.
3. Click wherever you want it and press **⌘V**.

## Notes / tweaks
- **Language:** defaults to `en-US`. Change the `locale` in
  `Sources/NotchVoice/SpeechManager.swift`.
- **Hotkey:** Right Option = virtual keyCode `61` in
  `Sources/NotchVoice/HotkeyManager.swift`.
- The transcript is intentionally left on the clipboard after each session.
- If the recognizer revises earlier words mid-stream, NotchVoice waits for the
  next stable result rather than corrupt what's already shown.

## License
[PolyForm Noncommercial 1.0.0](LICENSE.md) — free for any noncommercial use.
