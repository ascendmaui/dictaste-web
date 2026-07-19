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
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 126),
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
            // The pill commits to dark glass regardless of system appearance.
            panel.appearance = NSAppearance(named: .darkAqua)
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
            y: frame.minY + 14
        ))
    }
}

private extension Color {
    static let recRed = Color(red: 1.0, green: 0.31, blue: 0.33)
    static let recRedDeep = Color(red: 0.80, green: 0.10, blue: 0.22)
    static let readyGreen = Color(red: 0.30, green: 0.85, blue: 0.48)
    static let readyGreenDeep = Color(red: 0.08, green: 0.58, blue: 0.33)
}

/// Recording = red (mic is live), ready/done = green.
private let recordGradient = LinearGradient(
    colors: [.recRed, .recRedDeep],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let readyGradient = LinearGradient(
    colors: [.readyGreen, .readyGreenDeep],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let pillShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

struct HUDView: View {
    var appState: AppState

    var body: some View {
        // Fixed slots — the layout skeleton never reflows between phases,
        // so phase changes can't smear content across the pill.
        HStack(spacing: 14) {
            leadingIcon
                .frame(width: 40, height: 40)
            content
                .frame(width: 366, height: 40, alignment: .leading)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 460)
        // Layers back-to-front: blur → dark tint → top sheen → content.
        .background(pillShape.fill(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.10), location: 0),
                    .init(color: .white.opacity(0.02), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        ))
        .background(pillShape.fill(Color(red: 0.05, green: 0.05, blue: 0.09).opacity(0.62)))
        .background(.ultraThinMaterial, in: pillShape)
        .overlay(
            pillShape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        // Hard clip: nothing (mid-transition text included) ever renders outside the pill.
        .clipShape(pillShape)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
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
                Circle().fill(Color.white.opacity(0.12))
                ProgressView().controlSize(.small)
            }
        case .polishing:
            ZStack {
                Circle().fill(readyGradient)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        case .inserting:
            ZStack {
                Circle().fill(readyGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
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
                        .foregroundStyle(.white.opacity(0.45))
                        .transition(.opacity)
                } else {
                    FlowingTranscriptView(text: appState.volatileText, width: 268)
                }
            }
        case .transcribing:
            if appState.volatileText.isEmpty {
                Text("Transcribing…").foregroundStyle(.white.opacity(0.45))
            } else {
                FlowingTranscriptView(text: appState.volatileText, width: 366)
                    .opacity(0.75)
            }
        case .polishing:
            Text("Polishing…")
                .fontWeight(.semibold)
                .foregroundStyle(readyGradient)
        case .inserting:
            FlowingTranscriptView(text: appState.volatileText, width: 366)
        case .error(let message):
            Text(message).foregroundStyle(.white.opacity(0.75))
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
                .stroke(recordGradient.opacity(0.5), lineWidth: 2)
                .scaleEffect(1 + CGFloat(level) * 0.55)
                .opacity(0.9 - Double(level) * 0.6)
            Circle()
                .fill(recordGradient)
                .scaleEffect(1 + CGFloat(level) * 0.14)
                .shadow(color: .recRed.opacity(0.35 + Double(level) * 0.5),
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
                    .fill(recordGradient)
                    .frame(width: 3.5, height: max(4, CGFloat(value(at: index)) * 30))
                    .opacity(0.5 + 0.5 * Double(index) / Double(barCount))
            }
        }
        .frame(height: 30)
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
/// Pure-layout marquee: the word row is pinned to a minimum of the slot width
/// (so short text sits at the left, past the fade zone), and the outer frame is
/// trailing-anchored (so once the row outgrows the slot, the newest words stay
/// visible and older ones flow left out through the fade).
struct FlowingTranscriptView: View {
    var text: String
    var width: CGFloat

    private let fadeWidth: CGFloat = 22

    private var words: [String] {
        text.split(separator: " ").map(String.init)
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .tracking(0.2)
                    .opacity(index == words.count - 1 ? 1 : 0.72)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(.leading, fadeWidth)
        .frame(minWidth: width, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: width, alignment: .trailing)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fadeWidth / max(width, 1)),
                    .init(color: .black, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: words)
    }
}
