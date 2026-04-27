import UIKit
import SwiftUI

/// Card-builder helpers for `StatisticsViewController`.
///
/// Lifted into an extension so the main type body stays under SwiftLint's
/// `type_body_length` ceiling. Each `make…()` returns a fully-laid-out
/// `SPCard`-rooted view ready for insertion into `dataStack`. The factories
/// are non-private so the controller can call them from another file —
/// internal access is enough to keep them out of the module's public surface.
extension StatisticsViewController {

    // MARK: - Summary row

    /// Two-column summary row: pain-tinted "Потрачено" + neutral "Откладываний".
    /// Returns a horizontal `UIStackView` rather than a single SPCard so the
    /// two values can sit side-by-side without nesting cards inside cards.
    func makeSummaryRow() -> UIView {
        let leftCard = makeSummaryTile(caption: "Потрачено", valueLabel: spentAmountLabel)
        let rightCard = makeSummaryTile(caption: "Откладываний", valueLabel: snoozeCountLabel)
        let row = UIStackView(arrangedSubviews: [leftCard, rightCard])
        row.axis = .horizontal
        row.spacing = AppSpacing.sp3
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// One tile inside the summary row — caps caption above a `moneyMd`
    /// numeric value, both inside an `SPCard(.surface)` with the standard
    /// 16pt internal padding.
    func makeSummaryTile(caption: String, valueLabel: UILabel) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)

        let captionLabel = UILabel()
        captionLabel.attributedText = NSAttributedString(
            string: caption.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        return card
    }

    // MARK: - Heatmap

    /// Heatmap card — title + 7-column heatmap grid wrapped in an SPCard.
    func makeHeatmapCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)
        let titleLabel = UILabel()
        titleLabel.text = "Календарь"
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = AppColors.fg1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, heatmapView])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        return card
    }

    // MARK: - Chart

    /// Chart card — title + Apple-Charts bar chart wrapped in an SPCard.
    /// Stores the hosting controller on the VC so `refresh()` can swap the
    /// rootView when the period changes without re-building the SwiftUI
    /// hierarchy.
    func makeChartCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)
        let titleLabel = UILabel()
        titleLabel.text = "Средний штраф по дням"
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = AppColors.fg1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let chartView = WeekdayChartView(bars: [])
        let hosting = UIHostingController(rootView: chartView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.didMove(toParent: self)
        chartHostingController = hosting

        let stack = UIStackView(arrangedSubviews: [titleLabel, hosting.view])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            hosting.view.heightAnchor.constraint(equalToConstant: 200)
        ])
        return card
    }

    // MARK: - Streak

    /// Tappable streak card — flame icon + caption + current/best lines +
    /// trailing chevron. Tapping anywhere on the card triggers
    /// `streakTapped()` which presents `StreakModalViewController`.
    func makeStreakCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp4)

        let flameConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let flameView = UIImageView(image: UIImage(systemName: "flame.fill", withConfiguration: flameConfig))
        flameView.tintColor = AppColors.warn500
        flameView.translatesAutoresizingMaskIntoConstraints = false
        flameView.setContentHuggingPriority(.required, for: .horizontal)

        let titleCaption = UILabel()
        titleCaption.attributedText = NSAttributedString(
            string: "ТЕКУЩАЯ СЕРИЯ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        titleCaption.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleCaption, streakValueLabel, streakBestLabel])
        textStack.axis = .vertical
        textStack.spacing = AppSpacing.sp1
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AppColors.fg3
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [flameView, textStack, chevron])
        row.axis = .horizontal
        row.spacing = AppSpacing.sp3
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            flameView.widthAnchor.constraint(equalToConstant: 32),
            flameView.heightAnchor.constraint(equalToConstant: 32)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(streakTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
        return card
    }
}
