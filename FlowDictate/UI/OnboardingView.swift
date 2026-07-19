import SwiftUI

struct OnboardingView: View {
    var appState: AppState
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to FlowDictate")
                    .font(.title.bold())
                Text("Three quick steps and you can dictate into any app: hold fn 🌐, speak, release.")
                    .foregroundStyle(.secondary)
            }

            stepRow(
                done: appState.permissions.micGranted,
                title: "Microphone",
                detail: "So FlowDictate can hear you.",
                buttonTitle: "Grant Access"
            ) {
                appState.permissions.requestMic()
            }

            stepRow(
                done: appState.permissions.axGranted,
                title: "Accessibility",
                detail: "Lets FlowDictate watch the fn key and type into the focused field. Enable FlowDictate in System Settings › Privacy & Security › Accessibility.",
                buttonTitle: "Grant Access"
            ) {
                appState.permissions.requestAccessibility()
            }

            stepRow(
                done: appState.permissions.fnKeyFreed,
                title: "Free up the fn 🌐 key",
                detail: "In System Settings › Keyboard, set “Press 🌐 key to” to “Do Nothing” so it doesn't open the emoji picker. If the Dictation shortcut uses fn, turn that off too.",
                buttonTitle: "Open Keyboard Settings"
            ) {
                appState.permissions.openKeyboardSettings()
            }

            Divider()

            if appState.permissions.allGranted {
                Label {
                    Text("You're all set — hold fn 🌐 and start talking. \(appState.modelStatus).")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .font(.headline)
            } else {
                Text(appState.modelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 540, alignment: .leading)
        .onReceive(refresh) { _ in
            appState.permissions.refresh()
            if appState.permissions.axGranted {
                appState.hotkey.startIfPossible()
            }
        }
    }

    @ViewBuilder
    private func stepRow(
        done: Bool,
        title: String,
        detail: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !done {
                    Button(buttonTitle, action: action)
                        .padding(.top, 2)
                }
            }
        }
    }
}
