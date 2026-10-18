import UIKit
import XCTest
@testable import SnoozePay

final class SPRowInteractionTests: XCTestCase {
    func testSwitchWithoutRowActionReceivesHitsThroughEveryAncestor() {
        let toggle = UISwitch()
        let row = SPRow(title: "Fade in", trailing: toggle)
        let root = mount(row)
        assertHit(in: root, reaches: toggle)
        XCTAssertTrue(root.hitTest(row.convert(CGPoint(x: 5, y: 5), to: root), with: nil) === root,
                      "an inert part of a row must not consume touches")
    }

    func testNestedSwitchDoesNotTriggerRowActionAndOtherHitsStillTapTheRow() {
        let toggle = UISwitch()
        let accessory = UIStackView(arrangedSubviews: [toggle])
        var rowTaps = 0
        let row = SPRow(title: "Fade in", trailing: accessory, onTap: { rowTaps += 1 })
        let root = mount(row)
        let recorder = SwitchRecorder()
        toggle.addTarget(recorder, action: #selector(SwitchRecorder.changed), for: .valueChanged)

        // Dispatch only after hit-testing from ABOVE the row. sendActions on
        // the child alone would bypass both disabled ancestors behind #930.
        assertHit(in: root, reaches: toggle)
        toggle.setOn(true, animated: false)
        toggle.sendActions(for: .valueChanged)
        XCTAssertEqual(recorder.changes, 1)
        XCTAssertEqual(rowTaps, 0, "an accessory action must not also fire the row")

        let hit = root.hitTest(row.convert(CGPoint(x: 5, y: 5), to: root), with: nil)
        XCTAssertTrue(hit === row)
        (hit as? UIControl)?.sendActions(for: .touchUpInside)
        XCTAssertEqual(rowTaps, 1)
        XCTAssertEqual(recorder.changes, 1)
    }

    func testTappableRowsRouteTitleAccessoryAndPaddingToTheRowExactlyOnce() {
        let value = UILabel()
        value.text = "70%"
        var taps = 0
        let row = SPRow(title: "Volume", trailing: value, onTap: { taps += 1 })
        let root = mount(row)
        let points = [CGPoint(x: 10, y: 40), CGPoint(x: 340, y: 40), CGPoint(x: 175, y: 1)]
        for (index, point) in points.enumerated() {
            let hit = root.hitTest(row.convert(point, to: root), with: nil)
            XCTAssertTrue(hit === row)
            (hit as? UIControl)?.sendActions(for: .touchUpInside)
            XCTAssertEqual(taps, index + 1)
        }
        row.isUserInteractionEnabled = false
        XCTAssertTrue(root.hitTest(row.center, with: nil) === root)
        row.isUserInteractionEnabled = true
        row.isHidden = true
        XCTAssertTrue(root.hitTest(row.center, with: nil) === root)
    }

    private func mount(_ row: SPRow) -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        root.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            row.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            row.widthAnchor.constraint(equalToConstant: 350),
            row.heightAnchor.constraint(equalToConstant: 80)
        ])
        root.layoutIfNeeded()
        return root
    }

    private func assertHit(in root: UIView, reaches control: UIControl,
                           file: StaticString = #filePath, line: UInt = #line) {
        let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: root)
        let hit = root.hitTest(point, with: nil)
        XCTAssertTrue(hit === control || hit?.isDescendant(of: control) == true,
                      "the accessory must receive the hit through the row and its stacks", file: file, line: line)
    }

    private final class SwitchRecorder: NSObject {
        var changes = 0
        @objc func changed() { changes += 1 }
    }
}
