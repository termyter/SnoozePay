import UIKit
import StoreKit
import os

/// Wallet / Top-up screen rebuilt under the SP design system (#148).
///
/// Layout, top-down:
///   1. `SPBalanceCard` — current balance + week-delta arrow (sum of
///      `charge` transactions in the last 7 days).
///   2. Caps section header "СУММА ДЛЯ ПОПОЛНЕНИЯ".
///   3. 2×2 grid of `SPAmountPreset` tiles: 49 / 149 (popular) / 299 / 999 ₽
///      with localised "~N откладываний" labels. The 149 ₽ tile is selected
///      by default per spec.
///   4. Apple Pay primary CTA — `SPButton` `.money .lg fullWidth` with the
///      Apple Pay glyph and a dynamic "Пополнить N ₽" title that follows
///      the active preset.
///   5. SPRow `.quiet` "Восстановить покупки" trigger.
///   6. Footer hint inside an `SPCard` `.outline` ("средства начисляются
///      мгновенно. Неиспользованный баланс не сгорает").
///
/// Success state: when `purchaseCompletedNotification` fires the form
/// area crossfades into a centred green checkmark + "+N ₽" headline.
/// The controller auto-dismisses after 2 s so the user lands back on
/// the alarms list without having to tap anything.
///
/// VISA / МИР card visuals were removed entirely — Apple Pay is the
/// only payment surface the wallet supports per PM directive.
///
/// Layout / setup helpers live in `TopUpViewController+Layout.swift`;
/// restore-purchases support lives in `TopUpViewController+Restore.swift`
/// so this primary file stays focused on state + lifecycle.
class TopUpViewController: UIViewController {

    // MARK: - Preset model

    /// One top-up tile. The amount is shown directly; the StoreKit
    /// product is resolved by `productID` once `loadProducts()` finishes.
    /// We do not surface `Product.displayPrice` here because the spec
    /// pins each tile to a fixed RUB amount — non-RU storefronts go
    /// through the same product list and are not a supported wallet
    /// topology yet.
    struct Preset {
        let amount: Int
        let label: String
        let productID: String
        let popular: Bool
    }

    /// Spec calls for 4 tiles: 49 / 149 / 299 / 999 ₽. The 149 ₽ tile
    /// is the popular default. The 499 ₽ product still exists in App
    /// Store Connect (kept for the firing-time bottom sheet) but is
    /// intentionally not exposed in the wallet grid.
    static let walletPresets: [Preset] = [
        Preset(amount: 49, label: "~1 откладывание", productID: "com.snooze_pay.balance.49", popular: false),
        Preset(amount: 149, label: "~3 откладывания", productID: "com.snooze_pay.balance.149", popular: true),
        Preset(amount: 299, label: "~6 откладываний", productID: "com.snooze_pay.balance.299", popular: false),
        Preset(amount: 999, label: "~20 откладываний", productID: "com.snooze_pay.balance.999", popular: false)
    ]

    /// Default-selected preset value. Spec: 149 ₽.
    static let defaultSelectedAmount: Int = 149

    // MARK: - State

    /// Currently selected preset value. Mirrored into the `SPAmountPreset`
    /// tiles + the Apple Pay button title via `selectAmount(_:)`.
    var selectedAmount: Int = TopUpViewController.defaultSelectedAmount

    /// `true` once `loadProducts()` has finished at least once. Used to
    /// disable the Apple Pay CTA until the resolved StoreKit product is
    /// known — we never want a tap to silently fall through to a
    /// "магазин недоступен" alert when the user has no other signal.
    var didFinishInitialLoad = false

    /// Set once a successful purchase resolves. Drives the success-state
    /// swap + 2-second auto-dismiss timer. Guards against the same
    /// notification arriving twice (foreground purchase + background
    /// `Transaction.updates` listener can both post `purchaseCompletedNotification`).
    var successAmount: Int?

    /// `true` while `purchase(_:)` is awaiting StoreKit. Suppresses
    /// re-taps on the Apple Pay button so we don't queue a second
    /// transaction on top of the first.
    var purchaseInFlight: Bool = false

    let storeService = StoreKitService.shared
    let balanceService = BalanceService.shared
    let transactionRepository = TransactionRepository.shared

    /// Notification observer tokens — torn down in `deinit`.
    var purchaseFailedObserver: NSObjectProtocol?
    var purchasePendingObserver: NSObjectProtocol?
    var purchaseCompletedObserver: NSObjectProtocol?
    var balanceChangedObserver: NSObjectProtocol?

    // MARK: - Subviews

    /// Vertical scroll container so the form stays reachable when the
    /// success state inflates the layout (and on smaller devices).
    let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.alwaysBounceVertical = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let balanceCard: SPBalanceCard

    let presetsSectionHeader: UILabel = TopUpViewControllerFactory.capsLabel(text: "СУММА ДЛЯ ПОПОЛНЕНИЯ")

    /// 2-column × 2-row grid of preset tiles. Built as a vertical stack
    /// of horizontal stacks (`.fillEqually`) so each row's two tiles
    /// share the available width without an extra UICollectionView dependency.
    var presetTiles: [SPAmountPreset] = []
    let presetGrid: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Primary Apple Pay CTA. The title is rebuilt whenever the preset
    /// selection changes — `SPButton` doesn't expose a public title
    /// setter, so we replace the button instance per tap. Cheap (≤ one
    /// alloc per preset switch) and keeps the gradient + shadow recipe
    /// in one place.
    var applePayButton: SPButton

    let restoreRow: SPRow

    let footerCard: SPCard
    let footerCapsLabel: UILabel = TopUpViewControllerFactory.capsLabel(text: "ПОЛЕЗНО ЗНАТЬ")
    let footerBodyLabel: UILabel = TopUpViewControllerFactory.bodyLabel(
        text: "Средства добавляются на ваш баланс мгновенно. Неиспользованный баланс не сгорает."
    )

    /// Success-state overlay. Hidden until `successAmount` is set. Sized
    /// to match the scroll content area so it covers the form during
    /// the cross-fade.
    let successContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let successCheck: UIImageView = TopUpViewControllerFactory.successCheckImageView()
    let successAmountLabel: UILabel = TopUpViewControllerFactory.successAmountLabel()

    /// Gradient layer masked onto `successAmountLabel`'s rendered text.
    /// Mirrors the `SPBalanceCard.applyValueGradient(...)` recipe so the
    /// "+N ₽" headline reads as a brand surface, not a flat tint.
    let successAmountGradient = CAGradientLayer()
    let successCaption: UILabel = TopUpViewControllerFactory.successCaptionLabel()

    // MARK: - Init

    init() {
        let initialBalance = Decimal(BalanceService.shared.balance)
        self.balanceCard = SPBalanceCard(balance: initialBalance, delta: nil, hint: nil)
        self.applePayButton = TopUpViewControllerFactory.applePayButton(
            amount: TopUpViewController.defaultSelectedAmount
        )
        self.restoreRow = SPRow(
            title: "Восстановить покупки",
            subtitle: nil,
            leading: nil,
            trailing: nil,
            divider: false
        )
        self.footerCard = SPCard(tone: .outline, padding: AppSpacing.sp4)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let center = NotificationCenter.default
        for token in [
            purchaseFailedObserver,
            purchasePendingObserver,
            purchaseCompletedObserver,
            balanceChangedObserver
        ].compactMap({ $0 }) {
            center.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Кошелёк"
        view.backgroundColor = AppColors.bg0

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setupLayout()
        setupPresetTiles()
        setupRestoreRow()
        setupFooter()
        setupSuccessOverlay()
        wireStoreCallbacks()
        refreshBalanceCard()
        rebuildApplePayButton()
        loadStoreProducts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySuccessGradient()
    }

    // MARK: - Actions

    @objc func cancelTapped() {
        dismiss(animated: true)
    }

    @objc func restoreTapped() {
        performRestorePurchases()
    }

    @objc func applePayTapped() {
        guard !purchaseInFlight, didFinishInitialLoad else { return }
        guard let preset = TopUpViewController.walletPresets.first(where: { $0.amount == selectedAmount }) else {
            return
        }

        purchaseInFlight = true
        applePayButton.isEnabled = false

        guard let product = storeService.products.first(where: { $0.id == preset.productID }) else {
            purchaseInFlight = false
            applePayButton.isEnabled = true
            presentErrorAlert("Магазин временно недоступен. Попробуйте позже.")
            return
        }

        Task { [weak self] in
            guard let service = self?.storeService else { return }
            await service.purchase(product)
            await MainActor.run {
                guard let self else { return }
                // Re-enable the button only on the failure path — the
                // success path tears down the form via `handlePurchaseSuccess`.
                if self.successAmount == nil {
                    self.purchaseInFlight = false
                    self.applePayButton.isEnabled = true
                }
            }
        }
    }
}
