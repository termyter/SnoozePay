import UIKit

/// Stateless factory for the `TopUpViewController` subview ladder.
/// Pulled out of the controller so the stored-property initialisers
/// stay readable and the lint thresholds for the host class are easy
/// to hold under future tweaks.
enum TopUpViewControllerFactory {

    static func capsLabel(text: String) -> UILabel {
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

    static func bodyLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.numberOfLines = 0
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func successCheckImageView() -> UIImageView {
        let configuration = UIImage.SymbolConfiguration(pointSize: 80, weight: .regular)
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: configuration)
        let view = UIImageView(image: image)
        view.tintColor = AppColors.money500
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func successAmountLabel() -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneyXl
        // Neutral colour — `applySuccessGradient(...)` masks a money
        // gradient onto the rendered glyphs once layout resolves so the
        // amount renders with the same brand sweep as `SPBalanceCard`.
        label.textColor = AppColors.money400
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func successCaptionLabel() -> UILabel {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.text = "Зачислено на баланс"
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func applePayButton(amount: Int) -> SPButton {
        let button = SPButton(
            title: "Пополнить \(MoneyFormatter.string(amount))",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "applelogo"),
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Walk the view tree to the first `UILabel`. Used to reach into
    /// `SPRow` for the one-off quiet-variant title style without adding
    /// a public hook to the design-system primitive.
    static func findTitleLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for sub in view.subviews {
            if let label = findTitleLabel(in: sub) {
                return label
            }
        }
        return nil
    }
}
