import AppKit
import AVFoundation
import Observation

@MainActor
@Observable
final class PermissionsModel {
    var micGranted = false
    var axGranted = false
    /// True when the fn key is set to "Do Nothing" in System Settings › Keyboard.
    var fnKeyFreed = false

    var allGranted: Bool { micGranted && axGranted && fnKeyFreed }

    func refresh() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
        // com.apple.HIToolbox AppleFnUsageType: 0 = Do Nothing, 1 = Change Input
        // Source, 2 = Show Emoji & Symbols, 3 = Start Dictation. Missing = default (not 0).
        let fnUsage = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .object(forKey: "AppleFnUsageType") as? Int
        fnKeyFreed = fnUsage == 0
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
