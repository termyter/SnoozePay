import Foundation

/// App-wide constant values that would otherwise be duplicated as string
/// literals across screens. Keeping them here gives a single source of truth
/// so a rebrand (e.g. support address) is a one-line change (#316).
enum AppConstants {

    /// Support contact address, shown in Settings → «Связаться с нами» and used
    /// for the `mailto:` deep link. Post-rebrand domain (#316) — the old
    /// `support@alarmcash.app` predated the SnoozePay name.
    static let supportEmail = "support@snoozepay.app"
}
