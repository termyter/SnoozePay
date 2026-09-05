import UIKit

/// App-wide navigation-bar chrome (#508). Sibling of `SceneDelegate`'s
/// `applyTabBarStyle` — one recipe, applied wherever the app builds a
/// `UINavigationController`, so the bar never falls back to system default.
///
/// **What the canon says.** `components.css` `.sp-navbar` is
/// `background: transparent` with **no** `border-bottom`, and every prototype
/// screen sits on `var(--sp-bg-0)` (`SPScreens.jsx` `Screen`). So the bar has
/// no surface of its own: it reads as the page. That is the opposite of
/// `.sp-tabbar`, which the same stylesheet *does* give a fill
/// (`rgba(14,19,32,.85)`), a blur and a `border-top` hairline — the design
/// deliberately separates the bottom bar and deliberately does not separate the
/// top one. Translated to UIKit that is an **opaque `bg0` bar with a cleared
/// shadow**: identical to "transparent over the page" at rest, but it also
/// keeps scrolled content from bleeding through the title, which a literally
/// transparent bar would allow. Title tokens are `.sp-navbar__title`
/// (`--sp-t-h4` / `--sp-fg-1`) and `.sp-navbar--large .sp-navbar__largeTitle`
/// (`--sp-t-h1` / `--sp-fg-1`, `letter-spacing: -.02em`).
///
/// **Why the appearance object may hold dynamic colours.** `UIBarAppearance`
/// stores `UIColor`, not `CGColor`: UIKit resolves it against the *bar's* live
/// trait collection at render time, so one appearance object built once is
/// correct in both themes and after a theme flip. This is the same guarantee
/// `applyTabBarStyle` already leans on. The trap this file must avoid is the
/// one that bit five sites elsewhere today — snapshotting a token with
/// `resolvedColor(with:)` (or `.cgColor`) before storing it, which freezes one
/// theme forever. `AppNavigationBarStyleTests` pins that: it flips a hosted
/// window and fails if the stored colours resolve identically in both themes.
///
/// **Forced-dark screens are unaffected.** `AlarmFiringViewController`,
/// `WokeMorningViewController`, `FiringTopUpBottomSheetViewController`,
/// `OnboardingViewController`, `SplashViewController` and
/// `PermissionsViewController` pin `overrideUserInterfaceStyle = .dark` and
/// none of them is inside a navigation controller. Even if one were, the
/// dynamic tokens above resolve against the bar's inherited traits, so the bar
/// would follow the screen dark rather than fight it — no global appearance
/// proxy is installed here for exactly that reason (it would also restyle
/// system chrome such as `PHPickerViewController`).
enum AppNavigationBarStyle {

    /// Build the shared appearance. A fresh instance per call: appearance
    /// objects are value-ish but mutable, and sharing one across bars invites
    /// a future caller's tweak to leak app-wide.
    static func makeAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        // Opaque rather than `configureWithTransparentBackground()`: the canon
        // bar is transparent *over `bg0`*, which is what an opaque `bg0` bar
        // renders as, minus the content bleed-through.
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.bg0
        // No `border-bottom` in `.sp-navbar` — UIKit models the bar's bottom
        // edge line as its "shadow", and the system default draws one. The
        // hairline is precisely what makes the seam visible once the fill
        // matches, so it has to go too.
        appearance.shadowColor = .clear

        appearance.titleTextAttributes = [
            .font: AppTypography.h4,
            .foregroundColor: AppColors.fg1
        ]
        appearance.largeTitleTextAttributes = [
            .font: AppTypography.h1,
            .foregroundColor: AppColors.fg1,
            // `.sp-navbar__largeTitle` overrides the `.sp-h1` tracking to
            // -.02em, so this is not `AppTypography.h1Kerning`.
            .kern: AppTypography.kern(em: -0.02, size: 32)
        ]
        return appearance
    }

    /// Install the recipe on all three (four, counting compact-scroll-edge)
    /// appearance slots. Setting only `standardAppearance` leaves the bar
    /// system-white at rest, which is the state the seam was reported in.
    static func apply(to navigationBar: UINavigationBar) {
        let appearance = makeAppearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }

    /// Preferred way to build a navigation controller in this app. Call sites
    /// use this instead of `UINavigationController(rootViewController:)` so a
    /// new screen can't silently ship with the system bar.
    static func makeNavigationController(
        rootViewController: UIViewController
    ) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        apply(to: navigationController.navigationBar)
        return navigationController
    }

    // MARK: - Brand controls in the bar (#649, #666)

    /// Wrap a brand control as a bar-button item the bar does not re-decorate.
    ///
    /// iOS 26 paints its shared glass capsule OVER a custom view, sampling
    /// what is behind it. On a control that already draws its own filled
    /// background that is a translucent copy of our own fill laid over our own
    /// ink: it lifted the create screen's «Готово» from 7.05:1 to **2.41:1**,
    /// under WCAG's 3:1 floor, on the terminal action of the screen (#649).
    /// The `.money` variant itself is fine — the same button measures 6.76:1
    /// in the wallet header; only the ones inside a navigation bar were
    /// washed out.
    ///
    /// The `.quiet` items opt out for the second reason rather than contrast:
    /// that pill measures 14.46:1 either way, but the capsule draws a second
    /// ring around chrome that already has its own fill. The canon has no such
    /// ring on any of the three: `SPMore.jsx:313` and `SPMore2.jsx:340` put a
    /// bare `SPButton variant="quiet" size="sm"` in the picker headers, and
    /// `SPScreensV2.jsx:525` puts an equally bare pill on the alarm form — in
    /// the `money` variant, not `quiet`. What the three share is the absence of
    /// a ring over the button's own fill, NOT the variant: the form's «Готово»
    /// is the screen's terminal money CTA (`CreateAlarmViewController:170`
    /// builds it `.money`) and levelling it to `.quiet` would be a regression,
    /// not consistency.
    ///
    /// Line numbers above are into the canon copy,
    /// `docs/design/snoozepay-2026-04-27/project/components/`. A second,
    /// differently numbered copy of `SPMore2.jsx` lives under
    /// `docs/design/v2-handoff/` — naming only the file is how the reference
    /// this commit corrected came to point at the wrong artboard.
    ///
    /// Lives here rather than on any one screen because three of them build
    /// such items — the alarm form plus the sound and theme pickers (#666) —
    /// and a fourth would otherwise copy the recipe again. A `static func` on
    /// the enum that already owns this app's bar chrome, not a `UIBarButtonItem`
    /// extension: the call sites are all inside this app, so widening the type
    /// buys nothing.
    ///
    /// `CreateAlarmBarButtonGlassTests` and `AlarmPickerBarButtonGlassTests`
    /// pin this, and carry the numbers.
    static func barItem(for control: UIView) -> UIBarButtonItem {
        let item = UIBarButtonItem(customView: control)
        item.hidesSharedBackground = true
        return item
    }

    // MARK: - Bar-less roots (#517)

    /// Hide the bar for a tab root that draws its own in-screen header
    /// (`AlarmsListViewController` and `WalletViewController` #280,
    /// `StatisticsViewController` #319). Call from `viewWillAppear`.
    ///
    /// Pairs with `pushRestoringBar(_:from:)`, and the pairing is the whole
    /// point: three tabs hide the bar, and #517 was one of them forgetting to
    /// put it back before a push — the referral screen opened with no bar, no
    /// back button, content under the status bar, and none of the #508 chrome,
    /// because a hidden bar renders none of it.
    ///
    /// The second half here is the case that is easy to miss. An interactive
    /// swipe-back that the user **cancels** halfway still runs this root's
    /// `viewWillAppear`, so the bar goes away — but the child stays on screen
    /// and is now in exactly the reported state. `notifyWhenInteractionChanges`
    /// is the callback that separates a cancelled pop from a completed one.
    static func hideBar(on viewController: UIViewController, animated: Bool) {
        guard let stack = viewController.navigationController else { return }
        stack.setNavigationBarHidden(true, animated: animated)
        viewController.transitionCoordinator?.notifyWhenInteractionChanges { [weak stack] context in
            restoreBarIfInteractionCancelled(on: stack, cancelled: context.isCancelled)
        }
    }

    /// The branch inside the coordinator callback, lifted out so it is
    /// reachable from a test — a real `transitionCoordinator` only exists
    /// during a live transition and cannot be injected.
    static func restoreBarIfInteractionCancelled(
        on stack: UINavigationController?,
        cancelled: Bool
    ) {
        guard cancelled else { return }
        stack?.setNavigationBarHidden(false, animated: true)
    }

    /// Push a child from a bar-less root. The bar has to come back *before*
    /// the push so the child keeps its standard back arrow and title; the
    /// root's `viewWillAppear` re-hides it when the user pops back.
    static func pushRestoringBar(_ child: UIViewController, from viewController: UIViewController) {
        guard let stack = viewController.navigationController else { return }
        stack.setNavigationBarHidden(false, animated: true)
        stack.pushViewController(child, animated: true)
    }
}
