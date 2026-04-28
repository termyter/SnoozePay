import UIKit

// MARK: - Page content builders
//
// Extracted from `OnboardingViewController.swift` (#182) so the host file
// stays under SwiftLint's `file_length` and `type_body_length` caps. The
// helpers below previously lived as `private` instance methods on the main
// type — only the physical location moved; behaviour is verbatim.

extension OnboardingViewController {

    /// Steps 1 & 2 — `h1` heading + `bodyLg` body, vertically centred and
    /// inset by 32pt so the text wraps naturally without hugging the edges.
    func makeTextPageView(title: String, body: String) -> UIView {
        let container = UIView()
        let stack = makeCopyStack(title: title, body: body)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            // Slightly above centre so the action button + page dots don't
            // optically crowd the body copy.
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -AppSpacing.sp9),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.sp7),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.sp7)
        ])
        return container
    }

    /// Step 3 — heading, body, three preset tiles, Apple Pay CTA, ghost
    /// "Позже". The CTAs live inside the page (rather than the shared
    /// `actionButton`) so the page-3 controls feel cohesive with the preset
    /// tiles instead of appearing detached at the screen bottom.
    func makeDepositPageView(title: String, body: String) -> UIView {
        let container = UIView()
        let copyStack = makeCopyStack(title: title, body: body)
        let presetsStack = makePresetsStack()
        container.addSubview(copyStack)
        container.addSubview(presetsStack)
        container.addSubview(ctaStack)
        let inset = AppSpacing.screenInset
        let outerInset = AppSpacing.sp7
        NSLayoutConstraint.activate([
            copyStack.topAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sp10
            ),
            copyStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: outerInset),
            copyStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -outerInset),

            presetsStack.topAnchor.constraint(equalTo: copyStack.bottomAnchor, constant: outerInset),
            presetsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            presetsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),

            ctaStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            ctaStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            ctaStack.bottomAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            )
        ])
        return container
    }

    func makeCopyStack(title: String, body: String) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppTypography.h1
        titleLabel.textColor = AppColors.fg1
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = AppTypography.bodyLg
        bodyLabel.textColor = AppColors.fg2
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Replace the Apple Pay button instance with a fresh one whose title
    /// reflects the currently-selected preset amount. SPButton has no public
    /// title setter (its label is private), so the cheapest faithful path is
    /// a full re-create — same trade-off `FiringTopUpBottomSheet` accepts
    /// (one extra alloc per preset tap; max 3 swaps).
    func updateApplePayTitle() {
        guard let oldButton = ctaStack.arrangedSubviews.first as? SPButton else { return }
        let amount = presetAmounts[selectedPresetIndex]
        let newButton = SPButton(
            title: "Начать с \(amount.formattedRubles())",
            variant: .money,
            size: .lg,
            fullWidth: true
        )
        newButton.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        ctaStack.removeArrangedSubview(oldButton)
        oldButton.removeFromSuperview()
        ctaStack.insertArrangedSubview(newButton, at: 0)
        applePayButton = newButton
    }

    // MARK: - Actions

    @objc
    func applePayTapped() {
        // Apple Pay path — mark onboarding completed and let the parent
        // SceneDelegate swap the root. The actual IAP is handled from the
        // main app's TopUp flow; the onboarding stays a pure UI layer so the
        // SceneDelegate transition isn't blocked on a StoreKit round-trip.
        // (PR #145 ships the visual + flag wiring; the StoreKit hook-up is a
        // follow-up issue.)
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.set(false, forKey: Self.firstTopUpDoneKey)
        onFinished?()
    }

    @objc
    func actionTapped() {
        // `actionTapped` only fires while the shared CTA is visible (steps
        // 1-2). Step 3 uses `applePayButton` / `laterButton` instead.
        let currentPage = pageControl.currentPage
        guard currentPage < pages.count - 1 else { return }
        let nextPage = currentPage + 1
        let offsetX = scrollView.bounds.width * CGFloat(nextPage)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
        pageControl.currentPage = nextPage
        updatePagerState(forPage: nextPage)
    }

    @objc
    func laterTapped() {
        // "Позже" path — finish without IAP. Same persistence as the Apple
        // Pay path so SceneDelegate doesn't re-mount onboarding next launch.
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.set(false, forKey: Self.firstTopUpDoneKey)
        onFinished?()
    }

    @objc
    func skipTapped() {
        // Top-right "Пропустить" — completes onboarding from any page; balance
        // stays at 0 (the existing default in `BalanceService`).
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinished?()
    }

    // MARK: - State

    /// Wired to each `SPAmountPreset.onTap` from `makePresetsStack`. Picks
    /// the new index, recolours the tile row, and rebuilds the Apple Pay
    /// CTA so its title shows the freshly-selected amount.
    func handlePresetTap(index: Int) {
        guard index < presetTiles.count else { return }
        selectedPresetIndex = index
        for (tileIndex, tile) in presetTiles.enumerated() {
            tile.isSelected = tileIndex == index
        }
        updateApplePayTitle()
    }

    /// Drive the shared CTA (steps 1-2) and page-control state on every
    /// scroll settle. Step 3 hides the shared CTA + page dots so the
    /// page-3 layout owns the bottom edge.
    func updatePagerState(forPage page: Int) {
        let isLastPage = page == pages.count - 1

        // Hide the shared action button on step 3 — that page mounts its own
        // Apple Pay + "Позже" CTAs inside its content view. Likewise hide the
        // page dots so they don't visually compete with the preset tiles.
        actionButton.isHidden = isLastPage
        pageControl.isHidden = isLastPage

        // Step 3 controls focus on the deposit decision; "Пропустить" stays
        // visible everywhere (including step 3) per spec — it's the global
        // escape hatch, distinct from "Позже" which still records the
        // first-top-up flag.
        skipButton.isHidden = false

        // The shared action button title is always "Далее" on steps 1-2 (no
        // per-page copy) so there's nothing to update beyond visibility.
    }

    // MARK: - Page builders

    func makePresetsStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = AppSpacing.sp3
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, amount) in presetAmounts.enumerated() {
            let tile = SPAmountPreset(value: amount, selected: index == defaultPresetIndex)
            tile.onTap = { [weak self] in self?.handlePresetTap(index: index) }
            presetTiles.append(tile)
            stack.addArrangedSubview(tile)
        }
        return stack
    }
}
