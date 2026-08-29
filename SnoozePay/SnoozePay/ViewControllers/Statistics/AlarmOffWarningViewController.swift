import UIKit

/// "Alarm off / disable warning" sheet — V2 design (`docs/design/v2-handoff/`
/// `components/SPMore4.jsx` lines 325-395, `AlarmOffWarning()`).
///
/// Triggered when the user has slept through three mornings in a row. The
/// V2 spec asks for a pain-tinted full-screen modal (or large sheet) with:
///   - Top bar: small "Закрыть" `SPButton(.quiet, .sm)` on the left + caps
///     "ВНИМАНИЕ" in pain400 centre.
///   - 80×80 pain-gradient rounded square with the flame icon.
///   - h1 headline "Вы поспали ещё 3 раза подряд".
///   - bodyLg body with an inline pain-tinted mono amount.
///   - Three suggestion rows: "Перенести будильник", "Снизить цену
///     откладывания", "Выключить SnoozePay" — each on an `SPCard(.surface)`
///     with leading icon + title + subtitle + trailing chevron.
///   - Bottom ghost `SPButton(.ghost, .md)` "Всё в порядке, продолжаем".
///
/// Trigger wiring lands in a follow-up — this PR exposes a DEBUG button in
/// the statistics screen so PM can preview the visual.
final class AlarmOffWarningViewController: UIViewController {

    /// 80×80 pain-gradient rounded square the flame glyph sits on.
    ///
    /// An `SPGradientView` — the gradient IS the view's layer, so Auto Layout
    /// sizes it — not a `CAGradientLayer` sublayer. The sublayer version (#536)
    /// got its frame once, from a `DispatchQueue.main.async` hop at build time,
    /// so every resize after the first left the fill at its old size with the
    /// flame on the bare sheet. Same defect as #516 (invisible streak badge,
    /// 1.01:1 dark / 1.16:1 light) and #529.
    ///
    /// Stops start empty on purpose: reading `SPSupport.painGradientColors`
    /// here bakes `UITraitCollection.current` into a `CGColor` that never
    /// re-resolves — `refreshHeroTheme()` installs them trait-explicitly.
    let heroBadge = SPGradientView(colors: [], locations: SPSupport.painGradientLocations)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        configureLayout()
        refreshHeroTheme()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (host: AlarmOffWarningViewController, _) in
            host.refreshHeroTheme()
        }
    }

    /// Re-resolve the badge's shadow + gradient: both are plain `CGColor`,
    /// frozen at build time, and the sheet is built once in `viewDidLoad`.
    private func refreshHeroTheme() {
        heroBadge.layer.shadowColor = AppColors.pain500.resolvedColor(with: traitCollection).cgColor
        heroBadge.refresh(
            colors: SPSupport.painGradientColors(for: traitCollection),
            locations: SPSupport.painGradientLocations
        )
    }

    // MARK: - Layout

    private func configureLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp5
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        stack.addArrangedSubview(makeTopBar())
        stack.addArrangedSubview(makeHero())
        stack.addArrangedSubview(makeBody())
        stack.addArrangedSubview(makeSuggestions())
        stack.addArrangedSubview(makeFooterButton())

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: AppSpacing.sp3),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -AppSpacing.sp7),
            stack.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            stack.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor,
                constant: -AppSpacing.screenInset * 2
            )
        ])
    }

    // MARK: - Top bar

    private func makeTopBar() -> UIView {
        let closeButton = SPButton(title: "Закрыть", variant: .quiet, size: .sm)
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "ВНИМАНИЕ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.pain400
            ]
        )
        caps.textAlignment = .center
        caps.translatesAutoresizingMaskIntoConstraints = false

        // Right-side spacer mirrors the close button's width (constrained
        // below) so the caps land visually centred.
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [closeButton, caps, spacer])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = AppSpacing.sp3
        row.translatesAutoresizingMaskIntoConstraints = false
        // Pin the caps to centerX of the row to defeat distribution drift on
        // wide layouts.
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            // Activated HERE, not beside `spacer`: autolayout resolves the common
            // ancestor at ACTIVATION time, and these two only share one once `row`
            // owns both (#514 — activating earlier raised "no common ancestor").
            spacer.widthAnchor.constraint(equalTo: closeButton.widthAnchor)
        ])
        return wrap
    }

    // MARK: - Hero

    private func makeHero() -> UIView {
        let badge = heroBadge
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = AppRadius.lg
        badge.layer.cornerCurve = .continuous
        // No clipping: the gradient is the view's own layer, so `cornerRadius`
        // already rounds the fill and `masksToBounds` would eat the shadow.
        badge.layer.masksToBounds = false
        // `shadowColor` and the gradient stops come from `refreshHeroTheme()`.
        badge.layer.shadowOpacity = 0.40
        badge.layer.shadowOffset = CGSize(width: 0, height: 16)
        badge.layer.shadowRadius = 24

        let flame = UIImageView(
            image: UIImage(
                systemName: "flame.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
            )
        )
        flame.tintColor = AppColors.fgOnPain
        flame.contentMode = .scaleAspectFit
        flame.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(flame)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 80),
            badge.heightAnchor.constraint(equalToConstant: 80),
            flame.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            flame.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])

        // Align the badge to the leading edge of the stack — the JSX places
        // it left-aligned at the top of the body.
        let wrap = UIStackView(arrangedSubviews: [badge, UIView()])
        wrap.axis = .horizontal
        wrap.alignment = .center
        wrap.translatesAutoresizingMaskIntoConstraints = false
        return wrap
    }

    // MARK: - Body copy

    private func makeBody() -> UIView {
        let headline = UILabel()
        headline.font = AppTypography.h1
        headline.textColor = AppColors.fg1
        headline.numberOfLines = 0
        headline.text = "Вы поспали ещё 3 раза подряд"
        headline.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.font = AppTypography.bodyLg
        body.textColor = AppColors.fg2
        body.numberOfLines = 0
        // Inline pain-tinted mono amount via NSAttributedString.
        let prefix = "За эту неделю списано "
        let suffix = ". Возможно, что-то пошло не так. Что хотите сделать?"
        let attr = NSMutableAttributedString(
            string: prefix,
            attributes: [
                .font: AppTypography.bodyLg,
                .foregroundColor: AppColors.fg2
            ]
        )
        attr.append(MoneyFormatter.attributed(
            Decimal(750),
            digitsFont: AppFonts.mono(.bold, 17),
            prefix: "−",
            color: AppColors.pain400
        ))
        attr.append(NSAttributedString(
            string: suffix,
            attributes: [
                .font: AppTypography.bodyLg,
                .foregroundColor: AppColors.fg2
            ]
        ))
        body.attributedText = attr
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [headline, body])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Suggestions

    private func makeSuggestions() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            makeSuggestionRow(
                icon: "clock.fill",
                iconTint: AppColors.fg2,
                iconBackground: AppColors.whiteOverlay06,
                title: "Перенести будильник",
                subtitle: "Сегодня поздно лёг — встаём в 08:00"
            ),
            makeSuggestionRow(
                icon: "creditcard.fill",
                iconTint: AppColors.warn400,
                iconBackground: AppColors.warnFill500.withAlphaComponent(0.14),
                title: "Снизить цену откладывания",
                subtitle: "Сейчас \(MoneyFormatter.string(50)) → попробовать \(MoneyFormatter.string(20))"
            ),
            makeSuggestionRow(
                icon: "xmark",
                iconTint: AppColors.pain400,
                iconBackground: AppColors.pain500.withAlphaComponent(0.14),
                title: "Выключить SnoozePay",
                subtitle: "Будильник останется обычным"
            )
        ])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSuggestionRow(
        icon: String,
        iconTint: UIColor,
        iconBackground: UIColor,
        title: String,
        subtitle: String
    ) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)
        let iconWell = makeIconWell(symbol: icon, tint: iconTint, background: iconBackground)
        let textStack = makeSuggestionTextStack(title: title, subtitle: subtitle)
        let chevron = makeChevron()

        let row = UIStackView(arrangedSubviews: [iconWell, textStack, chevron])
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(suggestionTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
        return card
    }

    /// 40×40 rounded square containing the suggestion's SF Symbol icon.
    /// Lifted out of `makeSuggestionRow` to keep the row builder under the
    /// SwiftLint function-body cap.
    private func makeIconWell(symbol: String, tint: UIColor, background: UIColor) -> UIView {
        let well = UIView()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.backgroundColor = background
        well.layer.cornerRadius = AppRadius.sm
        well.layer.cornerCurve = .continuous

        let image = UIImageView(
            image: UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            )
        )
        image.tintColor = tint
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(image)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 40),
            well.heightAnchor.constraint(equalToConstant: 40),
            image.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: well.centerYAnchor)
        ])
        return well
    }

    /// Two-line text column (h4 title + meta subtitle) used inside the
    /// suggestion row.
    private func makeSuggestionTextStack(title: String, subtitle: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = AppColors.fg1
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = AppTypography.meta
        subtitleLabel.textColor = AppColors.fg3
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// 14pt right-pointing chevron used as the trailing accessory on each
    /// suggestion card.
    private func makeChevron() -> UIImageView {
        let chevron = UIImageView(
            image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            )
        )
        chevron.tintColor = AppColors.fg3
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        return chevron
    }

    // MARK: - Footer

    private func makeFooterButton() -> UIView {
        let button = SPButton(
            title: "Всё в порядке, продолжаем",
            variant: .ghost,
            size: .md,
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        return button
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func suggestionTapped() {
        // No backend wiring yet — surface a haptic and dismiss so the user
        // sees the tap registered. Follow-up issues will route the three
        // suggestions to their respective screens (CreateAlarm, Settings,
        // Disable confirmation).
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
