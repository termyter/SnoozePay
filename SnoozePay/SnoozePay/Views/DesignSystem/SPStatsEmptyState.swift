import UIKit

/// State column for the behavioural statistics screen (V3 design).
///
/// Reference: `docs/design/v2-handoff/components/SPMore.jsx` L447-480
/// (`EmptyStats`). It has two modes: it is shown when the user has no charges
/// and no recorded wake events (there is nothing to aggregate yet, #289), or
/// when the ledger is unreadable / only partially readable (#459). The latter
/// withholds the whole ledger-derived screen rather than drawing a false clean
/// streak from surviving wake events.
///
/// Visual:
/// ```
///                ┌───────────┐
///                │    📊     │   <- 84×84 soft money-tint rounded square
///                └───────────┘
///            Пока нечего считать          <- h2 fg1
///   Статистика появится после первой
///   недели использования.                <- body-lg fg2
///        ( 🔥 Серия · 2 дня )            <- money-tinted pill
/// ```
final class SPStatsEmptyState: UIView {

    // MARK: - Subviews

    /// 84×84 rounded square with the soft money tint + money-400 border from
    /// the JSX recipe (`linear-gradient(135deg, rgba(46,219,159,.16),
    /// rgba(46,219,159,.04))`, `1px solid rgba(46,219,159,.25)`).
    private let iconHost: SPGradientView = {
        let view = SPGradientView(
            colors: [
                AppColors.money400.withAlphaComponent(0.16).cgColor,
                AppColors.money400.withAlphaComponent(0.04).cgColor
            ],
            locations: [0.0, 1.0]
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 24
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.money400.withAlphaComponent(0.25).cgColor
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.money400
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        view.image = UIImage(systemName: "chart.bar.xaxis", withConfiguration: config)
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Пока нечего считать"
        label.font = AppTypography.h2
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Статистика появится после первой недели использования."
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// Money-tinted pill: flame icon + "Серия · N дня".
    private let streakChip = UIView()
    private let streakChipLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.meta
        label.textColor = AppColors.money300
        return label
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Update the streak chip's day count + Russian declension.
    func setStreak(_ days: Int) {
        restoreEmptyAppearance()
        let word = StreakModalViewController.dayWord(for: days)
        // Canonical term is «Серия», not the «Стрик» anglicism (#318) — the
        // hero card of this same screen already reads «Серия».
        streakChipLabel.text = "Серия · \(days) \(word)"
        // Hide the chip entirely when there is no streak to celebrate.
        streakChip.isHidden = days <= 0
    }

    /// Replaces the no-data copy when the ledger is unavailable or partially
    /// readable. This keeps an incomplete history distinct from a genuinely
    /// new account and prevents a false clean streak.
    func setUnavailable(_ message: String) {
        titleLabel.text = "Статистика недоступна"
        subtitleLabel.text = message
        iconView.image = UIImage(
            systemName: "exclamationmark.triangle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        )
        iconView.tintColor = AppColors.warn300
        streakChip.isHidden = true
    }

    private func restoreEmptyAppearance() {
        titleLabel.text = "Пока нечего считать"
        subtitleLabel.text = "Статистика появится после первой недели использования."
        iconView.image = UIImage(
            systemName: "chart.bar.xaxis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        )
        iconView.tintColor = AppColors.money400
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear

        iconHost.addSubview(iconView)
        let chip = makeStreakChip()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = AppSpacing.sp2  // ~10pt
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let column = UIStackView(arrangedSubviews: [iconHost, textStack, chip])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = AppSpacing.sp5  // 20 — icon→title gap per JSX
        column.setCustomSpacing(AppSpacing.sp6, after: textStack)  // 24 — text→chip
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            iconHost.widthAnchor.constraint(equalToConstant: 84),
            iconHost.heightAnchor.constraint(equalToConstant: 84),
            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),

            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.sp7),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.sp7),
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
    }

    private func makeStreakChip() -> UIView {
        streakChip.translatesAutoresizingMaskIntoConstraints = false
        streakChip.backgroundColor = AppColors.money400.withAlphaComponent(0.10)
        streakChip.layer.cornerRadius = 999
        streakChip.layer.borderWidth = 1
        streakChip.layer.borderColor = AppColors.money400.withAlphaComponent(0.20).cgColor

        let flame = UIImageView(
            image: UIImage(
                systemName: "flame.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            )
        )
        flame.tintColor = AppColors.money400
        flame.contentMode = .scaleAspectFit
        flame.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [flame, streakChipLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp2
        row.translatesAutoresizingMaskIntoConstraints = false
        streakChip.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: streakChip.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: streakChip.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: streakChip.leadingAnchor, constant: AppSpacing.sp3),
            row.trailingAnchor.constraint(equalTo: streakChip.trailingAnchor, constant: -AppSpacing.sp3)
        ])
        return streakChip
    }
}
