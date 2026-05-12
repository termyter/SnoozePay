import UIKit
import SwiftUI

/// Card-builder helpers for `StatisticsViewController` (V2 design).
///
/// Lifted into an extension so the main type body stays under SwiftLint's
/// `type_body_length` ceiling. Each `make…()` returns a fully-laid-out
/// `SPCard`-rooted view ready for insertion into `dataStack`.
extension StatisticsViewController {

    // MARK: - Hero "Серия" card

    /// Top hero card — caps "Серия" + huge mono streak count + flame badge
    /// on the right, and the GitHub-style heatmap rendered below the divider.
    /// Tapping anywhere on the card triggers `streakTapped()`.
    func makeHeroStreakCard() -> UIView {
        let card = SPCard(tone: .raised, padding: AppSpacing.sp6, cornerRadius: AppRadius.xl)
        let topRow = makeHeroTopRow()
        let heatStack = makeHeroHeatmapStack()
        let outer = UIStackView(arrangedSubviews: [topRow, heatStack])
        outer.axis = .vertical
        outer.spacing = AppSpacing.sp5
        outer.alignment = .fill
        outer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            outer.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            outer.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(streakTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
        return card
    }

    /// Top row of the hero card — text column on the left, flame badge on the
    /// right. Lifted out of `makeHeroStreakCard` to keep function bodies
    /// under SwiftLint's 60-line ceiling.
    private func makeHeroTopRow() -> UIView {
        let caps = makeCapsLabel("СЕРИЯ", color: AppColors.warn300)
        let numberRow = UIStackView(arrangedSubviews: [streakBigLabel, streakBigWordLabel])
        numberRow.axis = .horizontal
        numberRow.alignment = .firstBaseline
        numberRow.spacing = AppSpacing.sp2
        numberRow.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [caps, numberRow, streakMetaLabel])
        textStack.axis = .vertical
        textStack.spacing = AppSpacing.sp1
        textStack.alignment = .leading
        textStack.setCustomSpacing(AppSpacing.sp2, after: numberRow)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [textStack, makeFlameBadge()])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = AppSpacing.sp4
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Heatmap section of the hero card — caps caption + heatmap grid + a
    /// "раньше · сегодня" range hint row underneath.
    private func makeHeroHeatmapStack() -> UIView {
        let heatmapCaps = makeCapsLabel("КАЛЕНДАРЬ ОТКЛАДЫВАНИЙ", color: AppColors.fg3)
        let rangeLeft = makeMetaLabel("раньше", alignment: .left)
        let rangeRight = makeMetaLabel("сегодня", alignment: .right)
        let rangeRow = UIStackView(arrangedSubviews: [rangeLeft, rangeRight])
        rangeRow.axis = .horizontal
        rangeRow.distribution = .fillEqually
        rangeRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [heatmapCaps, heatmapView, rangeRow])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Convenience caps-styled label constructor used across the hero card.
    private func makeCapsLabel(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: color
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Meta-styled label constructor — 13pt fg3 with configurable alignment.
    private func makeMetaLabel(_ text: String, alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.text = text
        label.textAlignment = alignment
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// 56×56 rounded square with the warn gradient + flame icon. Matches
    /// the JSX recipe (radius 18, warn gradient, warn-tinted shadow).
    private func makeFlameBadge() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 18
        container.layer.masksToBounds = false
        container.layer.shadowColor = AppColors.warn500.cgColor
        container.layer.shadowOpacity = 0.30
        container.layer.shadowOffset = CGSize(width: 0, height: 8)
        container.layer.shadowRadius = 16

        let gradient = CAGradientLayer()
        gradient.colors = SPSupport.warnGradientColors
        gradient.locations = SPSupport.warnGradientLocations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = 18
        container.layer.insertSublayer(gradient, at: 0)

        let flame = UIImageView(
            image: UIImage(
                systemName: "flame.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            )
        )
        flame.tintColor = AppColors.fgOnWarn
        flame.contentMode = .scaleAspectFit
        flame.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(flame)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 56),
            container.heightAnchor.constraint(equalToConstant: 56),
            flame.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            flame.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        // Resize the gradient sublayer on layout so it tracks bounds even when
        // the badge gets repositioned by stacks.
        container.layoutIfNeeded()
        DispatchQueue.main.async {
            gradient.frame = container.bounds
        }
        return container
    }

    // MARK: - Weekly bar-chart card

    /// "Эта неделя" — caps + meta hint + Apple-Charts bar chart + summary row
    /// with Сэкономили / Потратили / Чистый. Wrapped in an `SPCard(.surface)`.
    func makeWeeklyCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5)

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "ЭТА НЕДЕЛЯ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        caps.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.font = AppTypography.meta
        hint.textColor = AppColors.fg3
        hint.text = "зелёное — копится · красное — теряется"
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        // Hosting controller for the SwiftUI chart.
        let chartView = WeekdayChartView(bars: [])
        let hosting = UIHostingController(rootView: chartView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.didMove(toParent: self)
        chartHostingController = hosting

        let topRow = UIStackView(arrangedSubviews: [caps, hint])
        topRow.axis = .vertical
        topRow.alignment = .leading
        topRow.spacing = AppSpacing.sp1
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // Summary row — 3 columns with caps caption + mono number.
        let summary = makeWeeklySummaryRow()

        let stack = UIStackView(arrangedSubviews: [topRow, hosting.view, summary])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            hosting.view.heightAnchor.constraint(equalToConstant: 140)
        ])
        return card
    }

    private func makeWeeklySummaryRow() -> UIView {
        let separator = UIView()
        separator.backgroundColor = AppColors.stroke1
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let savedColumn = makeSummaryColumn(caption: "СЭКОНОМИЛИ", valueLabel: savedAmountLabel)
        let spentColumn = makeSummaryColumn(caption: "ПОТРАТИЛИ", valueLabel: spentAmountLabel)
        let netColumn = makeSummaryColumn(caption: "ЧИСТЫЙ", valueLabel: netAmountLabel)

        let columns = UIStackView(arrangedSubviews: [savedColumn, spentColumn, netColumn])
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.alignment = .top
        columns.spacing = AppSpacing.sp2
        columns.translatesAutoresizingMaskIntoConstraints = false

        let wrap = UIStackView(arrangedSubviews: [separator, columns])
        wrap.axis = .vertical
        wrap.spacing = AppSpacing.sp4
        wrap.alignment = .fill
        wrap.translatesAutoresizingMaskIntoConstraints = false
        return wrap
    }

    private func makeSummaryColumn(caption: String, valueLabel: UILabel) -> UIView {
        let captionLabel = UILabel()
        captionLabel.attributedText = NSAttributedString(
            string: caption,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Wake-time card

    /// "Время подъёма" — three averaged mono numbers (В среднем / Раньше было /
    /// Раньше на). Until the wake-time ledger lands the values render `--`
    /// so the card still surfaces in the V2 layout.
    func makeWakeTimeCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5)

        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "ВРЕМЯ ПОДЪЁМА",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        caps.translatesAutoresizingMaskIntoConstraints = false

        let columns = UIStackView(arrangedSubviews: [
            wakeColumn(caption: "В СРЕДНЕМ", value: "--", valueColor: AppColors.fg1),
            wakeColumn(
                caption: "РАНЬШЕ БЫЛО",
                value: "--",
                valueColor: AppColors.fg3,
                strike: true
            ),
            wakeColumn(caption: "РАНЬШЕ НА", value: "--", valueColor: AppColors.money400)
        ])
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.alignment = .top
        columns.spacing = AppSpacing.sp2
        columns.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [caps, columns])
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

    private func wakeColumn(
        caption: String,
        value: String,
        valueColor: UIColor,
        strike: Bool = false
    ) -> UIView {
        let captionLabel = UILabel()
        captionLabel.attributedText = NSAttributedString(
            string: caption,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = AppTypography.moneySm
        valueLabel.textColor = valueColor
        if strike {
            valueLabel.attributedText = NSAttributedString(
                string: value,
                attributes: [
                    .font: AppTypography.moneySm,
                    .foregroundColor: valueColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: valueColor
                ]
            )
        } else {
            valueLabel.text = value
        }
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Debug

    #if DEBUG
    /// Three-row DEBUG section that exposes the StreakModalV2 / Referral /
    /// AlarmOff modals while we don't have real trigger plumbing. Drops out
    /// of release builds via the `#if DEBUG` gate.
    func makeDebugButtonsRow() -> UIView {
        let caps = UILabel()
        caps.attributedText = NSAttributedString(
            string: "DEBUG · MODALS",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        caps.translatesAutoresizingMaskIntoConstraints = false

        let streakBtn = SPButton(title: "Streak modal", variant: .money, size: .md, fullWidth: true)
        streakBtn.addTarget(self, action: #selector(debugStreakTapped), for: .touchUpInside)

        let referralBtn = SPButton(title: "Реферальная программа", variant: .quiet, size: .md, fullWidth: true)
        referralBtn.addTarget(self, action: #selector(debugReferralTapped), for: .touchUpInside)

        let alarmOffBtn = SPButton(title: "AlarmOff warning", variant: .pain, size: .md, fullWidth: true)
        alarmOffBtn.addTarget(self, action: #selector(debugAlarmOffTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [caps, streakBtn, referralBtn, alarmOffBtn])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    #endif
}
