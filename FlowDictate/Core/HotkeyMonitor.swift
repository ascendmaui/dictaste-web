import AppKit
import CoreGraphics

/// Watches the fn/globe key and left ⌥ system-wide via an active CGEventTap.
/// fn: hold = record, release = insert; any other key while fn is down
/// (fn+arrow etc.) cancels instead of firing. Left ⌥: a clean, quick tap
/// (no other key, mouse, or scroll during the press) fires onToggleTap —
/// combos like ⌥+e or ⌥-click never trigger it.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onToggleTap: (() -> Void)?

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var fnDown = false
    private var cancelled = false
    private var optionDown = false
    private var optionTapValid = false
    private var optionDownTime: CFAbsoluteTime = 0

    private static let fnKeyCode: Int64 = 63 // kVK_Function
    private static let leftOptionKeyCode: Int64 = 58 // kVK_Option
    private static let tapMaxDuration: CFAbsoluteTime = 0.4

    func startIfPossible() {
        guard !isActive, AXIsProcessTrusted() else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
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
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case Self.fnKeyCode:
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
            case Self.leftOptionKeyCode:
                let down = event.flags.contains(.maskAlternate)
                if down && !optionDown {
                    optionDown = true
                    optionTapValid = true
                    optionDownTime = CFAbsoluteTimeGetCurrent()
                } else if !down && optionDown {
                    optionDown = false
                    if optionTapValid,
                       CFAbsoluteTimeGetCurrent() - optionDownTime < Self.tapMaxDuration {
                        DispatchQueue.main.async { self.onToggleTap?() }
                    }
                }
            default:
                break
            }
        case .keyDown:
            if optionDown { optionTapValid = false }
            if fnDown && !cancelled {
                cancelled = true
                DispatchQueue.main.async { self.onCancel?() }
            }
        case .leftMouseDown, .rightMouseDown, .scrollWheel:
            if optionDown { optionTapValid = false }
        default:
            break
        }
    }
}
