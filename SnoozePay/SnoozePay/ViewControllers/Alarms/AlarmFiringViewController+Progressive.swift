import UIKit

/// Progressive-snooze UI for the firing screen — extracted from
/// `AlarmFiringViewController` so the main type stays under SwiftLint's
/// `type_body_length` cap (mirrors the same pattern used by the +Audio file).
///
/// V2 spec (`SPDawnV3.jsx` lines 114-136 + 216-221): the indicator pill
/// «Прогрессив · {n}-й поспать ещё» (with a pain300 PulseDot) is hidden until
/// the first snooze, and below it a row of coloured mini-pill tickers
/// summarises today's charges (amber < 200 ₽ / red ≥ 200 ₽) separated by «·».
/// The snooze CTA itself stays GOLD on every step (#288). None of this chrome
/// is mounted for default alarms — the installer is a no-op via the call site.
extension AlarmFiringViewController {

    /// Build the progressive-snooze indicator pill + history ticker stack and
    /// pin it horizontally to the screen-inset. Pulse animation on the dot is
    /// started here once — no need to restart on `updateUI()`. Returns the
    /// stack so `setupUI` can wire it into the centre hero layout.
    func installProgressiveStack(inset: CGFloat) -> UIStackView {
        // Pill: pain-toned per V2 spec line 217-222. Caps text re-titled on
        // every updateUI. The leading dot is drawn as a sibling 8pt circle
        // view rather than via `SPPill(icon:)` because we need the dot to
        // host its own pulse animation while the pill keeps its background
        // / text styling untouched.
        // Seeded through the same helper `updateUI()` uses, so the initial
        // wording cannot drift from the wording of every later refresh.
        let pill = SPPill(text: Self.progressivePillText(snoozeCount: 0), tone: .pain)
        pill.translatesAutoresizingMaskIntoConstraints = false
        progressivePill = pill

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = AppColors.pain300
        dot.layer.cornerRadius = 4
        dot.isUserInteractionEnabled = false
        progressivePulseDot = dot

        // Wrap pill + dot so the dot sits 6pt to the leading edge of the
        // pill while staying centered horizontally as a group.
        let pillRow = UIStackView(arrangedSubviews: [dot, pill])
        pillRow.axis = .horizontal
        pillRow.spacing = AppSpacing.sp1 + 2   // 6pt — matches SPPill's internal gap recipe
        pillRow.alignment = .center
        // Hidden until the first snooze (`SPDawnV3.jsx:216`). `updateUI`
        // un-hides it once `snoozeCount > 0`.
        pillRow.isHidden = true
        progressivePillRow = pillRow

        // Ticker chip row — rebuilt on every updateUI from the VM's history.
        // Starts empty / hidden; the container reserves the slot in the stack.
        let tickerContainer = UIStackView()
        tickerContainer.axis = .vertical
        tickerContainer.alignment = .center
        historyTickerContainer = tickerContainer

        let stack = UIStackView(arrangedSubviews: [pillRow, tickerContainer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        view.addSubview(stack)
        progressiveStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])

        startPulseAnimation(on: dot)
        return stack
    }

    /// Indicator pill copy «Прогрессив · {n}-й поспать ещё» where
    /// n = snoozeCount + 1 (`SPDawnV3.jsx:219-221`). Pure function so the copy
    /// is unit-testable without loading the view hierarchy.
    static func progressivePillText(snoozeCount: Int) -> String {
        Localized.format("firing.progressive.pill", snoozeCount + 1)
    }

    /// `true` when the indicator pill should be visible — only after the first
    /// snooze (`SPDawnV3.jsx:216`). Pure for the same testability reason.
    static func progressivePillVisible(snoozeCount: Int) -> Bool {
        snoozeCount > 0
    }

    /// Refresh the indicator pill text + visibility and rebuild the history
    /// ticker chips. Called from `updateUI()` so the indicator counts up
    /// (`1-й` → `2-й` → ...) and the chip row grows as the user keeps snoozing.
    func updateProgressiveChrome() {
        progressivePill?.setText(Self.progressivePillText(snoozeCount: viewModel.snoozeCount))
        progressivePillRow?.isHidden = !Self.progressivePillVisible(snoozeCount: viewModel.snoozeCount)

        rebuildTicker()
    }

    /// Replace the ticker chip row in place with one built from the VM's
    /// current penalty history. Coloured mini-pills with «·» separators per
    /// `SPDawnV3.jsx:114-136`.
    ///
    /// The chips list money actually taken (`pastPenalties` now reads the
    /// ledger, #400), while the pill above — and the `ladderSteps` rungs, which
    /// keep marking a refunded rung `done` — count ATTEMPTS. So a snooze that
    /// failed to schedule and was refunded advances the pill and lights its
    /// rung, but leaves no chip. That asymmetry is intended: pill and ladder
    /// answer "which rung do I pay next", the chips are a receipt of money
    /// actually gone. The morning summary reconciles the two by naming the
    /// reversal outright (`WokeMorningContent.partiallyReversed`), which is
    /// where the user would otherwise be unable to square the numbers. An
    /// unreadable ledger yields no chips, hiding the row rather than inventing
    /// amounts.
    private func rebuildTicker() {
        guard let container = historyTickerContainer else { return }
        container.arrangedSubviews.forEach {
            container.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let entries = SPFiringTicker.entries(from: viewModel.pastPenalties)
        guard !entries.isEmpty else {
            container.isHidden = true
            return
        }
        container.isHidden = false
        container.addArrangedSubview(SPFiringTicker.makeRow(for: entries))
    }

    /// 0.4 → 1.0 opacity autoreverse pulse, 900ms each leg. Driven via
    /// CABasicAnimation rather than UIView.animate so the layer pulse keeps
    /// running while UIKit runs touch / scroll animations elsewhere.
    private func startPulseAnimation(on dot: UIView) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.4
        pulse.toValue = 1.0
        pulse.duration = SPSupport.durationAnxious
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.layer.add(pulse, forKey: "progressivePulse")
    }
}
