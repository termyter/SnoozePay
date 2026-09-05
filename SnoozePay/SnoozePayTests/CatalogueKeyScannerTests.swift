import Foundation
import XCTest
@testable import SnoozePay

/// The scanner is the outside opinion the copy suites compare their tables
/// against (#767), and nothing else asserts on it: if it stopped seeing a call
/// shape, the suites would report the keys of that shape as entries nobody
/// reads — and the obvious "fix" for that report is to delete the entries, i.e.
/// exactly the shrinkage the scanner exists to stop.
final class CatalogueKeyScannerTests: XCTestCase {

    /// The three shapes that matter, all of them taken from live sources: the
    /// plain one-liner, `Localized.format(` with its key on the line below
    /// (`AlarmsStreakBannerView:111`), and two keys inside one call as the arms
    /// of a ternary (`CreateAlarmViewController:96`). A line-based regex sees
    /// only the first.
    func testSeesKeysBelowTheCallAndOnBothArmsOfATernary() {
        let source = """
        label.text = Localized.text("create_alarm.sound.title")
        title = Localized.text(
            isEditing ? "create_alarm.title.edit" : "create_alarm.title.new"
        )
        capsLabel.text = Localized.format(
            "alarms.streak.caps", streakDays, word
        ).uppercased()
        """

        XCTAssertEqual(
            CatalogueKeyScanner.keys(in: source).sorted(),
            [
                "alarms.streak.caps", "create_alarm.sound.title",
                "create_alarm.title.edit", "create_alarm.title.new"
            ]
        )
    }

    /// The negative, and the reason the walk is anchored on `Localized.` rather
    /// than on the shape of the literal alone: an SF Symbol name is spelled
    /// exactly like a two-segment key, and there are dozens of them in these
    /// files. Counting one would put a phantom into every table this scanner
    /// is compared against.
    func testIgnoresKeyShapedLiteralsThatNeverReachLocalized() {
        let source = """
        chevron.image = UIImage(systemName: "chevron.right")
        let defaultsKey = "stored_alarms"
        cell.accessibilityIdentifier = "alarms.cell.first"
        """

        XCTAssertEqual(CatalogueKeyScanner.keys(in: source), [])
    }

    /// Copy is Russian, formatted and punctuated, and it travels in the same
    /// calls as the keys. None of it may be mistaken for one.
    func testIgnoresTheCopyAndFormatArgumentsTravellingInTheSameCall() {
        let source = """
        Localized.format("alarms.streak.caps", "%1$lld %2$@ БЕЗ ОТКЛАДЫВАНИЙ", "Отмена")
        Localized.text("CREATE_ALARM.SOUND.TITLE")
        Localized.text("create_alarm")
        """

        XCTAssertEqual(CatalogueKeyScanner.keys(in: source), ["alarms.streak.caps"])
    }

    /// An escaped quote inside an argument must not end that argument: were it
    /// to, the walk would resume in the middle of a string, and every quote
    /// after it would be paired off by one — swallowing the *next* call's key
    /// and everything behind it. Hence the odd number of escapes here; a pair
    /// of them restores the parity by accident and proves nothing.
    func testAnEscapedQuoteInAnArgumentDoesNotSwallowTheNextCall() {
        let source = """
        Localized.format("create_alarm.snooze.hint", "10\\" мин")
        Localized.text("create_alarm.penalty.minimum")
        """

        XCTAssertEqual(
            CatalogueKeyScanner.keys(in: source).sorted(),
            ["create_alarm.penalty.minimum", "create_alarm.snooze.hint"]
        )
    }

    /// A file that is not there has to be *reported*, not counted as a file with
    /// no keys in it. Same reasoning as the key list itself: the failure mode
    /// this whole mechanism exists to close is a check that quietly covers less.
    func testAMissingSourceIsReportedRatherThanReadAsEmpty() {
        let reading = CatalogueKeyScanner.read(
            ["NoSuchCell.swift"], under: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        XCTAssertEqual(reading.unreadable, ["NoSuchCell.swift"])
        XCTAssertEqual(reading.keys, [])
    }
}
