import XCTest
@testable import SnoozePay

/// Guards the alarm-domain keys `AlarmBackendAvailability`,
/// `CreateAlarmViewModel` and `AlarmFiringViewModel` moved into
/// `Localizable.xcstrings` (#599, part of #569).
///
/// Sibling of `ViewModelLocalizationTests`, which covers the earlier
/// alarms-list / statistics slice of the same issue. Split by slice rather than
/// merged so a red run names the migration that broke, and so two agents
/// working the epic in parallel do not collide on one file.
///
/// The failure this exists for is silent: `Localized` echoes an unknown key, so
/// a typo turns the permission screen's heading into
/// `alarms.backend_guard.title.wont_ring` on screen without anything throwing,
/// logging, or failing to compile. Neither the compiler nor SwiftLint can see
/// it — a key is an ordinary `String`.
///
/// Behavioural assertions on the migrated call sites are mostly NOT repeated
/// here. `AlarmsListBackendGuardTests`, `CreateAlarmViewModelTests`,
/// `CreateAlarmRepeatValidityTests`, `AlarmRepeatModeTests`,
/// `AlarmFiringViewModelTests` and `AlarmFiringSnoozedStateTests` already
/// compare those call sites against the Russian words verbatim; left untouched
/// by this migration, they now assert the whole chain (call site → key →
/// catalogue → copy) instead of just its tail. The one gap they leave is the
/// three requirement-screen *messages* — those tests check the titles and
/// action labels only — so those are asserted below.
final class AlarmViewModelLocalizationTests: XCTestCase {

    /// Every key this slice introduced. Listed literally rather than derived
    /// from the catalogue, so deleting an entry fails instead of shrinking the
    /// loop.
    private static let migratedKeys = [
        "alarms.backend_guard.action.open_settings",
        "alarms.backend_guard.action.request",
        "alarms.backend_guard.message.indeterminate",
        "alarms.backend_guard.message.not_requested",
        "alarms.backend_guard.message.unavailable",
        "alarms.backend_guard.title.indeterminate",
        "alarms.backend_guard.title.wont_ring",
        "create_alarm.progressive.step",
        "create_alarm.repeat.hint.once",
        "create_alarm.repeat.hint.once_on_days",
        "create_alarm.repeat.hint.weekly",
        "create_alarm.validation.weekly_without_days",
        "firing.snooze.button.affordable",
        "firing.snooze.button.no_balance",
        "firing.snoozed.suffix"
    ]

    // MARK: - The keys resolve

    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.migratedKeys {
            let value = Localized.text(key)
            XCTAssertNotEqual(
                value, key,
                "missing catalogue entry: \(key) — the UI would render the key itself"
            )
            XCTAssertFalse(value.isEmpty, "empty catalogue value for \(key)")
        }
    }

    /// A key present in both places but empty in the catalogue would pass the
    /// check above by accident. Requiring Cyrillic pins each entry to the
    /// language the source catalogue is written in.
    func testMigratedCopyIsTheRussianSourceText() {
        for key in Self.migratedKeys {
            let scalars = Localized.text(key).unicodeScalars
            let isCyrillic = scalars.contains { (0x0400...0x04FF).contains($0.value) }
            XCTAssertTrue(isCyrillic, "catalogue value for \(key) carries no Russian text")
        }
    }

    /// Nothing in this slice may collapse onto one entry by accident: the three
    /// requirement states each explain a different cause, and a copy-paste that
    /// pointed two of them at one key would still read perfectly on screen.
    func testMigratedKeysCarryDistinctCopy() {
        let values = Self.migratedKeys.map { Localized.text($0) }
        XCTAssertEqual(Set(values).count, values.count, "two migrated keys resolve to the same copy")
    }

    // MARK: - Substitutions survived the move into JSON

    /// The specifier is the part most easily lost in the trip through JSON:
    /// drop `%1$lld` while retyping and the sentence still reads fine, just
    /// without the number in it.
    func testFormatKeysKeepTheirSubstitutionSpecifiers() {
        XCTAssertTrue(Localized.text("create_alarm.progressive.step").contains("%1$lld"))
        XCTAssertTrue(Localized.text("create_alarm.progressive.step").contains("%2$@"))
        XCTAssertTrue(Localized.text("firing.snooze.button.affordable").contains("%1$lld"))
        XCTAssertTrue(Localized.text("firing.snooze.button.affordable").contains("%2$@"))
        XCTAssertTrue(Localized.text("firing.snoozed.suffix").contains("%@"))
    }

    /// The snooze button's price is prefixed with U+2212 MINUS SIGN, not a
    /// hyphen — it matches the ledger, and a retyped hyphen is invisible in
    /// review while changing the rendered glyph.
    func testSnoozeButtonKeepsTheTypographicMinusSign() {
        let title = Localized.text("firing.snooze.button.affordable")
        XCTAssertTrue(title.unicodeScalars.contains(Unicode.Scalar(0x2212)!), "− became a plain hyphen")
    }

    // MARK: - The requirement-screen messages still say what they used to

    /// The gap left by `AlarmsListBackendGuardTests`, which asserts the titles
    /// and action labels of these three states but not their bodies. Each was
    /// two concatenated Swift literals before the migration and is one
    /// catalogue entry now; the rendered sentence must come out identical.
    func testNotRequestedMessageIsUnchanged() {
        let warning = AlarmBackendWarning(availability: .notRequested)
        XCTAssertEqual(
            warning?.message,
            "Приложение ещё не спросило разрешение на будильники и уведомления. "
                + "Без него созданные будильники не сработают."
        )
    }

    func testUnavailableMessageIsUnchanged() {
        let warning = AlarmBackendWarning(availability: .unavailable)
        XCTAssertEqual(
            warning?.message,
            "Разрешение на будильники и уведомления выключено. "
                + "Включите его в Настройках — иначе созданные будильники не сработают."
        )
    }

    func testIndeterminateMessageIsUnchanged() {
        let warning = AlarmBackendWarning(availability: .indeterminate)
        XCTAssertEqual(
            warning?.message,
            "Приложение не смогло узнать, разрешены ли будильники и уведомления. "
                + "Проверьте их в Настройках — без разрешения будильники не сработают."
        )
    }

    /// The two ringing states still produce no copy at all. Guards against a
    /// migration that wired every branch to a key and lost the `nil` that call
    /// sites read as «nothing to warn about».
    func testRingingStatesStillProduceNoWarning() {
        XCTAssertNil(AlarmBackendWarning(availability: .available))
        XCTAssertNil(AlarmBackendWarning(availability: .unresolved))
    }

    // MARK: - The validation copy stays single-sourced

    /// The repeat hint and the save-blocked alert must keep reading from one
    /// key. Two keys with identical Russian would pass every assertion above
    /// and drift apart on the first translation.
    func testValidationCopyIsSharedByTheHintAndTheError() {
        let suiteName = "test.alarmViewModelLocalization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = CreateAlarmViewModel(repository: AlarmRepository(defaults: defaults))
        viewModel.repeatMode = .weekly
        viewModel.repeatDays = []

        let expected = Localized.text("create_alarm.validation.weekly_without_days")
        XCTAssertEqual(viewModel.repeatModeHint, expected)
        XCTAssertEqual(viewModel.validationError?.errorDescription, expected)
    }
}
