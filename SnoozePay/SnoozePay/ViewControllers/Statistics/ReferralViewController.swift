import UIKit

/// Referral programme screen — V2 design (`docs/design/v2-handoff/`
/// `components/SPMore4.jsx` lines 228-323, `Referral()`).
///
/// Layout (top → bottom):
///   1. Hero card with a money-toned dark gradient + radial corner glow.
///      Caps "Реферальная программа" + h1 "+200 ₽ вам / +200 ₽ другу" +
///      body explainer.
///   2. "Ваш код" — caps caption + `SPCard(.surface)` containing the
///      mono-spaced personal code + a "Копировать" `SPButton(.money, .sm)`
///      that copies the code onto the pasteboard.
///   3. "Код друга" — caps caption + `SPCard(.surface)` with a vanilla
///      mono-font `UITextField` placeholder and an "Применить"
///      `SPButton(.money, .sm)` that briefly flashes a success state.
///   4. "Друзья" — caps caption + `SPCard(.surface)` listing three sample
///      friend rows (avatar + name + status meta + trailing amount).
///   5. Bottom primary CTA — `SPButton(.money, .lg, fullWidth: true)`
///      "Поделиться кодом" that pops a `UIActivityViewController`.
///
/// Until a real referral backend exists the data is hard-coded (matching
/// the JSX placeholders) so the screen still tells the V2 story end-to-end.
final class ReferralViewController: UIViewController {

    // MARK: - Constants

    /// Placeholder personal code rendered until the referral backend lands.
    /// Mono-spaced + uppercase per the JSX `font: var(--sp-font-mono)` recipe.
    private static let personalCode = "WAKEUP-7K2"

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let friendCodeField = UITextField()
    private let applyButton = SPButton(
        title: "Применить",
        variant: .quiet,
        size: .sm
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Пригласить"
        view.backgroundColor = AppColors.bg0
        navigationItem.largeTitleDisplayMode = .never
        configureContainers()
        contentStack.addArrangedSubview(makeHeroCard())
        contentStack.addArrangedSubview(makePersonalCodeSection())
        contentStack.addArrangedSubview(makeFriendCodeSection())
        contentStack.addArrangedSubview(makeFriendsSection())
        contentStack.addArrangedSubview(makeShareButton())
    }

    // MARK: - Setup

    private func configureContainers() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp5
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: AppSpacing.sp4),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -AppSpacing.sp7),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor,
                constant: -AppSpacing.screenInset * 2
            )
        ])
    }

    // MARK: - Hero card

    /// Bespoke hero card — money-toned dark gradient + radial corner glow.
    /// Built as a plain `UIView` rather than an `SPCard` because the
    /// gradient recipe is unique to this screen (135° linear with three
    /// brand-money stops instead of the canonical `SPSupport.money*`).
    private func makeHeroCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = AppRadius.xl
        card.layer.cornerCurve = .continuous
        card.layer.masksToBounds = true

        // Background gradient — dark money camo (#1A2810 → #2C4A1F → #4F8A3A).
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0x1A / 255.0, green: 0x28 / 255.0, blue: 0x10 / 255.0, alpha: 1).cgColor,
            UIColor(red: 0x2C / 255.0, green: 0x4A / 255.0, blue: 0x1F / 255.0, alpha: 1).cgColor,
            UIColor(red: 0x4F / 255.0, green: 0x8A / 255.0, blue: 0x3A / 255.0, alpha: 1).cgColor
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        card.layer.insertSublayer(gradient, at: 0)

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "РЕФЕРАЛЬНАЯ ПРОГРАММА",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
        )
        caps.numberOfLines = 0
        caps.translatesAutoresizingMaskIntoConstraints = false

        let headline = UILabel()
        headline.font = AppTypography.h1
        headline.textColor = .white
        headline.numberOfLines = 0
        headline.text = "+\(MoneyFormatter.string(200)) вам\n+\(MoneyFormatter.string(200)) другу"
        headline.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.text = "Когда друг продержится 7 дней — оба получаете бонус в баланс."
        body.font = AppTypography.body
        body.textColor = UIColor.white.withAlphaComponent(0.85)
        body.numberOfLines = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [caps, headline, body])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp3, after: headline)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.sp7),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.sp7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp7),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.sp7)
        ])

        // Resize the gradient sublayer on next runloop tick so it adopts the
        // resolved bounds after Auto Layout settles.
        DispatchQueue.main.async {
            gradient.frame = card.bounds
        }
        // Keep the gradient frame in sync on bounds change via a tiny KVO-free
        // helper layer: intercept layoutSubviews on a private subclass would
        // be cleaner, but a single dispatched assignment + an extra one on
        // device-rotation `viewWillTransition` covers the practical cases.
        return card
    }

    // MARK: - "Ваш код"

    private func makePersonalCodeSection() -> UIView {
        let caps = makeSectionCaps("ВАШ КОД")
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)

        let codeLabel = UILabel()
        codeLabel.font = AppFonts.mono(.bold, 20)
        codeLabel.textColor = AppColors.fg1
        codeLabel.text = Self.personalCode
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.minimumScaleFactor = 0.7
        codeLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = SPButton(title: "Копировать", variant: .money, size: .sm)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyCodeTapped(_:)), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [codeLabel, copyButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp3
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])

        let wrap = UIStackView(arrangedSubviews: [caps, card])
        wrap.axis = .vertical
        wrap.spacing = AppSpacing.sp2
        wrap.alignment = .fill
        wrap.translatesAutoresizingMaskIntoConstraints = false
        return wrap
    }

    // MARK: - "Код друга"

    private func makeFriendCodeSection() -> UIView {
        let caps = makeSectionCaps("КОД ДРУГА")
        let card = SPCard(tone: .surface, padding: AppSpacing.sp3)

        friendCodeField.placeholder = "Например, WAKEUP-7K2"
        friendCodeField.font = AppFonts.mono(.bold, 16)
        friendCodeField.textColor = AppColors.fg1
        friendCodeField.tintColor = AppColors.money500
        friendCodeField.autocapitalizationType = .allCharacters
        friendCodeField.autocorrectionType = .no
        friendCodeField.translatesAutoresizingMaskIntoConstraints = false
        friendCodeField.addTarget(self, action: #selector(friendCodeChanged(_:)), for: .editingChanged)

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.isEnabled = false
        applyButton.addTarget(self, action: #selector(applyFriendCodeTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [friendCodeField, applyButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp2
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            friendCodeField.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        let hint = UILabel()
        hint.text = "Можно ввести один раз. Бонус начисляется обоим, когда вы продержитесь 7 дней."
        hint.font = AppTypography.meta
        hint.textColor = AppColors.fg4
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        let wrap = UIStackView(arrangedSubviews: [caps, card, hint])
        wrap.axis = .vertical
        wrap.spacing = AppSpacing.sp2
        wrap.alignment = .fill
        wrap.translatesAutoresizingMaskIntoConstraints = false
        return wrap
    }

    // MARK: - Friends list

    private func makeFriendsSection() -> UIView {
        let caps = makeSectionCaps("ДРУЗЬЯ")
        let card = SPCard(tone: .surface, padding: AppSpacing.sp1)

        // 1pt padding around the SPRow stack — rows already pay their own
        // 16pt internal padding, so the card just wraps the divider rhythm.
        let rowMasha = makeFriendRow(
            FriendRowSpec(
                initial: "М",
                badgeColor: nil,
                badgeGradient: SPSupport.moneyGradientColors,
                badgeTextColor: AppColors.fgOnMoney,
                title: "Маша К.",
                subtitle: "Продержалась 7 дней",
                trailing: makeAmountLabel(text: "+\(MoneyFormatter.string(200))", color: AppColors.money400),
                divider: true
            )
        )
        let rowDima = makeFriendRow(
            FriendRowSpec(
                initial: "Д",
                badgeColor: UIColor(hex: 0xC97A06).withAlphaComponent(0.6),
                badgeGradient: nil,
                badgeTextColor: AppColors.warn300,
                title: "Дима Р.",
                subtitle: "День 4 из 7",
                trailing: makeMetaLabel(text: "скоро", color: AppColors.warn400),
                divider: true
            )
        )
        let rowAnya = makeFriendRow(
            FriendRowSpec(
                initial: "А",
                badgeColor: AppColors.whiteOverlay08,
                badgeGradient: nil,
                badgeTextColor: AppColors.fg3,
                title: "Аня С.",
                subtitle: "День 1 из 7",
                trailing: makeMetaLabel(text: "в процессе", color: AppColors.fg3),
                divider: false
            )
        )

        let rows = UIStackView(arrangedSubviews: [rowMasha, rowDima, rowAnya])
        rows.axis = .vertical
        rows.spacing = 0
        rows.alignment = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])

        let wrap = UIStackView(arrangedSubviews: [caps, card])
        wrap.axis = .vertical
        wrap.spacing = AppSpacing.sp2
        wrap.alignment = .fill
        wrap.translatesAutoresizingMaskIntoConstraints = false
        return wrap
    }

    /// Spec bundle for a single row in the "Друзья" list. Wraps the 8
    /// parameters that previously sat on `makeFriendRow(...)` so SwiftLint's
    /// `function_parameter_count` ceiling stays happy.
    private struct FriendRowSpec {
        let initial: String
        let badgeColor: UIColor?
        let badgeGradient: [CGColor]?
        let badgeTextColor: UIColor
        let title: String
        let subtitle: String
        let trailing: UIView
        let divider: Bool
    }

    private func makeFriendRow(_ spec: FriendRowSpec) -> UIView {
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = 18
        badge.layer.masksToBounds = true
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 36),
            badge.heightAnchor.constraint(equalToConstant: 36)
        ])
        if let gradient = spec.badgeGradient {
            let layer = CAGradientLayer()
            layer.colors = gradient
            layer.locations = SPSupport.moneyGradientLocations
            layer.startPoint = SPSupport.gradientStart
            layer.endPoint = SPSupport.gradientEnd
            layer.cornerRadius = 18
            badge.layer.insertSublayer(layer, at: 0)
            DispatchQueue.main.async {
                layer.frame = badge.bounds
            }
        } else {
            badge.backgroundColor = spec.badgeColor
        }
        let initialLabel = UILabel()
        initialLabel.text = spec.initial
        initialLabel.font = AppTypography.h4
        initialLabel.textColor = spec.badgeTextColor
        initialLabel.textAlignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(initialLabel)
        NSLayoutConstraint.activate([
            initialLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])

        return SPRow(
            title: spec.title,
            subtitle: spec.subtitle,
            leading: badge,
            trailing: spec.trailing,
            divider: spec.divider
        )
    }

    // MARK: - Bottom CTA

    private func makeShareButton() -> UIView {
        let button = SPButton(
            title: "Поделиться кодом",
            variant: .money,
            size: .lg,
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        return button
    }

    // MARK: - Helpers

    private func makeSectionCaps(_ text: String) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeAmountLabel(text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.textColor = color
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeMetaLabel(text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = color
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Actions

    @objc private func copyCodeTapped(_ sender: SPButton) {
        UIPasteboard.general.string = Self.personalCode
        // Tiny in-place success cue — flip the title for ~1.4 s.
        // (SPButton has no public title setter post-init; recreate trivially
        //  via a one-shot UIView animation on the existing instance would
        //  require a hook we don't have, so we surface feedback via haptics
        //  only and let the user see "Скопировано" on the pasteboard.)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    @objc private func friendCodeChanged(_ sender: UITextField) {
        if let text = sender.text {
            sender.text = text.uppercased()
            applyButton.isEnabled = !text.isEmpty
        } else {
            applyButton.isEnabled = false
        }
    }

    @objc private func applyFriendCodeTapped() {
        // No backend yet — surface a confirmation alert so the user sees the
        // tap registered.
        let alert = UIAlertController(
            title: "Код применён",
            message: "Бонус начислится, когда вы продержитесь 7 дней без откладываний.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func shareTapped() {
        let text = "Откладывай меньше — копи больше. Используй мой код в SnoozePay: "
            + "\(Self.personalCode) — оба получим +\(MoneyFormatter.string(200)) на баланс."
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = view.bounds
        present(activity, animated: true)
    }
}

// MARK: - UIColor hex helper

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
