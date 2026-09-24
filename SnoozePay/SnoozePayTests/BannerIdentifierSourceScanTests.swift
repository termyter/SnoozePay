import Foundation
import XCTest

/// No app code builds a `UNNotificationRequest` whose identifier is not minted
/// by `AppBannerNotification.makeIdentifier()` (#844).
///
/// A banner posted under a literal identifier compiles and passes every other
/// test, and in the foreground `willPresent` drops it as a bad alarm payload:
/// that is #842, which happened to all four banners at once. The compiler
/// cannot see the convention, so this reads the sources instead. Every
/// construction site under `SnoozePay/SnoozePay/` must pass
/// `<receiver>.makeIdentifier()` as its identifier, or sit in a file on
/// ``allowlist``. A site is any of:
///
///  * `UNNotificationRequest(` and `UNNotificationRequest.init(`;
///  * a bare `.init(identifier:`, the type-inferred spelling
///    (`let r: UNNotificationRequest = .init(…)`, `center.add(.init(…))`).
///
/// Since #844 there is exactly one site, `LocalNotificationPosting.postAppBanner`,
/// so a new banner is meant to go through it and never trip this.
///
/// `makeIdentifier()` is matched by name, not by type: a text scan cannot see
/// that `banner` in `banner.makeIdentifier()` is an `AppBannerNotification`.
/// `testMakeIdentifierIsDeclaredOnlyOnAppBannerNotification` closes that from
/// the other side, because no other app type may declare the name.
///
/// # Misses
///
/// Loud (reported as a violation, so they fail rather than hide):
///  * the identifier held in a variable, or built by a helper that takes it as
///    a parameter: the site reads `id`, which is not a `makeIdentifier()` call;
///  * a string literal holding a comma, which cuts the identifier early;
///  * a site inside a comment or a `"""` literal (over-reported);
///  * a bare `.init(identifier:` of some other type, e.g. `self.init(identifier:`
///    in a convenience init (over-reported). `Locale.init(identifier:` is not a
///    site: the bare form needs no identifier character before its dot.
///
/// Silent (a literal identifier here passes):
///  * the type reached through a `typealias` or a metatype value
///    (`Req(identifier:`, `type.init(identifier:`), or a generic `T.init`;
///  * code outside `SnoozePay/SnoozePay/`. There is no such target today;
///  * the right mechanism with the wrong case, e.g. `.rescheduleFailed` minted
///    by the snooze builder. That is not this check's job: `AppBannerPostingTests`
///    pins each builder's case.
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

    /// `isMinted` trusts the name `makeIdentifier()`. That is only safe while
    /// `AppBannerNotification` is the one app type declaring it.
    func testMakeIdentifierIsDeclaredOnlyOnAppBannerNotification() throws {
        let declaration = try NSRegularExpression(pattern: #"\b(?:func|var|let)\s+makeIdentifier\b"#)
        let declaring = try Self.appSources().flatMap { source -> [String] in
            let range = NSRange(location: 0, length: (source.text as NSString).length)
            return Array(repeating: source.file, count: declaration.numberOfMatches(in: source.text, range: range))
        }
        XCTAssertEqual(
            declaring, ["Models/AppBannerNotification.swift"],
            "makeIdentifier is declared somewhere else too, so the scan can no longer tell a banner "
                + "identifier by its name. Rename the other one"
        )
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

    /// The shapes the scan has to read, planted directly, plus two it must
    /// leave alone.
    func testScanReadsTheSpellingsItClaims() {
        let source = """
            let a = UNNotificationRequest(identifier: "fixed", content: c, trigger: nil)
            let b = UNNotificationRequest.init(identifier: id, content: c, trigger: nil)
            let c = UNNotificationRequest(
                identifier: AppBannerNotification.rescheduleFailed.makeIdentifier(),
                content: c, trigger: nil
            )
            let d: UNNotificationRequest = .init(identifier: "typed", content: c, trigger: nil)
            center.add(.init(identifier: banner.makeIdentifier(), content: c, trigger: nil))
            func f(_ r: UNNotificationRequest) -> [UNNotificationRequest] { [] }
            let locale = Locale.init(identifier: "ru")
            let color: UIColor = .init(red: 1, green: 0, blue: 0, alpha: 1)
            """
        let identifiers = Self.sites(in: source, file: "x").map(\.identifier)

        XCTAssertEqual(
            identifiers,
            [
                "\"fixed\"", "id", "AppBannerNotification.rescheduleFailed.makeIdentifier()",
                "\"typed\"", "banner.makeIdentifier()"
            ]
        )
        XCTAssertEqual(identifiers.map(Self.isMinted), [false, false, true, false, true])
    }

    // MARK: - Scanner

    /// Either the type named at the call, or a bare `.init(` whose first
    /// argument is `identifier:`. The bare form is only a site when no
    /// identifier character precedes the dot, so `Locale.init(identifier:` is
    /// not one. The two do not double-count: the first alternative consumes
    /// `UNNotificationRequest.init(` whole.
    private static let construction = try? NSRegularExpression(
        pattern: #"UNNotificationRequest\s*(?:\.\s*init\s*)?\(\s*|(?<![A-Za-z0-9_])\.\s*init\s*\(\s*(?=identifier:)"#
    )

    /// `<receiver>.makeIdentifier()` and nothing else.
    private static func isMinted(_ identifier: String) -> Bool {
        identifier.range(of: #"^[A-Za-z_][A-Za-z0-9_.]*\.makeIdentifier\(\)$"#, options: .regularExpression) != nil
    }

    /// Every Swift file under the app's source root, relative path and text.
    private static func appSources() throws -> [(file: String, text: String)] {
        let root = appSourceDirectory()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var sources: [(file: String, text: String)] = []
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".swift") else { continue }
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            sources.append((file: relative, text: text))
        }
        // 177 on the day this was written; a floor far below it only catches
        // a scan pointed at the wrong directory.
        XCTAssertGreaterThan(sources.count, 50, "scanned \(sources.count) Swift files under \(root.path)")
        return sources
    }

    private static func appSites() throws -> [Site] {
        try appSources().flatMap { Self.sites(in: $0.text, file: $0.file) }
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
