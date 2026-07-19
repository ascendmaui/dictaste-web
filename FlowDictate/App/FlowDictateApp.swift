import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--transcribe-file") {
            runFileMode()
        } else {
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
}

struct FlowDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState)
        } label: {
            Image(systemName: "waveform.circle.fill")
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
