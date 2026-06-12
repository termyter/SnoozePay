import UIKit

// MARK: - Page builders + state for OnboardingViewController (V2)
//
// Split out so the host VC stays under SwiftLint's `file_length` cap. The
// helpers here own:
//   - per-page content builders (`makePage1` / `makePage2` / `makePage3`),
//   - the bespoke pill-dot row used in place of `UIPageControl`,
//   - the action handlers wired from the primary / "Позже" / "Пропустить" CTAs,
//   - the CTA-rebuild that swaps "Дальше" → "Пополнить" on step 3.
//
// Single-purpose helper view classes (glow host, penalty pill, numbered step
// row, page dot, deposit option card) live in `OnboardingComponents.swift`.

extension OnboardingViewController {

    // MARK: - Page stack

    func buildPageStack() {
        scrollView.subviews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()
        depositOptionViews.removeAll()

        let page1 = makePage1()
        let page2 = makePage2()
        let page3 = makePage3()
        for page in [page1, page2, page3] {
            scrollView.addSubview(page)
            pageViews.append(page)
        }
    }

    // MARK: - Page 1 — concept

    func makePage1() -> UIView {
        let container = UIView()
        let glowHost = makePage1Glow()
        container.addSubview(glowHost)
        let clockLabel = makePage1Clock()
        let pill = OnboardingPenaltyPill()
        let titleLabel = makePage1Title()
        let bodyLabel = makePage1Body()

        let stack = UIStackView(arrangedSubviews: [clockLabel, pill, titleLabel, bodyLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.setCustomSpacing(AppSpacing.sp5, after: clockLabel)
        stack.setCustomSpacing(AppSpacing.sp7 + 4, after: pill)
        stack.setCustomSpacing(AppSpacing.sp3 + 2, after: titleLabel)
        container.addSubview(stack)

        // The inequality leading/trailing pins alone don't force a width —
        // Auto Layout would happily collapse the stack to ~1 glyph and wrap
        // the title one character per line (#269). Pin centerX and ask for
        // the full container width at 999 so the required ≤320 cap still
        // wins on wide screens.
        let preferredWidth = stack.widthAnchor.constraint(
            equalTo: container.widthAnchor,
            constant: -(AppSpacing.sp4 * 2)
        )
        preferredWidth.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            glowHost.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
            glowHost.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            glowHost.widthAnchor.constraint(equalToConstant: 420),
            glowHost.heightAnchor.constraint(equalToConstant: 420),

            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: AppSpacing.sp4
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -AppSpacing.sp4
            ),
            preferredWidth,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
        return container
    }

    // MARK: - Page 1 helpers

    private func makePage1Glow() -> OnboardingGlowHostView {
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [
            UIColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 0.25).cgColor,
            UIColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 0.0).cgColor
        ]
        glow.locations = [0.0, 0.6]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1.0, y: 1.0)
        let host = OnboardingGlowHostView(layer: glow, size: 420)
        host.translatesAutoresizingMaskIntoConstraints = false
        return host
    }

    private func makePage1Clock() -> UILabel {
        let label = UILabel()
        label.text = "07:00"
        label.font = AppTypography.clockXl
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        // Tabular numbers so digits column-align across glyphs.
        let descriptor = label.font.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                ]
            ]
        ])
        label.font = UIFont(descriptor: descriptor, size: label.font.pointSize)
        return label
    }

    private func makePage1Title() -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Будильник\nсо ставкой",
            attributes: [
                .font: AppTypography.h1,
                .kern: -0.32,
                .foregroundColor: UIColor.white
            ]
        )
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makePage1Body() -> UILabel {
        let label = UILabel()
        label.text = "Каждое откладывание стоит денег. Деньги не вернутся. Зато вы встанете."
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    // MARK: - Page 2 — mechanics

    func makePage2() -> UIView {
        let container = UIView()

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "КАК ЭТО РАБОТАЕТ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
            ]
        )

        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: "Положи баланс.\nОткладывай — теряй.",
            attributes: [
                .font: AppTypography.h1,
                .kern: -0.32,
                .foregroundColor: UIColor.white
            ]
        )
        titleLabel.numberOfLines = 0

        let rows = [
            ("1", "Положили \(MoneyFormatter.string(500))", "Это запас, из которого спишутся откладывания."),
            ("2", "Поспать ещё в 07:00 → −\(MoneyFormatter.string(50))", "Каждый раз когда вы тянете, деньги уходят."),
            ("3", "Встали с первого раза → ничего", "Баланс продолжает лежать. Готов к завтрашнему утру.")
        ].map { OnboardingStepRow(number: $0.0, title: $0.1, body: $0.2) }

        let rowsStack = UIStackView(arrangedSubviews: rows)
        rowsStack.axis = .vertical
        rowsStack.spacing = AppSpacing.sp3 + 2     // 14pt — matches JSX `gap: 14`
        rowsStack.alignment = .fill

        let mainStack = UIStackView(arrangedSubviews: [caps, titleLabel, rowsStack])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.setCustomSpacing(AppSpacing.sp2, after: caps)
        mainStack.setCustomSpacing(AppSpacing.sp7, after: titleLabel)

        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.sp4),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.sp4)
        ])
        return container
    }

    // MARK: - Page 3 — deposit

    func makePage3() -> UIView {
        let container = UIView()

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "БАЛАНС · СКОЛЬКО ПОЛОЖИТЬ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.money300
            ]
        )

        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: "Сколько ставите\nна свою дисциплину?",
            attributes: [
                .font: AppTypography.h1,
                .kern: -0.32,
                .foregroundColor: UIColor.white
            ]
        )
        titleLabel.numberOfLines = 0

        let optionsStack = UIStackView()
        optionsStack.axis = .vertical
        optionsStack.spacing = AppSpacing.sp2
        optionsStack.alignment = .fill

        for (index, option) in depositOptions.enumerated() {
            let optionView = OnboardingDepositOptionView(option: option)
            optionView.isSelectedOption = index == defaultDepositIndex
            optionView.onTap = { [weak self] in self?.handleDepositOptionTap(at: index) }
            depositOptionViews.append(optionView)
            optionsStack.addArrangedSubview(optionView)
        }

        // V3: no "Можно поменять в любой момент" footer — the deposit column
        // ends with the option cards; the content block centres vertically
        // like pages 1/2 (JSX `flex: 1; justify-content: center`).
        let mainStack = UIStackView(arrangedSubviews: [caps, titleLabel, optionsStack])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.setCustomSpacing(AppSpacing.sp2, after: caps)
        mainStack.setCustomSpacing(AppSpacing.sp6, after: titleLabel)

        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.sp4),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.sp4)
        ])
        return container
    }

    // MARK: - Pager state

    /// Rebuild the pill-dot row — the active page gets a 24×6 money-gradient
    /// pill, the rest stay 6×6 with `whiteOverlay12`.
    func rebuildDotsRow(activePage: Int) {
        dotsStack.arrangedSubviews.forEach {
            dotsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for index in 0..<pageCount {
            let dot = OnboardingPageDot(isActive: index == activePage)
            dotsStack.addArrangedSubview(dot)
        }
    }

    /// Pager state — toggles glow, the "Позже" secondary, and the primary
    /// button (which transforms into the deposit CTA on step 3).
    ///
    /// The "Позже" slot is alpha-faded rather than `isHidden`-collapsed so
    /// the green primary button bottoms out at the same Y on every page —
    /// the V3 CTA-anchor rule (`SPMore.jsx` keeps a 20pt spacer under the
    /// "Дальше" button for the same effect).
    func updatePagerState(forPage page: Int) {
        rebuildDotsRow(activePage: page)
        let isDepositPage = page == pageCount - 1
        setStepGlow(active: isDepositPage)
        laterButton.alpha = isDepositPage ? 1 : 0
        laterButton.isUserInteractionEnabled = isDepositPage
        laterButton.isAccessibilityElement = isDepositPage
        // Dots sit 14pt above the CTA group on the deposit page
        // (JSX `marginBottom: 14`), 24pt on pages 1/2 (#289).
        dotsGapConstraint?.constant = isDepositPage
            ? -(AppSpacing.sp3 + 2)   // 14pt
            : -AppSpacing.sp6         // 24pt
        if isDepositPage {
            rebuildDepositCTA()
        } else {
            rebuildAdvanceCTA()
        }
    }

    // MARK: - CTA rebuilds

    /// Replace the primary button with the "Дальше" advance variant. Cheap
    /// (≤ 2 swaps over the user's onboarding lifetime).
    func rebuildAdvanceCTA() {
        guard primaryButton.allTargets.isEmpty == false || primaryButton.superview != nil else { return }
        let newButton = SPButton(title: "Дальше", variant: .money, size: .lg, fullWidth: true)
        swapPrimary(with: newButton)
    }

    /// Replace the primary button with the deposit CTA — title "Пополнить",
    /// suffix `{value} ₽`, leading wallet icon (V3 reads as "put money in",
    /// matching the Wallet deposit sheet). Re-run on every option-tap so the
    /// suffix tracks the selection.
    func rebuildDepositCTA() {
        let amount = depositOptions[selectedDepositIndex].amount
        let newButton = SPButton(
            title: "Пополнить",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "wallet.pass"),
            suffix: amount.formattedRubles(),
            fullWidth: true
        )
        swapPrimary(with: newButton)
    }

    private func swapPrimary(with newButton: SPButton) {
        let oldButton = primaryButton
        newButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        if let index = ctaStack.arrangedSubviews.firstIndex(of: oldButton) {
            ctaStack.removeArrangedSubview(oldButton)
            oldButton.removeFromSuperview()
            ctaStack.insertArrangedSubview(newButton, at: index)
        } else {
            ctaStack.insertArrangedSubview(newButton, at: 0)
        }
        primaryButton = newButton
    }

    // MARK: - Actions

    @objc
    func primaryTapped() {
        let currentPage = pageControl.currentPage
        if currentPage < pageCount - 1 {
            let nextPage = currentPage + 1
            let offsetX = scrollView.bounds.width * CGFloat(nextPage)
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
            pageControl.currentPage = nextPage
            updatePagerState(forPage: nextPage)
        } else {
            // Step 3 — deposit CTA tapped. The actual IAP / StoreKit hookup
            // ships separately; for now we mark onboarding done + first-top-up
            // pending so the SceneDelegate transition isn't blocked on a
            // network round-trip.
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            UserDefaults.standard.set(false, forKey: Self.firstTopUpDoneKey)
            onFinished?()
        }
    }

    @objc
    func laterTapped() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.set(false, forKey: Self.firstTopUpDoneKey)
        onFinished?()
    }

    /// Top-right "Пропустить" pill — available on every page; semantically
    /// identical to "Позже" (finish onboarding without a first top-up).
    @objc
    func skipTapped() {
        laterTapped()
    }

    // MARK: - Deposit option taps

    func handleDepositOptionTap(at index: Int) {
        guard index < depositOptionViews.count else { return }
        selectedDepositIndex = index
        for (viewIndex, view) in depositOptionViews.enumerated() {
            view.isSelectedOption = viewIndex == index
        }
        rebuildDepositCTA()
    }
}
