import UIKit
import StoreKit

/// Layout / setup helpers for `TopUpViewController` — kept in a separate
/// file so the host controller stays under the project's per-type
/// length lint threshold. Subview properties remain on the controller;
/// these helpers only assemble the constraints + interaction wiring.
extension TopUpViewController {

    // MARK: - Top-level layout

    func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.addSubview(successContainer)

        let inset = AppSpacing.screenInset

        contentStack.addArrangedSubview(balanceCard)
        contentStack.setCustomSpacing(AppSpacing.sp6, after: balanceCard)
        contentStack.addArrangedSubview(presetsSectionHeader)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: presetsSectionHeader)
        contentStack.addArrangedSubview(presetGrid)
        contentStack.setCustomSpacing(AppSpacing.sp6, after: presetGrid)
        contentStack.addArrangedSubview(applePayButton)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: applePayButton)
        contentStack.addArrangedSubview(restoreRow)
        contentStack.setCustomSpacing(AppSpacing.sp6, after: restoreRow)
        contentStack.addArrangedSubview(footerCard)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: AppSpacing.sp5
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: inset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -inset
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -inset * 2
            ),

            successContainer.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            successContainer.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            successContainer.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            successContainer.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Preset grid

    /// Build the 2×2 preset grid as two `.fillEqually` rows. Each
    /// `SPAmountPreset` owns its own selection toggle; we mirror the
    /// change back to `selectedAmount` and rebuild the Apple Pay CTA on
    /// every tap.
    func setupPresetTiles() {
        presetTiles.removeAll()
        let rowsCount = 2
        let columnsCount = 2

        for rowIdx in 0..<rowsCount {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = AppSpacing.sp3
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            for columnIdx in 0..<columnsCount {
                let presetIndex = rowIdx * columnsCount + columnIdx
                guard presetIndex < TopUpViewController.walletPresets.count else { continue }
                let preset = TopUpViewController.walletPresets[presetIndex]
                let tile = SPAmountPreset(
                    value: Decimal(preset.amount),
                    label: preset.label,
                    selected: preset.amount == selectedAmount,
                    popular: preset.popular
                ) { [weak self] in
                    self?.selectAmount(preset.amount)
                }
                presetTiles.append(tile)
                rowStack.addArrangedSubview(tile)
            }
            presetGrid.addArrangedSubview(rowStack)
        }
    }

    func selectAmount(_ amount: Int) {
        guard amount != selectedAmount else { return }
        selectedAmount = amount
        for (tile, preset) in zip(presetTiles, TopUpViewController.walletPresets) {
            tile.isSelected = preset.amount == amount
        }
        rebuildApplePayButton()
    }

    // MARK: - Apple Pay button

    /// Replace the existing Apple Pay button in the content stack so its
    /// title reflects the active preset. Re-wires the touch target and
    /// re-applies the loading-disabled state if needed.
    func rebuildApplePayButton() {
        let oldButton = applePayButton
        let newButton = TopUpViewControllerFactory.applePayButton(amount: selectedAmount)
        newButton.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)

        // Insert at the same position in the stack so the layout stays
        // anchored relative to the preset grid + restore row.
        if let index = contentStack.arrangedSubviews.firstIndex(of: oldButton) {
            contentStack.insertArrangedSubview(newButton, at: index)
            contentStack.setCustomSpacing(AppSpacing.sp3, after: newButton)
        } else {
            contentStack.addArrangedSubview(newButton)
        }
        oldButton.removeFromSuperview()
        applePayButton = newButton

        // Disable until products are loaded so a tap can never fall
        // through to a "магазин недоступен" alert without a leading signal.
        applePayButton.isEnabled = didFinishInitialLoad && !purchaseInFlight
    }

    // MARK: - Restore row

    /// SPRow doesn't expose a "quiet" tone directly, but we approximate
    /// the design recipe by tinting the inner title label with
    /// `info500` and centring its text. The row itself stays the tap
    /// target so VoiceOver still reads it as a button.
    func setupRestoreRow() {
        restoreRow.onTap = { [weak self] in
            self?.performRestorePurchases()
        }
        restoreRow.isUserInteractionEnabled = true
        restoreRow.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        if let titleLabel = TopUpViewControllerFactory.findTitleLabel(in: restoreRow) {
            titleLabel.textColor = AppColors.info500
            titleLabel.textAlignment = .center
            titleLabel.font = AppTypography.button
        }
        restoreRow.isAccessibilityElement = true
        restoreRow.accessibilityTraits = .button
        restoreRow.accessibilityLabel = "Восстановить покупки"
    }

    // MARK: - Footer

    func setupFooter() {
        footerCard.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [footerCapsLabel, footerBodyLabel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        footerCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footerCard.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: footerCard.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: footerCard.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footerCard.layoutMarginsGuide.trailingAnchor)
        ])
    }

    // MARK: - Success overlay

    func setupSuccessOverlay() {
        successContainer.addSubview(successCheck)
        successContainer.addSubview(successAmountLabel)
        successContainer.addSubview(successCaption)

        // Pre-configure the gradient layer; it's masked onto the
        // rendered glyphs in `applySuccessGradient()` after layout
        // resolves.
        successAmountGradient.colors = SPSupport.moneyGradientColors
        successAmountGradient.locations = SPSupport.moneyGradientLocations
        successAmountGradient.startPoint = SPSupport.gradientStart
        successAmountGradient.endPoint = SPSupport.gradientEnd

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            successCheck.centerXAnchor.constraint(equalTo: successContainer.centerXAnchor),
            successCheck.centerYAnchor.constraint(
                equalTo: successContainer.centerYAnchor,
                constant: -AppSpacing.sp7
            ),
            successCheck.widthAnchor.constraint(equalToConstant: 96),
            successCheck.heightAnchor.constraint(equalToConstant: 96),

            successAmountLabel.topAnchor.constraint(
                equalTo: successCheck.bottomAnchor,
                constant: AppSpacing.sp5
            ),
            successAmountLabel.leadingAnchor.constraint(
                equalTo: successContainer.leadingAnchor,
                constant: inset
            ),
            successAmountLabel.trailingAnchor.constraint(
                equalTo: successContainer.trailingAnchor,
                constant: -inset
            ),

            successCaption.topAnchor.constraint(
                equalTo: successAmountLabel.bottomAnchor,
                constant: AppSpacing.sp3
            ),
            successCaption.leadingAnchor.constraint(
                equalTo: successContainer.leadingAnchor,
                constant: inset
            ),
            successCaption.trailingAnchor.constraint(
                equalTo: successContainer.trailingAnchor,
                constant: -inset
            )
        ])
    }

    /// Mask a money-gradient layer onto the rendered glyphs of the
    /// success amount label. Mirrors `SPBalanceCard.applyValueGradient(...)`
    /// — see that recipe for the rationale (CALayer's `mask` is the
    /// closest CoreGraphics analogue of CSS's `background-clip: text`).
    func applySuccessGradient() {
        let bounds = successAmountLabel.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        if successAmountGradient.superlayer !== successAmountLabel.layer {
            successAmountLabel.layer.addSublayer(successAmountGradient)
        }
        successAmountGradient.frame = bounds

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let mask = renderer.image { _ in
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (successAmountLabel.text ?? "").draw(
                in: bounds,
                withAttributes: [
                    .font: successAmountLabel.font as Any,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: style
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = bounds
        maskLayer.contents = mask.cgImage
        successAmountGradient.mask = maskLayer
        successAmountLabel.textColor = .clear
    }

}

// State / notifications / balance refresh / alert helpers live in
// `TopUpViewController+State.swift` so this file stays under the
// per-file length limit. Subview factory lives in
// `TopUpViewControllerFactory.swift`.
