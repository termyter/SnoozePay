import UIKit

/// Progressive-snooze UI for the firing screen — extracted from
/// `AlarmFiringViewController` so the main type stays under SwiftLint's
/// `type_body_length` cap (mirrors the same pattern used by the +Audio file).
///
/// V2 spec (`SPDawnV3.jsx` lines 215–225): when `alarm.progressiveScale ==
/// true` the firing screen mounts an indicator pill ("Прогрессив · N-е
/// откладывание") above the snooze CTA, with a pain300 PulseDot to its left,
/// and a single-line history ticker ("сегодня: −50 → −100 → −200 ₽") below.
/// The snooze CTA itself cross-fades from warn → pain as the user keeps
/// snoozing. None of this is touched for default alarms — the +Progressive
/// installer is a no-op via guard at the call site.
extension AlarmFiringViewController {

    /// Build the progressive-snooze indicator pill + history ticker stack
    /// and pin it horizontally to the screen-inset. Pulse animation on the
    /// dot is started here once — no need to restart on `updateUI()`.
    /// Returns the stack so `setupUI` can wire it into the bottom layout.
    func installProgressiveStack(inset: CGFloat) -> UIStackView {
        // Pill: pain-toned per V2 spec line 217–222. Caps text re-titled on
        // every updateUI. The leading dot is drawn as a sibling 8pt circle
        // view rather than via `SPPill(icon:)` because we need the dot to
        // host its own pulse animation while the pill keeps its background
        // / text styling untouched.
        let pill = SPPill(text: "Прогрессив · 1-е откладывание", tone: .pain)
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

        let ticker = UILabel()
        ticker.translatesAutoresizingMaskIntoConstraints = false
        ticker.font = AppTypography.meta.monospacedDigit()
        ticker.textColor = AppColors.fg3
        ticker.textAlignment = .center
        ticker.numberOfLines = 1
        ticker.lineBreakMode = .byTruncatingHead
        ticker.adjustsFontSizeToFitWidth = true
        ticker.minimumScaleFactor = 0.7
        ticker.isHidden = true
        historyTicker = ticker

        let stack = UIStackView(arrangedSubviews: [pillRow, ticker])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp2
        view.addSubview(stack)
        progressiveStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])

        startPulseAnimation(on: dot)
        return stack
    }

    /// Refresh the indicator pill text + the history ticker. Called from
    /// `updateUI()` so the indicator counts up (`1-й` → `2-й` → ...) and
    /// the ticker grows as the user keeps snoozing.
    func updateProgressiveChrome() {
        let nextIndex = viewModel.snoozeCount + 1
        progressivePill?.setText("Прогрессив · \(nextIndex)-е откладывание")

        guard let ticker = historyTicker else { return }
        let past = viewModel.pastPenalties
        if past.isEmpty {
            // No history yet — keep the pill, hide the ticker.
            ticker.isHidden = true
            ticker.text = nil
            return
        }
        var parts = past.map { "−\(Self.formatPenalty($0))" }
        parts.append("−\(Self.formatPenalty(viewModel.currentPenalty))")
        // Trailing currency glyph after the last amount only — keeps the
        // arrow chain visually balanced ("−50 → −100 → −200 ₽").
        if let last = parts.last {
            parts[parts.count - 1] = "\(last) ₽"
        }
        ticker.text = "сегодня: \(parts.joined(separator: " → "))"
        ticker.isHidden = false
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

    /// Format a penalty amount for the history ticker. The ticker is a
    /// glanceable single-line summary, so we strip thousand separators and
    /// the currency glyph (`formattedRubles` adds " ₽" to each value).
    /// Trailing fraction is dropped — the doubling rule produces integers.
    private static func formatPenalty(_ amount: Double) -> String {
        let intValue = Int(amount.rounded())
        return "\(intValue)"
    }
}
