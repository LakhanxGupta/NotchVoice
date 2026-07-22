import AppKit

/// Push-to-talk hotkeys. Two keys are watched, each a right-hand modifier:
///   • Right Option  → plain dictation
///   • Right Command → AI mode
///
/// We watch `.flagsChanged` to know when a modifier goes down/up. Right Command
/// is also used for ordinary shortcuts (⌘C, ⌘V…), so its key uses a short hold
/// delay before it "arms", and any real keypress while a key is held cancels the
/// session — so shortcuts keep working and don't fire the mic.
final class HotkeyManager {

    /// Identifiers for the two modes, passed back to the callbacks.
    enum Mode: String {
        case dictate
        case ai
    }

    var onPress: ((Mode) -> Void)?
    var onRelease: ((Mode) -> Void)?
    /// The held key was interrupted by another keypress (i.e. it was a shortcut,
    /// not dictation) — abandon whatever was started.
    var onCancel: ((Mode) -> Void)?

    private struct Key {
        let code: UInt16
        let flag: NSEvent.ModifierFlags
        let mode: Mode
        /// Hold this long (alone) before arming, to avoid triggering on quick
        /// shortcut chords. 0 = arm immediately.
        let holdDelay: TimeInterval
    }

    private let keys: [Key] = [
        Key(code: 61, flag: .option, mode: .dictate, holdDelay: 0),
        Key(code: 54, flag: .command, mode: .ai, holdDelay: 0.22),
    ]

    private var globalFlags: Any?
    private var localFlags: Any?
    private var globalKeys: Any?
    private var localKeys: Any?

    /// The mode currently armed (capture running).
    private var activeMode: Mode?
    /// A key held but still within its hold delay (not yet armed).
    private var pendingMode: Mode?
    private var pendingTimer: DispatchWorkItem?
    /// Safety net: if we never see the key-up (focus steal, app switch), force a
    /// release so the mic can't get stuck capturing forever.
    private var maxHoldTimer: DispatchWorkItem?
    private let maxHold: TimeInterval = 30

    func start() {
        globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e); return e
        }
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.handleOtherKey()
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleOtherKey(); return e
        }
    }

    func stop() {
        [globalFlags, localFlags, globalKeys, localKeys].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        globalFlags = nil; localFlags = nil; globalKeys = nil; localKeys = nil
    }

    private func handleFlags(_ event: NSEvent) {
        guard let key = keys.first(where: { $0.code == event.keyCode }) else { return }
        let pressed = event.modifierFlags.contains(key.flag)

        if pressed {
            // Ignore if something is already active/pending.
            guard activeMode == nil, pendingMode == nil else { return }
            if key.holdDelay <= 0 {
                arm(key.mode)
            } else {
                pendingMode = key.mode
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.pendingMode == key.mode else { return }
                    self.pendingMode = nil
                    self.arm(key.mode)
                }
                pendingTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + key.holdDelay, execute: work)
            }
        } else {
            // Release.
            if pendingMode == key.mode {
                // Released before arming — it was a tap, not a hold.
                cancelPending()
            } else if activeMode == key.mode {
                clearActive()
                onRelease?(key.mode)
            }
        }
    }

    /// A normal key was pressed. If a modifier is held/pending, treat it as a
    /// shortcut chord and abandon the session.
    private func handleOtherKey() {
        if pendingMode != nil {
            cancelPending()
        } else if let mode = activeMode {
            clearActive()
            onCancel?(mode)
        }
    }

    private func arm(_ mode: Mode) {
        activeMode = mode
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeMode == mode else { return }
            self.clearActive()
            // Treat the timeout as a release so whatever was captured is still
            // processed rather than silently dropped.
            self.onRelease?(mode)
        }
        maxHoldTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxHold, execute: work)
        onPress?(mode)
    }

    private func clearActive() {
        maxHoldTimer?.cancel()
        maxHoldTimer = nil
        activeMode = nil
    }

    private func cancelPending() {
        pendingTimer?.cancel()
        pendingTimer = nil
        pendingMode = nil
    }
}
