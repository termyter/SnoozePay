import XCTest

/// Checks the compiled InfoPlist tables, independently of the device language.
/// System prompt language negotiation still needs the device acceptance in #596.
final class AlarmPermissionPurposeLocalizationTests: XCTestCase {
    func testCompiledRussianPurposeMatchesApprovedCopy() throws {
        XCTAssertEqual(
            try compiledPurpose(in: "ru"),
            "SnoozePay использует будильники, чтобы будить вас вовремя — даже в беззвучном режиме."
        )
    }

    func testCompiledEnglishPurposeMatchesApprovedCopy() throws {
        XCTAssertEqual(
            try compiledPurpose(in: "en"),
            "SnoozePay uses alarms to wake you on time, even when your phone is on silent."
        )
    }

    private func compiledPurpose(in language: String) throws -> String {
        let localizationURL = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "The app bundle has no \(language).lproj localization."
        )
        let localizationBundle = try XCTUnwrap(Bundle(url: localizationURL))
        let tableURL = try XCTUnwrap(
            localizationBundle.url(forResource: "InfoPlist", withExtension: "strings"),
            "\(language).lproj/InfoPlist.strings was not compiled into the app."
        )
        let data = try Data(contentsOf: tableURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let table = try XCTUnwrap(plist as? [String: String])
        let key = "NSAlarmKitUsageDescription"
        XCTAssertEqual(Set(table.keys), [key], "Only the approved AlarmKit purpose belongs in this catalogue.")
        let purpose = try XCTUnwrap(table[key])
        XCTAssertEqual(
            localizationBundle.localizedString(forKey: key, value: nil, table: "InfoPlist"),
            purpose,
            "The explicit \(language) bundle must resolve the compiled permission purpose."
        )
        return purpose
    }
}
