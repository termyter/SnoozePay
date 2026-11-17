import StoreKit
import UIKit
import os

/// One fetched catalogue, in a form a test can build without StoreKit (#1109).
struct LoadedCatalogue {
    /// Cheapest first. Empty in tests, which cannot construct a `Product`.
    let products: [Product]
    /// One per product that converts to a valid offer.
    let offers: [TopUpOffer]
    /// Products that did not convert; any of them voids the scale.
    let invalidProductIDs: [String]

    static let empty = LoadedCatalogue(products: [])

    init(products: [Product]) {
        self.products = products.sorted { $0.price < $1.price }
        offers = self.products.compactMap(TopUpOffer.init(product:))
        let converted = Set(offers.map(\.productID))
        invalidProductIDs = self.products.map(\.id).filter { !converted.contains($0) }
    }

    init(offers: [TopUpOffer]) {
        products = []
        self.offers = offers
        invalidProductIDs = []
    }

    var loadedIDs: [String] { offers.map(\.productID) + invalidProductIDs }

    /// Every `productIDs` entry exactly once, all valid.
    var isComplete: Bool {
        let ids = offers.map(\.productID)
        return invalidProductIDs.isEmpty && ids.count == StoreKitService.productIDs.count
            && Set(ids) == Set(StoreKitService.productIDs)
    }

    /// The storefront currency, when every offer agrees on one.
    var currency: Currency? {
        guard let first = offers.first?.currency, offers.allSatisfy({ $0.currency == first }) else { return nil }
        return first
    }
}

/// What asked for a catalogue load. Only `.launch` reports a failure to the user.
enum CatalogueReloadTrigger: String {
    case launch, storefrontChanged, foreground
}

/// Removes a block-based observer when released, so the owner's deinit needs no
/// access to the token.
nonisolated final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit { center.removeObserver(token) }
}

// MARK: - Catalogue reload (#1109)
//
// Before #1109 the catalogue loaded once, in `init`. A first launch offline or
// a storefront switch then left a non-rouble wallet without a price scale until
// the app was killed. Two triggers reload it, both through `loadProducts`, so
// a reload records its scale exactly like the launch load:
// - `Storefront.updates`, for the life of the service;
// - `willEnterForeground`, only while the catalogue is unhealthy. Not
//   `didBecomeActive`: that also fires when a system sheet (the purchase sheet,
//   Face ID, Control Center) closes, which would reload in the middle of a
//   purchase. No timers: an unhealthy catalogue waits for the next trigger.
extension StoreKitService {

    typealias CatalogueLoader = @MainActor () async throws -> LoadedCatalogue

    static func loadStoreCatalogue() async throws -> LoadedCatalogue {
        LoadedCatalogue(products: try await Product.products(for: Set(productIDs)))
    }

    /// `Storefront.updates` as a stream the service can own and tests can replace.
    static func storefrontChangeStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in Storefront.updates { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Whether a foreground should reload: the last load failed, the catalogue
    /// is partial, or no scale is cached for the catalogue's currency.
    var needsCatalogueReload: Bool { catalogueReloadReason != nil }

    /// Why the catalogue is unhealthy, or `nil` when it is healthy.
    var catalogueReloadReason: String? {
        if lastCatalogueLoadFailed { return "last load failed" }
        guard catalogue.isComplete else { return "partial catalogue" }
        guard let currency = catalogue.currency else { return "mixed currencies" }
        return priceScaleStore.scale(for: currency) == nil ? "no scale for \(currency.code)" : nil
    }

    func startCatalogueReloadTriggers(storefrontChanges: AsyncStream<Void>?, foregroundCenter: NotificationCenter?) {
        if let storefrontChanges {
            storefrontObserver = Task { [weak self] in
                for await _ in storefrontChanges {
                    self?.requestCatalogueReload(.storefrontChanged)
                }
            }
        }
        if let foregroundCenter {
            let token = foregroundCenter.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadCatalogueOnForegroundIfNeeded() }
            }
            foregroundObservation = NotificationObservation(center: foregroundCenter, token: token)
        }
    }

    /// A load already in flight is newer than this foreground, so it is not queued behind.
    func reloadCatalogueOnForegroundIfNeeded() {
        guard !isCatalogueReloadInFlight, let reason = catalogueReloadReason else { return }
        AppLogger.storeKit.debug("foreground catalogue reload: \(reason, privacy: .public)")
        requestCatalogueReload(.foreground)
    }

    /// Starts a load, or — while one is in flight — queues at most one follow-up:
    /// a storefront change mid-load may have been fetched from the old storefront.
    func requestCatalogueReload(_ trigger: CatalogueReloadTrigger) {
        guard !isCatalogueReloadInFlight else {
            queuedCatalogueReload = trigger
            return
        }
        isCatalogueReloadInFlight = true
        Task { [weak self] in await self?.runCatalogueReloads(from: trigger) }
    }

    private func runCatalogueReloads(from trigger: CatalogueReloadTrigger) async {
        var next: CatalogueReloadTrigger? = trigger
        while let current = next {
            await loadProducts(current)
            next = queuedCatalogueReload
            queuedCatalogueReload = nil
        }
        isCatalogueReloadInFlight = false
        onCatalogueReloadsSettled?()
    }
}
