import UIKit

/// Onboarding flow shown on first launch.
/// Three fullscreen pages with swipe navigation and pagination dots.
final class OnboardingViewController: UIViewController {

    // MARK: - Constants

    private static let completedKey = "onboarding_completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    // MARK: - Page Data

    private struct Page {
        let emoji: String
        let title: String
        let description: String
        let buttonTitle: String
    }

    private let pages: [Page] = [
        Page(
            emoji: "\u{23F0}",
            title: "Откладывание стоит денег",
            description: "Каждый раз, когда вы откладываете будильник, с вашего баланса списывается штраф. Это мотивирует просыпаться вовремя.",
            buttonTitle: "Далее"
        ),
        Page(
            emoji: "\u{1F4B0}",
            title: "Штраф 10–1000\u{20BD}",
            description: "Вы устанавливаете размер штрафа сами. Если баланс = 0, откладывание блокируется.",
            buttonTitle: "Далее"
        ),
        Page(
            emoji: "\u{1F525}",
            title: "Статистика и streak",
            description: "Следите за своими успехами и экономьте деньги. Каждый день без откладывания увеличивает ваш streak!",
            buttonTitle: "Начать"
        )
    ]

    // MARK: - Callback

    var onFinished: (() -> Void)?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bounces = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.currentPageIndicatorTintColor = .systemBlue
        pc.pageIndicatorTintColor = UIColor.systemGray.withAlphaComponent(0.5)
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.isUserInteractionEnabled = false
        return pc
    }()

    private let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Пропустить", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let actionButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return a
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var pageViews: [UIView] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        updateActionButton(forPage: 0)
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Recalculate page widths after layout
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        for (index, pageView) in pageViews.enumerated() {
            pageView.frame = CGRect(
                x: width * CGFloat(index),
                y: 0,
                width: width,
                height: scrollView.bounds.height
            )
        }
        scrollView.contentSize = CGSize(width: width * CGFloat(pages.count), height: scrollView.bounds.height)
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(skipButton)
        view.addSubview(pageControl)
        view.addSubview(actionButton)

        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0

        NSLayoutConstraint.activate([
            // Skip button — top right
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Scroll view — full screen behind everything
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Action button — bottom, full width with margins
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 50),

            // Page control — above button
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -24)
        ])

        scrollView.delegate = self
        skipButton.addTarget(self, action: #selector(finishOnboarding), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        // Create page content views
        for page in pages {
            let pageView = makePageView(page: page)
            scrollView.addSubview(pageView)
            pageViews.append(pageView)
        }
    }

    private func makePageView(page: Page) -> UIView {
        let container = UIView()

        let emojiLabel = UILabel()
        emojiLabel.text = page.emoji
        emojiLabel.font = UIFont.systemFont(ofSize: 64)
        emojiLabel.textAlignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = page.title
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = page.description
        descLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        descLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [emojiLabel, titleLabel, descLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -60),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        return container
    }

    // MARK: - Actions

    @objc private func actionTapped() {
        let currentPage = pageControl.currentPage
        if currentPage < pages.count - 1 {
            // Advance to next page
            let nextPage = currentPage + 1
            let offsetX = scrollView.bounds.width * CGFloat(nextPage)
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
            pageControl.currentPage = nextPage
            updateActionButton(forPage: nextPage)
        } else {
            // Last page — finish
            finishOnboarding()
        }
    }

    @objc private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinished?()
    }

    private func updateActionButton(forPage page: Int) {
        actionButton.setTitle(pages[page].buttonTitle, for: .normal)

        // Hide skip on last page
        skipButton.isHidden = (page == pages.count - 1)
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        pageControl.currentPage = page
        updateActionButton(forPage: page)
    }
}
