import UIKit

/// Empty-state column for the alarms list (V3 design).
///
/// Reference (`EmptyAlarms`):
/// `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:379-409` contains "function EmptyAlarms".
///
/// Visual:
/// ```
///                ┌───────────┐
///                │    🔔     │   <- 84×84 whiteOverlay06 tile, bell fg3
///                └───────────┘
///         Ни одного будильника    <- h2
///   Создайте первый — выставите
///   время, цену откладывания и
///   положите баланс.              <- body-lg fg2
///
///        [  ＋ Создать будильник  ]  <- intrinsic-width money lg
/// ```
///
/// Hosted as an overlay over the table view in
/// `AlarmsListViewController` and toggled via `isHidden`.
final class SPAlarmsListEmptyState: UIView {

    // MARK: - Public API

    /// Triggered when the user taps «Создать будильник».
    var onAddAlarmTap: (() -> Void)?

    // MARK: - Subviews

    /// 84×84 whiteOverlay06 tile (radius 24, whiteOverlay08 hairline) hosting
    /// the bell glyph,
    /// `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:388-394` contains "IconBell size={40}".
    /// A quiet neutral tile, not the warn-gradient hero the V2 layout used
    /// (#280).
    private let iconHost: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay06
        view.layer.cornerRadius = AppRadius.xl  // 24pt → matches `borderRadius: 24`
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fg3
        // Code-drawn outline bell at fg3,
        // `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:393` contains "IconBell size={40}".
        view.image = SPIcons.bell(size: 40)
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // h2 24pt bold with −0.01em tracking per
        // `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:395-396` contains "Ни одного будильника".
        label.attributedText = NSAttributedString(
            string: Localized.text("alarms.empty.title"),
            attributes: [
                .font: AppTypography.h2,
                .kern: AppTypography.h2Kerning,
                .foregroundColor: AppColors.fg1
            ]
        )
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // Drops the previously banned «снуз» word — copy per
        // `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:399` contains "Создайте первый".
        label.text = Localized.text("alarms.empty.body")
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// Intrinsic-width money CTA — NOT full-width: the design wraps the button
    /// in a plain `<div>` so it hugs its label,
    /// `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:401-403` contains "Создать будильник".
    private let addButton: SPButton = {
        let button = SPButton(
            title: Localized.text("alarms.empty.button"),
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "plus")
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPAlarmsListEmptyState, _) in
                view.refreshDynamicColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    private func refreshDynamicColors() {
        // CALayer cgColor doesn't auto-resolve dynamic UIColors.
        iconHost.layer.borderColor = AppColors.whiteOverlay08.cgColor
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear

        addSubview(iconHost)
        iconHost.addSubview(iconView)
        iconHost.layer.borderColor = AppColors.whiteOverlay08.cgColor

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        // h2 → body-lg gap of 10pt (`marginTop: 10`) per
        // `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:398-399` contains "Создайте первый".
        textStack.spacing = 10
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        addSubview(addButton)

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            // Icon centered, 84×84.
            iconHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconHost.bottomAnchor.constraint(equalTo: textStack.topAnchor, constant: -AppSpacing.sp5),
            iconHost.widthAnchor.constraint(equalToConstant: 84),
            iconHost.heightAnchor.constraint(equalToConstant: 84),

            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),

            // Text — centered group, ~280pt max width (`maxWidth: 280`).
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.sp7),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.sp7),
            textStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

            // CTA — intrinsic width, centered, 28pt below the text
            // (`marginTop: 28`).
            addButton.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: AppSpacing.sp7),
            addButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            addButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.screenInset),
            addButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.screenInset)
        ])
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddAlarmTap?()
    }
}
