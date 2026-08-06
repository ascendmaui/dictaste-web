import SwiftUI

struct AccountView: View {
    @State private var licenseKey = CloudPolisher.licenseKey
    @State private var openAIKey = CloudPolisher.openAIKey
    @State private var preferManaged = CloudPolisher.preferManagedPro
    @State private var saved = false
    @State private var refreshing = false
    private var usage = UsageStore.shared

    var body: some View {
        Form {
            Section {
                Text("Dictation is free. Developers: star GitHub + paste license + your LLM key for unlimited polish (no cost to us). Free tier otherwise includes 2,000 managed words/day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("AI polish usage") {
                HStack {
                    Text("Plan")
                    Spacer()
                    Text(usage.plan.capitalized)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Used")
                    Spacer()
                    Text(usage.meterLabel)
                        .foregroundStyle(usage.isAtLimit ? .orange : .secondary)
                        .monospacedDigit()
                }
                ProgressView(value: usage.fraction)
                    .tint(usage.isAtLimit ? .orange : Color(red: 0.18, green: 0.82, blue: 0.42))
                if usage.isAtLimit {
                    Text("You've hit today's free cap. Dictation still works; polish resumes after upgrade or tomorrow's reset.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if usage.isNearLimit {
                    Text("You're close to the free daily limit.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(refreshing ? "Refreshing…" : "Refresh usage") {
                    refreshing = true
                    Task {
                        await usage.refreshFromServer()
                        refreshing = false
                    }
                }
                .disabled(refreshing || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Link("Upgrade to Pro…", destination: URL(string: "https://flowdictate-web.vercel.app/#pricing")!)
            }

            Section("Managed polish (free or Pro)") {
                SecureField("License key (fd_live_…)", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                Toggle("Prefer managed polish when licensed", isOn: $preferManaged)
                Link("Open dashboard…", destination: URL(string: "https://flowdictate-web.vercel.app/dashboard")!)
            }

            Section("Bring your own key (unlimited on your bill)") {
                SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                Text("Optional. Bypasses our free/Pro caps — usage bills to your OpenAI account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save") {
                    CloudPolisher.licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    CloudPolisher.openAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    CloudPolisher.preferManagedPro = preferManaged
                    saved = true
                    Task { await usage.refreshFromServer() }
                }
                .keyboardShortcut(.defaultAction)
                if saved {
                    Text("Saved.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 520)
        .task { await usage.refreshFromServer() }
    }
}
