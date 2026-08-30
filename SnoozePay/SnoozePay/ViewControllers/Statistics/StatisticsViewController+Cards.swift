import UIKit

/// Card-builder helpers for `StatisticsViewController` (V3 behavioural
/// design, #235).
///
/// Lifted into an extension so the main type body stays under SwiftLint's
/// `type_body_length` ceiling. Each `make…()` returns a fully-laid-out
/// `SPCard`-rooted view ready for insertion into `contentStack`.
extension StatisticsViewController {

    // MARK: - Constants

    /// Flame badge geometry from the JSX recipe — 56pt square, radius 18.
    /// Both sit between `AppRadius` steps, so they are named here rather than
    /// rounded onto a token that would change the artboard.
    static let flameBadgeSide: CGFloat = 56
    static let flameBadgeRadius: CGFloat = 18
    static let flameBadgeIconSize: CGFloat = 26

    // MARK: - Hero "Серия" card

    /// Top hero card — caps "СЕРИЯ" + huge mono streak count + flame badge
    /// on the right, and the calendar-month heatmap below. Tapping the top
    /// row opens the streak modal; taps on the heatmap belong to the grid
    /// (cell tooltip, artboard 27a) so the gesture lives on the row, not
    /// the whole card.
    func makeHeroStreakCard() -> UIView {
        // Radius 24 + 24v/20h padding per `SPMore4.jsx` (audit P2-3 #289).
        // SPCard's `padding:` is uniform, so seed it with the vertical inset and
        // override `layoutMargins` to tighten the horizontal sides to 20.
        let card = SPCard(tone: .raised, padding: AppSpacing.sp6, cornerRadius: AppSpacing.sp6)
        card.layoutMargins = UIEdgeInsets(
            top: AppSpacing.sp6, left: AppSpacing.sp5,
            bottom: AppSpacing.sp6, right: AppSpacing.sp5
        )
        // The tooltip bubble overhangs the card's bottom edge for last-row
        // cells — let it escape instead of clipping (issue acceptance:
        // "Tooltip рендерится корректно, не обрезается сеткой").
        card.clipsToBounds = false

        let topRow = makeHeroTopRow()
        // The heatmap paints four states and used to name none of them. The
        // only legend on this screen belongs to the NEXT card down («ЭТА
        // НЕДЕЛЯ»: «зелёное — сэкономлено · красное — потеряно»), and read as
        // this chart's caption it misled twice over — the map has no red in a
        // clean month, and it has a gold the neighbour never mentions (#637).
        // Placement mirrors `SPWeekMoneyCard`, which puts its own legend
        // directly against its chart.
        let legend = SPSupport.makeMetaLabel(Localized.text("statistics.streak.legend"))
        legend.numberOfLines = 0
        let outer = UIStackView(arrangedSubviews: [topRow, heatmapView, legend])
        outer.axis = .vertical
        outer.spacing = AppSpacing.sp5
        outer.alignment = .fill
        outer.setCustomSpacing(AppSpacing.sp3, after: heatmapView)
        outer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            outer.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            outer.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(streakTapped))
        topRow.addGestureRecognizer(tap)
        topRow.isUserInteractionEnabled = true
        return card
    }

    /// Top row of the hero card — text column on the left, flame badge on the
    /// right.
    private func makeHeroTopRow() -> UIView {
        let caps = makeCapsLabel("СЕРИЯ", color: StatisticsAccentTones.warn)
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

    /// 56×56 rounded square with the warn gradient + flame icon. Matches
    /// the JSX recipe (radius 18, warn gradient, warn-tinted shadow).
    ///
    /// An `SPGradientView` — the gradient IS the view's layer, so Auto Layout
    /// sizes it — not a `CAGradientLayer` inserted as a sublayer. The sublayer
    /// version (#529) assigned its frame exactly once, from a
    /// `DispatchQueue.main.async` hop after a `layoutIfNeeded()`. That renders
    /// on the first pass only because the badge is pinned to a fixed 56×56;
    /// every later resize (Dynamic Type, rotation, a rebuilt card) left the
    /// fill at its old size and the flame on bare card. The same shape already
    /// cost the streak modal an invisible badge in #516 — measured 1.01:1 dark
    /// / 1.16:1 light on the sheet fill. A `layerClass` gradient cannot be
    /// forgotten.
    ///
    /// Internal rather than private so `StatisticsFlameBadgeTests` can resize
    /// the badge and measure the fill; no token-level assertion catches a
    /// gradient that is merely the wrong size.
    func makeFlameBadge() -> SPGradientView {
        // Stops start empty on purpose: `SPSupport.warnGradientColors` reads
        // `UITraitCollection.current`, which inside a builder method is not
        // necessarily the badge's own trait collection. `applyWarnPalette`
        // installs them from the trait-explicit overload instead.
        let badge = SPGradientView(colors: [], locations: SPSupport.warnGradientLocations)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = Self.flameBadgeRadius
        badge.layer.cornerCurve = .continuous
        // No `masksToBounds`: the gradient is the view's own layer, so
        // `cornerRadius` already rounds the fill, and clipping would eat the
        // warn-tinted shadow.
        badge.layer.masksToBounds = false
        badge.layer.shadowOpacity = 0.30
        badge.layer.shadowOffset = CGSize(width: 0, height: AppSpacing.sp2)
        badge.layer.shadowRadius = AppSpacing.sp4

        // Both the gradient stops and the tinted shadow are CGColors: they
        // freeze at whatever theme was current when the card was built, and
        // this card is built once in `viewDidLoad`. Re-resolve on every flip.
        let applyWarnPalette = { [weak badge] in
            guard let badge else { return }
            badge.refresh(
                colors: SPSupport.warnGradientColors(for: badge.traitCollection),
                locations: SPSupport.warnGradientLocations
            )
            badge.layer.shadowColor = AppColors.warnFill500
                .resolvedColor(with: badge.traitCollection).cgColor
        }
        applyWarnPalette()
        badge.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: UIView, _) in
            applyWarnPalette()
        }

        let flame = UIImageView(
            image: UIImage(
                systemName: "flame.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Self.flameBadgeIconSize, weight: .semibold
                )
            )
        )
        // `fgOnWarn` is ink on a SOLID warn fill — white in light, near-black
        // in dark. Correct here (the badge *is* a solid gradient tile) and
        // wrong anywhere the warn tone is only a wash.
        flame.tintColor = AppColors.fgOnWarn
        flame.contentMode = .scaleAspectFit
        flame.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(flame)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.flameBadgeSide),
            badge.heightAnchor.constraint(equalToConstant: Self.flameBadgeSide),
            flame.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            flame.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    // MARK: - "По дням недели" card

    /// Weekday distribution — caps + "Чаще всего — среда" headline + 4-week
    /// meta line + the seven-bar chart with the worst day in pain.
    func makeWeekdayCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)

        let caps = makeCapsLabel("ПО ДНЯМ НЕДЕЛИ", color: AppColors.fg3)
        let meta = makeMetaLabel("За последние 4 недели")

        let header = UIStackView(arrangedSubviews: [caps, weekdayHeadlineLabel, meta])
        header.axis = .vertical
        header.alignment = .leading
        header.spacing = AppSpacing.sp1
        header.setCustomSpacing(AppSpacing.sp2, after: caps)
        header.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [header, weekdayBarsView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp4
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

    // MARK: - "Динамика откладываний" card

    /// 8-week trend — headline + diagonal arrow on the left, "Эта неделя"
    /// count on the right, the bar trend below and the axis caption row.
    func makeTrendCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)

        let caps = makeCapsLabel("ДИНАМИКА ОТКЛАДЫВАНИЙ", color: AppColors.fg3)

        let headlineRow = UIStackView(arrangedSubviews: [trendHeadlineLabel, trendArrowView])
        headlineRow.axis = .horizontal
        headlineRow.alignment = .center
        headlineRow.spacing = AppSpacing.sp2
        headlineRow.translatesAutoresizingMaskIntoConstraints = false

        let leftColumn = UIStackView(arrangedSubviews: [headlineRow, trendSubtitleLabel])
        leftColumn.axis = .vertical
        leftColumn.alignment = .leading
        // Half a grid step: the caption and the number below it are one unit.
        leftColumn.spacing = AppSpacing.sp1 / 2
        leftColumn.translatesAutoresizingMaskIntoConstraints = false

        let weekCaption = makeMetaLabel("Эта неделя")
        weekCaption.textAlignment = .right
        let rightColumn = UIStackView(arrangedSubviews: [weekCaption, trendWeekValueLabel])
        rightColumn.axis = .vertical
        rightColumn.alignment = .trailing
        rightColumn.spacing = AppSpacing.sp1 / 2
        rightColumn.translatesAutoresizingMaskIntoConstraints = false

        let summaryRow = UIStackView(arrangedSubviews: [leftColumn, rightColumn])
        summaryRow.axis = .horizontal
        summaryRow.alignment = .top
        summaryRow.distribution = .equalSpacing
        summaryRow.spacing = AppSpacing.sp3
        summaryRow.translatesAutoresizingMaskIntoConstraints = false

        let axisLeft = makeMetaLabel("8 недель назад")
        let axisRight = makeMetaLabel("эта неделя")
        axisRight.font = AppFonts.sans(.semibold, 13)
        axisRight.textColor = AppColors.fg1
        axisRight.textAlignment = .right
        let axisRow = UIStackView(arrangedSubviews: [axisLeft, axisRight])
        axisRow.axis = .horizontal
        axisRow.distribution = .fillEqually
        axisRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [caps, summaryRow, trendBarsView, axisRow])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp4, after: summaryRow)
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

    // MARK: - Shared label constructors

    /// Thin forwarders onto the design-system constructors. The recipes moved
    /// into `SPSupport` once #348 added two more cards that needed byte-identical
    /// copies of them; these stay so the call sites below keep reading as
    /// `makeCapsLabel(…)` rather than a fully-qualified mouthful.
    private func makeCapsLabel(_ text: String, color: UIColor) -> UILabel {
        SPSupport.makeCapsLabel(text, color: color)
    }

    private func makeMetaLabel(_ text: String) -> UILabel {
        SPSupport.makeMetaLabel(text)
    }

    // MARK: - Debug

    #if DEBUG
    /// DEBUG section exposing the StreakModalV2 / Referral / AlarmOff modals
    /// while we don't have real trigger plumbing. Drops out of release builds
    /// via the `#if DEBUG` gate (kept per issue #235 scope).
    ///
    /// The referral shortcut follows `AppFeatureFlags.referralEnabled` along
    /// with the Settings section (#676): it is the only other way into
    /// `ReferralViewController`, and leaving it wired would make "hidden"
    /// depend on which build you happen to be running.
    func makeDebugButtonsRow() -> UIView {
        let caps = makeCapsLabel("DEBUG · MODALS", color: AppColors.fg3)

        let streakBtn = SPButton(title: "Streak modal", variant: .money, size: .md, fullWidth: true)
        streakBtn.addTarget(self, action: #selector(debugStreakTapped), for: .touchUpInside)

        var buttons: [UIView] = [caps, streakBtn]

        if AppFeatureFlags.referralEnabled {
            let referralBtn = SPButton(title: "Реферальная программа", variant: .quiet, size: .md, fullWidth: true)
            referralBtn.addTarget(self, action: #selector(debugReferralTapped), for: .touchUpInside)
            buttons.append(referralBtn)
        }

        let alarmOffBtn = SPButton(title: "AlarmOff warning", variant: .pain, size: .md, fullWidth: true)
        alarmOffBtn.addTarget(self, action: #selector(debugAlarmOffTapped), for: .touchUpInside)
        buttons.append(alarmOffBtn)

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    #endif
}
