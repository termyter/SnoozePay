import UIKit

/// Referral programme screen — V2 design (`docs/design/v2-handoff/`
/// `components/SPMore4.jsx` lines 228-323, `Referral()`).
///
/// Layout (top → bottom):
///   1. `ReferralHeroCardView` — deep-green promo panel (dark fill in BOTH
///      themes, so its copy is white in both). Caps "Реферальная программа" +
///      h1 "+200 ₽ вам / +200 ₽ другу" + body explainer.
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

    /// Avatar diameter in the "Друзья" list — 36pt per the JSX
    /// (`width: 36, height: 36, borderRadius: 18`). Deliberately off the 4pt
    /// `AppSpacing` grid: it is a component size, not spacing.
    private static let avatarDiameter: CGFloat = 36

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

    /// Deep-green promo panel. The gradient stops, the ink and the theme
    /// bookkeeping live in `ReferralHeroCardView` — the fill is dark in both
    /// themes (like `--sp-grad-night`), so the copy stays white in both.
    private func makeHeroCard() -> UIView {
        ReferralHeroCardView(
            caps: "РЕФЕРАЛЬНАЯ ПРОГРАММА",
            headline: "+\(MoneyFormatter.string(200)) вам\n+\(MoneyFormatter.string(200)) другу",
            body: "Когда друг продержится 7 дней — оба получаете бонус в баланс."
        )
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
            friendCodeField.heightAnchor.constraint(greaterThanOrEqualToConstant: AppSpacing.sp7)
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
                // `--sp-warn-700` in the JSX, a token that does not exist in
                // `tokens.css`; the wash token carries the same 60% bronze in
                // the dark theme and inverts to a faint tint + dark ink on the
                // light card, where 60% bronze left the initial at 1.08:1.
                badgeColor: AppColors.warnWash,
                badgeGradient: nil,
                badgeTextColor: AppColors.fgOnWarnWash,
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
        badge.layer.cornerRadius = Self.avatarDiameter / 2
        badge.layer.masksToBounds = true
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.avatarDiameter),
            badge.heightAnchor.constraint(equalToConstant: Self.avatarDiameter)
        ])
        if let gradient = spec.badgeGradient {
            let layer = CAGradientLayer()
            layer.colors = gradient
            layer.locations = SPSupport.moneyGradientLocations
            layer.startPoint = SPSupport.gradientStart
            layer.endPoint = SPSupport.gradientEnd
            layer.cornerRadius = Self.avatarDiameter / 2
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
