import UIKit

/// Single source of truth for rendering rouble amounts — the Swift port of
/// the design system's `fmtRub` helper (`docs/design/v2-handoff/components/
/// SPComponents.jsx` L12-24).
///
/// The fmtRub rule (design v3, 2026-06-05 handoff):
/// - Digits are grouped with the ru-RU thousands separator ("1 234").
/// - The gap before `₽` is a **narrow** space (~4pt), not a full mono cell.
///   JetBrains Mono renders every glyph — including U+0020 — at a full
///   ~0.6em advance, which made "50 ₽" read as "50  ₽". The JSX fixes it by
///   wrapping the space in a proportional-font span; the UIKit equivalents:
///   - `string(_:)` uses U+202F NARROW NO-BREAK SPACE for plain-text labels
///     (proportional fonts render it at roughly half a normal space).
///   - `attributed(_:digitsFont:)` additionally re-fonts the separator run
///     with the proportional sans so mono-font money labels get the same
///     ~4pt gap the design calls for.
/// - `₽` keeps the digits' size and baseline — no superscript, no shrink.
enum MoneyFormatter {

    /// U+202F NARROW NO-BREAK SPACE — the gap between the digits and `₽`.
    /// Exposed so tests (and ad-hoc composers like "−50 ₽ → −100 ₽" tickers)
    /// can reference the canonical separator instead of copy-pasting the
    /// invisible character.
    static let narrowSpace = "\u{202F}"

    // MARK: - Digits

    /// Grouped integer digits without the currency glyph, e.g. `1 234`
    /// (ru-RU NBSP thousands separator). Truncates the fraction — the app
    /// transacts whole roubles only.
    static func digits(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        return Self.groupingFormatter.string(from: number) ?? "\(number.intValue)"
    }

    static func digits(_ amount: Int) -> String {
        digits(Decimal(amount))
    }

    // MARK: - Plain string

    /// `"1 234 ₽"` — grouped digits + narrow no-break space + rouble glyph.
    /// Use for proportional-font labels, accessibility strings and
    /// notification copy. Mono-font labels should prefer `attributed(_:)`
    /// so the separator run drops out of the mono advance grid.
    static func string(_ amount: Decimal) -> String {
        "\(digits(amount))\(narrowSpace)₽"
    }

    static func string(_ amount: Int) -> String {
        string(Decimal(amount))
    }

    static func string(_ amount: Double) -> String {
        string(Decimal(amount))
    }

    // MARK: - Attributed (mono digits + proportional gap)

    /// fmtRub for mono-font money labels: digits and `₽` render in
    /// `digitsFont` (JetBrains Mono / monospaced system), while the
    /// separator space is re-fonted with the proportional sans at the same
    /// point size — that collapses the gap from a full mono cell (~0.6em)
    /// to the ~4pt the design specifies.
    ///
    /// - Parameters:
    ///   - amount: Whole-rouble amount (fraction truncated).
    ///   - digitsFont: The label's mono font — kept for digits and `₽`.
    ///   - prefix: Optional sign/sigil rendered before the digits in the
    ///     digits font ("+", "−", "Баланс " …).
    ///   - color: Optional foreground colour applied to the whole run.
    static func attributed(
        _ amount: Decimal,
        digitsFont: UIFont,
        prefix: String = "",
        color: UIColor? = nil
    ) -> NSAttributedString {
        var digitAttributes: [NSAttributedString.Key: Any] = [.font: digitsFont]
        var spaceAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFonts.sans(.regular, digitsFont.pointSize)
        ]
        if let color = color {
            digitAttributes[.foregroundColor] = color
            spaceAttributes[.foregroundColor] = color
        }
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: prefix + digits(amount), attributes: digitAttributes))
        result.append(NSAttributedString(string: narrowSpace, attributes: spaceAttributes))
        result.append(NSAttributedString(string: "₽", attributes: digitAttributes))
        return result
    }

    // MARK: - Private

    /// Shared grouping formatter — `NumberFormatter` construction costs
    /// ~0.5ms; money strings rebuild on every balance tick so cache it.
    /// `NumberFormatter.string(from:)` is documented thread-safe for reads.
    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .down
        return formatter
    }()
}
