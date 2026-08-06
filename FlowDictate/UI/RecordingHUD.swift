import AppKit
import SwiftUI

/// Floating bottom-center HUD. Idle = compact green-glow pill; active = expanded bar.
/// Non-activating so the target app keeps keyboard focus.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil {
            // Room for expanded state; content is clear outside the pill.
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 140),
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
    static let recRed = Color(red: 1.0, green: 0.35, blue: 0.37)
    static let recRedDeep = Color(red: 0.78, green: 0.12, blue: 0.24)
    static let readyGreen = Color(red: 0.24, green: 0.89, blue: 0.42)
    static let readyGreenDeep = Color(red: 0.06, green: 0.55, blue: 0.30)
    static let glass = Color(red: 0.04, green: 0.07, blue: 0.06)
}

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

private let pillShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
private let miniPillShape = Capsule(style: .continuous)

struct HUDView: View {
    var appState: AppState

    private var isExpanded: Bool {
        switch appState.phase {
        case .idle: return false
        default: return true
        }
    }

    /// Accent border glow ships with phase: red / green / orange.
    private var accentGlow: Color {
        switch appState.phase {
        case .recording: return .recRed
        case .transcribing: return Color.white.opacity(0.55)
        case .polishing, .inserting: return .readyGreen
        case .error: return .orange
        case .idle: return .readyGreen
        }
    }

    private var helpText: String {
        switch appState.phase {
        case .recording:
            return appState.triggerSource == .toggleTap
                ? "Tap ⌥ to stop · Esc cancels"
                : "Release fn to stop · Esc cancels"
        case .transcribing:
            return "Transcribing…"
        case .polishing:
            return "AI polishing…"
        case .inserting:
            return "Inserted"
        case .error:
            return "Try again"
        case .idle:
            return "Hold fn 🌐"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if isExpanded {
                    expandedBar
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.55, anchor: .bottom)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.55, anchor: .bottom)
                                .combined(with: .opacity)
                        ))
                } else {
                    miniPill
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.35, anchor: .bottom)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.6, anchor: .bottom)
                                .combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: appState.phase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Mini idle pill

    private var miniPill: some View {
        HStack(spacing: 7) {
            // Soft pulsing green core
            ZStack {
                Circle()
                    .fill(Color.readyGreen.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .blur(radius: 3)
                Circle()
                    .fill(readyGradient)
                    .frame(width: 8, height: 8)
                    .shadow(color: .readyGreen.opacity(0.9), radius: 4)
            }
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.readyGreen.opacity(0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            ZStack {
                miniPillShape.fill(.ultraThinMaterial)
                miniPillShape.fill(Color.glass.opacity(0.88))
                miniPillShape.fill(
                    LinearGradient(
                        colors: [
                            Color.readyGreen.opacity(0.12),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(
            miniPillShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.readyGreen.opacity(0.85),
                        Color.readyGreen.opacity(0.35),
                        Color.readyGreen.opacity(0.65),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
        )
        .clipShape(miniPillShape)
        .shadow(color: .readyGreen.opacity(0.55), radius: 10, y: 0)
        .shadow(color: .readyGreen.opacity(0.28), radius: 18, y: 0)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .modifier(IdleGreenPulse())
    }

    // MARK: - Expanded active bar

    private var expandedBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                leadingIcon
                    .frame(width: 32, height: 32)
                content
                    .frame(width: 300, height: 32, alignment: .leading)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 370)
            .background {
                ZStack {
                    pillShape.fill(.ultraThinMaterial)
                    pillShape.fill(
                        LinearGradient(
                            colors: [
                                Color.glass.opacity(0.8),
                                Color.glass.opacity(0.94),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    pillShape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.1), location: 0),
                                .init(color: .white.opacity(0.02), location: 0.45),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay(
                pillShape.strokeBorder(
                    LinearGradient(
                        colors: [
                            accentGlow.opacity(0.65),
                            accentGlow.opacity(0.2),
                            accentGlow.opacity(0.4),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
            )
            .clipShape(pillShape)
            .shadow(color: accentGlow.opacity(0.28), radius: 12, y: 0)
            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)

            Text(helpText)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                ProgressView().controlSize(.mini)
            }
        case .polishing:
            ZStack {
                Circle()
                    .fill(readyGradient)
                    .shadow(color: .readyGreen.opacity(0.4), radius: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        case .inserting:
            ZStack {
                Circle()
                    .fill(readyGradient)
                    .shadow(color: .readyGreen.opacity(0.35), radius: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .error:
            ZStack {
                Circle().fill(Color.orange.opacity(0.9))
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
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
            HStack(spacing: 8) {
                WaveformView(levels: appState.levelHistory, live: true)
                if appState.volatileText.isEmpty {
                    Text("Listening…")
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                } else {
                    FlowingTranscriptView(text: appState.volatileText, width: 220)
                }
            }
        case .transcribing:
            if appState.volatileText.isEmpty {
                Text("Transcribing…").foregroundStyle(.white.opacity(0.4))
            } else {
                FlowingTranscriptView(text: appState.volatileText, width: 300)
                    .opacity(0.78)
            }
        case .polishing:
            VStack(alignment: .leading, spacing: 4) {
                Text("AI polishing…")
                    .fontWeight(.semibold)
                    .foregroundStyle(readyGradient)
                PolishProgressBar()
            }
        case .inserting:
            FlowingTranscriptView(text: appState.volatileText, width: 300)
        case .error(let message):
            Text(message)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}

/// Gentle green glow pulse while idle.
private struct IdleGreenPulse: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.04 : 1.0)
            .opacity(pulse ? 1.0 : 0.92)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct MicOrbView: View {
    var level: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(recordGradient.opacity(0.55), lineWidth: 1.5)
                .scaleEffect(1 + CGFloat(level) * 0.45)
                .opacity(0.85 - Double(level) * 0.55)
            Circle()
                .fill(recordGradient)
                .scaleEffect(1 + CGFloat(level) * 0.1)
                .shadow(color: .recRed.opacity(0.4 + Double(level) * 0.4),
                        radius: 5 + CGFloat(level) * 8)
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: level)
    }
}

struct WaveformView: View {
    var levels: [Float]
    var live: Bool = false
    private let barCount = 12

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(live ? AnyShapeStyle(recordGradient) : AnyShapeStyle(readyGradient))
                    .frame(width: 2.5, height: max(3, CGFloat(value(at: index)) * 22))
                    .opacity(0.45 + 0.55 * Double(index) / Double(barCount))
            }
        }
        .frame(height: 22)
        .animation(.spring(response: 0.2, dampingFraction: 0.72), value: levels)
    }

    private func value(at index: Int) -> Float {
        let recent = levels.suffix(barCount)
        let offset = index - (barCount - recent.count)
        guard offset >= 0 else { return 0.08 }
        return max(0.08, Array(recent)[offset])
    }
}

struct PolishProgressBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(readyGradient)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: phase * (geo.size.width * 0.6))
                    .shadow(color: .readyGreen.opacity(0.45), radius: 4)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

struct FlowingTranscriptView: View {
    var text: String
    var width: CGFloat

    private let fadeWidth: CGFloat = 14

    private var words: [String] {
        text.split(separator: " ").map(String.init)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .tracking(0.1)
                    .opacity(index == words.count - 1 ? 1 : 0.68)
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
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: words)
    }
}
