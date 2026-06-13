import UIKit

/// Fixed page-title header — an h1 title row over a 1pt hairline, with no back
/// button. Mirrors the chrome of `SPAlarmsListHeader` (#280) minus the balance
/// pill, for screens whose design calls for the same title block as Будильники
/// / Кошелёк (`SPMore4.jsx:100-109`). The host controller hides the system nav
/// bar so the screen doesn't render the title twice.
///
/// ```
///  ┌────────────────────────────────────────┐
///  │ Статистика                              │   <- h1, 16pt insets
///  └────────────────────────────────────────┘
///  ── 1pt whiteOverlay06 hairline ──
/// ```
final class SPPageHeader: UIView {

    private let titleLabel = UILabel()

    private let bottomHairline: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay06
        return view
    }()

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = AppColors.bg0
        configure(title: title)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPPageHeader, _) in
                // CALayer-backed colours don't auto-resolve on trait change.
                view.bottomHairline.backgroundColor = AppColors.whiteOverlay06
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(title: String) {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // h1 32pt extrabold with full -0.02em tracking — same recipe as the
        // AlarmsList header title (`SPScreensV2.jsx:315`, tokens.css L80).
        titleLabel.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: AppTypography.h1,
                .kern: AppTypography.kern(em: -0.02, size: 32),
                .foregroundColor: AppColors.fg1
            ]
        )

        addSubview(titleLabel)
        addSubview(bottomHairline)

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            // 16pt insets per the design page-title block.
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp4),

            bottomHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomHairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomHairline.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
}
