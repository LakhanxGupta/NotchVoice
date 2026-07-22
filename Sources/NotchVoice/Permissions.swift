import AVFoundation
import AppKit
import ApplicationServices
import Speech

/// Requests the three permissions the app needs. All are no-ops if already granted.
enum Permissions {

    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    static func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    /// Accessibility is required to post the ⌘V paste event that inserts the
    /// transcript at the cursor. Passing the prompt option opens the system
    /// dialog directing the user to enable us in Privacy & Security.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Whether we're currently trusted for Accessibility (without prompting).
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }
}
