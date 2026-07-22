import Foundation

/// Light, on-device tidy-up of a finished transcript — the kind of polish that
/// makes dictation feel finished without sending anything off the machine.
/// Strips common filler words, collapses the whitespace their removal leaves
/// behind, and fixes spacing around punctuation.
enum TranscriptCleaner {

    /// Filler words to drop when they stand alone as a word. Kept deliberately
    /// short and safe — only sounds that are almost never meaningful content.
    private static let fillers: Set<String> = [
        "um", "uh", "erm", "hmm", "uhm", "mmm"
    ]

    static func clean(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Drop filler tokens. We compare on a lowercased, punctuation-stripped
        // form so "um," and "Um" are both caught, but keep the original token
        // for everything we retain (preserving the recognizer's casing).
        let kept = trimmed.split(separator: " ", omittingEmptySubsequences: true).filter { token in
            let bare = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !fillers.contains(bare)
        }

        var result = kept.joined(separator: " ")

        // Removing a filler can strand a space before punctuation ("hello , there")
        // or double a space — normalize both.
        result = result.replacingOccurrences(
            of: " +([,.!?;:])",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
