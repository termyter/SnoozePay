import UIKit

// MARK: - Snoozed firing state (#226)
//
// After a foreground «Поспать ещё» tap the firing screen does NOT dismiss —
// it transitions in place into the "отложено" state described by
// `docs/design/v2-handoff/components/SPFiringThemeSnoozed.jsx`:
//   • the big live clock is replaced by a live mm:ss countdown to the next ring,
//   • the bell tile dims (.7) and gains a `zZ` badge,
//   • the hero name reads "… · отложено до 07:05",
//   • a fly-up «−N ₽» rises over the (already-decremented) balance pill,
//   • progressive alarms also surface a "Прогрессив · N-й поспать ещё" pill +
//     the 4-rung charge ladder.
// At countdown zero the chrome tears down and the active firing UI returns.
//
// The theme only affects accents — colours are pulled from `firingPalette`
// exactly as the active firing screen does. Storage lives in associated
// objects (the host type body is at the SwiftLint `type_body_length` cap).

extension AlarmFiringViewController {

    // MARK: - Entry / exit

    /// Switch the live firing screen into the snoozed state in place (no VC
    /// recreation). Called from `snoozeTapped()` after a successful charge.
    func enterSnoozedState() {
        guard !isSnoozedStateActive else { return }
        // Defensive: if the next ring is already due (clock skew, or a
        // backgrounded-then-foregrounded VC where the snooze interval has
        // already elapsed), there's nothing to count down to — stay in the
        // active firing UI rather than installing a timer that fires once to
        // undo itself and flashes 00:00.
        guard viewModel.secondsUntilNextRing(from: Date()) > 0 else { return }
        isSnoozedStateActive = true

        installSnoozedChromeIfNeeded()
        refreshSnoozedChrome()
        showSnoozedChrome(true)
        flyUpLastCharge()
        startCountdownTicker()
    }

    /// Tear down the snoozed chrome and restore the active firing UI — the big
    /// clock re-appears, the countdown / ladder / zZ badge hide, and the alarm
    /// "rings again" visually. Audio re-fire is owned by the scheduler.
    func exitSnoozedState() {
        guard isSnoozedStateActive else { return }
        isSnoozedStateActive = false

        countdownTimer?.invalidate()
        countdownTimer = nil
        showSnoozedChrome(false)
        // Restore the active hero name — `refreshSnoozedChrome` overwrote it with
        // the "… · отложено до 07:05" suffix on entry, and `showSnoozedChrome`
        // only toggles the clock/eyebrow/badge, not the name. Without this the
        // active firing UI returns with a stale "отложено до …" label (#226 QA).
        nameLabel.text = viewModel.heroTitle
    }

    /// Invalidate the countdown timer on teardown — mirrors the `clockTimer`
    /// teardown in `viewDidDisappear`. Call from the host's `viewDidDisappear`.
    func teardownSnoozedTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Chrome install

    private func installSnoozedChromeIfNeeded() {
        guard snoozedCountdownLabel == nil else { return }

        let countdown = UILabel()
        countdown.font = AppTypography.clockXl.monospacedDigit()
        countdown.textColor = .white
        countdown.textAlignment = .center
        countdown.adjustsFontSizeToFitWidth = true
        countdown.minimumScaleFactor = 0.7
        countdown.translatesAutoresizingMaskIntoConstraints = false
        // Same warm halo as the active clock; re-tinted to the theme below.
        countdown.layer.shadowColor = (firingPalette?.timeShadowColor ?? .white).cgColor
        countdown.layer.shadowOpacity = firingPalette?.timeShadowOpacity ?? 0.2
        countdown.layer.shadowRadius = 30
        countdown.layer.shadowOffset = CGSize(width: 0, height: 4)
        countdown.layer.masksToBounds = false
        countdown.isHidden = true
        countdown.accessibilityIdentifier = "firing.countdown"
        view.addSubview(countdown)
        snoozedCountdownLabel = countdown

        let ladder = makeLadderStack()
        snoozedLadderStack = ladder

        let pill = makeProgressivePill()
        snoozedProgressivePill = pill

        // Vertical stack: progressive pill (mt 14) then ladder (mt 16).
        let center = UIStackView(arrangedSubviews: [pill, ladder])
        center.translatesAutoresizingMaskIntoConstraints = false
        center.axis = .vertical
        center.alignment = .center
        center.spacing = AppSpacing.sp4 - 2   // ≈16; the 14/16 deltas are within token tolerance
        center.isHidden = true
        view.addSubview(center)
        snoozedCenterStack = center

        installZzBadge()

        NSLayoutConstraint.activate([
            // Countdown takes the big clock's slot.
            countdown.centerXAnchor.constraint(equalTo: timeLabel.centerXAnchor),
            countdown.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            countdown.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp4),
            countdown.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp4),

            center.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            center.topAnchor.constraint(equalTo: countdown.bottomAnchor, constant: AppSpacing.sp4 - 2)
        ])
    }

    // MARK: - Visibility

    /// Swap between the active firing hero and the snoozed chrome. Progressive
    /// pill + ladder only show for progressive alarms; the countdown + zZ badge
    /// always show in the snoozed state.
    private func showSnoozedChrome(_ snoozed: Bool) {
        // Active-state elements hidden while snoozed.
        timeLabel.isHidden = snoozed
        wakeUpCapsLabel.isHidden = snoozed
        progressiveStack?.isHidden = snoozed

        // Snoozed-state elements.
        snoozedCountdownLabel?.isHidden = !snoozed
        snoozedZzBadge?.isHidden = !snoozed
        bellTile.alpha = snoozed ? 0.7 : 1.0

        let showLadder = snoozed && viewModel.isProgressiveActive
        snoozedCenterStack?.isHidden = !showLadder
    }

    // MARK: - Refresh (text + ladder + accents)

    /// Re-render the snoozed chrome from the current VM state. Updates the hero
    /// name suffix, countdown label, progressive pill copy and the ladder rungs.
    func refreshSnoozedChrome() {
        guard isSnoozedStateActive else { return }
        let now = Date()
        nameLabel.text = viewModel.snoozedHeroTitle(after: now)
        updateCountdownLabel(now: now)

        guard viewModel.isProgressiveActive else { return }
        snoozedProgressivePill?.text =
            AlarmFiringViewController.progressivePillText(snoozeCount: viewModel.snoozeCount)
        rebuildLadder()
    }

    // MARK: - Countdown ticker

    private func startCountdownTicker() {
        countdownTimer?.invalidate()
        updateCountdownLabel(now: Date())
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
    }

    private func tickCountdown() {
        let now = Date()
        updateCountdownLabel(now: now)
        if viewModel.secondsUntilNextRing(from: now) <= 0 {
            exitSnoozedState()
        }
    }

    private func updateCountdownLabel(now: Date) {
        let seconds = viewModel.secondsUntilNextRing(from: now)
        snoozedCountdownLabel?.text = AlarmFiringViewModel.countdownText(seconds: seconds)
    }

    // MARK: - Fly-up «−N ₽»

    /// Animate a transient «−N ₽» label rising over the balance pill (the pill
    /// itself already shows the decremented balance). 1500ms: fade-in + rise,
    /// then fade-out + continued rise, matching the JSX keyframes.
    private func flyUpLastCharge() {
        guard let pill = balancePill else { return }
        let charge = Int(viewModel.lastChargeAmount.rounded())
        guard charge > 0 else { return }

        let label = UILabel()
        label.text = "−\(charge) ₽"
        label.font = AppFonts.mono(.bold, 14)
        label.textColor = UIColor(snoozedRGB: 0xFF7A6B)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: pill.topAnchor, constant: -AppSpacing.sp1)
        ])
        label.alpha = 0
        label.transform = CGAffineTransform(translationX: 0, y: 6)

        // opacity 0/+6 → 1/−8 → 1/−28 → 0/−36 over 1500ms.
        UIView.animateKeyframes(withDuration: 1.5, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                label.alpha = 1
                label.transform = CGAffineTransform(translationX: 0, y: -8)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.6) {
                label.transform = CGAffineTransform(translationX: 0, y: -28)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                label.alpha = 0
                label.transform = CGAffineTransform(translationX: 0, y: -36)
            }
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer for the snoozed-state colours. File-scoped
    /// copy — `private` is file-scope in Swift, mirroring the identical helpers
    /// in the sibling +Layout / +Theme files (the brand-token `UIColor(hex:)`
    /// in AppColors is itself `private` and not visible across files).
    convenience init(snoozedRGB rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
