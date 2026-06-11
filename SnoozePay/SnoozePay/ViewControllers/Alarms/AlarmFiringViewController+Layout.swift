import UIKit

// MARK: - View-stack + constraint builders (V2 Dawn)
//
// Extracted from `AlarmFiringViewController.swift` so the host file stays
// under SwiftLint's `file_length` and `type_body_length` caps. V2 spec lives
// in `docs/design/v2-handoff/components/SPScreensV2.jsx` lines 37–103
// (FiringDawn) and `SPDawnV3.jsx` (FiringDawnV3) — top-bar with date + balance
// pill, centered hero (clock + caps "Подъём"), bottom CTAs.

extension AlarmFiringViewController {

    /// Build the firing-screen view stack and pin everything to the screen.
    /// Called once from `viewDidLoad`. Composes:
    /// 1. Atmospheric `SPDawnBackgroundView` filling the bounds.
    /// 2. Top header — date caps left, balance pill right.
    /// 3. Centered hero — 96pt mono clock, "Подъём" caps, alarm name.
    /// 4. Progressive chrome (only when alarm.progressiveScale).
    /// 5. Audio warning banner, snooze CTA, ghost dismiss.
    /// 6. No-balance stack (hidden by default).
    func buildFiringLayout() {
        view.backgroundColor = .black
        installThemedBackground()
        installTopHeader()
        installHeroCenter()

        // VM exposes `currentPenalty` as `Double`; wrap in `Decimal` so
        // `SPSnoozePrice.formattedRubles()` does the locale-aware format.
        // Tone defaults to warn; progressive alarms cross-fade toward pain
        // as snoozeCount climbs.
        let initialTone: SPSnoozePrice.Tone = viewModel.isProgressiveActive
            ? .progressive(intensity: viewModel.progressiveIntensity)
            : .warn
        let snooze = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: initialTone,
            hint: snoozeHintText()
        )
        snooze.translatesAutoresizingMaskIntoConstraints = false
        snooze.onTap = { [weak self] in self?.snoozeTapped() }
        view.addSubview(snooze)
        snoozeCTA = snooze

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        view.addSubview(dismissButton)
        view.addSubview(audioWarningBanner)

        let inset: CGFloat = AppSpacing.sp4      // 16pt — V2 spec uses sp4 edge padding
        let gap: CGFloat = 10                     // 10pt CTA gap — matches SPScreensV2 line 91 ("gap: 12")

        // Progressive escalation chrome — only mounted for alarms with the
        // doubling-penalty toggle. The default flow stays clean. Anchor the
        // audio-fallback banner to the chrome's top so the banner never
        // overlaps the indicator when both are on screen.
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
        // affordability swap a single property toggle (no constraint churn).
        installNoBalanceStack(inset: inset, gap: AppSpacing.sp3)

        updateUI()
    }

    /// Install the atmospheric Dawn background — fills the full bounds and
    /// sits at the bottom of the view tree.
    private func installDawnBackground() {
        view.insertSubview(dawnBackgroundView, at: 0)
        NSLayoutConstraint.activate([
            dawnBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            dawnBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dawnBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dawnBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Install the top-bar row: caps date label left, balance pill right.
    /// Both elements are added unconditionally; the +Theme extension can
    /// hide the whole row when a custom-photo theme is in effect.
    private func installTopHeader() {
        let dateString = Self.dateFormatter.string(from: Date())
        dateLabel.attributedText = NSAttributedString(
            string: dateString.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ]
        )

        // Initial balance pill — money tone with current balance. Re-built in
        // `updateBalancePill()` when the tone needs to flip to pain (zero).
        let balance = Int(viewModel.balance.rounded())
        let initialTone: SPPill.Tone = balance == 0 ? .pain : .money
        let pill = SPPill(
            text: "Баланс \(MoneyFormatter.string(balance))",
            tone: initialTone,
            icon: SPIcons.coin(size: 12)
        )
        pill.translatesAutoresizingMaskIntoConstraints = false
        balancePill = pill

        topHeaderRow.addArrangedSubview(dateLabel)
        topHeaderRow.addArrangedSubview(pill)
        view.addSubview(topHeaderRow)

        NSLayoutConstraint.activate([
            topHeaderRow.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sp4
            ),
            topHeaderRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp4),
            topHeaderRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp4)
        ])
    }

    /// Install the centered hero: clock + "Подъём" caps + optional name.
    /// The caps label is below the clock with 12pt gap per spec line 81.
    private func installHeroCenter() {
        view.addSubview(timeLabel)
        view.addSubview(wakeUpCapsLabel)
        view.addSubview(nameLabel)
    }

    /// Pin every always-mounted element. Split out of `buildFiringLayout` so
    /// neither function trips SwiftLint's function_body_length.
    private func activateMainConstraints(
        snooze: SPSnoozePrice,
        bannerBottomAnchor: NSLayoutYAxisAnchor,
        inset: CGFloat,
        gap: CGFloat
    ) {
        NSLayoutConstraint.activate([
            // Center the clock + caps stack vertically — pull it slightly
            // above geometric center so the bottom CTAs have generous room.
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            wakeUpCapsLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: AppSpacing.sp3),
            wakeUpCapsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            nameLabel.topAnchor.constraint(equalTo: wakeUpCapsLabel.bottomAnchor, constant: AppSpacing.sp2),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset),

            audioWarningBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            audioWarningBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            audioWarningBanner.bottomAnchor.constraint(equalTo: bannerBottomAnchor, constant: -AppSpacing.sp3),

            snooze.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            snooze.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            snooze.bottomAnchor.constraint(equalTo: dismissButton.topAnchor, constant: -gap),

            dismissButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            dismissButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp7   // 32pt bottom inset per V2 spec
            )
        ])
    }

    // MARK: - Background install entry point
    //
    // The host VC's `viewDidLoad → buildFiringLayout` calls
    // `installThemedBackground()` (in +Theme); for the default Dawn case the
    // theme installer routes to `installDawnBackground()` here. Keeping the
    // entry point in +Theme means custom-photo themes can fully replace the
    // Dawn background by swapping the install path.
    func installDawnAtmosphericBackground() {
        installDawnBackground()
    }

    // MARK: - Date formatter
    //
    // Captured once so we don't rebuild a `DateFormatter` on every firing.
    // Locale fixed to `ru_RU` so "Пт · 27 апр" reads as in the spec; format
    // "EEE · d MMM" matches `SPScreensV2.jsx` line 64.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEE · d MMM"
        return formatter
    }()
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initializer mirrored from
    /// `AlarmFiringViewController.swift`. `private` is file-scope in Swift,
    /// so each file that needs the helper carries its own copy.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
