import XCTest
@testable import SnoozePay

/// Coverage for the V3 themed-firing palette table (#225) — the
/// `AlarmTheme → AlarmFiringThemePalette` mapping that drives the firing
/// screen's background, scrim, glow and accent tinting, plus the
/// `AlarmThemeRendering` delegation that keeps picker tiles in sync, and the
/// `heroTitle` string the hero name row renders.
final class AlarmFiringThemePaletteTests: XCTestCase {

    // MARK: - Helpers

    /// Expected accent per stock theme — the `accent` column of
    /// `FIRING_THEMES` in `SPThemedFiring.jsx`. A drift here means the
    /// eyebrow / balance pill stop matching the design table.
    private let expectedAccents: [(AlarmTheme, UInt32)] = [
        (.dawn, 0xFFD479),
        (.ocean, 0x9EE6CC),
        (.mountains, 0xE1E5EA),
        (.forest, 0xA8D89A),
        (.neon, 0xFF7EC8),
        (.abstract, 0xFFFFFF)
    ]

    private func assertColor(
        _ color: UIColor,
        matchesHex hex: UInt32,
        alpha expectedAlpha: CGFloat = 1.0,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let expectedRed = CGFloat((hex >> 16) & 0xFF) / 255.0
        let expectedGreen = CGFloat((hex >> 8) & 0xFF) / 255.0
        let expectedBlue = CGFloat(hex & 0xFF) / 255.0
        XCTAssertEqual(red, expectedRed, accuracy: 0.001, "\(message) (r)", file: file, line: line)
        XCTAssertEqual(green, expectedGreen, accuracy: 0.001, "\(message) (g)", file: file, line: line)
        XCTAssertEqual(blue, expectedBlue, accuracy: 0.001, "\(message) (b)", file: file, line: line)
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.001, "\(message) (a)", file: file, line: line)
    }

    // MARK: - Table coverage

    func testEveryStockThemeHasAPalette() {
        for theme in AlarmTheme.builtInOrder {
            XCTAssertNotNil(
                AlarmFiringThemePalette.palette(for: theme),
                "Stock theme \(theme.id) must map to a firing palette"
            )
        }
    }

    func testCustomThemeHasNoPalette() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        XCTAssertNil(
            AlarmFiringThemePalette.palette(for: .custom(imagePath: url)),
            "Photo themes keep the un-themed firing treatment — no palette"
        )
    }

    func testAccentsMatchDesignTable() {
        for (theme, hex) in expectedAccents {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else {
                XCTFail("Missing palette for \(theme.id)")
                continue
            }
            assertColor(palette.accent, matchesHex: hex, "accent for \(theme.id)")
        }
    }

    func testBackgroundStopsPairWithLocations() {
        for theme in AlarmTheme.builtInOrder {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else { continue }
            XCTAssertEqual(
                palette.backgroundColors.count,
                palette.backgroundLocations.count,
                "Colour/location count mismatch for \(theme.id) would mis-distribute the gradient"
            )
            XCTAssertEqual(
                palette.bellGradientColors.count,
                AlarmFiringThemePalette.bellGradientLocations.count,
                "Bell gradient for \(theme.id) must carry the 0 / 0.6 / 1 stop trio"
            )
        }
    }

    func testAbstractIsTheLoneTwoStopTheme() {
        for theme in AlarmTheme.builtInOrder {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else { continue }
            let expectedStops = theme == .abstract ? 2 : 3
            XCTAssertEqual(
                palette.backgroundColors.count,
                expectedStops,
                "FIRING_THEMES gives \(theme.id) \(expectedStops) background stops"
            )
        }
    }

    func testScrimAlphasDarkenOutward() {
        for theme in AlarmTheme.builtInOrder {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else { continue }
            XCTAssertLessThan(
                palette.scrimInnerAlpha,
                palette.scrimOuterAlpha,
                "Scrim for \(theme.id) must be a vignette — darker at the edges than the centre"
            )
        }
    }

    func testNeonScrimAndPillMatchDesignTable() {
        // Spot-check one non-trivial row end-to-end so a copy/paste slip in
        // the table doesn't survive (neon has the most distinctive values).
        guard let neon = AlarmFiringThemePalette.palette(for: .neon) else {
            return XCTFail("Missing neon palette")
        }
        XCTAssertEqual(neon.scrimInnerAlpha, 0.10, accuracy: 0.001)
        XCTAssertEqual(neon.scrimOuterAlpha, 0.55, accuracy: 0.001)
        assertColor(neon.pillBackground, matchesHex: 0xFF3D8A, alpha: 0.20, "neon pillBg")
        assertColor(neon.pillBorder, matchesHex: 0xFF7EC8, alpha: 0.40, "neon pillBorder")
        assertColor(neon.timeShadowColor, matchesHex: 0xFF3D8A, "neon timeShadow colour")
        XCTAssertEqual(neon.timeShadowOpacity, 0.40, accuracy: 0.001)
    }

    // MARK: - Drained variant (#227)

    /// Expected drained accent per stock theme — the no-balance table in
    /// `SPFiringNoBalanceThemes.jsx`.
    private let expectedDrainedAccents: [(AlarmTheme, UInt32)] = [
        (.dawn, 0xFAD89A),
        (.ocean, 0xB4ECD8),
        (.mountains, 0xDEE3EB),
        (.forest, 0xB6DEA0),
        (.neon, 0xF4A6D2),
        (.abstract, 0xDADADA)
    ]

    func testEveryStockThemeHasADrainedPalette() {
        for theme in AlarmTheme.builtInOrder {
            XCTAssertNotNil(
                AlarmFiringThemePalette.drainedPalette(for: theme),
                "Stock theme \(theme.id) must map to a drained firing palette"
            )
        }
    }

    func testCustomThemeHasNoDrainedPalette() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        XCTAssertNil(
            AlarmFiringThemePalette.drainedPalette(for: .custom(imagePath: url)),
            "Photo themes keep their image — no drained palette"
        )
    }

    func testDrainedAccentsMatchDesignTable() {
        for (theme, hex) in expectedDrainedAccents {
            guard let palette = AlarmFiringThemePalette.drainedPalette(for: theme) else {
                XCTFail("Missing drained palette for \(theme.id)")
                continue
            }
            assertColor(palette.accent, matchesHex: hex, "drained accent for \(theme.id)")
        }
    }

    func testDrainedBackgroundStopsPairWithLocations() {
        for theme in AlarmTheme.builtInOrder {
            guard let palette = AlarmFiringThemePalette.drainedPalette(for: theme) else { continue }
            XCTAssertEqual(
                palette.backgroundColors.count,
                palette.backgroundLocations.count,
                "Drained colour/location count mismatch for \(theme.id)"
            )
            let expectedStops = theme == .abstract ? 2 : 3
            XCTAssertEqual(palette.backgroundColors.count, expectedStops)
        }
    }

    func testDrainedDawnBackgroundMatchesDesignTable() {
        // Spot-check the dawn drained gradient end-to-end.
        guard let dawn = AlarmFiringThemePalette.drainedPalette(for: .dawn) else {
            return XCTFail("Missing dawn drained palette")
        }
        assertColor(dawn.backgroundColors[0], matchesHex: 0x41290F, "dawn drained bg stop 0")
        assertColor(dawn.backgroundColors[1], matchesHex: 0x804F1E, "dawn drained bg stop 1")
        assertColor(dawn.backgroundColors[2], matchesHex: 0xCE8A30, "dawn drained bg stop 2")
    }

    // MARK: - AlarmThemeRendering delegation

    func testPickerTileGradientsDelegateToPaletteForNonDawnThemes() {
        for theme in AlarmTheme.builtInOrder where theme != .dawn {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else { continue }
            XCTAssertEqual(
                AlarmThemeRendering.gradientColors(for: theme),
                palette.backgroundColors.map { $0.cgColor },
                "Picker tile for \(theme.id) must use the same stops as the firing background"
            )
            XCTAssertEqual(
                AlarmThemeRendering.gradientLocations(for: theme),
                palette.backgroundLocations,
                "Picker tile locations for \(theme.id) must match the firing background"
            )
        }
    }

    func testDawnPickerTileMirrorsTheDawnAtmosphericBase() {
        // Dawn's firing background is the tone-reactive SPDawnBackgroundView,
        // not the palette gradient — so the tile mirrors that view's calm base
        // instead of the stale pre-#151 blue-black recipe it used to carry
        // (#463: the picker read as one dark surface).
        XCTAssertEqual(
            AlarmThemeRendering.gradientColors(for: .dawn),
            SPDawnBackgroundView.calmBaseColors.map { $0.cgColor }
        )
        XCTAssertEqual(
            AlarmThemeRendering.gradientLocations(for: .dawn),
            SPDawnBackgroundView.calmBaseLocations
        )
    }

    // MARK: - Hero title

    private func makeViewModel(name: String, hour: Int, minute: Int) -> AlarmFiringViewModel {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 11
        components.hour = hour
        components.minute = minute
        let time = Calendar.current.date(from: components) ?? Date()
        let alarm = Alarm(time: time, name: name)
        return AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
    }

    func testHeroTitleJoinsNameAndScheduledTime() {
        let viewModel = makeViewModel(name: "Будни", hour: 7, minute: 0)
        XCTAssertEqual(viewModel.heroTitle, "Будни · 07:00")
    }

    func testHeroTitleDegradesToTimeWhenNameIsBlank() {
        let viewModel = makeViewModel(name: "   ", hour: 9, minute: 5)
        XCTAssertEqual(
            viewModel.heroTitle,
            "09:05",
            "Whitespace-only names must not render a dangling separator"
        )
    }
}
