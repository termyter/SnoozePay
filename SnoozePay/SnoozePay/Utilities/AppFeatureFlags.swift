import Foundation

/// Compile-time switches for features that exist in code but must not reach
/// the user yet. Separate from `AppConstants` (values a screen renders) —
/// these decide whether a screen is reachable at all.
///
/// A flag here is a plain `Bool` constant, not a `UserDefaults` read or an
/// `#if`: every branch stays type-checked in both positions, so turning a
/// feature back on is a one-line edit that cannot have rotted in the
/// meantime. Dead code behind an `#if` compiles only in the configuration
/// that defines the symbol and drifts out of sync silently.
enum AppFeatureFlags {

    /// Whether the referral programme is offered anywhere in the UI —
    /// Settings → «ПРИГЛАСИТЬ ДРУГА» and the DEBUG stats shortcut into
    /// `ReferralViewController`.
    ///
    /// `false` since #676: there is no server behind it. The code a user
    /// copies is generated locally and resolves nowhere, and the +200 ₽
    /// credited on «Применить» comes out of the local wallet rather than
    /// from an actual invite — i.e. the screen promises a payout the app
    /// cannot make, which is also an App Store review risk. The screen, its
    /// views, `ReferralService` and their tests stay compiled and covered so
    /// flipping this back to `true` restores the feature whole once a
    /// backend exists.
    static let referralEnabled = false
}
