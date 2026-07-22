import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if appState.history.isEmpty {
                Text("Hold fn 🌐, or tap left ⌥ to start and stop. Esc cancels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recent — click to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(appState.history.prefix(6)) { record in
                    HistoryRow(record: record)
                }
            }

            Divider()

            Toggle("AI Polish", isOn: Binding(
                get: { appState.polishEnabled },
                set: { appState.polishEnabled = $0 }
            ))
            .toggleStyle(.checkbox)
            .disabled(!appState.polisher.isAvailable)
            if let reason = appState.polisher.unavailabilityReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Toggle("Tap left ⌥ to start/stop", isOn: Binding(
                get: { appState.optionTapEnabled },
                set: { appState.optionTapEnabled = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle("Start at login & auto-restart", isOn: Binding(
                get: { appState.agentEnabled },
                set: { appState.setAgentEnabled($0) }
            ))
            .toggleStyle(.checkbox)

            Divider()

            Button("Custom Vocabulary…") {
                appState.showVocabulary()
            }

            Button("Permissions Setup…") {
                appState.showOnboarding()
            }

            Button("Quit FlowDictate") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 310)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.30, green: 0.85, blue: 0.48),
                                            Color(red: 0.08, green: 0.58, blue: 0.33)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("FlowDictate")
                .font(.headline)
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        let (label, color): (String, Color) = {
            if !appState.permissions.allGranted { return ("Setup needed", .orange) }
            if !appState.modelReady { return ("Preparing…", .orange) }
            switch appState.phase {
            case .recording: return ("Recording", .red)
            case .transcribing, .polishing: return ("Working…", .blue)
            default: return ("Ready", .green)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct HistoryRow: View {
    let record: DictationRecord
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                copied = false
            }
        } label: {
            HStack {
                Text(record.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if copied {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if hovering {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
