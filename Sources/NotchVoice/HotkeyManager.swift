import AppKit

/// Push-to-talk: hold **Right Option** to dictate, release to stop.
///
/// We watch `.flagsChanged` events. The Right Option key has virtual keyCode 61.
/// When that key's event carries the `.option` flag it's a press; when it doesn't
/// it's a release. We use both a global monitor (events destined for other apps)
/// and a local monitor (events for our own process), so it works everywhere.
final class HotkeyManager {

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// Virtual keyCode for the Right Option key.
    private let rightOptionKeyCode: UInt16 = 61

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == rightOptionKeyCode else { return }
        let pressed = event.modifierFlags.contains(.option)
        if pressed, !isDown {
            isDown = true
            onPress?()
        } else if !pressed, isDown {
            isDown = false
            onRelease?()
        }
    }
}
