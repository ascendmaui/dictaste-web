import AppKit
import CoreGraphics

/// Watches the fn/globe key system-wide via an active CGEventTap.
/// Hold = record, release = insert. Pressing any other key while fn is
/// down (fn+arrow etc.) cancels the dictation instead of firing it.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var fnDown = false
    private var cancelled = false

    private static let fnKeyCode: Int64 = 63 // kVK_Function

    func startIfPossible() {
        guard !isActive, AXIsProcessTrusted() else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<HotkeyMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                        .handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeyCode else { return }
            let down = event.flags.contains(.maskSecondaryFn)
            if down && !fnDown {
                fnDown = true
                cancelled = false
                DispatchQueue.main.async { self.onPress?() }
            } else if !down && fnDown {
                fnDown = false
                let wasCancelled = cancelled
                cancelled = false
                if !wasCancelled {
                    DispatchQueue.main.async { self.onRelease?() }
                }
            }
        case .keyDown:
            if fnDown && !cancelled {
                cancelled = true
                DispatchQueue.main.async { self.onCancel?() }
            }
        default:
            break
        }
    }
}
