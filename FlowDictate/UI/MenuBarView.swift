import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.tint)
                Text("FlowDictate")
                    .font(.headline)
                Spacer()
                statusDot
            }

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if appState.history.isEmpty {
                Text("Hold the fn 🌐 key and speak into any text field.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recent — click to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(appState.history.prefix(6)) { record in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    } label: {
                        Text(record.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }

            Divider()

            Toggle("Launch at Login", isOn: launchAtLogin)
                .toggleStyle(.checkbox)

            Button("Permissions Setup…") {
                appState.showOnboarding()
            }

            Button("Quit FlowDictate") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.permissions.allGranted && appState.modelReady ? .green : .orange)
            .frame(width: 8, height: 8)
    }

    private var statusLine: String {
        if !appState.permissions.allGranted { return "Setup needed — open Permissions Setup" }
        return appState.modelStatus
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Launch at login failed: \(error)")
                }
            }
        )
    }
}
