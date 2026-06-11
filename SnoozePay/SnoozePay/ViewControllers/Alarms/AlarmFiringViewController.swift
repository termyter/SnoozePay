import UIKit
import os

/// Fullscreen alarm firing screen — V2 Dawn redesign.
///
/// V2 (`docs/design/v2-handoff/components/SPDawnV3.jsx` + `SPScreensV2.jsx`
/// `FiringDawn`) elevates the original Dawn treatment with a three-layer
/// atmospheric background (base gradient + radial overlay + breathing sun)
/// plus a top header that surfaces the date and balance pill, and a centered
/// hero block with a 96pt mono clock and a "Подъём" caps label. The bottom
/// CTAs preserve the warn-tone snooze + ghost dismiss pair from #138 with a
/// tighter 10pt gap and 32pt bottom inset.
///
/// All existing audio + coordinator wiring (AudioService stacking guard,
/// vibration-fallback banner, snooze schedule failure alert, no-balance
/// recovery observer) is preserved verbatim from the V1 implementation —
/// this rewrite is the visual layer only, not a behaviour change.
class AlarmFiringViewController: UIViewController {

    // MARK: - ViewModel

    /// `internal` so the +Audio and +Progressive extensions in sibling files
    /// can read VM state during their UI updates.
    let viewModel: AlarmFiringViewModel

    // MARK: - Background

    /// V2 atmospheric background — three CAGradientLayers (base, overlay,
    /// breathing sun). Replaces the V1 `themeGradientLayer` + `warmGlowLayer`
    /// pair. `internal` so the +Theme extension can swap its tone when the
    /// alarm has a custom theme, and so +ViewLifecycle can attach the
    /// 4-second opacity breathing animation to the sun layer.
    let dawnBackgroundView = SPDawnBackgroundView(tone: .calm)

    /// Image view used when `viewModel.alarm.theme == .custom(_)`. Lives on
    /// the layer tree even when not in use (hidden) so the theme swap is a
    /// single visibility flip rather than a rebuild. `internal` so the
    /// +Theme extension can configure it.
    let themeImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    /// Translucent dim layer drawn over `.custom` photo backgrounds so the
    /// 96pt mono clock + warn snooze CTA keep enough contrast to remain
    /// legible against arbitrary user-picked imagery.
    let themeImageDimView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.isHidden = true
        return view
    }()

    /// Accent palette resolved from the alarm's theme (#225). Nil only for
    /// `.custom` photo themes — every stock theme (including Dawn) maps to a
    /// `FIRING_THEMES` entry. Written once by `installThemedBackground()`;
    /// read by the accent helpers in +Theme and by `updateAtmosphereTone()`.
    var firingPalette: AlarmFiringThemePalette?

    // MARK: - Top header (V2)

    /// Top-bar caps label "Пт · 27 апр" rendered left of the balance pill.
    /// Date is computed once on `viewDidLoad` (per spec — the firing screen
    /// is a snapshot of "when the alarm rang", not a live tick).
    let dateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.caps
        label.textColor = UIColor.white.withAlphaComponent(0.55)
        label.numberOfLines = 1
        return label
    }()

    /// "Баланс N ₽" pill on the right side of the top bar. Tone flips between
    /// `.money` (positive) and `.pain` (balance == 0). Re-rendered on every
    /// `updateUI()` because the balance is decremented mid-firing when the
    /// user snoozes (the firing flow dismisses on success, but for the
    /// progressive path the count climbs in place).
    var balancePill: SPPill?

    /// Container holding `dateLabel` + `balancePill`. `internal` so the
    /// +Theme extension can hide it when a `.custom` photo background is in
    /// use (the user picked a hero image; we don't want chrome over it).
    let topHeaderRow: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()

    // MARK: - Center hero

    /// 72×72 bell tile above the alarm name — V3 themed firing (#225).
    /// Gradient + ring are tinted from `firingPalette` in the +Theme accent
    /// pass; hidden for `.custom` photo themes so the image stays clean.
    let bellTile = SPFiringBellTile()

    /// 96pt mono clock — `AppTypography.clockXl` ultralight. `tabular-nums`
    /// equivalent applied via `.monospacedDigit()` so digit columns don't
    /// reflow on each tick. `internal` so the `+Layout` / `+ViewLifecycle`
    /// extensions can pin + update it.
    let timeLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.clockXl.monospacedDigit()
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        // Text shadow ≈ "0 4px 60px rgba(255,184,77,.20)" warm halo.
        label.layer.shadowColor = UIColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 1).cgColor
        label.layer.shadowOpacity = 0.20
        label.layer.shadowRadius = 30
        label.layer.shadowOffset = CGSize(width: 0, height: 4)
        label.layer.masksToBounds = false
        return label
    }()

    /// Caps eyebrow below the clock — "Пора вставать" / "Только встать".
    /// V3 tints it with the theme accent at 85% (`SPThemedFiring.jsx` line
    /// 167); the colour is applied in `updateAtmosphereTone()` because it
    /// flips to pain when the wallet drains.
    let wakeUpCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 1
        return label
    }()

    /// "Будни · 07:00" h3 title between the bell tile and the clock — V3
    /// places the alarm identity ABOVE the live time (`SPThemedFiring.jsx`
    /// line 147). `internal` so the `+Layout` extension can pin it.
    let nameLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h3
        label.textColor = UIColor.white.withAlphaComponent(0.92)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Big snooze CTA. Built in `setupUI` because its constructor needs
    /// VM-derived price + minutes that aren't valid at property-init time.
    /// Tone defaults to `.warn`; for `progressiveScale == true` alarms the
    /// VC swaps it to `.progressive(intensity:)` and bumps the intensity on
    /// every snooze tap. `internal` so the +Progressive extension can re-tone
    /// it on `updateUI()`.
    var snoozeCTA: SPSnoozePrice?

    /// `internal` so the +NoBalance extension can hide / show this when
    /// swapping between the normal (balance OK) and no-balance layouts.
    /// V2 spec calls for the full "Я встал — выключить" copy, ghost variant,
    /// lg size, full-width — matches `SPScreensV2.jsx` line 98.
    let dismissButton = SPButton(
        title: "Я встал — выключить",
        variant: .ghost,
        size: .lg,
        fullWidth: true
    )

    // MARK: - No-balance UI — shown when `viewModel.canSnooze == false`.
    //
    // The no-balance state replaces the snooze CTA + dismiss group with a
    // disabled snooze card on top, an Apple Pay 500 ₽ primary CTA, and a big
    // ghost "Я встал — выключить" secondary. All three are mounted
    // unconditionally so swapping is just a visibility flip — saves us from
    // rebuilding constraints when the user tops up mid-firing and crosses
    // the affordability threshold.

    /// Disabled snooze card shown above the Apple Pay CTA. Mirrors the
    /// `.warn` tone of the live card so the visual continuity reads as
    /// "this WAS the action you wanted, but it's locked".
    var noBalanceSnoozeCard: SPSnoozePrice?

    /// Apple Pay 500 ₽ primary CTA. Single-tap purchase via StoreKitService
    /// (SKU `com.snooze_pay.balance.499`); falls back to direct
    /// `BalanceService.topUp` when the StoreKit product list hasn't loaded
    /// yet (test / debug paths) so the wallet still credits end-to-end.
    var applePayNoBalanceButton: SPButton?

    /// Big ghost "Я встал — выключить" secondary. Calls `viewModel.dismiss()`
    /// the same way the normal-state dismissButton does — PM directive was
    /// that this MUST be a full-width lg button, not a small text link, so
    /// the half-asleep user can find it.
    var noBalanceDismissButton: SPButton?

    /// Small quiet/sm link "Выбрать другую сумму" rendered below the ghost
    /// dismiss. Routes to the existing `presentTopUpSheet()` for users who
    /// want a different amount than the 500 ₽ default.
    var chooseAmountLink: SPButton?

    /// Container stacking the no-balance views vertically. Hidden when the
    /// user can afford the next snooze; shown otherwise. Membership lets the
    /// +NoBalance extension hide a single view rather than four.
    var noBalanceContainer: UIStackView?

    /// Observer token for `BalanceService.balanceChangedNotification`. Drives
    /// auto-recovery: when the user tops up past the snooze threshold the
    /// no-balance stack hides and the normal Dawn snooze CTA returns. Removed
    /// in `deinit` so blocks don't leak across screen presentations.
    var balanceChangeObserver: NSObjectProtocol?

    /// Observer token for `StoreKitService.purchaseFailedNotification`.
    /// Surfaces the alert from the no-balance Apple Pay tap; the success
    /// path is handled implicitly via `balanceChangedNotification`.
    var purchaseFailedObserver: NSObjectProtocol?

    /// Re-entrancy guard for the Apple Pay tap so a double-tap can't kick
    /// off two purchases.
    var noBalancePurchaseInFlight: Bool = false

    // MARK: - Progressive UI — only mounted when `alarm.progressiveScale`.

    /// Container holding the indicator pill + history ticker. Built lazily
    /// inside `setupUI` so the default firing flow skips both views
    /// entirely — they never enter the layout pass.
    var progressiveStack: UIStackView?

    /// "Прогрессив · N-е откладывание" pill above the snooze CTA. Re-titled
    /// on every `updateUI()` so the label tracks `snoozeCount + 1`. V2 spec
    /// uses pain tone with an inline pulsing dot.
    var progressivePill: SPPill?

    /// Pulsing dot rendered to the left of `progressivePill`. CABasicAnimation
    /// drives a 0.4 → 1.0 opacity autoreverse pulse on 900ms cadence
    /// (`durationAnxious`).
    var progressivePulseDot: UIView?

    /// Single-line ticker rendered between the pill and the snooze CTA.
    /// `meta` typography, fg-3, mono digits — "сегодня: −50 → −100 → ..."
    /// Hidden when `snoozeCount == 0` (no history to show yet).
    var historyTicker: UILabel?

    /// Banner shown when AudioService falls back to vibration / silent mode.
    /// Hidden by default; surfaces only on `.silentBecauseConfigFailed` or
    /// `.vibrationOnly`. `internal` so the AudioState extension in the
    /// sibling file can update it.
    let audioWarningBanner: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = AppColors.pain500.withAlphaComponent(0.85)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.isAccessibilityElement = true
        label.accessibilityTraits = [.staticText, .updatesFrequently]
        return label
    }()

    /// `internal` so the `+ViewLifecycle.startClockTicker` can own the timer
    /// instance and `viewDidDisappear` can invalidate it.
    var clockTimer: Timer?

    /// Observer token for `AudioService.stateChangedNotification`. Removed
    /// in `deinit` so blocks don't leak across screen presentations.
    /// `internal` so the AudioState extension in the sibling file can write it.
    var audioStateObserver: NSObjectProtocol?

    // MARK: - Init

    init(alarm: Alarm, snoozeCount: Int = 0) {
        self.viewModel = AlarmFiringViewModel(alarm: alarm, snoozeCount: snoozeCount)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let token = audioStateObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = balanceChangeObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = purchaseFailedObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Per `tokens.css` and the V2 spec: the firing screen is intentionally
        // exempt from the brand light theme. Pin `.dark` so the system theme
        // can't bleed through.
        overrideUserInterfaceStyle = .dark
        buildFiringLayout()
        bindViewModel()
        observeAudioState()
        observeBalanceForNoBalanceState()
        startClockTicker()
        startGlowBreathing()

        // Pass `alarmID` so a stacking-replace race does not silence the next
        // alarm when this VC's `viewDidDisappear` fires. Volume + fade-in
        // honour the per-alarm settings.
        AudioService.shared.startAlarmSound(
            soundID: viewModel.alarm.soundID,
            alarmID: viewModel.alarm.id,
            volume: viewModel.alarm.volume,
            fadeIn: viewModel.alarm.volumeFadeIn
        )

        // Initial transition may have happened synchronously inside
        // `startAlarmSound` before our observer is wired — sync now.
        applyAudioState(AudioService.shared.state)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        clockTimer?.invalidate()
        dawnBackgroundView.sunLayer.removeAllAnimations()

        // Stop alarm sound only if AudioService still belongs to *this*
        // alarm. Stacking handoff (alarm B fires while A is on-screen)
        // could otherwise silence B.
        if AudioService.shared.currentAlarmID == viewModel.alarm.id {
            AudioService.shared.stopAlarmSound()
        } else {
            let ownerDesc = String(describing: AudioService.shared.currentAlarmID)
            let ours = self.viewModel.alarm.id
            AppLogger.audio.notice(
                "viewDidDisappear: skip stop — owner=\(ownerDesc, privacy: .private), ours=\(ours, privacy: .private)"
            )
        }
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Setup
    //
    // The view-stack + constraint composition lives in
    // `AlarmFiringViewController+Layout.swift` so this file stays under
    // SwiftLint's `file_length` cap. `viewDidLoad` calls
    // `buildFiringLayout()` which is the verbatim former `setupUI()`.

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] in
            self?.updateUI()
        }
    }

    func updateUI() {
        nameLabel.text = viewModel.heroTitle

        // Refresh snooze CTA — VM may have bumped `snoozeCount` (progressive
        // scaling) since the last update, which changes `currentPenalty`.
        // The hint surfaces "Следующее откладывание: N ₽" when progressive
        // is active and not at max, mirroring `SPScreensV2.jsx` line 96.
        if let snooze = snoozeCTA {
            snooze.update(
                price: Decimal(viewModel.currentPenalty),
                minutes: viewModel.alarm.snoozeMinutes,
                hint: snoozeHintText()
            )
            snooze.isEnabled = viewModel.canSnooze
            if viewModel.isProgressiveActive {
                // Cross-fade the gradient toward pain as snoozeCount climbs.
                // SPSnoozePrice.setTone is a no-op when intensity hasn't
                // moved, so calling it on every updateUI() is cheap.
                snooze.setTone(.progressive(intensity: viewModel.progressiveIntensity))
            }
        }

        if viewModel.isProgressiveActive {
            updateProgressiveChrome()
        }

        updateBalancePill()
        applyThemeAccentToBalancePill()
        updateAtmosphereTone()

        // Swap between the normal snooze + dismiss group and the no-balance
        // (Apple Pay 500 ₽) stack based on affordability. `canSnooze` is
        // the single source of truth.
        refreshNoBalanceVisibility()
    }

    /// Build the eyebrow caps copy below the clock. Mirrors `SPDawnV3.jsx`
    /// line 212 / `SPThemedFiring.jsx` line 172 — "пора вставать" normally,
    /// dropping to "только встать" when the wallet can't cover a snooze.
    func wakeUpCapsText() -> String {
        viewModel.canSnooze ? "Пора вставать" : "Только встать"
    }

    /// Snooze CTA hint — "Следующее откладывание: N ₽" when progressive is
    /// active and not at the price ceiling. Mirrors `SPScreensV2.jsx` line 96.
    /// V1 passed nil here; V2 surfaces the escalating cost so the user can
    /// see what they're agreeing to.
    func snoozeHintText() -> String? {
        guard viewModel.isProgressiveActive else { return nil }
        // Probe the alarm's penalty schedule one step ahead. The double-snooze
        // rule produces `currentPenalty * 2`, but we route through the model
        // so caps / custom schedules pick up the right "next" value.
        let next = viewModel.alarm.penalty(forSnoozeCount: viewModel.snoozeCount + 2)
        let nextInt = Int(next.rounded())
        return "Следующее откладывание: \(MoneyFormatter.string(nextInt))"
    }

    /// Refresh the top-right balance pill so the displayed amount + tone
    /// track the live balance. Called from `updateUI` (every VM tick) and
    /// implicitly from the balance observer (which calls `updateUI`).
    private func updateBalancePill() {
        let balance = Int(viewModel.balance.rounded())
        let tone: SPPill.Tone = balance == 0 ? .pain : .money
        guard let pill = balancePill else { return }
        pill.setText("Баланс \(MoneyFormatter.string(balance))")
        // SPPill's `tone` is `let` (constructor-only), so we re-build when
        // the tone needs to flip between money and pain. Cheap — pill is a
        // 26pt-tall capsule with two labels.
        if pill.tone != tone {
            rebuildBalancePill(tone: tone, text: "Баланс \(MoneyFormatter.string(balance))")
        }
    }

    /// Replace the existing balance pill with a new instance using the
    /// supplied tone. Used when the balance crosses the 0 ↔ positive
    /// boundary and the chip needs to flip from money → pain or back.
    private func rebuildBalancePill(tone: SPPill.Tone, text: String) {
        guard let old = balancePill else { return }
        let new = SPPill(text: text, tone: tone, icon: SPIcons.coin(size: 12))
        new.translatesAutoresizingMaskIntoConstraints = false
        if let index = topHeaderRow.arrangedSubviews.firstIndex(of: old) {
            topHeaderRow.removeArrangedSubview(old)
            old.removeFromSuperview()
            topHeaderRow.insertArrangedSubview(new, at: index)
        }
        balancePill = new
    }

    /// Sync the Dawn background tone with the current VM state. Drained when
    /// the user can't afford the next snooze; tense when the snooze price
    /// has escalated past the warn → pain threshold; calm otherwise.
    private func updateAtmosphereTone() {
        let tone: SPDawnBackgroundView.Tone
        if !viewModel.canSnooze {
            tone = .drained
        } else if viewModel.isProgressiveActive && viewModel.progressiveIntensity >= 0.5 {
            tone = .tense
        } else {
            tone = .calm
        }
        dawnBackgroundView.setTone(tone)

        // Eyebrow colour flips with the tone — theme accent at 85% normally
        // (`SPThemedFiring.jsx` line 167; `.custom` photos keep the neutral
        // white), pain300 when drained (SPDawnV3 spec line 212). Tracking is
        // the wider .18em used by the firing eyebrow, not the stock caps .12em.
        let normalColor = firingPalette?.accent.withAlphaComponent(0.85)
            ?? UIColor.white.withAlphaComponent(0.5)
        wakeUpCapsLabel.attributedText = NSAttributedString(
            string: wakeUpCapsText().uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.18,
                .foregroundColor: viewModel.canSnooze ? normalColor : AppColors.pain300
            ]
        )
    }

    // MARK: - Actions

    /// `internal` so the +NoBalance extension can wire its big ghost
    /// "Я встал — выключить" button to the same dismiss path.
    @objc func dismissTapped() {
        viewModel.dismiss()
        dismiss(animated: true)
    }

    // Clock ticking, glow breathing, snooze tap handler, top-up sheet, and
    // the snooze-failure alert live in
    // `AlarmFiringViewController+ViewLifecycle.swift`.
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initializer so the Dawn gradient stops read as in
    /// `tokens.css`. File-local copy mirroring the (private) helper in
    /// AppColors — duplicated as `fileprivate` in
    /// `AlarmFiringViewController+Layout.swift` because `private` means
    /// file-scope, not type-scope, and the +Layout extension also needs the
    /// helper for atmospheric stops in its background fill.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
