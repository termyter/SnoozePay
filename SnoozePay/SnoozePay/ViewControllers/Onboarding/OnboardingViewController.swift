import UIKit

/// First-launch onboarding — V2 redesign
/// (`docs/design/v2-handoff/components/SPMore.jsx` lines 9-149).
///
/// Three full-screen pages on a horizontally-paged `UIScrollView`:
/// 1. Concept — giant clock "07:00" with a warn "−50 ₽" pill and a hero h1.
/// 2. Mechanics — three numbered steps explaining the snooze-tax loop.
/// 3. Deposit — caps eyebrow, h1, three option cards (250 / 500 / 1000 ₽)
///    with a money-tinted selection, plus a "Пополнить {value} ₽" CTA and a
///    secondary "Позже — попробовать без баланса" link.
///
/// V3 (2026-06 handoff, `docs/design/v2-handoff/components/SPMore.jsx`):
/// a "Пропустить" pill floats top-right on every page, the deposit page
/// content centres vertically like pages 1/2, and the green CTA keeps the
/// same bottom Y on all pages (the secondary "Позже" slot stays in the
/// layout on pages 1/2 at alpha 0 — the UIKit equivalent of the JSX's
/// 20pt CTA-anchor spacer).
///
/// Behavioural contract preserved from V1 so SceneDelegate keeps working:
/// `completedKey`, `isCompleted`, `firstTopUpDoneKey`, and `onFinished` all
/// behave exactly as before. The `UIPageControl` is kept as a direct subview
/// (alpha 0) so the existing `OnboardingTests` page-count test keeps passing;
/// visually the V2 design renders a bespoke pill-dot row instead.
final class OnboardingViewController: UIViewController {

    // MARK: - Persistence keys

    static let completedKey = "onboarding_completed"
    /// Set to `false` when the user finishes step 3 without paying, so future
    /// analytics / re-engagement can distinguish "user opted out of the
    /// first deposit" from "user paid".
    static let firstTopUpDoneKey = "first_top_up_done"

    /// `true` once the user has finished onboarding (either Apple Pay path
    /// or "Позже" path). Read by `SceneDelegate`.
    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    // MARK: - Page data

    /// Deposit presets shown on step 3. The middle preset is the default
    /// selection so the "Пополнить" CTA reads "500 ₽" on first appear.
    struct DepositOption {
        let amount: Decimal
        let title: String
        let description: String
        let isPopular: Bool
    }

    /// `internal` so the cross-file `+Pages` extension can read these when
    /// building option cards and the CTA suffix.
    let depositOptions: [DepositOption] = [
        DepositOption(
            amount: 250,
            title: "Попробовать",
            description: "≈ 5 откладываний по \(MoneyFormatter.string(50))",
            isPopular: false
        ),
        DepositOption(
            amount: 500,
            title: "Серьёзно",
            description: "≈ 10 откладываний · хватит на 2 недели",
            isPopular: true
        ),
        DepositOption(
            amount: 1000,
            title: "Решительно",
            description: "≈ 20 откладываний · спокойный месяц",
            isPopular: false
        )
    ]

    /// Default-selected option index — the "Серьёзно" 500 ₽ preset.
    let defaultDepositIndex: Int = 1

    /// Cached page count — drives `UIPageControl.numberOfPages` and the
    /// custom pill-dot row.
    let pageCount: Int = 3

    // MARK: - Callback

    /// Invoked once the user finishes (or skips) onboarding. SceneDelegate
    /// swaps the root from the onboarding flow to the tab bar.
    var onFinished: (() -> Void)?

    // MARK: - State

    /// Currently-selected deposit option index — drives the option-card
    /// selection ring and the CTA suffix amount. `internal` so the
    /// `+Pages` extension can flip it on option tap.
    var selectedDepositIndex: Int

    // MARK: - Chrome subviews

    /// Horizontal pager hosting the three pages.
    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    /// Standard UIPageControl — kept as a direct subview of `view` with
    /// `alpha = 0` so `OnboardingTests.testOnboardingPages_count` keeps
    /// passing. The visible page indicator is the custom `dotsStack` below
    /// (rendered as pill bars that lengthen the active page per V2 spec).
    let pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.isUserInteractionEnabled = false
        pageControl.alpha = 0
        return pageControl
    }()

    /// Custom pill-dot row — three 6×6 pills, the active one stretches to
    /// 24×6 with a money gradient fill. `internal` so the `+Pages` extension
    /// can rebuild the row on page settle.
    let dotsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AppSpacing.sp1 + 2   // 6pt — matches `gap: 6` JSX
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()

    /// "Пропустить" escape hatch floating top-right on every page
    /// (`SPMore.jsx OnboardingSkip` — pill 16pt below the status bar, 16pt
    /// from the trailing edge, `whiteOverlay06` fill + `whiteOverlay08`
    /// hairline, `fg3` buttonSm label). Completes onboarding exactly like
    /// the "Позже" secondary.
    let skipButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 14, bottom: 6, trailing: 14
        )
        configuration.attributedTitle = AttributedString(
            "Пропустить",
            attributes: AttributeContainer([
                .font: AppTypography.buttonSm,
                .foregroundColor: AppColors.fg3
            ])
        )
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = AppColors.whiteOverlay06
        button.layer.borderWidth = 1
        button.layer.borderColor = AppColors.whiteOverlay08.cgColor
        button.layer.masksToBounds = true
        return button
    }()

    /// Primary CTA visible on every page. On pages 1 & 2 the title reads
    /// "Дальше"; on page 3 the VC swaps the instance via
    /// `rebuildDepositCTA()` so the title becomes "Пополнить" with a money
    /// suffix and a leading wallet icon. `internal` so the `+Pages` extension
    /// can swap the live instance + re-pin the constraints.
    var primaryButton = SPButton(
        title: "Дальше",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    /// Secondary "Позже — попробовать без баланса" link visible only on
    /// step 3. Always part of `ctaStack`'s layout — on steps 1/2 it fades to
    /// alpha 0 (interaction off) instead of collapsing, so the green primary
    /// CTA keeps the exact same bottom Y across all pages (the JSX mockup
    /// approximates this with a 20pt spacer; the shared-stack layout makes
    /// the alignment exact).
    let laterButton = SPButton(
        title: "Позже — попробовать без баланса",
        variant: .quiet,
        size: .md,
        fullWidth: true
    )

    /// Vertical stack hosting [primaryButton, laterButton] at the bottom of
    /// the screen. The "later" button is hidden on steps 1/2.
    let ctaStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.alignment = .fill
        return stack
    }()

    /// Stored so we can mark step 3 entry — soft-orange glow at the
    /// top-left corner per JSX (rgba(46,219,159,.25) radial). Painted
    /// directly on `view.layer` once and toggled via `setStepGlow(active:)`.
    private var stepGlowLayer: CAGradientLayer?

    /// Bottom gap between the pill-dot row and the CTA stack — 14pt on the
    /// deposit page (`SPMore.jsx` Onboarding3 `marginBottom: 14`), 16pt on
    /// pages 1/2. `internal` so `+Pages.updatePagerState` can retune it.
    var dotsGapConstraint: NSLayoutConstraint?

    /// Internal page containers managed by `+Pages.buildPageStack()`.
    var pageViews: [UIView] = []
    /// Option cards rendered on page 3 — owned so we can recolour them on
    /// selection change.
    var depositOptionViews: [OnboardingDepositOptionView] = []

    // MARK: - Compact-height adaptation (iPhone SE, #244)

    /// `true` on short devices (iPhone SE / mini family, ≤ 667pt). Drives a
    /// denser page layout so the vertically-centred content fits without a
    /// scroll: the hero clock drops 96 → 64pt (`clockXl` → `clockLg`), the
    /// page titles drop h1 → h2, and the inter-block spacing tightens. Above
    /// the threshold the canonical 390pt layout is untouched.
    ///
    /// 700pt threshold: iPhone SE 3rd-gen is 667pt, the next size up
    /// (iPhone 13 mini) is 812pt, so any cut here lands cleanly between the
    /// "needs SE polish" and "roomy" buckets.
    var isCompactHeight: Bool {
        view.bounds.height > 0 && view.bounds.height <= Self.compactHeightThreshold
    }

    /// Height at/below which the dense SE layout kicks in.
    private static let compactHeightThreshold: CGFloat = 700

    /// Compactness the live `pageViews` were built for — lets
    /// `viewDidLayoutSubviews` rebuild once if the first real `bounds` flips
    /// the verdict (page builders run in `viewDidLoad`, before the window
    /// size is guaranteed).
    private var builtForCompactHeight: Bool?

    // MARK: - Init

    init() {
        self.selectedDepositIndex = 1
        super.init(nibName: nil, bundle: nil)
        self.selectedDepositIndex = defaultDepositIndex
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Force dark — onboarding canvas is canonically dark per V2.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = AppColors.bg0
        installStepGlow()
        setupUI()
        updatePagerState(forPage: 0)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Page builders run in `viewDidLoad`; if the first resolved `bounds`
        // disagrees with the compactness they assumed, rebuild once so SE gets
        // the dense layout (and vice-versa on rotation / iPad multitasking).
        if builtForCompactHeight != isCompactHeight {
            builtForCompactHeight = isCompactHeight
            buildPageStack()
        }

        let width = scrollView.bounds.width
        let height = scrollView.bounds.height
        guard width > 0, height > 0 else { return }
        for (index, pageView) in pageViews.enumerated() {
            pageView.frame = CGRect(
                x: width * CGFloat(index),
                y: 0,
                width: width,
                height: height
            )
        }
        scrollView.contentSize = CGSize(width: width * CGFloat(pageCount), height: height)
        skipButton.layer.cornerRadius = skipButton.bounds.height / 2   // pill

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Glow positioning depends on the current page — keep its bounds
        // resolved here so size-class flips don't strand the layer.
        layoutStepGlow()
        CATransaction.commit()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(dotsStack)
        view.addSubview(ctaStack)
        view.addSubview(skipButton)

        pageControl.numberOfPages = pageCount
        pageControl.currentPage = 0

        ctaStack.addArrangedSubview(primaryButton)
        ctaStack.addArrangedSubview(laterButton)

        installLayoutConstraints()
        wireActionTargets()
        rebuildDotsRow(activePage: 0)
        buildPageStack()
        // Record the compactness the initial pages were built for so the
        // first `viewDidLayoutSubviews` only rebuilds if the resolved bounds
        // actually flip the verdict (avoids a redundant double-build).
        builtForCompactHeight = isCompactHeight
    }

    private func installLayoutConstraints() {
        let inset = AppSpacing.sp4   // 16pt — matches JSX `padding: ... 16px`
        let dotsGap = dotsStack.bottomAnchor.constraint(
            equalTo: ctaStack.topAnchor,
            constant: -AppSpacing.sp4
        )
        dotsGapConstraint = dotsGap
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: ctaStack.topAnchor),

            ctaStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            ctaStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            ctaStack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp4
            ),

            dotsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dotsGap,
            dotsStack.heightAnchor.constraint(equalToConstant: 6),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: dotsStack.topAnchor),

            // "Пропустить" pill — JSX `top: 70; right: 16` on a 54pt-status-bar
            // frame ⇒ 16pt below the safe-area top, 16pt from the trailing edge.
            skipButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sp4
            ),
            skipButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -AppSpacing.sp4
            )
        ])
    }

    private func wireActionTargets() {
        scrollView.delegate = self
        primaryButton.accessibilityIdentifier = "onboarding.primaryButton"
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        laterButton.accessibilityIdentifier = "onboarding.laterButton"
        laterButton.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)
        skipButton.accessibilityIdentifier = "onboarding.skipButton"
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    // MARK: - Step glow

    /// Mount a money-tinted radial glow at the top-left corner — shown on
    /// step 3 per JSX. Top-glow on step 1 (warn) is rendered inside the page
    /// container itself; step 2 has no glow.
    private func installStepGlow() {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [
            AppColors.money400.withAlphaComponent(0.25).cgColor,
            AppColors.money400.withAlphaComponent(0.0).cgColor
        ]
        gradient.locations = [0.0, 0.6]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.opacity = 0
        view.layer.insertSublayer(gradient, at: 0)
        stepGlowLayer = gradient
    }

    private func layoutStepGlow() {
        guard let glow = stepGlowLayer else { return }
        // 320pt radius positioned top-left, slightly offscreen so the soft
        // edge falls naturally onto the canvas — matches JSX `top: -120; left: -60`.
        glow.frame = CGRect(x: -60, y: -120, width: 320, height: 320)
    }

    func setStepGlow(active: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(SPSupport.durationBase)
        stepGlowLayer?.opacity = active ? 1 : 0
        CATransaction.commit()
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settlePagerState(for: scrollView)
    }

    /// A slow drag released without momentum settles here (`decelerate == false`)
    /// and never reaches `scrollViewDidEndDecelerating`. Resolve the page so the
    /// dot-row, glow, "Позже" link and primary CTA stay in sync. (#408)
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        settlePagerState(for: scrollView)
    }

    private func settlePagerState(for scrollView: UIScrollView) {
        let page = Self.resolvePage(offsetX: scrollView.contentOffset.x, width: scrollView.bounds.width)
        pageControl.currentPage = page
        updatePagerState(forPage: page)
    }

    /// Pure page-index resolution from a horizontal content offset. Static and
    /// side-effect-free so it can be unit-tested without a live scroll view.
    static func resolvePage(offsetX: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return Int(round(offsetX / width))
    }
}
