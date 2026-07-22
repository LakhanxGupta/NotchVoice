import AppKit

/// Inserts text at the current cursor by putting it on the pasteboard and
/// synthesizing a ⌘V into the frontmost app — the "it just appears where I'm
/// typing" behaviour, instead of making the user paste by hand.
///
/// Requires Accessibility permission (to post the keystroke). Callers should
/// fall back to leaving the text on the clipboard when we're not trusted.
enum Paster {

    /// Virtual keyCode for the `V` key on a US layout.
    private static let vKeyCode: CGKeyCode = 9

    /// Puts `text` on the clipboard, then presses ⌘V. Returns false (having
    /// still set the clipboard) if we lack Accessibility and can't paste.
    @discardableResult
    static func insert(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard Permissions.isAccessibilityTrusted else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
