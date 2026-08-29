import UIKit
import XCTest
@testable import SnoozePay

/// The firing screen's "Баланса не осталось" state has three vertical zones —
/// the balance-pill row, the centre column (hero + warning) and the bottom CTA
/// stack — and none of them may print over another (#547).
///
/// **Why rectangles and not coordinates.** The defect has already moved once:
/// #345 fixed "the warning lands on the price card" by adding a required
/// constraint below the block, which turned the same shortage of space into
/// "the warning lands on the clock". Both are the same fact — two zones
/// occupying the same pixels — and only an intersection test states that fact
/// directly. A test that pinned `block.top == caps.bottom + 24` would have been
/// green through both defects, because in each of them the constraint the test
/// checks is precisely the one the solver dropped.
///
/// **Why the safe-area insets are set by hand.** A `UIWindow` built in a unit
/// test has no scene and therefore no safe area, which hands the layout ~90pt
/// that no device has. On zero insets the pre-fix screen very nearly fits and
/// the overlap shrinks to a few points — the test would then be measuring the
/// harness. `additionalSafeAreaInsets` restores the device geometry (59/34 on
/// iPhone 17, 20/0 on the SE) so the assertion is about the screen, not the fake.
///
/// **Why the window is load-bearing.** A detached controller lays out at
/// `.zero`, every rectangle is empty and every intersection test passes
/// vacuously — the exact shape of a test that is green on a broken build.
/// `assertHarnessIsSane` fails loudly rather than letting that through.
final class AlarmFiringNoBalanceColumnLayoutTests: XCTestCase {

    // MARK: - Reference devices

    /// iPhone 17 — where #547 was reproduced. A "regular" height: the state
    /// used to overlap here, not just on compact hardware.
    private let regular = Device(size: CGSize(width: 402, height: 874), top: 59, bottom: 34)
    /// iPhone SE — the smallest supported screen. This element set cannot fit
    /// here at any spacing (the bottom stack alone is ~296pt), so the column has
    /// to shrink; what it must not do is overlap.
    private let compact = Device(size: CGSize(width: 375, height: 667), top: 20, bottom: 0)

    private struct Device {
        let size: CGSize
        let top: CGFloat
        let bottom: CGFloat
    }

    /// Windows are retained for the lifetime of the test: a `UIWindow` nothing
    /// holds may deallocate mid-assertion and take the hierarchy with it.
    private var hostWindows: [UIWindow] = []
    private var hostControllers: [AlarmFiringViewController] = []

    override func tearDown() {
        // `viewDidLoad` starts the alarm sound on the notification backend;
        // `viewDidDisappear` is what owns stopping it (and the clock ticker).
        hostControllers.forEach { $0.viewDidDisappear(false) }
        AudioService.shared.stopAlarmSound()
        hostWindows.forEach { $0.rootViewController = nil }
        hostControllers = []
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect

    func testNoBalance_warningDoesNotPrintOverTheHero_regularHeight() throws {
        let sut = try makeHostedFiring(on: regular, balance: 0)
        let block = try XCTUnwrap(sut.firing.noBalanceCenterBlock, "no-balance centre block was never built")
        try assertHarnessIsSane(sut, block: block)

        assertNoOverlap(
            rect(block, in: sut.window), rect(sut.firing.timeLabel, in: sut.window),
            "«Баланса не осталось» over the clock",
            hint: "the block's hero pin was breakable while its «stay above the bottom stack» "
                + "pin was required, so the solver bought room by dropping the block onto the hero"
        )
        assertNoOverlap(
            rect(block, in: sut.window), rect(sut.firing.wakeUpCapsLabel, in: sut.window),
            "the warning body over the «ТОЛЬКО ВСТАТЬ» eyebrow",
            hint: "the eyebrow is the hero's bottom edge — the block has to start below it"
        )
    }

    func testNoBalance_zonesDoNotIntersect_regularHeight() throws {
        try assertZonesAreDisjoint(on: regular)
    }

    func testNoBalance_zonesDoNotIntersect_compactHeight() throws {
        try assertZonesAreDisjoint(on: compact)
    }

    /// The compact screen has to give something up — the acceptance is that it
    /// gives up *size*, not legibility through an overlap. The clock shrinks and
    /// the decorative bell tile (absent from the canon column in this state)
    /// steps aside; the warning itself keeps every point it asks for.
    func testNoBalance_compactHeightDegradesBySizeNotByOverlap() throws {
        let sut = try makeHostedFiring(on: compact, balance: 0)
        let block = try XCTUnwrap(sut.firing.noBalanceCenterBlock)
        try assertHarnessIsSane(sut, block: block)

        XCTAssertLessThan(
            sut.firing.timeLabel.font.pointSize, AppTypography.clockXl.pointSize,
            "the clock kept its full 96pt on a screen that cannot hold the column — "
            + "something else must be overlapping to pay for it"
        )
        XCTAssertGreaterThanOrEqual(
            sut.firing.timeLabel.font.pointSize, AlarmFiringViewController.noBalanceClockFloor,
            "the clock shrank past the point of reading as the hero of the screen"
        )
        // The warning itself is the one element that must stay whole: both the
        // pill and the body paragraph laid out, and both inside the block.
        let blockRect = rect(block, in: sut.window)
        XCTAssertFalse(blockRect.isEmpty, "the warning was squeezed out of existence")
        XCTAssertEqual(block.arrangedSubviews.count, 2, "the warning lost a part")
        for part in block.arrangedSubviews {
            let partRect = rect(part, in: sut.window)
            XCTAssertFalse(partRect.isEmpty, "\(type(of: part)) in the warning did not lay out")
            XCTAssertTrue(
                blockRect.insetBy(dx: -0.5, dy: -0.5).contains(partRect),
                "\(type(of: part)) (\(partRect)) spills out of the warning (\(blockRect))"
            )
        }
    }

    // MARK: - Scope: the solvent screen is untouched

    /// The fix lives in the no-balance state. With money in the wallet the hero
    /// keeps the pin and the point size it has always had — no silent
    /// re-centring of the normal firing screen rode along.
    func testSolventWallet_heroKeepsItsShippedPositionAndSize() throws {
        let sut = try makeHostedFiring(on: regular, balance: 1000)
        XCTAssertTrue(
            sut.firing.noBalanceCenterBlock?.isHidden ?? true,
            "the no-balance warning is up on a solvent wallet"
        )
        XCTAssertEqual(
            sut.firing.timeLabel.center.y,
            sut.firing.view.bounds.midY - 60,
            accuracy: 0.5,
            "the hero moved off its design position on the normal screen"
        )
        XCTAssertEqual(
            sut.firing.timeLabel.font.pointSize, AppTypography.clockXl.pointSize,
            "the normal screen's clock was resized by the no-balance fit pass"
        )
        XCTAssertFalse(sut.firing.bellTile.isHidden, "the normal screen lost its bell tile")
    }

    // MARK: - Scope: the snoozed countdown still owns the screen

    /// #398 hid the no-balance stack while the countdown runs. The column's
    /// constraints have to step aside with it, otherwise the hero stays squeezed
    /// under a block nobody can see — and come back on exit.
    func testSnoozedState_handsTheColumnBack_andTakesItAgainOnExit() throws {
        let sut = try makeHostedFiring(on: regular, balance: 0, snoozeCount: 1, snoozed: true)
        let block = try XCTUnwrap(sut.firing.noBalanceCenterBlock)

        sut.firing.enterSnoozedState()
        try XCTSkipUnless(
            sut.firing.isSnoozedStateActive,
            "the snoozed state refused to start — a harness fact, not a layout one"
        )
        layOut(sut)

        XCTAssertTrue(block.isHidden, "the warning stayed up under the countdown")
        XCTAssertEqual(
            sut.firing.timeLabel.font.pointSize, AppTypography.clockXl.pointSize,
            "the clock slot stayed shrunk while the countdown was using it — the countdown "
            + "is pinned to `timeLabel`, so it inherits whatever the no-balance fit left behind"
        )
        XCTAssertEqual(
            sut.firing.timeLabel.center.y,
            sut.firing.view.bounds.midY - 60,
            accuracy: 0.5,
            "the countdown's slot is still pushed up by the hidden warning's constraints"
        )

        sut.firing.exitSnoozedState()
        layOut(sut)
        XCTAssertFalse(block.isHidden, "the warning did not return after the countdown")
        assertNoOverlap(
            rect(block, in: sut.window), rect(sut.firing.timeLabel, in: sut.window),
            "the warning over the clock after the snoozed round trip"
        )
    }

    // MARK: - Zone assertions

    private func assertZonesAreDisjoint(on device: Device) throws {
        let sut = try makeHostedFiring(on: device, balance: 0)
        let block = try XCTUnwrap(sut.firing.noBalanceCenterBlock)
        try assertHarnessIsSane(sut, block: block)

        let header = rect(sut.firing.topHeaderRow, in: sut.window)
        let bottom = rect(try XCTUnwrap(sut.firing.noBalanceContainer), in: sut.window)
        let column: [(String, UIView)] = [
            ("bell tile", sut.firing.bellTile),
            ("alarm name", sut.firing.nameLabel),
            ("clock", sut.firing.timeLabel),
            ("eyebrow caps", sut.firing.wakeUpCapsLabel),
            ("no-balance warning", block)
        ]

        for (name, element) in column where !element.isHidden {
            let frame = rect(element, in: sut.window)
            assertNoOverlap(frame, header, "\(name) over the balance-pill row")
            assertNoOverlap(frame, bottom, "\(name) over the bottom CTA stack")
            XCTAssertGreaterThanOrEqual(
                frame.minY, header.maxY - 0.5,
                "\(name) starts above the balance-pill row at \(Int(device.size.height))pt"
            )
            XCTAssertLessThanOrEqual(
                frame.maxY, bottom.minY + 0.5,
                "\(name) runs into the bottom CTA stack at \(Int(device.size.height))pt"
            )
        }

        // The pairing the issue is actually about: the warning against each
        // piece of hero above it.
        let blockRect = rect(block, in: sut.window)
        for (name, element) in column.dropLast() where !element.isHidden {
            assertNoOverlap(
                blockRect, rect(element, in: sut.window),
                "no-balance warning over \(name) at \(Int(device.size.height))pt"
            )
        }
    }

    private func assertNoOverlap(
        _ lhs: CGRect,
        _ rhs: CGRect,
        _ what: String,
        hint: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let overlap = lhs.intersection(rhs)
        // Sub-point contact is a rounding artefact of the layout engine, not ink
        // on ink; anything thicker is a real collision.
        let collides = !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5
        XCTAssertFalse(
            collides,
            "\(what): \(lhs) intersects \(rhs) over \(overlap)"
            + (hint.isEmpty ? "" : " — \(hint)"),
            file: file,
            line: line
        )
    }

    /// Fails on the two ways this suite could be green for nothing: a hierarchy
    /// that never laid out, and a state that never turned on.
    private func assertHarnessIsSane(
        _ sut: Hosted,
        block: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertFalse(block.isHidden, "the no-balance state never turned on", file: file, line: line)
        XCTAssertFalse(
            sut.firing.noBalanceContainer?.isHidden ?? true,
            "the no-balance CTA stack never turned on", file: file, line: line
        )
        XCTAssertFalse(
            rect(sut.firing.timeLabel, in: sut.window).isEmpty,
            "the hero never laid out — every intersection below would pass vacuously",
            file: file, line: line
        )
        XCTAssertFalse(
            rect(block, in: sut.window).isEmpty,
            "the warning never laid out", file: file, line: line
        )
        XCTAssertGreaterThan(
            sut.firing.view.safeAreaInsets.top, 0,
            "`additionalSafeAreaInsets` did not apply — the layout is being handed "
            + "~90pt of room no device has", file: file, line: line
        )
    }

    // MARK: - Harness

    private struct Hosted {
        let firing: AlarmFiringViewController
        let window: UIWindow
    }

    private func makeHostedFiring(
        on device: Device,
        balance: Double,
        snoozeCount: Int = 0,
        snoozed: Bool = false
    ) throws -> Hosted {
        let alarm = Alarm(name: "Работа", snoozeMinutes: 5, penaltyAmount: 50)
        let viewModel = AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: snoozeCount,
            snoozeAnchor: snoozed ? Date() : nil,
            balanceService: StubWallet(balance: balance)
        )
        let firing = AlarmFiringViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(origin: .zero, size: device.size))
        window.rootViewController = firing
        hostWindows.append(window)
        hostControllers.append(firing)

        firing.loadViewIfNeeded()
        firing.additionalSafeAreaInsets = UIEdgeInsets(
            top: device.top, left: 0, bottom: device.bottom, right: 0
        )
        // The clock mounts faded and translated 8pt; `viewDidAppear` is what
        // returns it to identity, and a transform would otherwise skew every
        // rectangle this suite measures.
        firing.viewDidAppear(false)
        let sut = Hosted(firing: firing, window: window)
        layOut(sut)
        return sut
    }

    /// Force layout to settle. The fit pass runs in `viewDidLayoutSubviews` and
    /// may resize the clock, which dirties layout once more — so drive the pass
    /// until it stops changing rather than assuming a single pass is final.
    private func layOut(_ sut: Hosted) {
        sut.firing.view.frame = sut.window.bounds
        for _ in 0..<4 {
            sut.window.setNeedsLayout()
            sut.firing.view.setNeedsLayout()
            sut.window.layoutIfNeeded()
        }
    }

    private func rect(_ view: UIView, in window: UIWindow) -> CGRect {
        view.convert(view.bounds, to: window)
    }
}

// MARK: - Test doubles

/// Wallet stub — `canSnooze` is the single switch between the normal screen and
/// the no-balance state, and it reads nothing but `canAfford`.
private final class StubWallet: AlarmFiringBalancing {
    var balance: Double

    init(balance: Double) {
        self.balance = balance
    }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }

    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        balance -= amount
        return Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
    }

    @discardableResult
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        balance += amount
        return true
    }
}
