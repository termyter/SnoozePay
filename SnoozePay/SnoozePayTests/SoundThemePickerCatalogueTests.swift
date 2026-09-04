import XCTest
@testable import SnoozePay

/// Unit tests for the extracted V3 picker logic (#285): the sound catalogue +
/// subtitle mapping and the alarm-theme subtitle mapping. Pure-value tests —
/// no simulator/UIKit layout exercised.
final class SoundThemePickerCatalogueTests: XCTestCase {

    // MARK: - Sound catalogue

    func testSoundCatalogue_keepsAllTenSounds() {
        XCTAssertEqual(SoundCatalogue.entries.count, 10, "Catalogue must keep all 10 sounds, not cut to 6")
    }

    func testSoundCatalogue_idsAreUnique() {
        let ids = SoundCatalogue.entries.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Sound ids must be unique")
    }

    func testSoundCatalogue_everyEntryHasNameAndSubtitle() {
        for entry in SoundCatalogue.entries {
            XCTAssertFalse(entry.name.isEmpty, "Sound '\(entry.id)' has empty name")
            XCTAssertFalse(entry.subtitle.isEmpty, "Sound '\(entry.id)' has empty subtitle")
        }
    }

    func testSoundCatalogue_customSlot_isDistinctAndNotInEntries() {
        XCTAssertEqual(SoundCatalogue.customSlot.id, "custom")
        XCTAssertFalse(
            SoundCatalogue.entries.contains(where: { $0.id == SoundCatalogue.customSlot.id }),
            "The custom slot must not be part of the selectable catalogue"
        )
    }

    func testCreateAlarmViewModel_availableSounds_mirrorsCatalogue() {
        let suite = "test.catalogue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = CreateAlarmViewModel(repository: AlarmRepository(defaults: defaults))
        XCTAssertEqual(vm.availableSounds.map { $0.id }, SoundCatalogue.entries.map { $0.id })
    }

    // MARK: - Theme subtitles

    func testThemeSubtitles_everyBuiltInThemeHasSubtitle() {
        for theme in AlarmTheme.builtInOrder {
            XCTAssertFalse(
                AlarmThemeSubtitles.subtitle(for: theme).isEmpty,
                "Theme '\(theme.id)' is missing a subtitle"
            )
        }
    }

    func testThemeSubtitles_knownThemesResolve() {
        XCTAssertEqual(AlarmThemeSubtitles.subtitle(for: .dawn), "Тёплый янтарь")
        XCTAssertEqual(AlarmThemeSubtitles.subtitle(for: .ocean), "Холодный мятный")
    }

    func testThemeSubtitles_customThemeUsesGallerySubtitle() {
        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertEqual(AlarmThemeSubtitles.subtitle(for: custom), AlarmThemeSubtitles.customSlotSubtitle)
        XCTAssertEqual(AlarmThemeSubtitles.customSlotSubtitle, "Из галереи")
    }
}
