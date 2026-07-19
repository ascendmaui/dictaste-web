import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--transcribe-file") {
            runFileMode()
        } else if CommandLine.arguments.contains("--polish-text") {
            runPolishMode()
        } else {
            // Single instance: if FlowDictate is already running (e.g. launchd
            // spawned a second copy at registration), the new one bows out.
            let mine = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
            ).filter { $0.processIdentifier != mine }
            if !others.isEmpty { exit(0) }
            FlowDictateApp.main()
        }
    }

    // Headless pipeline check: FlowDictate --transcribe-file audio.aiff
    private static func runFileMode() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--transcribe-file"),
              idx + 1 < CommandLine.arguments.count else {
            FileHandle.standardError.write(Data("usage: FlowDictate --transcribe-file <audio file>\n".utf8))
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var exitCode: Int32 = 0
        Task.detached {
            do {
                try await SpeechModel.ensureInstalled()
                let raw = try await FileTranscriber.transcribe(url: url)
                print(TextCleaner.clean(raw))
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                exitCode = 1
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }

    // Headless polish check: FlowDictate --polish-text "um so i was thinking"
    private static func runPolishMode() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--polish-text"),
              idx + 1 < CommandLine.arguments.count else {
            FileHandle.standardError.write(Data("usage: FlowDictate --polish-text <text>\n".utf8))
            exit(2)
        }
        let input = CommandLine.arguments[idx + 1]
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var exitCode: Int32 = 0
        Task.detached {
            let polisher = TextPolisher()
            let cleaned = TextCleaner.clean(input)
            if let polished = await polisher.polish(cleaned) {
                print(polished)
            } else {
                let reason = polisher.unavailabilityReason ?? "polish failed"
                FileHandle.standardError.write(Data("fallback (\(reason)): \(cleaned)\n".utf8))
                exitCode = 1
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }
}

struct FlowDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.phase == .idle
                  ? "waveform.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.start()
    }
}
