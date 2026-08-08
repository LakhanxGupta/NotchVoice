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

**Qwen3-ASR** is available as an optional alternative engine, picked from the
menu bar. See [Transcription engines](#transcription-engines).

## Requirements
- **Apple Silicon** Mac, **macOS 15 (Sequoia)** or newer
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

## Transcription engines

**Parakeet Unified 0.6B is the default** and needs no setup. Qwen3-ASR is
offered alongside it so the two can be compared on real dictation rather than
on published benchmarks — pick one from the menu-bar item, and the choice
persists across restarts.

Measured here on an M3 (16 GB), short push-to-talk utterances:

| Engine | Runs on | Mean speed | Mean latency |
|---|---|---|---|
| Parakeet Unified 0.6B (int8) | Neural Engine | 34.7× realtime | 0.17 s |
| Qwen3-ASR 0.6B (8-bit) | GPU via MLX | 12.4× realtime | ~0.32 s |

Both are comfortably fast enough for push-to-talk. Note the published 123×
figure for Parakeet does not transfer to 2–5 second clips, where fixed overhead
dominates.

Every transcription appends a row to
`~/Library/Application Support/NotchVoice/engine-timings.csv`
(timestamp, engine, audio seconds, transcribe seconds, speed, transcript) so
accuracy and speed can be judged on your own voice.

### Enabling the Qwen3-ASR engines

They stay hidden until MLX's shader library is present, because MLX calls
`abort()` — uncatchable from Swift — if it can't find one:

```bash
bash fetch-mlx-metallib.sh   # once, ~50 MB download
bash build.sh
```

`swift build` never compiles Metal, and the `metal` compiler ships only with
full Xcode (not Command Line Tools). Rather than require a 10 GB download,
`fetch-mlx-metallib.sh` downloads the *already compiled* `mlx.metallib` that
Apple's MLX team publishes in the `mlx-metal` wheel on PyPI, and `build.sh`
bundles it next to the executable. No Python runs at runtime — pip is only a
download mechanism, and the app stays a pure Swift binary.

The version is pinned to the MLX core inside the `mlx-swift` checkout; the
script refuses to run if the two ever drift apart, since a mismatched shader
library aborts or produces garbage.

On first selection each Qwen model downloads ~1 GB from HuggingFace.

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
- **Warm-up:** at launch, after the model loads, it runs one silent
  transcription in the background so the first *real* dictation isn't slower
  than the rest.

## License
[PolyForm Noncommercial 1.0.0](LICENSE.md) — free for any noncommercial use.
