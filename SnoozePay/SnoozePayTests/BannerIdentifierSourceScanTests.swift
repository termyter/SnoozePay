import Foundation
import XCTest

/// No app code builds a `UNNotificationRequest` whose identifier is not minted
/// by `AppBannerNotification.makeIdentifier()` (#844).
///
/// A banner posted under a literal identifier compiles and passes every other
/// test, and in the foreground `willPresent` drops it as a bad alarm payload:
/// that is #842, which happened to all four banners at once. The compiler
/// cannot see the convention, so this reads the sources instead. Every
/// `UNNotificationRequest(` or `UNNotificationRequest.init(` under
/// `SnoozePay/SnoozePay/` must pass `<something>.makeIdentifier()` as its
/// identifier, or sit in a file on ``allowlist``.
///
/// Since #844 there is exactly one such site,
/// `LocalNotificationPosting.postAppBanner`, so a new banner is meant to go
/// through it and never trip this.
///
/// What it does not see: a request built through a helper that takes the
/// identifier as a parameter (the site then passes a variable and goes red,
/// the loud direction), and one written inside a comment (over-reported, also
/// loud). A string literal holding a comma cuts the identifier early. It still
/// is not a `makeIdentifier()` call, so that reads as a violation too.
final class BannerIdentifierSourceScanTests: XCTestCase {

    /// Files, relative to the app's source root, allowed to build a request
    /// with an identifier of their own. Empty: alarms go through AlarmKit and
    /// build no `UNNotificationRequest`. A file listed here must say why,
    /// and `testEveryAllowlistEntryStillBuildsARequest` drops it when it stops
    /// building one.
    private static let allowlist: Set<String> = []

    /// One construction site: the file it sits in and the identifier argument
    /// as written.
    private struct Site: Equatable {
        let file: String
        let identifier: String
    }

    func testEveryRequestIdentifierIsMintedByABanner() throws {
        let sites = try Self.appSites()
        XCTAssertFalse(
            sites.isEmpty,
            "found no UNNotificationRequest at all; postAppBanner builds one, so the scan is reading the wrong tree"
        )

        let offenders = sites.filter { !Self.allowlist.contains($0.file) && !Self.isMinted($0.identifier) }
        XCTAssertEqual(
            offenders, [],
            "a UNNotificationRequest in app code does not take its identifier from AppBannerNotification. "
                + "willPresent will drop it in the foreground (#842). Post it through postAppBanner"
        )
    }

    func testEveryAllowlistEntryStillBuildsARequest() throws {
        let files = Set(try Self.appSites().map(\.file))
        XCTAssertEqual(Self.allowlist.subtracting(files), [], "allowlisted files that no longer build a request")
    }

    /// The check has to be able to fail. The real `postAppBanner` source, with
    /// its minted identifier swapped for the literal a hurried banner would use,
    /// run through the same scan.
    func testALiteralIdentifierInTheRealSourceGoesRed() throws {
        let path = "Models/AppBannerNotification.swift"
        let text = try String(contentsOf: Self.appSourceDirectory().appendingPathComponent(path), encoding: .utf8)
        let minted = "identifier: banner.makeIdentifier(),"
        XCTAssertTrue(text.contains(minted), "test precondition: postAppBanner no longer spells \(minted)")

        let mutated = text.replacingOccurrences(
            of: minted, with: "identifier: \"promo_\" + UUID().uuidString,"
        )
        let sites = Self.sites(in: mutated, file: path)

        XCTAssertEqual(sites, [Site(file: path, identifier: "\"promo_\" + UUID().uuidString")])
        XCTAssertEqual(sites.map { Self.isMinted($0.identifier) }, [false])
    }

    /// The shapes the scan has to read, planted directly.
    func testScanReadsTheSpellingsItClaims() {
        let source = """
            let a = UNNotificationRequest(identifier: "fixed", content: c, trigger: nil)
            let b = UNNotificationRequest.init(identifier: id, content: c, trigger: nil)
            let c = UNNotificationRequest(
                identifier: AppBannerNotification.rescheduleFailed.makeIdentifier(),
                content: c, trigger: nil
            )
            func f(_ r: UNNotificationRequest) -> [UNNotificationRequest] { [] }
            """
        let identifiers = Self.sites(in: source, file: "x").map(\.identifier)

        XCTAssertEqual(
            identifiers, ["\"fixed\"", "id", "AppBannerNotification.rescheduleFailed.makeIdentifier()"]
        )
        XCTAssertEqual(identifiers.map(Self.isMinted), [false, false, true])
    }

    // MARK: - Scanner

    private static let construction = try? NSRegularExpression(
        pattern: #"UNNotificationRequest\s*(?:\.\s*init\s*)?\(\s*"#
    )

    /// `<receiver>.makeIdentifier()` and nothing else.
    private static func isMinted(_ identifier: String) -> Bool {
        identifier.range(of: #"^[A-Za-z_][A-Za-z0-9_.]*\.makeIdentifier\(\)$"#, options: .regularExpression) != nil
    }

    private static func appSites() throws -> [Site] {
        let root = appSourceDirectory()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var found: [Site] = []
        var scanned = 0
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".swift") else { continue }
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            found += Self.sites(in: text, file: relative)
            scanned += 1
        }
        // 177 on the day this was written; a floor far below it only catches
        // a scan pointed at the wrong directory.
        XCTAssertGreaterThan(scanned, 50, "scanned \(scanned) Swift files under \(root.path)")
        return found
    }

    /// Every construction site in `source`, with the text of its identifier
    /// argument: from after `identifier:` up to the first `,` or `)` outside
    /// nested brackets. A site whose first argument is not `identifier:` is
    /// reported with its first argument, so it fails rather than hides.
    private static func sites(in source: String, file: String) -> [Site] {
        guard let construction = Self.construction else {
            XCTFail("the construction pattern does not compile")
            return []
        }
        let text = source as NSString
        let matches = construction.matches(in: source, range: NSRange(location: 0, length: text.length))
        return matches.map { match in
            var rest = Substring(text.substring(from: match.range.upperBound))
            if rest.hasPrefix("identifier:") { rest = rest.dropFirst("identifier:".count) }
            var depth = 0
            var end = rest.startIndex
            while end < rest.endIndex {
                let char = rest[end]
                if depth == 0, char == "," || char == ")" { break }
                if "([{".contains(char) { depth += 1 }
                if ")]}".contains(char) { depth -= 1 }
                end = rest.index(after: end)
            }
            return Site(file: file, identifier: rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// `<root>/SnoozePay/SnoozePay`, from this file's compiled-in path, as
    /// `AppDelegateCopyKeysTests.appSourceDirectory()` does.
    private static func appSourceDirectory(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()  // SnoozePayTests
            .deletingLastPathComponent()  // SnoozePay (project dir)
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("SnoozePay/SnoozePay")
    }
}
