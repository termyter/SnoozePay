import XCTest
@testable import SnoozePay

/// Tests for brand-font resolution (#273) — the bundled Manrope / JetBrains
/// Mono .ttf files must resolve through `AppFonts` / `AppTypography` instead
/// of the SF system fallback. The test host is the SnoozePay app, so the
/// `UIAppFonts` registration from `Info.plist` is active here.
final class AppFontsTests: XCTestCase {

    // MARK: - Registry sanity

    func testAllBundledFacesAreRegistered() {
        let faces = [
            "Manrope-ExtraLight", "Manrope-Regular", "Manrope-Medium",
            "Manrope-SemiBold", "Manrope-Bold", "Manrope-ExtraBold",
            "JetBrainsMono-ExtraLight", "JetBrainsMono-Light",
            "JetBrainsMono-Regular", "JetBrainsMono-Medium",
            "JetBrainsMono-SemiBold", "JetBrainsMono-Bold"
        ]
        for face in faces {
            XCTAssertNotNil(UIFont(name: face, size: 17), "\(face) not registered — check Resources/Fonts + UIAppFonts")
        }
    }

    // MARK: - AppFonts resolution

    func testSansResolvesManrope() {
        XCTAssertEqual(AppFonts.sans(.regular, 15).fontName, "Manrope-Regular")
        XCTAssertEqual(AppFonts.sans(.medium, 15).fontName, "Manrope-Medium")
        XCTAssertEqual(AppFonts.sans(.semibold, 15).fontName, "Manrope-SemiBold")
        XCTAssertEqual(AppFonts.sans(.bold, 15).fontName, "Manrope-Bold")
        XCTAssertEqual(AppFonts.sans(.extrabold, 15).fontName, "Manrope-ExtraBold")
    }

    func testMonoResolvesJetBrainsMono() {
        XCTAssertEqual(AppFonts.mono(.regular, 14).fontName, "JetBrainsMono-Regular")
        XCTAssertEqual(AppFonts.mono(.medium, 14).fontName, "JetBrainsMono-Medium")
        XCTAssertEqual(AppFonts.mono(.semibold, 14).fontName, "JetBrainsMono-SemiBold")
        XCTAssertEqual(AppFonts.mono(.bold, 14).fontName, "JetBrainsMono-Bold")
    }

    func testLightWeightsResolveBundledLightCuts() {
        // tokens.css clock-xl wants weight 200 → JBM ExtraLight, clock-lg 300 → Light.
        XCTAssertEqual(AppFonts.mono(.ultralight, 96).fontName, "JetBrainsMono-ExtraLight")
        XCTAssertEqual(AppFonts.mono(.light, 64).fontName, "JetBrainsMono-Light")
        // Manrope has no 100/300 static cut in the bundle — both map to ExtraLight.
        XCTAssertEqual(AppFonts.sans(.ultralight, 20).fontName, "Manrope-ExtraLight")
        XCTAssertEqual(AppFonts.sans(.light, 20).fontName, "Manrope-ExtraLight")
    }

    func testFontPreservesRequestedPointSize() {
        XCTAssertEqual(AppFonts.sans(.bold, 32).pointSize, 32)
        XCTAssertEqual(AppFonts.mono(.ultralight, 96).pointSize, 96)
    }

    // MARK: - AppTypography role resolution

    func testTypographyRolesResolveBrandFaces() {
        XCTAssertEqual(AppTypography.display.fontName, "Manrope-ExtraBold")
        XCTAssertEqual(AppTypography.h1.fontName, "Manrope-ExtraBold")
        XCTAssertEqual(AppTypography.h2.fontName, "Manrope-Bold")
        XCTAssertEqual(AppTypography.body.fontName, "Manrope-Medium")
        XCTAssertEqual(AppTypography.caps.fontName, "Manrope-Bold")
        XCTAssertEqual(AppTypography.moneyXl.fontName, "JetBrainsMono-Bold")
        XCTAssertEqual(AppTypography.moneySm.fontName, "JetBrainsMono-SemiBold")
        XCTAssertEqual(AppTypography.clockXl.fontName, "JetBrainsMono-ExtraLight")
        XCTAssertEqual(AppTypography.clockLg.fontName, "JetBrainsMono-Light")
    }

    // MARK: - Letter-spacing constants (tokens.css em × pointSize)

    func testKerningConstantsMatchTokensCss() {
        XCTAssertEqual(AppTypography.displayKerning, 88 * -0.025, accuracy: 0.001)
        XCTAssertEqual(AppTypography.h1Kerning, 32 * -0.01, accuracy: 0.001)
        XCTAssertEqual(AppTypography.h2Kerning, 24 * -0.01, accuracy: 0.001)
        XCTAssertEqual(AppTypography.moneyXlKerning, 56 * -0.02, accuracy: 0.001)
        XCTAssertEqual(AppTypography.clockXlKerning, 96 * -0.04, accuracy: 0.001)
        XCTAssertEqual(AppTypography.clockLgKerning, 64 * -0.04, accuracy: 0.001)
    }

    func testKernHelperConvertsEmToPoints() {
        XCTAssertEqual(AppTypography.kern(em: -0.02, size: 50), -1.0, accuracy: 0.001)
        XCTAssertEqual(AppTypography.kern(em: 0.12, size: 12), 1.44, accuracy: 0.001)
    }

    func testKernedBuilderCarriesFontAndTracking() {
        let attributed = AppTypography.kerned(
            "07:30",
            font: AppTypography.clockXl,
            kerning: AppTypography.clockXlKerning
        )
        let attrs = attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attrs[.font] as? UIFont)?.fontName, "JetBrainsMono-ExtraLight")
        XCTAssertEqual(attrs[.kern] as? CGFloat ?? 0, AppTypography.clockXlKerning, accuracy: 0.001)
        XCTAssertEqual(attributed.string, "07:30")
    }
}
