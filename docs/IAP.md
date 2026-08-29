# IAP / пополнение баланса — StoreKit

Пополнение баланса идёт через **In-App Purchase (StoreKit 2)**, а не через Apple Pay
(PassKit). Apple требует продавать внутреннюю валюту приложения только через IAP.
В UI бренд «Apple Pay» убран в нейтральное «Пополнить», но идентификаторы вида
`applePayNoBalanceButton` в коде остались историческими — PassKit нигде не импортируется,
под капотом везде `StoreKitService.purchase()` → `StoreKit.Transaction`.

## Состояние (2026-08-28)

Продукты живут в **App Store Connect**, локальный конфиг для работы не нужен.

| | |
|---|---|
| Приложение | `SnoozePay`, Apple ID `6783752162` |
| ID пакета (Bundle ID) | `io.mobilife.SnoozePay` |
| SKU | `io.mobilife.snoozepay` — **служебное поле, ни на что в рантайме не влияет** |
| Продукты | 5 consumable, статус «Подготовка к отправке» |

Статуса «Подготовка к отправке» достаточно для sandbox-покупок. В `Approved` продукты
перейдут только вместе с первой отправкой бинарника на review — это про релиз, не про
тестирование.

### Продукты

Источник истины по ID — константы `StoreKitService.productIDs` / `productAmounts`.
Пространство имён продуктов **строчное** и с bundle ID намеренно не совпадает:

| productID | Сумма зачисления |
|-----------|------------------|
| `io.mobilife.snoozepay.balance.49`  | 49 ₽  |
| `io.mobilife.snoozepay.balance.149` | 149 ₽ |
| `io.mobilife.snoozepay.balance.299` | 299 ₽ |
| `io.mobilife.snoozepay.balance.499` | 499 ₽ |
| `io.mobilife.snoozepay.balance.999` | 999 ₽ |

## ⚠️ Пустой каталог — почти всегда bundle ID

Самый дорогой класс ошибок здесь выглядит как работающее приложение. Если
`Product.products(for:)` вернул пусто, то `products.first(where:)` даёт `nil`, и топап
уходит в `#if DEBUG`-фолбэк `BalanceService.topUp` — **баланс растёт, диалога
подтверждения нет, ошибки нет**. Три точки входа ведут себя одинаково:
`DepositBottomSheetViewController`, `FiringTopUpBottomSheetViewController`,
`AlarmFiringViewController+NoBalance`.

В release-сборке фолбэка нет (#385/#388): пустой каталог даёт «Не удалось загрузить
пакеты пополнения», а не бесплатный баланс.

Диагноз за один запуск — лог из `StoreKitService`:

```
loaded 0/5 products; missing: io.mobilife.snoozepay.balance.49, …
```

Проверять в порядке убывания вероятности:

1. **Bundle ID сборки против поля «ID пакета» в ASC, побуквенно.** Регистр значим.
   На странице App Information поля `ID пакета` и `SKU` стоят рядом и отличаются
   только регистром — скопировать SKU в Xcode означает собрать приложение, которого
   в ASC нет. Ровно это стоило дня 2026-08-28 (#476).
2. **Симулятор.** Sandbox из ASC работает только на устройстве — см. ниже.
3. **Paid Applications Agreement** в статусе `Active` (ASC → Business → Agreements).
   Apple периодически выпускает новые редакции; до принятия продукты не отдаются.

## Тестирование

**На устройстве** — основной путь: sandbox Apple ID в `Настройки → App Store →
Аккаунт Sandbox`, запуск сборки, покупка проходит настоящий системный лист.

**В симуляторе** реальный sandbox не работает вообще. Если нужен флоу покупки в
симуляторе, есть локальный StoreKit Configuration — файл `SnoozePay.storekit` лежит
в ветке `feature/IOS-195-storekit-config-local` (PR #365 закрыт без merge).

> ⚠️ Подключать его только руками: `Edit Scheme → Run → Options → StoreKit
> Configuration`, и отключать после. **Не коммитить ссылку в схему.** Подключённый
> конфиг перекрывает обращение к ASC — включая запуск на устройстве, — и покупки
> становятся локальными и ненастоящими, внешне неотличимо от настоящих. Именно
> поэтому PR #365 не был смержен.

Test-action схемы конфигурации не несёт и нести не должен: `NoBalanceTopUpUITests`
тапает «Пополнить» и рассчитывает на fallback-ветку. Со StoreKit-листом, который
XCUITest не закроет, тест зависнет. CI гоняет Test-action, поэтому остаётся на
fallback и проходит.

### Матрица ручных проверок

Интерактивная, headless-инструментами не воспроизводится — прогоняет PM в Xcode через
`Debug → StoreKit → Manage Transactions`:

- [ ] Покупка → баланс растёт (`user_balance` в UserDefaults)
- [ ] Restore Purchases — для consumable не дублирует кредиты
- [ ] Ask-to-Buy → `purchasePendingNotification`, кредит после approve
- [ ] Отказ в диалоге → баланс не меняется
- [ ] Прерванная покупка → `Transaction.updates` досылает после возобновления
- [ ] Refund → обрабатывается, баланс не уходит в минус
- [ ] Failed transaction → `purchaseFailedNotification` + алерт

## Осталось до релиза

Продукты уйдут в `Approved` только с первой отправкой сборки, а ей мешает отдельный
список — см. эпик #480 (`PrivacyInfo.xcprivacy`, Critical Alerts entitlement,
version/build bump, project-level `DEVELOPMENT_TEAM`). Для каждого продукта в ASC ещё
не приложен обязательный скриншот в «Информация для проверки».

## Android

Моковая `BillingRepository` для разработки → реальная Play Billing после оплаты
Console ($25). Отдельная задача.
