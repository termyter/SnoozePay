import XCTest
@testable import SnoozePay

/// Pins the alarms-list sound pill after #599 deleted the ten private literals
/// `AlarmsListViewModel` used to render it from, leaving
/// `Localized.optionalText(SoundCatalogue.nameKey(for:))` as the only source.
///
/// This slice introduced **no catalogue keys**. The ten `common.sound.name.*`
/// entries were already in `Localizable.xcstrings` — #598 put them there and
/// exposed `SoundCatalogue.nameKey(for:)` as the seam this side was meant to
/// collapse onto — so what is asserted here is a *reader*, not a migration.
/// The keys read by this call site, named in full so the next slice has a
/// checklist rather than a prefix to guess at:
///
///     common.sound.name.dawn      common.sound.name.waves
///     common.sound.name.radar     common.sound.name.birds
///     common.sound.name.drops     common.sound.name.classic
///     common.sound.name.piano     common.sound.name.jazz
///     common.sound.name.guitar
///     common.sound.name.bell
///
/// Plus `common.sound.name.custom`, read only to assert it is **absent**: the
/// picker's custom slot names its copy under `create_alarm.*`, and the list
/// screen reaching it would mean it started rendering a row nobody can pick.
///
/// That is the whole of what this suite covers. It is not the whole of what
/// `ViewModels/` reads — the directory resolves some fifty catalogue keys, and
/// the rest are covered elsewhere in the test target (`ViewModelLocalizationTests`,
/// `AlarmViewModelLocalizationTests`, and the per-screen copy suites). What
/// closes #599's lane is a separate fact, measured with
/// `count-cyrillic-literals.py`: zero Cyrillic string literals remain in
/// `ViewModels/`. Zero literals is not the same claim as full coverage by this
/// file, and the checklist above is only the former.
///
/// Three layers, so a red run names which one broke:
///
///  1. **Catalogue layer** — each key exists and does not resolve to itself.
///  2. **Copy layer** — each key still holds the word the deleted literal held.
///     Transcribed from `AlarmsListViewModel.soundDisplayNames` as it stood on
///     `origin/main`, not read back out of the catalogue: a list derived from
///     the file under test agrees with any mistake in it.
///  3. **Call-site layer** — the view model is driven for real and what it
///     returns is compared against those same transcribed words. Layers 1 and 2
///     are blind to a wrong key at the call site, because there the catalogue
///     itself is fine.
///
/// # Why this is not folded into `SoundCatalogueCopyTests`
///
/// That suite owns the picker's 22 keys and asserts, from #598's side, that the
/// alarms list agrees with the catalogue word for word — it compares the view
/// model against `SoundCatalogue.entries`, i.e. catalogue against catalogue.
/// After the collapse both sides read one key, so that comparison can no longer
/// fail on a wrong word; it now only proves the two call sites agree. The
/// hardcoded Russian below is what still fails when the *copy* moves at this
/// reader, and it belongs with the reader it protects. It is no longer the only
/// place copy drift reddens: since #763 `SoundCatalogueCopyTests` holds its own
/// id-keyed literals, so a moved word reds there as well.
///
/// What that suite no longer does is *depend* on the table below. Until #763
/// its own name expectation was looked up through `SoundCatalogue.nameKey(for:)`
/// — the builder it was checking — so this file was the only place a permuted
/// builder reddened, and deleting this suite would have unpinned the names
/// project-wide without a single red run. It now carries its own id-keyed
/// `namesBySoundID`. The two transcriptions are independent by design: each is
/// checked against the catalogue, neither is derived from the other.
///
/// # The fallback is behaviour, not a detail
///
/// `alarmSoundName(at:)` renders the raw `soundID` for an id the catalogue does
/// not know. That is why it reads through `optionalText` and not `text`, which
/// echoes the key: a pill saying «common.sound.name.foo» would be a regression
/// against one saying «foo». `testUncataloguedSoundStillFallsBackToItsRawID`
/// is the assertion that keeps the two apart, and it is the one thing the
/// collapse could plausibly have changed.
final class AlarmsListSoundNameTests: XCTestCase {

    /// Resolves synchronously so `repository.save` never reaches
    /// `UNUserNotificationCenter`.
    private final class NoopScheduler: AlarmScheduling {
        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }

    /// The ten words the deleted lookup table held, keyed by sound id.
    /// Transcribed from the pre-#599 literals.
    ///
    /// `SoundCatalogueCopyTests.namesBySoundID` holds the same ten words for
    /// the picker's reader. Duplicated rather than shared on purpose (#763),
    /// and the reason is the coupling that change removed, not a sharing
    /// mechanism: before it, `SoundCatalogueCopyTests` had no id-keyed table at
    /// all and leaned on this one across a file boundary, so narrowing this
    /// suite unpinned the picker in silence. A shared table would not reproduce
    /// that — hoisted into a helper, deleting either suite leaves it untouched;
    /// left here and made non-private, deleting this file is a compile error,
    /// which is the loudest signal there is. What a shared table would cost is
    /// the independence: one transcription, so a typo in it agrees with itself
    /// in both suites. That is what the duplication buys, and it is the whole
    /// price of keeping ten Russian words in two places.
    private static let namesBeforeTheCollapse: [String: String] = [
        "dawn": "Рассвет",
        "radar": "Радар",
        "drops": "Капли",
        "piano": "Пиано",
        "guitar": "Гитара",
        "bell": "Колокольчик",
        "waves": "Волны",
        "birds": "Птицы",
        "classic": "Классика",
        "jazz": "Джаз"
    ]

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsListSoundName.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel(withSoundIDs soundIDs: [String]) -> AlarmsListViewModel {
        for soundID in soundIDs {
            repository.save(Alarm(name: "sound-\(soundID)", soundID: soundID))
        }
        // A private centre, not `.default`: the view model registers three
        // observers and defaults its `AlarmBackendMonitor` onto whichever
        // centre it was handed, so on `.default` a test-host activation would
        // drag `SystemAlarmBackendProbe` → `AlarmScheduler.shared` →
        // `UNUserNotificationCenter` into this suite. `AlarmsListViewModel.init`
        // documents exactly that hazard; `AlarmsListBackendGuardTests` and
        // `AlarmsListZeroBalanceAndWrapTests` inject for the same reason.
        // Nothing here posts a notification, so an isolated centre costs
        // nothing.
        let viewModel = AlarmsListViewModel(
            alarmRepository: repository,
            notificationCenter: NotificationCenter()
        )
        viewModel.loadData()
        return viewModel
    }

    // MARK: - Layer 1: the keys resolve

    func testEveryKeyThisCallSiteReadsResolvesToCopyRatherThanToItself() {
        for soundID in SoundCatalogue.ids {
            let key = SoundCatalogue.nameKey(for: soundID)
            XCTAssertNotNil(
                Localized.optionalText(key),
                "missing catalogue entry: \(key) — the sound pill would render the raw id"
            )
            XCTAssertNotEqual(Localized.text(key), key, "\(key) resolves to itself")
        }
    }

    /// The lookup table covered exactly the catalogued ids. A sound added to
    /// `SoundCatalogue.ids` without a name key would now reach the list screen
    /// as a bare id instead of failing to compile, so the coverage is asserted
    /// rather than assumed.
    func testTheCatalogueCoversPreciselyTheSoundsTheDeletedTableCovered() {
        XCTAssertEqual(Set(SoundCatalogue.ids), Set(Self.namesBeforeTheCollapse.keys))
    }

    // MARK: - Layer 2: the words did not move

    func testCatalogueStillHoldsTheWordsTheDeletedTableHeld() {
        for (soundID, expected) in Self.namesBeforeTheCollapse {
            XCTAssertEqual(
                Localized.text(SoundCatalogue.nameKey(for: soundID)), expected,
                "copy drifted for sound '\(soundID)'"
            )
        }
    }

    // MARK: - Layer 3: what the view model hands the cell

    func testEverySoundRendersTheWordItRenderedBeforeTheCollapse() {
        let viewModel = makeViewModel(withSoundIDs: SoundCatalogue.ids)
        XCTAssertEqual(viewModel.alarms.count, SoundCatalogue.ids.count)

        for (index, alarm) in viewModel.alarms.enumerated() {
            XCTAssertEqual(
                viewModel.alarmSoundName(at: index),
                Self.namesBeforeTheCollapse[alarm.soundID],
                "alarms-list name for '\(alarm.soundID)' changed"
            )
        }
    }

    /// The same failure as the test above, approached from the other side: a
    /// wrong key resolves to nothing and falls through to the raw id, which
    /// reads plausibly enough to survive review — «dawn» in a pill is odd but
    /// not obviously broken. Not an independent layer of protection (the
    /// word-for-word check already fails on every mutation this one catches),
    /// but it names the *cause* in its failure message rather than the symptom,
    /// which is what a reader of a red run needs first.
    func testNoSoundPillFallsThroughToAnIDOrToAKey() {
        let viewModel = makeViewModel(withSoundIDs: SoundCatalogue.ids)

        for (index, alarm) in viewModel.alarms.enumerated() {
            let name = viewModel.alarmSoundName(at: index)
            XCTAssertNotEqual(name, alarm.soundID, "'\(alarm.soundID)' fell back to its raw id")
            XCTAssertNotEqual(name, SoundCatalogue.nameKey(for: alarm.soundID))
            XCTAssertEqual(name?.hasPrefix("common."), false, "a catalogue key reached the cell")
        }
    }

    /// The documented behaviour of this method, and the reason it reads through
    /// `optionalText`. An id from a custom file — or from a build that shipped
    /// a sound this one does not know — renders as itself.
    func testUncataloguedSoundStillFallsBackToItsRawID() {
        let unknown = ["custom", "nonexistent-sound"]
        let viewModel = makeViewModel(withSoundIDs: unknown)

        for (index, alarm) in viewModel.alarms.enumerated() {
            XCTAssertEqual(viewModel.alarmSoundName(at: index), alarm.soundID)
        }
        // The custom slot has copy in the catalogue, but under the picker's own
        // namespace. Reaching it from here would mean the list screen started
        // rendering a row the user cannot pick.
        XCTAssertNil(Localized.optionalText(SoundCatalogue.nameKey(for: "custom")))
    }

    /// Out-of-range indices returned `nil` before the collapse and still do —
    /// the cell reads this as «no sound pill», not as an empty one.
    func testOutOfRangeIndexYieldsNoName() {
        let viewModel = makeViewModel(withSoundIDs: ["dawn"])
        XCTAssertEqual(viewModel.alarmSoundName(at: 0), "Рассвет")
        XCTAssertNil(viewModel.alarmSoundName(at: 1))
        XCTAssertNil(viewModel.alarmSoundName(at: 99))
    }
}
