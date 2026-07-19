import AVFoundation
import Speech

enum DictationError: LocalizedError {
    case noMicrophone
    case noSession
    case localeUnsupported
    case noAnalyzerFormat
    case timeout

    var errorDescription: String? {
        switch self {
        case .noMicrophone: return "No microphone available"
        case .noSession: return "No transcription session"
        case .localeUnsupported: return "English dictation isn't supported on this Mac"
        case .noAnalyzerFormat: return "Speech engine has no usable audio format"
        case .timeout: return "Timed out waiting for the transcript"
        }
    }
}

/// One-time (per boot of the app) check that Apple's on-device speech model
/// for English is downloaded and installed.
enum SpeechModel {
    static func ensureInstalled() async throws {
        let locale = try await supportedEnglishLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    static func supportedEnglishLocale() async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        if let exact = supported.first(where: { $0.identifier(.bcp47) == "en-US" }) {
            return exact
        }
        if let anyEnglish = supported.first(where: { $0.language.languageCode?.identifier == "en" }) {
            return anyEnglish
        }
        throw DictationError.localeUnsupported
    }
}

/// A single dictation: consumes mic (or file) buffers, streams volatile text
/// while you speak, and returns the finalized transcript on finish().
final class TranscriptionSession {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let feedTask: Task<Void, Never>
    private let resultsTask: Task<String, Error>

    init(
        inputFormat: AVAudioFormat,
        buffers: AsyncStream<AVAudioPCMBuffer>,
        onVolatile: (@Sendable (String) -> Void)?
    ) async throws {
        let locale = try await SpeechModel.supportedEnglishLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.noAnalyzerFormat
        }
        let converter = AudioBufferConverter(from: inputFormat, to: analyzerFormat)

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        resultsTask = Task {
            var finalText = ""
            for try await result in transcriber.results {
                let piece = String(result.text.characters)
                if result.isFinal {
                    finalText += piece
                    onVolatile?(finalText)
                } else {
                    onVolatile?(finalText + piece)
                }
            }
            return finalText
        }

        feedTask = Task {
            for await buffer in buffers {
                guard !Task.isCancelled else { break }
                if let converted = converter.convert(buffer) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Call after the buffer stream has been finished (mic stopped / file read).
    func finish() async throws -> String {
        await feedTask.value
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await withTimeout(seconds: 15) { [resultsTask] in
            try await resultsTask.value
        }
    }

    func cancel() {
        feedTask.cancel()
        inputContinuation.finish()
        resultsTask.cancel()
        let analyzer = self.analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

/// Converts mic/file buffers to the analyzer's preferred format (rate + sample type).
final class AudioBufferConverter {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
        converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}

enum FileTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        let session = try await TranscriptionSession(inputFormat: format, buffers: stream, onVolatile: nil)

        let chunkFrames: AVAudioFrameCount = 4096
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { break }
            try file.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0 else { break }
            continuation.yield(buffer)
        }
        continuation.finish()
        return try await session.finish()
    }
}

func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DictationError.timeout
        }
        guard let result = try await group.next() else { throw DictationError.timeout }
        group.cancelAll()
        return result
    }
}
