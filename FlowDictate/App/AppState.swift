import AppKit
import Observation
import SwiftUI

struct DictationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let duration: TimeInterval
}

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case inserting
        case error(String)
    }

    enum TriggerSource {
        case holdFn   // hold fn to talk, release to insert
        case toggleTap // tap left ⌥ to start, tap again to stop
    }

    var phase: Phase = .idle
    var triggerSource: TriggerSource = .holdFn
    var optionTapEnabled: Bool = (UserDefaults.standard.object(forKey: "optionTapEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(optionTapEnabled, forKey: "optionTapEnabled") }
    }
    var volatileText = ""
    var levelHistory: [Float] = []
    var modelStatus = "Checking speech model…"
    var modelReady = false
    var history: [DictationRecord] = []

    let permissions = PermissionsModel()
    let hotkey = HotkeyMonitor()

    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private var hud: HUDController?
    private var onboardingWindow: NSWindow?
    private var pollTimer: Timer?
    private var pressTime = Date.distantPast
    private var sessionTask: Task<TranscriptionSession, Error>?
    private var dismissTask: Task<Void, Never>?

    private static let historyKey = "dictationHistory"

    func start() {
        hud = HUDController(appState: self)
        loadHistory()
        permissions.refresh()
        if !permissions.allGranted {
            showOnboarding()
        }

        hotkey.onPress = { [weak self] in self?.beginDictation(source: .holdFn) }
        hotkey.onRelease = { [weak self] in
            guard let self, self.triggerSource == .holdFn else { return }
            self.endDictation()
        }
        hotkey.onCancel = { [weak self] in
            guard let self, self.triggerSource == .holdFn else { return }
            self.cancelDictation()
        }
        hotkey.onToggleTap = { [weak self] in self?.handleToggleTap() }
        hotkey.startIfPossible()

        recorder.onLevel = { [weak self] level in
            guard let self, self.phase == .recording else { return }
            self.levelHistory.append(level)
            if self.levelHistory.count > 28 { self.levelHistory.removeFirst() }
        }

        // Keep permission state fresh; arm the hotkey tap as soon as Accessibility lands.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.permissions.refresh()
                if self.permissions.axGranted { self.hotkey.startIfPossible() }
            }
        }

        Task {
            do {
                try await SpeechModel.ensureInstalled()
                modelStatus = "Speech model ready"
                modelReady = true
            } catch {
                modelStatus = "Speech model failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Dictation lifecycle

    private func handleToggleTap() {
        guard optionTapEnabled else { return }
        switch phase {
        case .idle, .inserting:
            beginDictation(source: .toggleTap)
        case .recording:
            endDictation()
        default:
            break
        }
    }

    func beginDictation(source: TriggerSource) {
        if phase == .inserting { dismissTask?.cancel(); finishCycle() }
        guard phase == .idle else { return }
        guard permissions.micGranted else { showOnboarding(); return }

        triggerSource = source
        phase = .recording
        volatileText = ""
        levelHistory = []
        pressTime = Date()
        NSSound(named: "Pop")?.play()
        hud?.show()

        do {
            let (format, buffers) = try recorder.start()
            sessionTask = Task {
                let session = try await TranscriptionSession(
                    inputFormat: format,
                    buffers: buffers,
                    onVolatile: { text in
                        Task { @MainActor [weak self] in
                            guard let self, self.phase == .recording || self.phase == .transcribing else { return }
                            self.volatileText = text
                        }
                    }
                )
                return session
            }
        } catch {
            fail("Mic error: \(error.localizedDescription)")
        }
    }

    func endDictation() {
        guard phase == .recording else { return }
        // Accidental tap — under 0.25s of hold means it wasn't a dictation.
        guard Date().timeIntervalSince(pressTime) >= 0.25 else {
            cancelDictation()
            return
        }
        let duration = Date().timeIntervalSince(pressTime)
        phase = .transcribing
        recorder.stop()

        Task {
            do {
                guard let sessionTask else { throw DictationError.noSession }
                let session = try await sessionTask.value
                let raw = try await session.finish()
                let text = TextCleaner.clean(raw)
                guard phase == .transcribing else { return }
                guard !text.isEmpty else {
                    fail("No speech detected")
                    return
                }
                volatileText = text
                phase = .inserting
                inserter.insert(text + " ")
                addToHistory(text, duration: duration)
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    guard !Task.isCancelled else { return }
                    finishCycle()
                }
            } catch {
                fail("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelDictation() {
        recorder.stop()
        let task = sessionTask
        sessionTask = nil
        Task { (try? await task?.value)?.cancel() }
        finishCycle()
    }

    private func finishCycle() {
        phase = .idle
        volatileText = ""
        levelHistory = []
        sessionTask = nil
        hud?.hide()
    }

    private func fail(_ message: String) {
        recorder.stop()
        phase = .error(message)
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            finishCycle()
        }
    }

    // MARK: - History

    private func addToHistory(_ text: String, duration: TimeInterval) {
        history.insert(DictationRecord(id: UUID(), text: text, date: .now, duration: duration), at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let records = try? JSONDecoder().decode([DictationRecord].self, from: data) else { return }
        history = records
    }

    // MARK: - Onboarding window

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Set Up FlowDictate"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(appState: self))
            window.center()
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
