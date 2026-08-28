import UIKit

/// Which side of the ledger a wallet row sits on. Extracted so the wallet
/// preview card and the full transaction history can't drift apart on the
/// one decision users read the screen by — "did this add money or take it".
///
/// `.unclassified` is the `TransactionType.unknown` row: a build that can't
/// tell credit from debit must not guess a direction, so it renders neutral
/// and carries no sign (see `TransactionType.unknown`).
enum WalletLedgerDirection: Equatable {
    case incoming
    case outgoing
    case unclassified

    init(_ type: TransactionType) {
        switch type {
        case .topup, .promotion, .refund: self = .incoming
        case .charge: self = .outgoing
        case .unknown: self = .unclassified
        }
    }

    /// Sign prefix for the amount — `nil` when the direction is unknown.
    ///
    /// This is the reason a row is legible without colour at all: the tint
    /// only reinforces a distinction the "+" / "−" already makes. Both light
    /// tints land within 0.05 of each other in contrast against the card
    /// (money400 5.27:1, pain400 5.22:1), so luminance alone cannot separate
    /// them for a red-green colour-blind reader — the sign has to.
    var signPrefix: String? {
        switch self {
        case .incoming: return "+"
        case .outgoing: return "−"
        case .unclassified: return nil
        }
    }
}

/// Colours for a transaction row's amount and its leading icon tile.
///
/// Both are theme-aware through `AppColors` — the `money`/`pain` scales
/// resolve per trait collection since #489, so nothing here caches a
/// `cgColor` and nothing needs re-resolving on a theme flip: the tokens are
/// handed to `UILabel.textColor` / `UIView.backgroundColor`, which UIKit
/// re-resolves itself.
///
/// Step choice is the `400` one from the canon prototype
/// (`SPMore3.jsx:92` — `var(--sp-pain-400)` / `var(--sp-money-400)`), which
/// after #489 measures on the light card surface (`bg1` = `#FFFFFF`):
///
///     money400 #0B7B56  5.27:1      pain400 #C04032  5.22:1
///
/// and on the dark card (`bg1` = `#0E1320`) 10.37:1 / 7.28:1. Row sums are
/// 20pt bold mono, so their WCAG bar is 3:1 — both clear the stricter 4.5:1
/// body-text bar in both themes. `AppColorsContrastTests` pins the scale;
/// `WalletLightThemeTests` pins this call site.
enum WalletAmountTint {

    /// Ink for the amount label.
    static func ink(for direction: WalletLedgerDirection) -> UIColor {
        switch direction {
        case .incoming: return AppColors.money400
        case .outgoing: return AppColors.pain400
        case .unclassified: return AppColors.fg3
        }
    }

    /// Fill for the 36×36 leading icon tile — the ink laid as a 14% wash over
    /// the card, per `rgba(244,82,63,.14)` in the canon prototype.
    ///
    /// A wash is not a solid fill: the glyph on top stays the full-strength
    /// ink (4.36:1 / 4.26:1 on the light wash), never `fgOnMoney`/`fgOnPain`,
    /// which are white in light and would vanish here.
    static func iconWash(for direction: WalletLedgerDirection) -> UIColor {
        ink(for: direction).withAlphaComponent(washAlpha)
    }

    /// Wash strength shared by both wallet screens.
    private static let washAlpha: CGFloat = 0.14
}

/// Ink for the wallet's quiet meta copy — the footer disclaimer and the
/// weekday initials under the 7-day chart.
///
/// The canon prototype paints both `--sp-fg-4` (`SPScreensV2.jsx:474`), and
/// in DARK they stay exactly that: 2.55:1, deliberately quiet, untouched by
/// this issue.
///
/// The light block of `tokens.css` reuses the same 32% alpha over the
/// near-black ink, which on `bg0` (`#F4F6FB`) measures **2.10:1** — below even
/// the 3:1 large-text floor, on 13pt copy the user is expected to actually
/// read ("покупка не возвращается"). Light therefore steps up one rung to
/// `fg3` — **4.26:1** — which is the "meta" role these lines have always had
/// semantically. `fg4` is documented as *disabled / placeholder*, and neither
/// of these is disabled.
///
/// Composed here rather than added to `AppColors` because the two call sites
/// are both on this screen: a token earns its place in the shared palette
/// when a second SCREEN needs it.
enum WalletQuietInk {
    static let caption = UIColor { trait in
        trait.userInterfaceStyle == .light
            ? AppColors.fg3.resolvedColor(with: trait)
            : AppColors.fg4.resolvedColor(with: trait)
    }
}
