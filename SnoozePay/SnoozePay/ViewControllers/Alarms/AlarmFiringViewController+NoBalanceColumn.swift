import UIKit

// MARK: - No-balance centre column (#547)
//
// Canon: `SPScreensV2.jsx` → `FiringNoBalanceV2` (lines 227–277). The screen is
// three vertical zones — the balance-pill row, a `flex: 1` centre column, and
// the bottom CTA stack. The column SHARES the leftover space with its
// neighbours, so an overlap is impossible by construction there: a flex child
// cannot print over a sibling, it can only be squeezed by one.
//
// What the app had instead: the centre block was tied to the hero by a
// `.defaultHigh` pin and to the bottom stack by a required one. Two constraints
// pulling opposite ways, and the breakable one always lost — so the warning
// landed on the clock (#547) after #345 had moved the same collision off the
// price card. Nothing in the set ever said "do not print over the hero".
//
// This file reproduces the flex behaviour with three rules that hold together:
//
//   1. a REQUIRED floor under the block — `block.top >= caps.bottom + sp2` — so
//      the warning cannot reach the hero at any screen height;
//   2. the REQUIRED ceiling from #345 — `block.bottom <= bottomStack.top - sp4`
//      — kept as is;
//   3. the hero is free to slide up into the room the top zone is not using:
//      its design position (`centerY - 60`) drops to priority 500 while the
//      state is on, bounded by a guard that keeps it clear of the header row.
//
// Rules 1–3 are jointly satisfiable only while the column actually fits, and on
// a compact screen this element set does not fit at all: on 667pt the bottom
// stack alone is ~296pt and the header ~42pt. So the column also has to shrink,
// which is what `updateNoBalanceColumnFit()` does — it picks the largest clock
// that fits and, when even a 72pt clock will not buy the room, parks the
// decorative bell tile (the canon column carries no tile in this state at all).
// That is the readable degradation the issue asks for, in place of an overlap.
//
// Everything here is scoped to the no-balance state: with a solvent wallet the
// screen keeps the exact constraints it shipped with, which is why the normal
// firing screen and the snoozed countdown are untouched by this change.

/// Constraint bundle for the no-balance centre column.
///
/// Extensions cannot add stored properties and the host VC body is already at
/// the SwiftLint `type_body_length` budget, so the whole set travels in one
/// associated object — the same route `noBalanceCenterBlock` takes.
final class AlarmFiringNoBalanceColumn {

    // MARK: Built in `+Layout`, swapped here

    /// `timeLabel.centerY == view.centerY - 60`, required — the hero's design
    /// position, and the only thing that positions it on the normal screen.
    var heroDesignCenterY: NSLayoutConstraint?
    /// `bellTile.bottom == nameLabel.top - sp4`, required — deactivated when
    /// the tile is what stands between the warning and a readable column.
    var bellToName: NSLayoutConstraint?

    // MARK: Built here, inactive until the state turns on

    /// `timeLabel.centerY <= view.centerY - 60` — the hero may rise, never sink.
    var heroCeiling: NSLayoutConstraint?
    /// The design position again, at priority 500: honoured whenever the column
    /// fits, yields to the required block constraints when it does not.
    var heroPreferredCenterY: NSLayoutConstraint?
    /// `bellTile.top >= topHeaderRow.bottom + sp3` — the hero stops at the
    /// header row instead of climbing through it.
    var bellTopGuard: NSLayoutConstraint?
    /// The same guard measured from the name label, for when the tile is parked.
    var nameTopGuard: NSLayoutConstraint?
    /// Priority-250 twin of `bellToName` so the parked tile keeps a determinate
    /// position instead of leaving an ambiguous layout behind.
    var bellIdle: NSLayoutConstraint?
    /// Priority-250 placement for the hidden block while the state is off.
    var blockIdleTop: NSLayoutConstraint?
    /// Required floor — the fix for #547.
    var blockTopFloor: NSLayoutConstraint?
    /// The design gap, high but breakable, so the floor is only reached under
    /// pressure and the block otherwise sits where it always did.
    var blockTopPreferred: NSLayoutConstraint?
    /// Required ceiling — the #345 guarantee.
    var blockBottom: NSLayoutConstraint?

    /// `true` while the no-balance layout owns the column.
    var isActive = false
    /// `true` while the column reserves the bell tile's 84pt slot — which is
    /// the shipped state, and what `bellToName` encodes.
    ///
    /// Tracked here rather than read back off `bellTile.isHidden` because the
    /// two answer different questions: a `.custom` photo theme hides the tile
    /// (its call, never ours) but the constraint still holds its slot open, and
    /// a fit computed against a slot the layout is still reserving is a fit that
    /// silently overshoots by 100pt.
    var bellReserved = true
}

extension AlarmFiringViewController {

    // MARK: - Tuning

    /// Slack kept between the measured column and the space it is given, so a
    /// point of rounding in a font metric cannot turn into a broken guard.
    static var noBalanceColumnSafety: CGFloat { 8 }
    /// Gap between the header row and the top of the column.
    static var noBalanceColumnHeaderGap: CGFloat { AppSpacing.sp3 }
    /// The clock never shrinks past this — below it the hour stops reading as
    /// the hero of the screen and the state may as well drop the bell tile.
    static var noBalanceClockKeepsBell: CGFloat { 72 }
    /// Absolute floor for the clock once the tile is already parked.
    static var noBalanceClockFloor: CGFloat { 40 }

    // MARK: - Install

    /// Build the hero-slack constraints. All start inactive: with a solvent
    /// wallet the hero keeps the required `centerY - 60` pin from `+Layout`.
    func installNoBalanceColumnSlack() {
        let column = noBalanceColumn

        let ceiling = timeLabel.centerYAnchor.constraint(
            lessThanOrEqualTo: view.centerYAnchor, constant: -60
        )
        let preferred = timeLabel.centerYAnchor.constraint(
            equalTo: view.centerYAnchor, constant: -60
        )
        preferred.priority = UILayoutPriority(500)

        let bellGuard = bellTile.topAnchor.constraint(
            greaterThanOrEqualTo: topHeaderRow.bottomAnchor,
            constant: Self.noBalanceColumnHeaderGap
        )
        bellGuard.priority = UILayoutPriority(999)
        let nameGuard = nameLabel.topAnchor.constraint(
            greaterThanOrEqualTo: topHeaderRow.bottomAnchor,
            constant: Self.noBalanceColumnHeaderGap
        )
        nameGuard.priority = UILayoutPriority(999)

        // Redundant while `bellToName` holds; the whole point is what happens
        // after it is switched off.
        let idle = bellTile.bottomAnchor.constraint(
            equalTo: nameLabel.topAnchor, constant: -AppSpacing.sp4
        )
        idle.priority = UILayoutPriority(250)
        idle.isActive = true

        column.heroCeiling = ceiling
        column.heroPreferredCenterY = preferred
        column.bellTopGuard = bellGuard
        column.nameTopGuard = nameGuard
        column.bellIdle = idle
    }

    /// Build the center "БАЛАНСА НЕ ОСТАЛОСЬ" pill + body text — the bottom
    /// half of the centre column, under the hero's eyebrow caps. Mirrors
    /// `SPScreensV2.jsx` lines 239–251.
    func installNoBalanceCenterPill(inset: CGFloat) {
        // Pain-tinted "coin off" pill — V3 swaps the shield glyph for the
        // crossed-out-coin icon used across the zero-balance surfaces (#227).
        let shieldPill = SPPill(
            text: "Баланса не осталось",
            tone: .pain,
            icon: SPIcons.coinOff(size: 14)
        )
        shieldPill.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = AppTypography.bodyLg
        body.textColor = UIColor.white.withAlphaComponent(0.7)
        body.textAlignment = .center
        body.numberOfLines = 0
        body.text = "Откладывать больше не получится. Только встать."

        let block = UIStackView(arrangedSubviews: [shieldPill, body])
        block.translatesAutoresizingMaskIntoConstraints = false
        block.axis = .vertical
        block.alignment = .center
        block.spacing = AppSpacing.sp4
        // The warning is the one thing on this screen that must never be
        // squeezed: required resistance sends any remaining shortage to the
        // hero's top guard (which can always yield upward) instead of into the
        // text the state exists to deliver.
        block.setContentCompressionResistancePriority(.required, for: .vertical)
        block.isHidden = true
        view.addSubview(block)
        noBalanceCenterBlock = block

        // Sit under the eyebrow caps — V3 moved the name label above the clock
        // (#225), so the eyebrow is the hero's bottom edge.
        //
        // Three constraints, not one (#547). The old single `.defaultHigh` pin
        // was the whole defect: paired with the required "stay above the bottom
        // stack" rule it described a layout with no solution on a tight column,
        // and the solver resolved that by dropping the pin and printing the
        // warning over the clock. The floor below is REQUIRED, so no amount of
        // pressure can put the block on the hero; the design gap keeps its
        // place at `.defaultHigh`, and the room now comes from the hero sliding
        // up plus the fit pass below.
        let topFloor = block.topAnchor.constraint(
            greaterThanOrEqualTo: wakeUpCapsLabel.bottomAnchor, constant: AppSpacing.sp2
        )
        let preferred = block.topAnchor.constraint(
            equalTo: wakeUpCapsLabel.bottomAnchor, constant: AppSpacing.sp6
        )
        preferred.priority = .defaultHigh
        // While the state is off the block is hidden and nothing else places
        // it; a priority-250 twin keeps the layout unambiguous.
        let idle = block.topAnchor.constraint(
            equalTo: wakeUpCapsLabel.bottomAnchor, constant: AppSpacing.sp6
        )
        idle.priority = UILayoutPriority(250)

        noBalanceColumn.blockTopFloor = topFloor
        noBalanceColumn.blockTopPreferred = preferred
        noBalanceColumn.blockIdleTop = idle

        NSLayoutConstraint.activate([
            block.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            idle,
            block.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            block.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset)
        ])
    }

    // MARK: - State swap

    /// Hand the column over to the no-balance rules, or give it back.
    ///
    /// Called from `refreshNoBalanceVisibility()` (the affordability swap) and
    /// from `showSnoozedChrome(true)`, which force-hides the block so the
    /// countdown owns the screen — the constraints have to step aside with it,
    /// otherwise the hero would stay squeezed under a block nobody can see.
    func setNoBalanceColumnActive(_ active: Bool) {
        let column = noBalanceColumn
        guard column.isActive != active else { return }
        column.isActive = active

        column.heroDesignCenterY?.isActive = !active
        column.heroCeiling?.isActive = active
        column.heroPreferredCenterY?.isActive = active
        column.blockIdleTop?.isActive = !active
        column.blockTopFloor?.isActive = active
        column.blockTopPreferred?.isActive = active
        column.blockBottom?.isActive = active

        if active {
            column.bellTopGuard?.isActive = column.bellReserved
            column.nameTopGuard?.isActive = !column.bellReserved
            view.setNeedsLayout()
        } else {
            resetNoBalanceColumnFit()
        }
    }

    // MARK: - Fit

    /// Pick the largest hero that fits the space between the header row and the
    /// bottom stack. Runs from `viewDidLayoutSubviews`, where both neighbours
    /// have their final frames.
    ///
    /// Converges in one extra pass and cannot loop: the space it measures comes
    /// from the header row and the bottom stack, and neither depends on the
    /// clock's point size.
    func updateNoBalanceColumnFit() {
        let column = noBalanceColumn
        guard column.isActive,
              let block = noBalanceCenterBlock,
              let bottomStack = noBalanceContainer,
              view.bounds.height > 0 else { return }

        let top = topHeaderRow.frame.maxY + Self.noBalanceColumnHeaderGap
        let bottom = bottomStack.frame.minY - AppSpacing.sp4
        let available = bottom - top - Self.noBalanceColumnSafety
        guard available > 0 else { return }

        // A `.custom` photo theme already hides the tile; there is nothing to
        // keep a slot open for in that case.
        let bellIsThemed = firingPalette != nil
        let bellSlot = SPFiringBellTile.outerSide + AppSpacing.sp4
        let rest = noBalanceColumnHeightWithoutClock(block: block)

        var reserveBell = bellIsThemed
        var size = Self.noBalanceClockSize(
            fitting: available - rest - (reserveBell ? bellSlot : 0),
            text: timeLabel.text
        )
        // The tile is decorative and the canon column carries none in this
        // state — it goes before the clock stops reading as the hero.
        if reserveBell && size < Self.noBalanceClockKeepsBell {
            reserveBell = false
            size = Self.noBalanceClockSize(fitting: available - rest, text: timeLabel.text)
        }
        applyNoBalanceColumnFit(clockSize: size, reserveBell: reserveBell)
    }

    /// Everything in the column except the clock, at its design spacing and its
    /// NATURAL height.
    ///
    /// Every term is a fitting size, never a laid-out frame. Frames are the
    /// output of the very constraints this measurement feeds, and they are what
    /// the solver squeezes when it runs short: reading `block.bounds.height`
    /// back understated the column by exactly the amount already lost, the next
    /// pass sized the clock to that understatement, and the deficit settled into
    /// the warning as a 9pt overflow of its own body text (caught by this
    /// suite's first green-looking CI run on the compact screen).
    private func noBalanceColumnHeightWithoutClock(block: UIView) -> CGFloat {
        let width = block.bounds.width > 0
            ? block.bounds.width
            : view.bounds.width - AppSpacing.sp4 * 2
        let blockHeight = block.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return nameLabel.intrinsicContentSize.height
            + AppSpacing.sp3            // name → clock
            + AppSpacing.sp3            // clock → caps
            + wakeUpCapsLabel.intrinsicContentSize.height
            + AppSpacing.sp6            // caps → block, the design gap
            + blockHeight
    }

    private func applyNoBalanceColumnFit(clockSize: CGFloat, reserveBell: Bool) {
        let column = noBalanceColumn
        if abs(timeLabel.font.pointSize - clockSize) > 0.5 {
            timeLabel.font = Self.noBalanceClockFont(size: clockSize)
        }

        // Touch the constraints only on a real flip: re-activating a constraint
        // that is already active dirties layout, and dirtying layout from inside
        // `viewDidLayoutSubviews` is how a layout loop starts.
        guard column.bellReserved != reserveBell else { return }
        column.bellReserved = reserveBell
        bellTile.isHidden = !reserveBell
        column.bellToName?.isActive = reserveBell
        column.bellTopGuard?.isActive = reserveBell
        column.nameTopGuard?.isActive = !reserveBell
    }

    /// Put the hero back the way the normal screen draws it.
    private func resetNoBalanceColumnFit() {
        let column = noBalanceColumn
        column.bellReserved = true
        timeLabel.font = Self.noBalanceClockFont(size: AppTypography.clockXl.pointSize)
        // The theme, not us, decides whether the tile shows at all.
        bellTile.isHidden = firingPalette == nil
        column.bellToName?.isActive = true
        column.bellTopGuard?.isActive = false
        column.nameTopGuard?.isActive = false
        view.setNeedsLayout()
    }

    // MARK: - Clock metrics

    static func noBalanceClockFont(size: CGFloat) -> UIFont {
        AppTypography.clockXl.monospacedDigit().withSize(size)
    }

    /// Largest point size whose rendered line still fits `height`.
    ///
    /// Text height is linear in point size, so one measurement of the design
    /// font is enough; the result is rounded DOWN and the caller has already
    /// held back `noBalanceColumnSafety` on top of that.
    static func noBalanceClockSize(fitting height: CGFloat, text: String?) -> CGFloat {
        let full = AppTypography.clockXl.pointSize
        let natural = noBalanceClockHeight(size: full, text: text)
        guard natural > 0 else { return full }
        guard height < natural else { return full }
        let scaled = (full * height / natural).rounded(.down)
        return min(full, max(noBalanceClockFloor, scaled))
    }

    static func noBalanceClockHeight(size: CGFloat, text: String?) -> CGFloat {
        let probe = (text.map { $0.isEmpty ? "00:00" : $0 } ?? "00:00") as NSString
        return ceil(probe.size(withAttributes: [.font: noBalanceClockFont(size: size)]).height)
    }
}

// MARK: - Column storage

private var noBalanceColumnKey: UInt8 = 0

extension AlarmFiringViewController {
    /// The column's constraint bundle, created on first use so `+Layout` can
    /// hand over its two constraints before this file builds the rest.
    var noBalanceColumn: AlarmFiringNoBalanceColumn {
        if let existing = objc_getAssociatedObject(self, &noBalanceColumnKey)
            as? AlarmFiringNoBalanceColumn {
            return existing
        }
        let created = AlarmFiringNoBalanceColumn()
        objc_setAssociatedObject(
            self,
            &noBalanceColumnKey,
            created,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return created
    }
}
