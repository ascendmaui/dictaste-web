import Foundation
import FoundationModels

/// Rewrites raw dictation into clean written text using the on-device
/// Apple Intelligence model. Returns nil whenever it can't (unavailable,
/// timeout, weird output) so the caller falls back to the basic cleanup.
final class TextPolisher {
    private var warmSession: LanguageModelSession?

    private static let instructions = """
    You are a dictation editor. The user dictates text by voice — often rambling, \
    unstructured, or thinking out loud — and you turn the raw transcript into clean, \
    well-organized written text.
    Rules:
    - Fix grammar, punctuation, and capitalization. Remove filler words (um, uh, \
    you know, like), stutters, false starts, and accidentally repeated words.
    - Remove stray punctuation the speech recognizer inserted mid-sentence.
    - If the dictation bundles two or more distinct points, requests, or requirements \
    together, actively restructure it: one short lead-in sentence stating the core \
    ask, then EACH separate point as its own line starting with "- ". Don't just \
    lightly edit disorganized speech — break it apart so each point is scannable on \
    its own line.
    - If the dictation is already a single clear thought with nothing separable, \
    keep it as one clean sentence or paragraph — don't force bullets that aren't needed.
    - Preserve the user's meaning and intent exactly. Never add information, never \
    answer questions contained in the text, never comment on it. Reorganizing is \
    allowed; inventing content is not.
    - Keep the user's own wording and phrasing where it already reads well.
    - Output ONLY the cleaned/restructured text itself. Never add a preamble, \
    label, or lead-in of your own like "Here's the cleaned version:" or "Sure,". \
    The first character of your output must be the first character of the result.

    Example — rambling, multiple asks:
    Input: "okay so i need the report by friday and also can you double check the \
    numbers on page three because i think theyre wrong and uh one more thing add \
    a summary at the top"
    Output: "I need the report by Friday, with two additions:
    - Double-check the numbers on page three — they may be wrong.
    - Add a summary at the top."

    Example — single clear thought, no restructuring needed:
    Input: "can you send me the invoice from last month"
    Output: "Can you send me the invoice from last month?"
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
            // Restructuring (bullets, line breaks) takes longer than light
            // cleanup and can legitimately add characters (formatting, broken-out
            // points) — longer than the old light-edit budget.
            let content: String = try await withTimeout(seconds: 14) {
                let response = try await session.respond(
                    to: "Raw transcript:\n\(text)",
                    options: GenerationOptions(temperature: 0.3)
                )
                return response.content
            }
            let polished = Self.stripPreamble(
                content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // Sanity check: reject empty or truly runaway output (the model
            // going off the rails), not just "longer than the input."
            guard !polished.isEmpty, polished.count < text.count * 5 + 400 else { return nil }
            return polished
        } catch {
            NSLog("Polish failed, falling back to basic cleanup: \(error)")
            return nil
        }
    }

    /// Safety net: the model sometimes ignores the "no preamble" instruction
    /// and prefixes a line like "Sure, here's the cleaned version:" — strip it
    /// rather than let it leak into the inserted text.
    private static func stripPreamble(_ text: String) -> String {
        let preamblePattern = #"^(sure|okay|ok|here'?s?|certainly|of course)[^\n]{0,60}[:\n]\s*"#
        guard let range = text.range(
            of: preamblePattern,
            options: [.regularExpression, .caseInsensitive]
        ) else { return text }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
