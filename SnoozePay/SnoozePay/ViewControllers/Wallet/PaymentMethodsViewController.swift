import UIKit

/// Payment methods screen — V2 design `PaymentMethods` in
/// `docs/design/v2-handoff/components/SPMore3.jsx` (L239-305).
///
/// Renders a single hero Apple Pay card (dark glassy fill, white Apple
/// glyph) followed by a ghost "Add card" tile that is intentionally a
/// no-op — StoreKit IAP handles all monetary flow, so additional cards
/// are not surfaced.
final class PaymentMethodsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        title = "Способы оплаты"
        navigationItem.largeTitleDisplayMode = .never
        setupLayout()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.sp5,
            leading: AppSpacing.screenInset,
            bottom: AppSpacing.sp7,
            trailing: AppSpacing.screenInset
        )
        stack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        stack.addArrangedSubview(makeApplePayCard())
        stack.addArrangedSubview(makeAddCardPlaceholder())
        stack.addArrangedSubview(makeFooterCaption())
    }

    private func makeApplePayCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1) // #15151A
        card.layer.cornerRadius = AppRadius.lg
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        card.layer.masksToBounds = true

        let defaultCaps = UILabel()
        defaultCaps.translatesAutoresizingMaskIntoConstraints = false
        defaultCaps.attributedText = NSAttributedString(
            string: "ПО УМОЛЧАНИЮ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
        )
        card.addSubview(defaultCaps)

        let applePay = makeApplePayLabel()
        applePay.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(applePay)

        let descCaps = UILabel()
        descCaps.translatesAutoresizingMaskIntoConstraints = false
        descCaps.attributedText = NSAttributedString(
            string: "ОПЛАТА ПОКУПОК",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: UIColor.white.withAlphaComponent(0.4)
            ]
        )
        card.addSubview(descCaps)

        let hint = UILabel()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = AppTypography.meta
        hint.textColor = UIColor.white.withAlphaComponent(0.5)
        hint.text = "Управляется в приложении Wallet"
        hint.numberOfLines = 0
        card.addSubview(hint)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 200),
            defaultCaps.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.sp5),
            defaultCaps.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp5),

            applePay.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.sp4),
            applePay.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.sp5),

            descCaps.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp5),
            descCaps.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -AppSpacing.sp1),

            hint.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp5),
            hint.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.sp5),
            hint.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.sp5)
        ])
        return card
    }

    private func makeApplePayLabel() -> UIView {
        // Compact Apple-glyph + "Pay" wordmark. Apple's HIG forbids
        // distributing the glyph asset in third-party code, so we render a
        // SF Symbol "applelogo" approximation alongside the wordmark.
        let container = UIStackView()
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 4
        let logo = UIImageView(image: UIImage(systemName: "applelogo"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.tintColor = .white
        logo.contentMode = .scaleAspectFit
        let pay = UILabel()
        pay.font = AppFonts.sans(.bold, 18)
        pay.textColor = .white
        pay.text = "Pay"
        container.addArrangedSubview(logo)
        container.addArrangedSubview(pay)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 18),
            logo.heightAnchor.constraint(equalToConstant: 22)
        ])
        return container
    }

    private func makeAddCardPlaceholder() -> UIView {
        let card = SPCard(tone: .outline, padding: AppSpacing.sp5, cornerRadius: AppRadius.md)
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "plus"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AppColors.fg3
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.text = "Добавить карту"

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp2
        card.addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            row.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            row.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        return card
    }

    private func makeFooterCaption() -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg4
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Пока поддерживается только Apple Pay"
        return label
    }
}
