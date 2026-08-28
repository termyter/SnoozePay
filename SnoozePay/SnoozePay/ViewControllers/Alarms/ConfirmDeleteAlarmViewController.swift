import UIKit

/// Bottom-sheet confirmation for destructive "Удалить будильник" (#163 /
/// #231 / V2).
///
/// Presented `.overFullScreen` so the alarm-edit form stays visible — and
/// dimmed — underneath, exactly like the `ConfirmDelete()` artboard in
/// `SPMore2.jsx`: a `rgba(0,0,0,.55)` scrim with a subtle blur, and the
/// sheet floating at the bottom with a `0 −24 64` upward shadow. Tapping the
/// scrim cancels.
///
/// Sheet layout mirrors `SPMore2.jsx` (`ConfirmDelete()`):
///   - 64×64 pain-tinted square with X icon
///   - h2 "Удалить будильник?" title
///   - body copy line
///   - `SPButton(.pain, .lg)` "Удалить"
///   - `SPButton(.quiet, .md)` "Отмена"
final class ConfirmDeleteAlarmViewController: UIViewController {

    // MARK: - Callbacks

    /// Invoked after the user taps "Удалить". The host VC handles the actual
    /// delete + repository wiring; this sheet only owns the confirmation UI.
    var onConfirm: (() -> Void)?

    // MARK: - Configuration

    /// Traits used for everything painted as part of the *scrim* rather than
    /// the sheet. A modal scrim darkens whatever is behind it, so it stays
    /// dark in both themes — same call as `StreakModalViewController`. The
    /// sheet itself keeps following the app theme.
    private static let scrimTrait = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: - Body copy

    /// Subtitle line shown below the headline. Defaults to the design's
    /// reassurance copy «Баланс N ₽ останется на месте — он привязан к
    /// аккаунту, а не к будильнику» with the live balance interpolated
    /// (#277); the host should pass `AlarmDeletionCopy.body(contextLine:
    /// balance:)` to prepend alarm-specific context (repeat + time).
    private let bodyCopy: String

    // MARK: - UI

    /// Subtle backdrop blur under the scrim — the artboard's
    /// `backdrop-filter: blur(2px)`. Deliberately the *dark* material in both
    /// themes: it sits under the scrim, and a light material there would haze
    /// the page toward white instead of dimming it.
    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Translucent scrim so the edit screen below reads as "present but
    /// inert" — `rgba(0,0,0,.55)` per the artboard. Resolved off `bg0` at the
    /// scrim traits instead of a black literal, so a `tokens.css` bump carries
    /// here and the value stays a token in both themes.
    private let scrimView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.bg0
            .resolvedColor(with: ConfirmDeleteAlarmViewController.scrimTrait)
            .withAlphaComponent(0.55)
        return view
    }()

    private let card: SPCard = {
        let card = SPCard(tone: .raised, padding: AppSpacing.sp6, cornerRadius: AppRadius.xl)
        card.translatesAutoresizingMaskIntoConstraints = false
        // Upward sheet shadow `0 -24px 64px rgba(0,0,0,.5)` — overrides the
        // tone's default downward shadow2 so the sheet reads as a layer
        // lifting off the dimmed screen below. The shadow falls on the SCRIM,
        // not on the page, so it keeps the scrim's dark value in both themes
        // — the light `shadow2` ink at 10% would be invisible there.
        card.layer.shadowColor = AppColors.bg0
            .resolvedColor(with: ConfirmDeleteAlarmViewController.scrimTrait)
            .cgColor
        card.layer.shadowOpacity = 0.5
        card.layer.shadowOffset = CGSize(width: 0, height: -24)
        card.layer.shadowRadius = 32
        return card
    }()

    private let iconBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.backgroundColor = AppColors.pain500.withAlphaComponent(0.14)
        view.layer.borderWidth = 1
        // `borderColor` is a `cgColor` and cannot re-resolve itself — it is
        // painted in `refreshBadgeStroke()` against the view's own traits.
        return view
    }()

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "xmark")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        )
        let view = UIImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = AppColors.pain400
        view.contentMode = .center
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.h2
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Удалить будильник?"
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let deleteButton = SPButton(
        title: "Удалить",
        variant: .pain,
        size: .lg,
        fullWidth: true
    )

    private let cancelButton = SPButton(
        title: "Отмена",
        variant: .quiet,
        size: .md,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameters:
    ///   - body: Subtitle copy. Defaults to the balance-stays-put reassurance
    ///     with the live balance (#277). Pass a tailored composition (e.g.
    ///     "Будни · Пн–Пт · 07:00. Баланс …") when the alarm context is rich.
    ///   - onConfirm: Closure invoked on the destructive tap. The sheet
    ///     dismisses itself before firing the callback.
    init(
        body: String = AlarmDeletionCopy.body(balance: BalanceService.shared.balance),
        onConfirm: (() -> Void)? = nil
    ) {
        self.bodyCopy = body
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        // Overlay presentation (#231): the edit screen must stay visible,
        // dimmed, behind the sheet — `.pageSheet` would push it back and
        // shrink it instead.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        bodyLabel.text = bodyCopy
        setupUI()
        deleteButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        scrimView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(cancelTapped))
        )
        refreshBadgeStroke()
        // The badge sits on the sheet, which follows the app theme, so its
        // stroke has to be re-resolved when the theme flips under an open
        // sheet — a `cgColor` keeps whatever it was born with.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (host: ConfirmDeleteAlarmViewController, _) in
            host.refreshBadgeStroke()
        }
    }

    /// Paint the pain-tinted hairline around the 64×64 icon badge with the
    /// current theme's `pain500`.
    private func refreshBadgeStroke() {
        iconBadge.layer.borderColor = AppColors.pain500
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.30)
            .cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(blurView)
        view.addSubview(scrimView)
        view.addSubview(card)

        iconBadge.addSubview(iconView)
        card.addSubview(iconBadge)
        card.addSubview(titleLabel)
        card.addSubview(bodyLabel)
        card.addSubview(deleteButton)
        card.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Bottom-floating sheet — `padding: 0 12px 16px` per the
            // artboard, anchored above the home indicator.
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp3),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp3),
            card.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp2
            ),

            iconBadge.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            iconBadge.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: 64),
            iconBadge.heightAnchor.constraint(equalToConstant: 64),

            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: AppSpacing.sp4),
            titleLabel.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp2),
            bodyLabel.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            deleteButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: AppSpacing.sp5),
            deleteButton.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            cancelButton.topAnchor.constraint(equalTo: deleteButton.bottomAnchor, constant: AppSpacing.sp2),
            cancelButton.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        // Dismiss first so the host's onDelete + dismiss(animated:) chain
        // doesn't race with the sheet's own dismissal animation.
        dismiss(animated: true) { [weak self] in
            self?.onConfirm?()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
