import Foundation
import os

/// Cache of the storefront snooze-price scale, one per currency (#1109, #1126).
///
/// The firing path must never wait on StoreKit, so the scale built from the last
/// loaded catalogue is kept here and read synchronously. Scales are kept **per
/// currency**: a storefront change records a new currency's scale next to the old
/// one and never overwrites it, because a wallet frozen in the old currency still
/// prices its snoozes from it.
///
/// Roubles are never stored or read: `scale(for: .rub)` is the constant
/// `SnoozePriceScale.rouble`.
///
/// `nonisolated` and lock-guarded like `WalletCurrencyStore`: the charging path
/// reads it off the main actor.
nonisolated final class SnoozePriceScaleStore: @unchecked Sendable {

    /// Posted (on the store's notification center, from the recording thread)
    /// after `record(_:)` changed a stored scale or the last storefront currency.
    static let snoozePriceScaleChangedNotification =
        Notification.Name("snoozepay.snoozePrice.scaleChanged")

    /// Dictionary: currency code → `["tiers": [String], "updatedAt": Date]`.
    /// Tiers are decimal strings so `0.99` is never written as a binary float.
    static let scalesKey = "snooze_price_scales"
    /// Bare ISO code of the storefront of the latest recorded catalogue.
    static let lastStorefrontCurrencyKey = "last_storefront_currency"

    static let tiersField = "tiers"
    static let updatedAtField = "updatedAt"

    static let shared = SnoozePriceScaleStore(defaults: .standard)

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    /// Serialises read-compare-write in `record(_:)`.
    private let lock = NSLock()

    init(defaults: UserDefaults, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    // MARK: - Read

    /// The cached scale of `currency`, or `nil` when none was recorded.
    ///
    /// A stored value that cannot be read back as a valid scale is `nil` and an
    /// error in the log — never a guessed default, which would be charged.
    func scale(for currency: Currency) -> SnoozePriceScale? {
        if currency == .rub { return .rouble }
        lock.lock()
        defer { lock.unlock() }
        return storedScale(for: currency)
    }

    /// The storefront currency of the latest recorded catalogue, or `nil` when no
    /// catalogue was recorded yet or the stored code is unreadable (logged).
    var lastStorefrontCurrency: Currency? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastStorefrontCurrency()
    }

    // MARK: - Write

    /// Records the scale of a loaded storefront catalogue and makes its currency
    /// the last storefront currency.
    ///
    /// Returns `true` and posts `snoozePriceScaleChangedNotification` only when
    /// something actually changed: the currency's stored tiers, or the last
    /// storefront currency. An identical record writes nothing. A rouble scale
    /// only moves the last storefront currency; its tiers are never stored.
    func record(_ scale: SnoozePriceScale) -> Bool {
        let changed: Bool = {
            lock.lock()
            defer { lock.unlock() }
            let code = scale.currency.code
            let storefrontChanged = storedLastStorefrontCurrency() != scale.currency
            let scaleChanged = scale.currency != .rub && storedScale(for: scale.currency) != scale
            if scaleChanged {
                var all = defaults.dictionary(forKey: Self.scalesKey) ?? [:]
                all[code] = [Self.tiersField: scale.tierStrings, Self.updatedAtField: Date()]
                defaults.set(all, forKey: Self.scalesKey)
            }
            if storefrontChanged {
                defaults.set(code, forKey: Self.lastStorefrontCurrencyKey)
            }
            return scaleChanged || storefrontChanged
        }()
        guard changed else { return false }
        let tiers = scale.tierStrings.joined(separator: "/")
        AppLogger.storeKit.notice(
            "snooze price scale recorded for \(scale.currency.code, privacy: .public): \(tiers, privacy: .public)"
        )
        notificationCenter.post(name: Self.snoozePriceScaleChangedNotification, object: self)
        return true
    }

    // MARK: - Unlocked readers (caller holds `lock`)

    private func storedScale(for currency: Currency) -> SnoozePriceScale? {
        guard let rawAll = defaults.object(forKey: Self.scalesKey) else { return nil }
        guard let all = rawAll as? [String: Any] else {
            AppLogger.storeKit.error("\(Self.scalesKey, privacy: .public) is not a dictionary — no cached scale")
            return nil
        }
        guard let rawEntry = all[currency.code] else { return nil }
        guard let entry = rawEntry as? [String: Any],
              let strings = entry[Self.tiersField] as? [String],
              let scale = SnoozePriceScale(currency: currency, tierStrings: strings) else {
            AppLogger.storeKit.error(
                "\(Self.scalesKey, privacy: .public)[\(currency.code, privacy: .public)] is corrupt — no cached scale"
            )
            return nil
        }
        return scale
    }

    private func storedLastStorefrontCurrency() -> Currency? {
        guard let rawValue = defaults.object(forKey: Self.lastStorefrontCurrencyKey) else { return nil }
        guard let raw = rawValue as? String, let currency = Currency(code: raw) else {
            AppLogger.storeKit.error(
                "\(Self.lastStorefrontCurrencyKey, privacy: .public) holds no ISO 4217 code — treating as unset"
            )
            return nil
        }
        return currency
    }
}
