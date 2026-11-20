import UIKit

/// One onboarding page. The page's column sits in `content`, centred in the
/// page as before, inside a vertical scroll view that only scrolls when grown
/// Dynamic Type no longer fits the page (#1111): at the default size the
/// content is exactly the page's height.
final class OnboardingPageView: UIView {

    /// Where a page builder pins its column horizontally. At least the page's
    /// height; it grows past it when the column and its clearance do not fit.
    let content = UIView()
    let scrollView: UIScrollView = ControlPanningScrollView()
    private var topClearance: NSLayoutConstraint?
    private var bottomClearance: NSLayoutConstraint?

    /// The page is mostly option cards at accessibility sizes, so a drag that
    /// starts on one must scroll the page instead of staying with the card.
    private final class ControlPanningScrollView: UIScrollView {
        override func touchesShouldCancel(in view: UIView) -> Bool {
            view is UIControl || super.touchesShouldCancel(in: view)
        }
    }

    init(column: UIView) {
        super.init(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        content.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(content)
        content.addSubview(column)

        let frame = scrollView.frameLayoutGuide
        let guide = scrollView.contentLayoutGuide
        let fitsPage = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
        fitsPage.priority = .defaultLow
        let top = column.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor)
        let bottom = column.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        topClearance = top
        bottomClearance = bottom
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(equalTo: guide.topAnchor),
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: frame.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor),
            fitsPage,
            column.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            top,
            bottom
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Room the column keeps free at the top and bottom of the page, for the
    /// floating «Пропустить» pill and the page dots it scrolls under.
    func setClearance(top: CGFloat, bottom: CGFloat) {
        topClearance?.constant = top
        bottomClearance?.constant = -bottom
    }
}
