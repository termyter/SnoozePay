import UIKit

// MARK: - View-stack + constraint builders
//
// Extracted from `AlarmFiringViewController.swift` (#182) so the host file
// stays under SwiftLint's `file_length` and `type_body_length` caps. The
// initial `setupUI` constructs the time/name/snooze/dismiss/banner stack and
// hands it off to the +Progressive / +NoBalance extensions for their
// respective overlays.

extension AlarmFiringViewController {

    /// Build the firing-screen view stack and pin everything to the screen.
    /// Called once from `viewDidLoad`. Behaviour mirrors the original
    /// `setupUI()` — only the location moved.
    func buildFiringLayout() {
        view.backgroundColor = UIColor(rgb: 0x050912)
        installThemedBackground()

        // VM exposes `currentPenalty` as `Double`; wrap in `Decimal` so
        // `SPSnoozePrice.formattedRubles()` does the locale-aware format.
        // Pick the initial tone based on the alarm config — progressive
        // alarms start at intensity 0 (still pure warn) and ramp up as the
        // user snoozes.
        let initialTone: SPSnoozePrice.Tone = viewModel.isProgressiveActive
            ? .progressive(intensity: viewModel.progressiveIntensity)
            : .warn
        let snooze = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: initialTone,
            hint: nil
        )
        snooze.translatesAutoresizingMaskIntoConstraints = false
        snooze.onTap = { [weak self] in self?.snoozeTapped() }
        view.addSubview(snooze)
        snoozeCTA = snooze

        view.addSubview(timeLabel)
        view.addSubview(nameLabel)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        view.addSubview(dismissButton)
        view.addSubview(audioWarningBanner)

        let inset: CGFloat = AppSpacing.sp5      // 20pt — Dawn spec
        let gap: CGFloat = AppSpacing.sp3         // 12pt — Dawn spec

        // Progressive escalation chrome — only mounted for alarms with the
        // doubling-penalty toggle. The default flow stays exactly as #138.
        // Anchor the audio-fallback banner to the chrome's top so the banner
        // never overlaps the indicator when both are on screen.
        let bannerBottomAnchor: NSLayoutYAxisAnchor
        if viewModel.isProgressiveActive {
            let stack = installProgressiveStack(inset: inset)
            NSLayoutConstraint.activate([
                stack.bottomAnchor.constraint(equalTo: snooze.topAnchor, constant: -AppSpacing.sp3)
            ])
            bannerBottomAnchor = stack.topAnchor
        } else {
            bannerBottomAnchor = snooze.topAnchor
        }

        activateMainConstraints(snooze: snooze, bannerBottomAnchor: bannerBottomAnchor, inset: inset, gap: gap)

        // No-balance stack overlays the same bottom area as the snooze CTA +
        // dismiss group. Initially hidden — `updateUI()` flips visibility
        // based on `viewModel.canSnooze`. Building it eagerly keeps the
        // affordability swap a single property toggle (no constraint churn)
        // when the user tops up mid-firing and crosses the threshold.
        installNoBalanceStack(inset: inset, gap: gap)

        updateUI()
    }

    /// Pin every always-mounted element. Split out of `buildFiringLayout` so
    /// neither function trips SwiftLint's function_body_length (#182).
    private func activateMainConstraints(
        snooze: SPSnoozePrice,
        bannerBottomAnchor: NSLayoutYAxisAnchor,
        inset: CGFloat,
        gap: CGFloat
    ) {
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            nameLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: AppSpacing.sp2),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset),

            audioWarningBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            audioWarningBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            audioWarningBanner.bottomAnchor.constraint(equalTo: bannerBottomAnchor, constant: -AppSpacing.sp4),

            snooze.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            snooze.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            snooze.bottomAnchor.constraint(equalTo: dismissButton.topAnchor, constant: -gap),

            dismissButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            dismissButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            )
        ])
    }

    /// Update the warm-glow frame on every layout pass so the radial halo
    /// stays anchored just below the bottom edge regardless of orientation
    /// changes (the bounds-driven math used to live inline in
    /// `viewDidLayoutSubviews`).
    func updateGlowFrame() {
        let bounds = view.bounds
        let glowSize = CGSize(width: bounds.width * 1.2, height: bounds.height * 0.6)
        warmGlowLayer.frame = CGRect(
            x: -(glowSize.width - bounds.width) / 2,
            y: bounds.height - glowSize.height * 0.55,
            width: glowSize.width,
            height: glowSize.height
        )
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initializer mirrored from
    /// `AlarmFiringViewController.swift`. `private` is file-scope in Swift,
    /// so each file that needs the helper carries its own copy (#182).
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
