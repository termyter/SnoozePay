import XCTest
@testable import SnoozePay

/// Coverage for the referral input's pure transform (#412). The delegate hook
/// `textField(_:shouldChangeCharactersIn:)` always returns `false` and rewrites
/// the text, so the caret offset has to be recomputed by hand — these tests
/// lock the uppercase + 6-char-cap behaviour and the caret math that keeps
/// mid-string edits from jumping to the end.
final class ReferralCodeInputTests: XCTestCase {

    private func transform(_ current: String, _ range: NSRange, _ string: String) -> ReferralCodeInput.Result? {
        ReferralCodeInput.transform(current: current, replacing: range, with: string)
    }

    // MARK: - Uppercase + append

    func testAppendingLowercase_uppercasesAndAdvancesCaret() {
        let result = transform("AB", NSRange(location: 2, length: 0), "c")
        XCTAssertEqual(result, .init(text: "ABC", caretOffset: 3))
    }

    func testAppendingToEmpty_uppercases() {
        let result = transform("", NSRange(location: 0, length: 0), "x")
        XCTAssertEqual(result, .init(text: "X", caretOffset: 1))
    }

    // MARK: - 6-char cap

    func testEditFillingToSixChars_isAccepted() {
        let result = transform("ABCDE", NSRange(location: 5, length: 0), "f")
        XCTAssertEqual(result, .init(text: "ABCDEF", caretOffset: 6))
    }

    func testEditExceedingSixChars_isRejected() {
        XCTAssertNil(transform("ABCDEF", NSRange(location: 6, length: 0), "G"))
    }

    func testPastingPastSixChars_isRejected() {
        XCTAssertNil(transform("", NSRange(location: 0, length: 0), "ABCDEFG"))
    }

    func testPastingExactlySixChars_isAccepted() {
        let result = transform("", NSRange(location: 0, length: 0), "abcdef")
        XCTAssertEqual(result, .init(text: "ABCDEF", caretOffset: 6))
    }

    // MARK: - Mid-string edits (the bug)

    func testInsertingMidString_keepsCaretAfterInsertion() {
        // "AC" with caret between A and C, type "B" -> "ABC", caret after B (offset 2)
        let result = transform("AC", NSRange(location: 1, length: 0), "b")
        XCTAssertEqual(result, .init(text: "ABC", caretOffset: 2))
    }

    func testBackspaceMidString_keepsCaretAtDeletionPoint() {
        // "ABC", delete the "B" (range location 1, length 1) -> "AC", caret at offset 1
        let result = transform("ABC", NSRange(location: 1, length: 1), "")
        XCTAssertEqual(result, .init(text: "AC", caretOffset: 1))
    }

    func testReplacingSelectionMidString_advancesByInsertedLength() {
        // "AXYZ B", select "XYZ" (loc 1 len 3), type "12" -> "A12 B", caret after "12" (offset 3)
        let result = transform("AXYZB", NSRange(location: 1, length: 3), "12")
        XCTAssertEqual(result, .init(text: "A12B", caretOffset: 3))
    }
}
