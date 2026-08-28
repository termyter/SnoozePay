# IAP / пополнение баланса — StoreKit

Пополнение баланса в SnoozePay идёт через **In-App Purchase (StoreKit 2)**, а не через
Apple Pay (PassKit). Apple требует продавать внутреннюю валюту приложения только через IAP;
настоящий Apple Pay для цифрового баланса использовать нельзя. В UI бренд «Apple Pay» убран
в нейтральное «Пополнить» (`AlarmFiringViewController+NoBalance.swift`), но под капотом —
`StoreKitService.purchase()` → `StoreKit.Transaction`.

## Локальное тестирование без оплаченного Apple Developer (#195)

В репозитории лежит `SnoozePay/SnoozePay.storekit` — локальный StoreKit Configuration File.
Он привязан к **Run-action** схемы `SnoozePay` (`Edit Scheme → Run → Options → StoreKit
Configuration`). Это даёт полный IAP-флоу в симуляторе без App Store Connect, без sandbox-
аккаунтов и без оплаченного аккаунта.

### Продукты (5 consumable)

ID — источник истины — это константы `StoreKitService.productIDs` / `productAmounts`:

| productID | Сумма зачисления |
|-----------|------------------|
| `io.mobilife.snoozepay.balance.49`  | 49 ₽  |
| `io.mobilife.snoozepay.balance.149` | 149 ₽ |
| `io.mobilife.snoozepay.balance.299` | 299 ₽ |
| `io.mobilife.snoozepay.balance.499` | 499 ₽ |
| `io.mobilife.snoozepay.balance.999` | 999 ₽ |

> ⚠️ При изменении ID/сумм в `.storekit` — синхронно править `StoreKitService.swift`
> (и наоборот). Расхождение → продукт не загрузится / зачислится не та сумма.

### Тест-action оставлен БЕЗ StoreKit Configuration

Намеренно: `NoBalanceTopUpUITests` тапает «Пополнить» и рассчитывает на fallback-ветку
`noBalanceApplePayTapped` (когда `StoreKitService.products` пуст → прямой
`BalanceService.topUp`). Если повесить `.storekit` на Test-action, тап откроет
StoreKit-лист подтверждения, который XCUITest не закроет → тест упадёт. CI (`xcodebuild test`)
гоняет Test-action, поэтому остаётся на fallback и проходит.

### Ручная матрица проверок (выполнять в Xcode на симуляторе)

`Debug → StoreKit → Manage Transactions` + `Editor`:

- [ ] Покупка → баланс растёт в UserDefaults (`user_balance`)
- [ ] Restore Purchases — для Consumable не дублирует кредиты
- [ ] Ask-to-Buy (`Editor → Enable Ask To Buy`) → `purchasePendingNotification`, кредит после approve
- [ ] Отказ пользователя в диалоге → баланс не меняется
- [ ] Прерванная покупка → `Transaction.updates` досылает после возобновления
- [ ] Refund (`Editor → Refund Transaction`) — обрабатывается, баланс не уходит в минус
- [ ] Failed transaction (`Editor → Fail Transactions`) → `purchaseFailedNotification` + алерт

> Эта матрица интерактивная (Xcode Transaction Manager) и не воспроизводится headless-
> тулзами CI/агента — её прогоняет PM в Xcode.

## Миграция на App Store (после оплаты Apple Developer $99/год)

1. Создать те же 5 продуктов в **App Store Connect** с теми же `productID` (Consumable).
2. Цены/локализации — как в `.storekit` (49/149/299/499/999 ₽).
3. Переключить схему: `Run → Options → StoreKit Configuration → None`.
4. Sandbox-тестирование через TestFlight + sandbox Apple ID.
5. Бандл-ID и подпись — зона PM (см. CLAUDE.md «No-touch zones»).

## Android (отдельная задача)

Моковая `BillingRepository` для разработки → реальная Play Billing после оплаты Console ($25).
Вне scope #195.
