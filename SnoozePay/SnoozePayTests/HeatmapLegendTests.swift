import XCTest
@testable import SnoozePay

/// The streak heatmap's legend.
///
/// The map paints four states and named none of them. The only legend on the
/// screen belongs to the next card down — «зелёное — сэкономлено · красное —
/// потеряно» — which describes a different chart: read as this one's caption
/// it misleads twice, since a clean month shows no red at all and the map has
/// a gold the neighbour never mentions (#637).
final class HeatmapLegendTests: XCTestCase {

    private var legend: String { Localized.text("statistics.streak.legend") }

    // MARK: - It exists, and it comes from the catalogue

    /// Acceptance: «строки заведены в Localizable.xcstrings, а не захардкожены».
    /// `Localized.text` echoes the key back when it resolves to nothing.
    func testLegendComesFromTheCatalogue() {
        XCTAssertNotEqual(legend, "statistics.streak.legend",
                          "legend string is missing from Localizable.xcstrings")
        XCTAssertFalse(legend.isEmpty)
    }

    // MARK: - It names every state

    /// The guard that matters. The switch is exhaustive over `DayStatus`, so
    /// adding a fifth cell state stops this test COMPILING — the legend cannot
    /// silently fall behind the chart it describes.
    func testLegendNamesEveryCellState() {
        for status in StatisticsViewModel.DayStatus.allCases {
            let term: String
            switch status {
            case .woke: term = "встал сразу"
            case .light: term = "1\u{2060}–\u{2060}2\u{00A0}откладывания"
            case .heavy: term = "3 и больше"
            case .empty: term = "без будильника"
            }
            XCTAssertTrue(legend.contains(term),
                          "legend does not describe \(status): expected «\(term)» in «\(legend)»")
        }
    }

    /// Every state's colour has to be named too — a legend that lists meanings
    /// without their colours cannot be matched to the squares.
    func testLegendNamesEveryColour() {
        for colour in ["зелёное", "золотое", "красное", "серое"] {
            XCTAssertTrue(legend.contains(colour), "legend omits «\(colour)»")
        }
    }

    // MARK: - It does not fight the neighbour

    /// Acceptance: «формулировки согласованы с легендой соседней карточки — не
    /// спорят с ней». Both use the same colour vocabulary and the same
    /// «цвет — значение · …» shape, so the two read as one system.
    func testLegendSharesTheNeighboursShapeAndVocabulary() {
        let neighbour = Localized.text("statistics.week.legend")

        XCTAssertTrue(legend.contains(" — "), "legend should use the neighbour's «цвет — значение» dash")
        XCTAssertTrue(legend.contains(" · "), "legend should separate entries with the neighbour's middot")
        for shared in ["зелёное", "красное"] {
            XCTAssertTrue(neighbour.contains(shared) && legend.contains(shared),
                          "both legends should name «\(shared)» the same way")
        }
    }

    /// The two legends describe different charts, so they must not be the same
    /// sentence — that would recreate the confusion the issue reported.
    func testLegendIsNotTheNeighboursLegend() {
        XCTAssertNotEqual(legend, Localized.text("statistics.week.legend"))
    }

    /// Same typography rule as #638: a count and the noun it counts may not be
    /// split across lines. The legend wraps to three lines on an iPhone, and
    /// without the non-breaking space it broke at «1–2 / откладывания».
    func testCountAndItsNounCannotBeSplitAcrossLines() {
        XCTAssertTrue(legend.contains("1\u{2060}–\u{2060}2\u{00A0}откладывания"),
                      "«1–2 откладывания» must be one unbreakable run")
        XCTAssertFalse(legend.contains("1–2 откладывания"),
                       "A plain space lets the layout break between the count and its noun")
        XCTAssertFalse(legend.contains("1–2"),
                       "A bare en dash is itself a break opportunity: «1–» wrapped away from «2» on screen")
    }
}
