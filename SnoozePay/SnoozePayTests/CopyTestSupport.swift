import XCTest

/// Fails for every catalogue key in `keys` that reached the screen as its own
/// name.
///
/// `Localized.text(_:)` answers a missing entry with the key itself
/// (`Localized.swift:102-103`), so a dropped entry surfaces on screen as
/// `create_alarm.volume.title` where the words should be.
///
/// # Why both spellings
///
/// Caps section labels render `Localized.text(key).uppercased()`. When the
/// entry goes missing, that call upper-cases the *key*, and an assertion
/// written as `rendered.contains(Localized.text(key).uppercased())` compares
/// the leaked key to itself and stays green. A guard matching only the
/// lower-case spelling is then the last thing that could have gone red, and it
/// does not, because the screen holds `CREATE_ALARM.VOLUME.TITLE` (#713).
///
/// # Why one implementation
///
/// This was six private copies across the copy suites, of which #713 taught
/// exactly one about caps, because its issue named one file. Fixing a
/// mechanism in the file that happened to be reported is what a copied
/// mechanism costs. `CopyTestSupportTests` is what holds this one to its
/// contract.
func assertNoKeysLeaked(
    _ keys: [String],
    in rendered: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for key in keys {
        // Both spellings are reported, not just the first match: a key that
        // leaks into a plain label AND a caps one is two call sites to fix,
        // and naming only the lower-case half sends the fixer to one of them.
        let spellings = key == key.uppercased() ? [key] : [key, key.uppercased()]
        for leaked in spellings where rendered.contains(leaked) {
            XCTFail(
                "«\(leaked)» rendered as its own key — the catalogue lookup missed",
                file: file, line: line
            )
        }
    }
}
