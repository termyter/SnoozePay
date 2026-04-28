import UIKit

/// First-launch onboarding — Dawn redesign (#145).
///
/// Three full-screen pages on a single horizontally-paged `UIScrollView`:
/// 1. "Что такое SnoozePay" — concept explainer.
/// 2. "Как работает" — snooze → penalty mechanic.
/// 3. "Стартовый депозит" — three preset tiles (200 / 500 / 1000 ₽) plus an
///    Apple Pay primary CTA *and* a ghost "Позже" button so the user can
///    skip the first top-up (per PM directive in `chat1.md` line 747).
///
/// Visual treatment is the shared design-refresh "Dawn" surface: a vertical
/// 4-stop atmospheric gradient (`--sp-grad-dawn`), Manrope/JetBrains Mono
/// typography, brand-token foregrounds. Behaviour preserves the existing
/// `UserDefaults` key (`onboarding_completed`) so the SceneDelegate root
/// re-init flow keeps working unchanged.
final class OnboardingViewController: UIViewController {

    // MARK: - Persistence keys

    /// `internal` so the cross-file `+Pages` extension can write the
    /// onboarding-completion flag from its tap handlers (#182).
    static let completedKey = "onboarding_completed"
    /// Set to `false` when the user finishes step 3 via "Позже" so future
    /// analytics / re-engagement can distinguish "user opted out of the
    /// first deposit" from "user paid". Stays absent until the user actually
    /// reaches step 3.
    static let firstTopUpDoneKey = "first_top_up_done"

    /// `true` once the user has finished onboarding (either Apple Pay path
    /// or "Позже" path). Read by `SceneDelegate` to decide whether to mount
    /// the onboarding flow on launch.
    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    // MARK: - Page Data

    /// `internal` so the `+Pages` extension's page-builder helpers (which
    /// receive `title` + `body` as plain strings) keep their parent type
    /// visible from the cross-file extension (#182).
    struct Page {
        let title: String
        let body: String
    }

    /// `internal` so the cross-file `+Pages` extension can iterate this list
    /// when computing pager state and the page count for the deposit page
    /// (#182).
    let pages: [Page] = [
        Page(
            title: "Что такое SnoozePay",
            body: """
            Будильник, за который вы платите рублём. \
            Каждое откладывание списывает деньги с депозита — \
            поэтому вставать вовремя проще, чем переспать.
            """
        ),
        Page(
            title: "Как работает",
            body: """
            Вы кладёте депозит и ставите будильник. \
            Жмёте «Поспать ещё» — со счёта списывается штраф. \
            Дисмиссите будильник вовремя — депозит остаётся при вас.
            """
        ),
        Page(
            title: "Стартовый депозит",
            body: """
            Положите небольшую сумму, чтобы старт был ощутимым. \
            Меньше денег на счёте — слабее мотивация; \
            больше — выше цена утреннего «ещё пять минут».
            """
        )
    ]

    /// Preset amounts on step 3. Default selection is the middle tile (500 ₽).
    /// `internal` so the cross-file `+Pages` extension can build the preset
    /// stack from this list (#182).
    let presetAmounts: [Decimal] = [200, 500, 1000]
    let defaultPresetIndex: Int = 1

    // MARK: - Callback

    /// Invoked once the user finishes (or skips) onboarding. SceneDelegate
    /// uses this to swap the root from the onboarding flow to the tab bar.
    var onFinished: (() -> Void)?

    // MARK: - Background (Dawn)

    /// Vertical 4-stop atmospheric gradient. Same recipe as
    /// `AlarmFiringViewController`'s `dawnGradientLayer` — sourced from
    /// `--sp-grad-dawn` in `tokens.css` (#14122A → #0F1A2E → #0A1320 → #050912).
    private let dawnGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(rgb: 0x14122A).cgColor,
            UIColor(rgb: 0x0F1A2E).cgColor,
            UIColor(rgb: 0x0A1320).cgColor,
            UIColor(rgb: 0x050912).cgColor
        ]
        gradient.locations = [0.0, 0.4, 0.7, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        return gradient
    }()

    // MARK: - UI Elements

    /// `internal` so the `+Pages` extension can drive page-snap from the
    /// "Далее" CTA tap handler (#182).
    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    /// Page dots — kept as `UIPageControl` so the existing test
    /// (`OnboardingTests.testOnboardingPages_count`) keeps reaching for the
    /// same view kind. Tinted with brand tokens: `money500` for the active
    /// dot (matches the deposit hero), `fg3` for the rest. `internal` so
    /// the `+Pages` extension can flip its visibility / index (#182).
    let pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = AppColors.money500
        pageControl.pageIndicatorTintColor = AppColors.fg3
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.isUserInteractionEnabled = false
        return pageControl
    }()

    /// Top-right "Пропустить" — restyled as `SPButton(.quiet, .sm)`.
    /// `internal` so `+Pages.updatePagerState` can flip its hidden flag.
    let skipButton = SPButton(
        title: "Пропустить",
        variant: .quiet,
        size: .sm
    )

    /// Primary CTA. On steps 1-2 this reads "Далее" and advances the pager;
    /// on step 3 the VC swaps it for an Apple Pay-flavoured money button
    /// (`actionButton` is the step-1/2 instance only; step-3 uses
    /// `applePayButton` mounted inside the page). `internal` so
    /// `+Pages.updatePagerState` can flip its hidden flag (#182).
    let actionButton = SPButton(
        title: "Далее",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    /// Step-3 Apple Pay primary CTA — mounted inside the third page so it
    /// scrolls in/out with the page. SPButton has no public title setter, so
    /// the title-change-on-preset-change path replaces the whole button via
    /// `updateApplePayTitle()` (same pattern as FiringTopUpBottomSheet).
    /// `internal` so the cross-file `+Pages.updateApplePayTitle` can swap
    /// the instance (#182).
    var applePayButton: SPButton = SPButton(
        title: "Начать с 500 ₽",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    /// Step-3 "Позже" — ghost CTA stacked right under `applePayButton`. Tap
    /// finishes onboarding without triggering an IAP and stamps
    /// `first_top_up_done = false` so future analytics can attribute the
    /// opt-out.
    private let laterButton = SPButton(
        title: "Позже",
        variant: .ghost,
        size: .lg,
        fullWidth: true
    )

    /// CTA stack on step 3 — owns the (re-creatable) Apple Pay button as its
    /// first arranged subview so `rebuildApplePayButton()` can swap the
    /// instance without re-pinning constraints. `internal` so the `+Pages`
    /// extension can mount it inside the deposit page (#182).
    let ctaStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = AppSpacing.sp3
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private var pageViews: [UIView] = []
    /// `internal` so the `+Pages` extension can append to the same array
    /// during the page-build pass (#182).
    var presetTiles: [SPAmountPreset] = []

    /// Currently-selected preset index on step 3. Initialised to
    /// `defaultPresetIndex` (500 ₽). Drives both the Apple Pay CTA title and
    /// which tile renders selected. `internal` so the cross-file `+Pages`
    /// extension can read the current selection inside `updateApplePayTitle`.
    lazy var selectedPresetIndex: Int = defaultPresetIndex

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        view.layer.insertSublayer(dawnGradientLayer, at: 0)
        setupUI()
        updatePagerState(forPage: 0)
    }

    override var prefersStatusBarHidden: Bool { true }

    /// Force dark UI so the Dawn gradient + brand foregrounds read correctly
    /// regardless of the user's system theme. Same approach as
    /// AlarmFiringViewController so onboarding doesn't flash light-mode tiles
    /// on first launch.
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Recalculate page widths after layout.
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
        scrollView.contentSize = CGSize(width: width * CGFloat(pages.count), height: height)
        // Disable implicit animation so the gradient layer doesn't crossfade
        // on each rotation / size-class change.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dawnGradientLayer.frame = view.bounds
        CATransaction.commit()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(skipButton)
        view.addSubview(pageControl)
        view.addSubview(actionButton)

        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0

        activateChromeConstraints()
        wireActionTargets()
        buildPageStack()
    }

    /// Pin skip button, scroll view, action button, and page control to the
    /// view edges. Split off `setupUI` so the function body stays under
    /// SwiftLint's `function_body_length` cap (#182).
    private func activateChromeConstraints() {
        NSLayoutConstraint.activate([
            // Skip button — top right.
            skipButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sp2
            ),
            skipButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),

            // Scroll view — full screen behind everything.
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Action button — bottom, full width with margins.
            actionButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            actionButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            actionButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            ),

            // Page control — above the action button.
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(
                equalTo: actionButton.topAnchor,
                constant: -AppSpacing.sp4
            )
        ])
    }

    /// Wire scrollView delegate + every CTA's target/action. Pulled out of
    /// `setupUI` so its body fits SwiftLint's function-length cap (#182).
    private func wireActionTargets() {
        scrollView.delegate = self
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        applePayButton.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        laterButton.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)

        ctaStack.addArrangedSubview(applePayButton)
        ctaStack.addArrangedSubview(laterButton)
    }

    /// Build page content — first two pages share one layout, step 3 is a
    /// bespoke "deposit" page with preset tiles + dual CTAs. Page builders
    /// live in `OnboardingViewController+Pages.swift` (#182).
    private func buildPageStack() {
        for (index, page) in pages.enumerated() {
            let pageView: UIView
            if index == pages.count - 1 {
                pageView = makeDepositPageView(title: page.title, body: page.body)
            } else {
                pageView = makeTextPageView(title: page.title, body: page.body)
            }
            scrollView.addSubview(pageView)
            pageViews.append(pageView)
        }
    }

    // Actions, preset-tap handler, and pager state live in
    // `OnboardingViewController+Pages.swift` (#182).
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        pageControl.currentPage = page
        updatePagerState(forPage: page)
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initializer so the Dawn gradient stops read as in
    /// `tokens.css`. Local copy mirroring the (private) helper in AppColors —
    /// kept file-local to match the AlarmFiringViewController convention.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
