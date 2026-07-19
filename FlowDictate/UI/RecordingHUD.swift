import AppKit
import SwiftUI

/// Floating pill at the bottom-center of the screen. Non-activating, so the
/// target app keeps keyboard focus the whole time.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 52),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: HUDView(appState: appState))
            self.panel = panel
        }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 28
        ))
    }
}

struct HUDView: View {
    var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            switch appState.phase {
            case .idle:
                EmptyView()
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                LevelBarsView(levels: appState.levelHistory)
                let listeningHint = appState.triggerSource == .toggleTap
                    ? "Listening… tap ⌥ to stop" : "Listening…"
                Text(appState.volatileText.isEmpty ? listeningHint : appState.volatileText)
                    .foregroundStyle(appState.volatileText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text(appState.volatileText.isEmpty ? "Transcribing…" : appState.volatileText)
                    .lineLimit(1)
                    .truncationMode(.head)
            case .inserting:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(appState.volatileText)
                    .lineLimit(1)
                    .truncationMode(.head)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 384, alignment: .leading)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .padding(8)
    }
}

struct LevelBarsView: View {
    var levels: [Float]
    private let barCount = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = value(at: index)
                Capsule()
                    .fill(.red.opacity(0.85))
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 20))
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.08), value: levels)
    }

    private func value(at index: Int) -> Float {
        let recent = levels.suffix(barCount)
        let offset = index - (barCount - recent.count)
        guard offset >= 0 else { return 0 }
        return Array(recent)[offset]
    }
}
