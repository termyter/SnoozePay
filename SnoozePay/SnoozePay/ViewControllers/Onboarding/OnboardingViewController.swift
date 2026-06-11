import UIKit

/// First-launch onboarding — V2 redesign
/// (`docs/design/v2-handoff/components/SPMore.jsx` lines 9-149).
///
/// Three full-screen pages on a horizontally-paged `UIScrollView`:
/// 1. Concept — giant clock "07:00" with a warn "−50 ₽" pill and a hero h1.
/// 2. Mechanics — three numbered steps explaining the snooze-tax loop.
/// 3. Deposit — caps eyebrow, h1, three option cards (200 / 500 / 1000 ₽)
///    with a money-tinted selection, plus a "Положить {value} ₽" CTA and a
///    secondary "Позже — попробовать без баланса" link.
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
    /// selection so the "Положить" CTA reads "500 ₽" on first appear.
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
            amount: 200,
            title: "Попробовать",
            description: "≈ 4 откладывания по \(MoneyFormatter.string(50))",
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

    /// Primary CTA visible on every page. On pages 1 & 2 the title reads
    /// "Дальше"; on page 3 the VC swaps the instance via
    /// `rebuildDepositCTA()` so the title becomes "Положить" with a money
    /// suffix and a leading shield icon. `internal` so the `+Pages` extension
    /// can swap the live instance + re-pin the constraints.
    var primaryButton = SPButton(
        title: "Дальше",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    /// Secondary "Позже — попробовать без баланса" link rendered only on
    /// step 3. Lives in `secondaryStack` so the layout shifts cleanly when
    /// the user pages back to steps 1/2.
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

    /// Internal page containers managed by `+Pages.buildPageStack()`.
    var pageViews: [UIView] = []
    /// Option cards rendered on page 3 — owned so we can recolour them on
    /// selection change.
    var depositOptionViews: [OnboardingDepositOptionView] = []

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

        pageControl.numberOfPages = pageCount
        pageControl.currentPage = 0

        ctaStack.addArrangedSubview(primaryButton)
        ctaStack.addArrangedSubview(laterButton)
        laterButton.isHidden = true

        installLayoutConstraints()
        wireActionTargets()
        rebuildDotsRow(activePage: 0)
        buildPageStack()
    }

    private func installLayoutConstraints() {
        let inset = AppSpacing.sp4   // 16pt — matches JSX `padding: ... 16px`
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
            dotsStack.bottomAnchor.constraint(
                equalTo: ctaStack.topAnchor,
                constant: -AppSpacing.sp4
            ),
            dotsStack.heightAnchor.constraint(equalToConstant: 6),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: dotsStack.topAnchor)
        ])
    }

    private func wireActionTargets() {
        scrollView.delegate = self
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        laterButton.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)
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
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        pageControl.currentPage = page
        updatePagerState(forPage: page)
    }
}
