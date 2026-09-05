import Foundation

/// Reads the `Localizable.xcstrings` keys a screen actually asks for, out of the
/// screen's own source.
///
/// The copy suites pin a table of key → words. Until #767 each of them also
/// *derived* the list of keys it walked from that same table, so removing a pair
/// from the table removed the key from every loop standing over it and nothing
/// went red: the suite kept passing over a smaller world. This is the outside
/// opinion those suites compare their table against — what the screen reads,
/// read off the screen.
///
/// # What it sees, and what it does not
///
/// A string literal in the shape of a key, sitting inside a `Localized.…(…)`
/// call. Blind, by construction, to a key that is not a literal at its call site
/// — assembled from parts, or held in a variable. That blindness is quiet in one
/// direction only: such a key goes missing from the reading, so the table that
/// pins it looks like it holds an entry nobody reads, which is a failure the
/// caller reports rather than a silence.
///
/// # Why a character walk and not a regex
///
/// Two shapes in these sources defeat a line-based match, and both are live:
/// `Localized.format(` with its key on the next line
/// (`AlarmsStreakBannerView:111`), and a ternary putting two keys inside one
/// call (`CreateAlarmViewController:96`). A per-line scan reports the keys it
/// cannot see as unused entries — noise that would be "fixed" by deleting the
/// entries, i.e. by the very shrinkage this exists to stop. (`grep -rn` has the
/// same shape of problem from the other end: it defeats the `^` anchor of a
/// comment filter — see `count-cyrillic-literals.py`.)
enum CatalogueKeyScanner {

    /// What one pass over a list of sources found. `unreadable` is carried
    /// rather than dropped: a scan that quietly reads fewer files is the same
    /// defect as a table that quietly holds fewer keys.
    struct Reading {
        var keys: Set<String> = []
        var unreadable: [String] = []
    }

    /// Reads `relativePaths` (as spelled, `Cells/…` included) under `root`.
    static func read(_ relativePaths: [String], under root: URL) -> Reading {
        var reading = Reading()
        for path in relativePaths {
            guard let contents = try? String(
                contentsOf: root.appendingPathComponent(path), encoding: .utf8
            ) else {
                reading.unreadable.append(path)
                continue
            }
            reading.keys.formUnion(keys(in: contents))
        }
        return reading
    }

    /// Every catalogue key handed to a `Localized.…(…)` call in `source`.
    static func keys(in source: String) -> Set<String> {
        let chars = Array(source)
        let marker = Array("Localized.")
        var found: Set<String> = []
        var index = 0

        while index < chars.count {
            guard chars[index] == "L", chars[index...].starts(with: marker) else {
                index += 1
                continue
            }
            var cursor = index + marker.count
            while cursor < chars.count, chars[cursor].isLetter { cursor += 1 }
            guard cursor < chars.count, chars[cursor] == "(" else {
                index = cursor
                continue
            }
            index = collect(from: chars, openParenAt: cursor, into: &found)
        }
        return found
    }

    /// Walks one `Localized.…(` call from its opening parenthesis to the
    /// matching close, collecting every key-shaped literal inside it, and hands
    /// back where to carry on. String literals are stepped over whole, so a
    /// bracket inside copy never moves the nesting depth.
    private static func collect(
        from chars: [Character], openParenAt index: Int, into found: inout Set<String>
    ) -> Int {
        var cursor = index + 1
        var depth = 1

        while cursor < chars.count, depth > 0 {
            switch chars[cursor] {
            case "\"":
                let literal = stringLiteral(in: chars, openingAt: cursor)
                if isCatalogueKey(literal.value) { found.insert(literal.value) }
                cursor = literal.end
            case "(":
                depth += 1
            case ")":
                depth -= 1
            default:
                break
            }
            cursor += 1
        }
        return cursor
    }

    /// The literal whose opening quote sits at `index`, plus the offset of its
    /// closing quote. Escapes are stepped over in pairs: an escaped quote does
    /// not end the literal, and no escaped character can be part of a key.
    private static func stringLiteral(
        in chars: [Character], openingAt index: Int
    ) -> (value: String, end: Int) {
        var value = ""
        var cursor = index + 1

        while cursor < chars.count, chars[cursor] != "\"" {
            if chars[cursor] == "\\" {
                cursor += 2
                continue
            }
            value.append(chars[cursor])
            cursor += 1
        }
        return (value, cursor)
    }

    /// `<domain>.<element>[.<qualifier>]` — lowercase ASCII with `_` inside a
    /// segment, the convention `Localized` documents. Strict on purpose: the
    /// same calls carry «Отмена» and `%1$lld %2$@ …` as arguments, and neither
    /// is a key.
    private static func isCatalogueKey(_ literal: String) -> Bool {
        let segments = literal.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.unicodeScalars.allSatisfy { keyScalars.contains($0) }
        }
    }

    private static let keyScalars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_"
    )
}
