import AppKit
import Observation
import ServiceManagement
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
        case polishing
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
    var polishEnabled: Bool = (UserDefaults.standard.object(forKey: "polishEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "polishEnabled") }
    }
    var agentEnabled = false
    var volatileText = ""
    var levelHistory: [Float] = []
    var currentLevel: Float = 0
    var modelStatus = "Checking speech model…"
    var modelReady = false
    var history: [DictationRecord] = []
    var usage = UsageStore.shared

    let permissions = PermissionsModel()
    let hotkey = HotkeyMonitor()
    let polisher = TextPolisher()

    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private var hud: HUDController?
    private var onboardingWindow: NSWindow?
    private var vocabularyWindow: NSWindow?
    private var accountWindow: NSWindow?
    private var pollTimer: Timer?
    private var pressTime = Date.distantPast
    private var sessionTask: Task<TranscriptionSession, Error>?
    private var dismissTask: Task<Void, Never>?
    private var backgroundActivity: NSObjectProtocol?

    private static let historyKey = "dictationHistory"
    private static let agentPlistName = "com.johnmatveyev.flowdictate.plist"
    private static let agentOptOutKey = "backgroundAgentOptOut"

    func start() {
        hud = HUDController(appState: self)
        // Always-visible mini pill; expands only while dictating.
        hud?.show()
        loadHistory()
        permissions.refresh()
        // Only block on mic + accessibility. fn key is optional.
        if !permissions.requiredGranted {
            showOnboarding()
        }

        // Never let App Nap idle the hotkey listener.
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.background, .automaticTerminationDisabled],
            reason: "Listening for the dictation hotkey"
        )
        registerBackgroundAgent()

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
        hotkey.onEscape = { [weak self] in self?.cancelDictation() }
        hotkey.isDictationActiveProvider = { [weak self] in
            MainActor.assumeIsolated {
                switch self?.phase {
                case .recording, .transcribing, .polishing: return true
                default: return false
                }
            }
        }
        hotkey.startIfPossible()

        recorder.onLevel = { [weak self] level in
            guard let self, self.phase == .recording else { return }
            self.currentLevel = level
            self.levelHistory.append(level)
            if self.levelHistory.count > 28 { self.levelHistory.removeFirst() }
        }

        // Keep permission state fresh and the event tap alive.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.permissions.refresh()
                if self.permissions.axGranted { self.hotkey.ensureHealthy() }
                self.agentEnabled = SMAppService.agent(plistName: Self.agentPlistName).status == .enabled
            }
        }

        polisher.prewarm()

        Task {
            do {
                try await SpeechModel.ensureInstalled()
                modelStatus = "Speech model ready"
                modelReady = true
            } catch {
                modelStatus = "Speech model failed: \(error.localizedDescription)"
            }
        }

        Task {
            await usage.refreshFromServer()
        }
    }

    // MARK: - HUD design preview (--hud-preview)

    func startHUDPreview() {
        hud = HUDController(appState: self)
        hud?.show()
        Task { await runPreviewLoop() }
    }

    private func runPreviewLoop() async {
        let sample = "So I was thinking we should move the meeting to Tuesday because the client isn't available on Monday"
            .split(separator: " ").map(String.init)
        var t = 0.0
        while !Task.isCancelled {
            phase = .recording
            triggerSource = .toggleTap
            volatileText = ""
            levelHistory = []
            hud?.show()
            for index in sample.indices {
                volatileText = sample[0...index].joined(separator: " ")
                for _ in 0..<4 {
                    t += 0.31
                    let level = Float(0.4 + 0.28 * sin(t) + Double.random(in: 0...0.28))
                    currentLevel = min(1, max(0.05, level))
                    levelHistory.append(currentLevel)
                    if levelHistory.count > 28 { levelHistory.removeFirst() }
                    try? await Task.sleep(for: .milliseconds(70))
                }
            }
            phase = .polishing
            try? await Task.sleep(for: .seconds(1.4))
            volatileText = "So I was thinking we should move the meeting to Tuesday, since the client isn't available on Monday."
            phase = .inserting
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Always-on background agent

    /// launchd agent: starts the app at login and relaunches it after a crash.
    /// Quitting from the menu (clean exit) stays quit until next login.
    private func registerBackgroundAgent() {
        // Migrate off the v1 plain login item.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        let agent = SMAppService.agent(plistName: Self.agentPlistName)
        if agent.status != .enabled,
           UserDefaults.standard.object(forKey: Self.agentOptOutKey) == nil {
            try? agent.register()
        }
        agentEnabled = agent.status == .enabled
    }

    func setAgentEnabled(_ enabled: Bool) {
        let agent = SMAppService.agent(plistName: Self.agentPlistName)
        if enabled {
            UserDefaults.standard.removeObject(forKey: Self.agentOptOutKey)
            try? agent.register()
        } else {
            UserDefaults.standard.set(true, forKey: Self.agentOptOutKey)
            try? agent.unregister()
        }
        agentEnabled = agent.status == .enabled
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
        currentLevel = 0
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
                let cleaned = VocabularyCorrector.apply(TextCleaner.clean(raw))
                guard phase == .transcribing else { return }
                guard !cleaned.isEmpty else {
                    fail("No speech detected")
                    return
                }

                var finalText = cleaned
                if polishEnabled {
                    // Managed free-tier hard stop: still insert raw cleaned text
                    let managedBlocked = usage.isAtLimit
                        && !CloudPolisher.licenseKey.isEmpty
                        && CloudPolisher.preferManagedPro
                        && CloudPolisher.openAIKey.isEmpty
                        && !polisher.isAvailable
                    if !managedBlocked {
                        phase = .polishing
                        volatileText = cleaned
                        // Order: Apple Intelligence (on-device, unlimited) → managed / BYO → raw
                        if polisher.isAvailable, let apple = await polisher.polish(cleaned) {
                            finalText = apple
                        } else if let cloud = await CloudPolisher.polish(cleaned) {
                            finalText = cloud
                        }
                        guard phase == .polishing else { return }
                    }
                }

                volatileText = finalText
                phase = .inserting
                inserter.insert(finalText + " ")
                addToHistory(finalText, duration: duration)
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
        currentLevel = 0
        sessionTask = nil
        // Stay visible as the minimized green pill (do not hide).
        hud?.show()
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

    func showVocabulary() {
        if vocabularyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Custom Vocabulary"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VocabularyView())
            window.center()
            vocabularyWindow = window
        }
        vocabularyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAccount() {
        if accountWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Account & AI Polish"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AccountView())
            window.center()
            accountWindow = window
        }
        accountWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
