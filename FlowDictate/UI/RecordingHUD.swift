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
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 92),
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
            y: frame.minY + 26
        ))
    }
}

private extension Color {
    static let flowBlue = Color(red: 0.32, green: 0.51, blue: 1.0)
    static let flowViolet = Color(red: 0.72, green: 0.38, blue: 1.0)
}

private let flowGradient = LinearGradient(
    colors: [.flowBlue, .flowViolet],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct HUDView: View {
    var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            leadingIcon
                .frame(width: 40, height: 40)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(width: 460)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .padding(18)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.phase)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch appState.phase {
        case .idle:
            EmptyView()
        case .recording:
            MicOrbView(level: appState.currentLevel)
        case .transcribing:
            ZStack {
                Circle().fill(flowGradient.opacity(0.25))
                ProgressView().controlSize(.small)
            }
        case .polishing:
            ZStack {
                Circle().fill(flowGradient)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        case .inserting:
            ZStack {
                Circle().fill(Color.green.opacity(0.9))
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .transition(.scale.combined(with: .opacity))
        case .error:
            ZStack {
                Circle().fill(Color.orange.opacity(0.85))
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .idle:
            EmptyView()
        case .recording:
            HStack(spacing: 12) {
                WaveformView(levels: appState.levelHistory)
                if appState.volatileText.isEmpty {
                    Text(appState.triggerSource == .toggleTap
                         ? "Listening — tap ⌥ to stop" : "Listening…")
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    FlowingTranscriptView(text: appState.volatileText)
                }
            }
        case .transcribing:
            if appState.volatileText.isEmpty {
                Text("Transcribing…").foregroundStyle(.secondary)
            } else {
                FlowingTranscriptView(text: appState.volatileText)
                    .opacity(0.75)
            }
        case .polishing:
            HStack(spacing: 8) {
                Text("Polishing")
                    .foregroundStyle(flowGradient)
                    .fontWeight(.semibold)
                FlowingTranscriptView(text: appState.volatileText)
                    .opacity(0.6)
            }
        case .inserting:
            FlowingTranscriptView(text: appState.volatileText)
        case .error(let message):
            Text(message).foregroundStyle(.secondary)
        }
    }
}

/// Gradient mic orb that swells and glows with the live input level.
struct MicOrbView: View {
    var level: Float

    var body: some View {
        ZStack {
            // Soft outer pulse ring.
            Circle()
                .stroke(flowGradient.opacity(0.5), lineWidth: 2)
                .scaleEffect(1 + CGFloat(level) * 0.55)
                .opacity(0.9 - Double(level) * 0.6)
            Circle()
                .fill(flowGradient)
                .scaleEffect(1 + CGFloat(level) * 0.14)
                .shadow(color: .flowViolet.opacity(0.35 + Double(level) * 0.5),
                        radius: 6 + CGFloat(level) * 14)
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: level)
    }
}

/// Symmetric, vertically centered gradient bars driven by recent levels —
/// newest sample on the right.
struct WaveformView: View {
    var levels: [Float]
    private let barCount = 16

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(flowGradient)
                    .frame(width: 3, height: max(4, CGFloat(value(at: index)) * 26))
                    .opacity(0.45 + 0.55 * Double(index) / Double(barCount))
            }
        }
        .frame(height: 28)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: levels)
    }

    private func value(at index: Int) -> Float {
        let recent = levels.suffix(barCount)
        let offset = index - (barCount - recent.count)
        guard offset >= 0 else { return 0 }
        return Array(recent)[offset]
    }
}

/// Words appear from the right and, as the line outgrows the pill, older words
/// slide left and dissolve under the fade — the transcript flows as you speak.
struct FlowingTranscriptView: View {
    var text: String

    private var words: [String] {
        text.split(separator: " ").map(String.init)
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.16),
                    .init(color: .black, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: words)
    }
}
