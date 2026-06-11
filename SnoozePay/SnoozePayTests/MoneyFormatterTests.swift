import XCTest
@testable import SnoozePay

/// Unit tests for `MoneyFormatter` — the single fmtRub implementation
/// (design v3): grouped digits, narrow no-break space (U+202F) before `₽`,
/// and the attributed variant that re-fonts the separator with the
/// proportional sans so mono money labels get a ~4pt gap.
final class MoneyFormatterTests: XCTestCase {

    private let narrowSpace = "\u{202F}"
    private let groupSpace = "\u{00A0}"   // ru-RU thousands separator

    // MARK: - digits(_:)

    func testDigits_smallAmount_noGrouping() {
        XCTAssertEqual(MoneyFormatter.digits(Decimal(50)), "50")
    }

    func testDigits_thousands_useNonBreakingGroupSeparator() {
        XCTAssertEqual(MoneyFormatter.digits(Decimal(1234)), "1\(groupSpace)234")
        XCTAssertEqual(MoneyFormatter.digits(1_234_567), "1\(groupSpace)234\(groupSpace)567")
    }

    func testDigits_truncatesFraction() {
        // The app transacts whole roubles; fmtRub truncates (rounds down).
        XCTAssertEqual(MoneyFormatter.digits(Decimal(string: "49.99")!), "49")
    }

    // MARK: - string(_:)

    func testString_usesNarrowNoBreakSpaceBeforeRouble() {
        XCTAssertEqual(MoneyFormatter.string(Decimal(50)), "50\(narrowSpace)₽")
    }

    func testString_neverUsesPlainSpaceBeforeRouble() {
        let formatted = MoneyFormatter.string(Decimal(1000))
        XCTAssertFalse(
            formatted.contains(" ₽"),
            "fmtRub must separate digits from ₽ with U+202F, not a plain space: \(formatted)"
        )
        XCTAssertEqual(formatted, "1\(groupSpace)000\(narrowSpace)₽")
    }

    func testString_intAndDoubleOverloadsAgree() {
        XCTAssertEqual(MoneyFormatter.string(150), MoneyFormatter.string(Decimal(150)))
        XCTAssertEqual(MoneyFormatter.string(150.0), MoneyFormatter.string(Decimal(150)))
    }

    func testString_zero() {
        XCTAssertEqual(MoneyFormatter.string(0), "0\(narrowSpace)₽")
    }

    // MARK: - attributed(_:digitsFont:)

    func testAttributed_digitsKeepMonoFontAndRoubleMatchesDigits() {
        let mono = UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        let attributed = MoneyFormatter.attributed(Decimal(50), digitsFont: mono)

        XCTAssertEqual(attributed.string, "50\(narrowSpace)₽")

        let digitsFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(digitsFont, mono, "Digits must render in the caller's mono font")

        let roubleIndex = attributed.length - 1
        let roubleFont = attributed.attribute(.font, at: roubleIndex, effectiveRange: nil) as? UIFont
        XCTAssertEqual(roubleFont, mono, "₽ keeps the digits' font/size/baseline per fmtRub")
    }

    func testAttributed_separatorIsProportionalFontAtSameSize() {
        let mono = UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        let attributed = MoneyFormatter.attributed(Decimal(50), digitsFont: mono)

        let spaceIndex = (attributed.string as NSString).range(of: narrowSpace).location
        XCTAssertNotEqual(spaceIndex, NSNotFound)
        let spaceFont = attributed.attribute(.font, at: spaceIndex, effectiveRange: nil) as? UIFont
        XCTAssertNotNil(spaceFont)
        XCTAssertNotEqual(
            spaceFont, mono,
            "Separator must escape the mono advance grid (proportional sans)"
        )
        XCTAssertEqual(spaceFont?.pointSize, 20, "Separator keeps the digits' point size")
    }

    func testAttributed_prefixRendersBeforeDigitsInDigitsFont() {
        let mono = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let attributed = MoneyFormatter.attributed(Decimal(50), digitsFont: mono, prefix: "−")

        XCTAssertEqual(attributed.string, "−50\(narrowSpace)₽")
        let prefixFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(prefixFont, mono)
    }

    func testAttributed_colorAppliedToWholeRun() {
        let mono = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let attributed = MoneyFormatter.attributed(Decimal(50), digitsFont: mono, color: .red)

        for index in 0..<attributed.length {
            let color = attributed.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor
            XCTAssertEqual(color, .red, "Every run (digits, separator, ₽) must carry the colour")
        }
    }

    func testAttributed_withoutColor_carriesNoForegroundColor() {
        // Labels that recolour via `textColor` (tone flips on SPSnoozePrice,
        // PenaltyCell) need attribute-free runs — an explicit colour attribute
        // would override `textColor` and freeze the tone.
        let mono = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let attributed = MoneyFormatter.attributed(Decimal(50), digitsFont: mono)

        for index in 0..<attributed.length {
            XCTAssertNil(attributed.attribute(.foregroundColor, at: index, effectiveRange: nil))
        }
    }

    // MARK: - Legacy bridge

    func testFormattedRubles_delegatesToMoneyFormatter() {
        XCTAssertEqual(Decimal(1234).formattedRubles(), MoneyFormatter.string(Decimal(1234)))
        XCTAssertEqual(Decimal(1234).formattedRubles(), "1\(groupSpace)234\(narrowSpace)₽")
    }
}

/// Smoke tests for the code-drawn `SPIcons` set — render size, template
/// mode (so `tintColor` plays SVG's `currentColor`) and non-empty output.
final class SPIconsTests: XCTestCase {

    func testIcons_renderAtRequestedSizeAsTemplates() {
        let icons: [UIImage] = [
            SPIcons.coin(size: 12),
            SPIcons.rubleCoin(size: 12),
            SPIcons.coinOff(size: 14),
            SPIcons.trendUp(size: 12),
            SPIcons.banknote(size: 16),
            SPIcons.snooze(size: 16)
        ]
        for icon in icons {
            XCTAssertEqual(icon.renderingMode, .alwaysTemplate)
            XCTAssertGreaterThan(icon.size.width, 0)
            XCTAssertEqual(icon.size.width, icon.size.height, "Icons are square")
        }
        XCTAssertEqual(SPIcons.coin(size: 12).size.width, 12)
        XCTAssertEqual(SPIcons.banknote(size: 16).size.width, 16)
    }

    func testRubleCoin_isSameGlyphAsCoin() {
        // JSX exports IconCoin and IconRubleCoin with identical paths —
        // the Swift port must not let them drift apart.
        let coin = SPIcons.coin(size: 24).pngData()
        let rubleCoin = SPIcons.rubleCoin(size: 24).pngData()
        XCTAssertNotNil(coin)
        XCTAssertEqual(coin, rubleCoin)
    }
}
