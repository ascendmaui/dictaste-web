import Foundation
import FoundationModels

/// Rewrites raw dictation into clean written text using the on-device
/// Apple Intelligence model. Returns nil whenever it can't (unavailable,
/// timeout, weird output) so the caller falls back to the basic cleanup.
final class TextPolisher {
    private var warmSession: LanguageModelSession?

    private static let instructions = """
    You are a dictation editor. The user dictates text by voice and you rewrite \
    the raw transcript into clean written text.
    Rules:
    - Fix grammar, punctuation, and capitalization. Remove filler words (um, uh, \
    you know, like), stutters, false starts, and accidentally repeated words.
    - Remove stray punctuation the speech recognizer inserted mid-sentence.
    - Preserve the meaning, tone, and approximate length. Never add information, \
    never answer questions contained in the text, never comment on it.
    - Keep the user's wording where it already reads well — this is light editing, \
    not a rewrite from scratch.
    - Output only the cleaned text, nothing else.
    """

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Human-readable reason polish is off, or nil when it's ready.
    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is still downloading"
        case .unavailable:
            return "Apple Intelligence is unavailable"
        }
    }

    /// Loads the model into memory so the first dictation isn't slow.
    func prewarm() {
        guard isAvailable else { return }
        if warmSession == nil {
            warmSession = LanguageModelSession(instructions: Self.instructions)
        }
        warmSession?.prewarm()
    }

    func polish(_ text: String) async -> String? {
        guard isAvailable else { return nil }
        // Fresh session per dictation: keeps polishes independent of each other
        // (no context carryover) while prewarm keeps the model itself warm.
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let content: String = try await withTimeout(seconds: 8) {
                let response = try await session.respond(
                    to: "Raw transcript:\n\(text)",
                    options: GenerationOptions(temperature: 0.3)
                )
                return response.content
            }
            let polished = content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Sanity check: reject empty or runaway output.
            guard !polished.isEmpty, polished.count < text.count * 3 + 100 else { return nil }
            return polished
        } catch {
            NSLog("Polish failed, falling back to basic cleanup: \(error)")
            return nil
        }
    }
}
