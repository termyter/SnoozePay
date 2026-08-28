import XCTest
@testable import SnoozePay

/// Coverage for `AlarmTheme` Codable + the `Alarm` migration path that lets
/// pre-#151 alarms decode cleanly without a `theme` field. The migration is
/// the contract that ships #151 safely on top of #143 — without it,
/// `AlarmRepository.readAll()` would throw `decodeFailure` on every existing
/// install and lock the entire alarm store via `_lastLoadFailed`.
final class AlarmThemeTests: XCTestCase {

    // MARK: - AlarmTheme round-trip

    func testBuiltInThemesRoundTripThroughJSON() throws {
        for theme in AlarmTheme.builtInOrder {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AlarmTheme.self, from: data)
            XCTAssertEqual(decoded, theme, "Round-trip failed for \(theme.id)")
        }
    }

    func testCustomThemeRoundTripPreservesPath() throws {
        let url = URL(fileURLWithPath: "/var/mobile/Caches/AlarmThemes/IMG.jpg")
        let theme = AlarmTheme.custom(imagePath: url)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: data)
        if case .custom(let decodedURL) = decoded {
            XCTAssertEqual(decodedURL.absoluteString, url.absoluteString)
        } else {
            XCTFail("Expected .custom, got \(decoded)")
        }
    }

    func testForestAndNeonDecodeFromRawIDs() throws {
        // The exact raw ids matter — they are the on-disk contract for #224.
        // A rename would silently degrade every saved forest/neon alarm to
        // `.dawn` via the unknown-id fallback below.
        let forest = try JSONDecoder().decode(AlarmTheme.self, from: #"{"id":"forest"}"#.data(using: .utf8)!)
        let neon = try JSONDecoder().decode(AlarmTheme.self, from: #"{"id":"neon"}"#.data(using: .utf8)!)
        XCTAssertEqual(forest, .forest)
        XCTAssertEqual(neon, .neon)
    }

    func testPreForestNeonThemeIDsStillDecode() throws {
        // Backwards-compat guard: alarms persisted before #224 keep decoding
        // to the same cases after the enum grew two members.
        let legacyIDs: [(String, AlarmTheme)] = [
            ("dawn", .dawn),
            ("mountains", .mountains),
            ("ocean", .ocean),
            ("abstract", .abstract)
        ]
        for (id, expected) in legacyIDs {
            let json = #"{"id":"\#(id)"}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(AlarmTheme.self, from: json)
            XCTAssertEqual(decoded, expected, "Legacy id \(id) no longer decodes to \(expected)")
        }
    }

    func testUnknownThemeIDDecodesAsDawn() throws {
        let json = #"{"id":"made-up-future-theme"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: json)
        XCTAssertEqual(decoded, .dawn)
    }

    func testCustomWithoutPathDecodesAsDawn() throws {
        // `.custom` requires `imagePath`. A corrupt entry without the path
        // should degrade to `.dawn` rather than throw — a missing theme
        // must not block the entire alarm decode.
        let json = #"{"id":"custom"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: json)
        XCTAssertEqual(decoded, .dawn)
    }

    // MARK: - Alarm migration

    func testLegacyAlarmJSONWithoutThemeDecodesWithDawnDefault() throws {
        // Hand-rolled JSON identical to a pre-#151 stored alarm — the
        // `theme` key is intentionally absent. Must decode to `.dawn` so
        // `AlarmRepository.readAll()` doesn't throw `decodeFailure` on
        // every existing install (issues #72 / #117).
        let json = """
        {
            "id":"\(UUID().uuidString)",
            "time":\(Date().timeIntervalSinceReferenceDate),
            "repeatDays":[0,1,2],
            "name":"Утренний",
            "soundID":"radar",
            "vibrationEnabled":true,
            "snoozeMinutes":9,
            "penaltyAmount":50.0,
            "progressiveScale":false,
            "enabled":true
        }
        """.data(using: .utf8)!
        let alarm = try JSONDecoder().decode(Alarm.self, from: json)
        XCTAssertEqual(alarm.theme, .dawn)
        XCTAssertEqual(alarm.name, "Утренний")
    }

    func testNewAlarmEncodesAndDecodesWithExplicitTheme() throws {
        let alarm = Alarm(
            penaltyAmount: 100,
            theme: .ocean
        )
        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(decoded.theme, .ocean)
    }

    func testAlarmListDecodesMixedLegacyAndNewEntries() throws {
        // Real-world AlarmRepository state right after the user upgrades:
        // some alarms were saved before #151 (no `theme`), some after.
        let legacyID = UUID()
        let modernID = UUID()
        let json = """
        [
            {
                "id":"\(legacyID.uuidString)",
                "time":770000000,
                "repeatDays":[],
                "name":"Старый",
                "soundID":"dawn",
                "vibrationEnabled":false,
                "snoozeMinutes":5,
                "penaltyAmount":25.0,
                "progressiveScale":false,
                "enabled":true
            },
            {
                "id":"\(modernID.uuidString)",
                "time":770003600,
                "repeatDays":[1,2,3],
                "name":"Новый",
                "soundID":"radar",
                "vibrationEnabled":true,
                "snoozeMinutes":9,
                "penaltyAmount":50.0,
                "progressiveScale":true,
                "enabled":true,
                "theme":{"id":"abstract"}
            }
        ]
        """.data(using: .utf8)!
        let alarms = try JSONDecoder().decode([Alarm].self, from: json)
        XCTAssertEqual(alarms.count, 2)
        let legacy = alarms.first { $0.id == legacyID }
        let modern = alarms.first { $0.id == modernID }
        XCTAssertEqual(legacy?.theme, .dawn)
        XCTAssertEqual(modern?.theme, .abstract)
    }

    // MARK: - Display

    func testDisplayNamesAreLocalised() {
        XCTAssertEqual(AlarmTheme.dawn.displayName, "Рассвет")
        XCTAssertEqual(AlarmTheme.mountains.displayName, "Горы")
        XCTAssertEqual(AlarmTheme.ocean.displayName, "Океан")
        XCTAssertEqual(AlarmTheme.forest.displayName, "Лес")
        XCTAssertEqual(AlarmTheme.neon.displayName, "Неон")
        // Renamed from "Абстракция" in the v3 lineup (#224).
        XCTAssertEqual(AlarmTheme.abstract.displayName, "Абстракт")
        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/x.jpg"))
        XCTAssertEqual(custom.displayName, "Своё фото")
    }

    func testBuiltInOrderMatchesDesignV3Lineup() {
        // Picker tile order is part of the v3 design contract (#224):
        // dawn, ocean, mountains, forest, neon, abstract.
        XCTAssertEqual(
            AlarmTheme.builtInOrder,
            [.dawn, .ocean, .mountains, .forest, .neon, .abstract]
        )
    }
}

/// Coverage for the orphaned-image reconcile sweep (#357). Co-located in this
/// file (rather than a new `AlarmThemeImageStoreTests.swift`) on purpose: the
/// SnoozePayTests group is an explicit Xcode group, so a brand-new file would
/// require a `project.pbxproj` edit — a no-touch zone gated behind PM override.
/// These tests stay in the AlarmTheme domain file to keep the fix mergeable
/// without touching the project file.
final class AlarmThemeImageStoreReconcileTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlarmThemeReconcileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    /// Write an empty placeholder file and return its URL.
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testReconcileDeletesUnreferencedFiles() throws {
        let kept = try makeFile("alarm-theme-KEEP.jpg")
        let orphanA = try makeFile("alarm-theme-ORPHAN-A.jpg")
        let orphanB = try makeFile("alarm-theme-ORPHAN-B.jpg")

        AlarmThemeImageStore.reconcile(in: tempDir, referencedURLs: [kept])

        XCTAssertTrue(exists(kept), "Referenced image must survive the sweep")
        XCTAssertFalse(exists(orphanA), "Orphaned image A should be deleted")
        XCTAssertFalse(exists(orphanB), "Orphaned image B should be deleted")
    }

    func testReconcileKeepsAllWhenEveryFileIsReferenced() throws {
        let first = try makeFile("alarm-theme-A.jpg")
        let second = try makeFile("alarm-theme-B.jpg")

        AlarmThemeImageStore.reconcile(in: tempDir, referencedURLs: [first, second])

        XCTAssertTrue(exists(first))
        XCTAssertTrue(exists(second))
    }

    func testReconcileDeletesAllWhenNothingReferenced() throws {
        let first = try makeFile("alarm-theme-A.jpg")
        let second = try makeFile("alarm-theme-B.jpg")

        AlarmThemeImageStore.reconcile(in: tempDir, referencedURLs: [])

        XCTAssertFalse(exists(first))
        XCTAssertFalse(exists(second))
    }

    func testReconcileMatchesByFilenameAcrossURLSpelling() throws {
        // `.custom` persists its path via `URL(string:)`, which can yield a
        // `file://`-prefixed URL whose `.path` differs from the on-disk
        // `URL(fileURLWithPath:)` spelling. Matching by lastPathComponent must
        // still treat them as the same image and keep it.
        let onDisk = try makeFile("alarm-theme-SAME.jpg")
        let referenced = URL(string: "file://\(tempDir.path)/alarm-theme-SAME.jpg")!

        AlarmThemeImageStore.reconcile(in: tempDir, referencedURLs: [referenced])

        XCTAssertTrue(exists(onDisk),
                      "A file referenced under a different URL spelling must not be deleted")
    }

    func testDeleteImageRemovesFileAndIsSilentWhenMissing() throws {
        let url = try makeFile("alarm-theme-DELETE.jpg")
        AlarmThemeImageStore.deleteImage(at: url)
        XCTAssertFalse(exists(url), "deleteImage should remove the file")
        // Second call on an already-gone file must not throw/crash.
        AlarmThemeImageStore.deleteImage(at: url)
    }

    // MARK: - Checked-read sweep (#271)

    private struct StubReadFailure: Error {}

    /// The whole point of routing the sweep through a *checked* read: an
    /// unreadable alarm store used to decode to `[]`, and `[]` is precisely
    /// the sweep's instruction to delete everything. A transient decode glitch
    /// therefore destroyed every custom theme photo the user had picked.
    func testReconcileWithFailingAlarmReadDeletesNothing() throws {
        let first = try makeFile("alarm-theme-A.jpg")
        let second = try makeFile("alarm-theme-B.jpg")

        let didSweep = AlarmThemeImageStore.reconcile(
            in: tempDir,
            readingAlarms: { throw StubReadFailure() }
        )

        XCTAssertFalse(didSweep, "An unreadable store must abort the sweep, not run it with []")
        XCTAssertTrue(exists(first), "A decode failure must never be read as 'unreferenced'")
        XCTAssertTrue(exists(second))
    }

    /// A readable store still reclaims orphans — the guard above must not have
    /// quietly disabled the feature it protects.
    func testReconcileWithSucceedingAlarmReadStillReclaimsOrphans() throws {
        let kept = try makeFile("alarm-theme-KEEP.jpg")
        let orphan = try makeFile("alarm-theme-ORPHAN.jpg")
        let alarm = Alarm(theme: .custom(imagePath: kept))

        let didSweep = AlarmThemeImageStore.reconcile(
            in: tempDir,
            readingAlarms: { [alarm] }
        )

        XCTAssertTrue(didSweep)
        XCTAssertTrue(exists(kept), "The referenced image must survive")
        XCTAssertFalse(exists(orphan), "Orphans are still reclaimed")
    }

    /// A store that genuinely holds no `.custom` themes is a legitimate
    /// "delete everything" instruction — only a *failed read* is not.
    func testReferencedImageURLsCollectsOnlyCustomThemes() throws {
        let customURL = try makeFile("alarm-theme-X.jpg")
        let alarms = [
            Alarm(theme: .custom(imagePath: customURL)),
            Alarm(theme: .ocean)
        ]

        XCTAssertEqual(AlarmThemeImageStore.referencedImageURLs(in: alarms), [customURL])
        XCTAssertTrue(AlarmThemeImageStore.referencedImageURLs(in: []).isEmpty,
                      "An empty (but successfully read) store references nothing")
    }
}
