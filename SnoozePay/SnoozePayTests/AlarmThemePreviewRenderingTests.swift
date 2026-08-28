import XCTest
@testable import SnoozePay

/// Regression cover for the theme picker's visual identity (#463).
///
/// The audit found the picker reading as a single dark surface: Dawn's tile
/// was painted with a pre-#151 blue-black gradient that matched no screen in
/// the app, and no tile carried the accent glow that the firing backgrounds
/// use to sell each theme. These tests pin the two properties that failure
/// violated — every stock theme has its own recipe, and that recipe is the one
/// its own firing background paints.
final class AlarmThemePreviewRenderingTests: XCTestCase {

    private let stockThemes = AlarmTheme.builtInOrder

    // MARK: - Every theme is renderable

    func testEveryStockThemeExposesAGradientAndAnAccentGlow() {
        for theme in stockThemes {
            XCTAssertNotNil(
                AlarmThemeRendering.gradientColors(for: theme),
                "\(theme.id) has no picker gradient"
            )
            XCTAssertNotNil(
                AlarmThemeRendering.accentGlowColor(for: theme),
                "\(theme.id) has no accent glow — its tile would read as a flat dark block"
            )
        }
    }

    func testCustomThemeRendersNoGradientAndNoGlow() {
        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/nonexistent.jpg"))
        XCTAssertNil(AlarmThemeRendering.gradientColors(for: custom))
        XCTAssertNil(AlarmThemeRendering.gradientLocations(for: custom))
        XCTAssertNil(AlarmThemeRendering.accentGlowColor(for: custom))
    }

    // MARK: - Identity: no two stock themes look alike

    func testStockThemeRecipesArePairwiseDistinct() {
        for (index, theme) in stockThemes.enumerated() {
            for other in stockThemes[(index + 1)...] {
                let lhs = AlarmThemeRendering.gradientColors(for: theme)
                let rhs = AlarmThemeRendering.gradientColors(for: other)
                XCTAssertNotEqual(
                    lhs, rhs,
                    "\(theme.id) and \(other.id) paint the same gradient — the picker stops being a choice"
                )
            }
        }
    }

    func testDawnGradientEndsOnAWarmHorizonNotACoolOne() {
        // The retired recipe ended on #050912 — bluer than it was red, so the
        // tile could only read as "night". The shipped Dawn atmosphere ends on
        // #1A1410, a warm horizon, which is the theme's whole promise.
        guard let last = AlarmThemeRendering.gradientColors(for: .dawn)?.last else {
            return XCTFail("Dawn has no gradient")
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(cgColor: last).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertGreaterThan(red, blue, "Dawn's last stop must lean warm, not cool")
    }

    // MARK: - Parity with the firing screen

    func testDawnPreviewMatchesTheDawnAtmosphere() {
        XCTAssertEqual(
            AlarmThemeRendering.gradientColors(for: .dawn),
            SPDawnBackgroundView.calmBaseColors.map { $0.cgColor },
            "Dawn's preview must be a miniature of SPDawnBackgroundView's calm base"
        )
        XCTAssertEqual(
            AlarmThemeRendering.accentGlowColor(for: .dawn),
            SPDawnBackgroundView.calmSunCoreColor,
            "Dawn's glow is its rising sun — that's what makes the tile read as «тёплый янтарь»"
        )
    }

    func testThemedPreviewGlowsMatchTheFiringAccentSoft() {
        for theme in stockThemes where theme != .dawn {
            guard let palette = AlarmFiringThemePalette.palette(for: theme) else {
                return XCTFail("Missing palette for \(theme.id)")
            }
            XCTAssertEqual(
                AlarmThemeRendering.accentGlowColor(for: theme),
                palette.accentSoft,
                "\(theme.id) preview glow must be the same accent the firing background uses"
            )
        }
    }

    // MARK: - SPThemePreviewView

    func testPreviewViewReportsWhetherItPaintedAGradient() {
        let view = SPThemePreviewView()
        for theme in stockThemes {
            XCTAssertTrue(view.apply(theme: theme), "\(theme.id) should paint a gradient")
            XCTAssertFalse(view.isHidden, "\(theme.id) preview should be visible")
        }

        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/nonexistent.jpg"))
        XCTAssertFalse(view.apply(theme: custom), "Custom photo has no gradient recipe")
        XCTAssertTrue(view.isHidden, "Custom preview hides itself so the caller can show the photo")
    }

    /// Both call sites pin the preview to their container's edges — a 3-column
    /// tile and the 180pt preview block. Exercises `layoutSubviews`, where the
    /// glow geometry is derived from the short side.
    func testPreviewViewFillsItsContainerAtTileAndBlockSizes() {
        for size in [CGSize(width: 104, height: 125), CGSize(width: 353, height: 180)] {
            let host = UIView(frame: CGRect(origin: .zero, size: size))
            let view = SPThemePreviewView()
            view.apply(theme: .ocean)
            host.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: host.topAnchor),
                view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            host.layoutIfNeeded()
            XCTAssertEqual(view.bounds.size, size, "preview must fill its container at \(size)")
        }
    }
}
