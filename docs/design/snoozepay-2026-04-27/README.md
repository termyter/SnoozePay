# CODING AGENTS: READ THIS FIRST

## ⚠️ Сверка канона с отгруженным (2026-08-29, issue #466)

Этот бандл — экспорт из Claude Design от 27 апреля. С тех пор часть решений была
осознанно изменена продуктом, и прототип **отставал** от кода, из-за чего каждый
`/audit design` выдавал одни и те же ложные находки. Артборды ниже приведены
к отгруженному состоянию; источник правды о том, «как отгружено» — код в
`SnoozePay/SnoozePay/ViewControllers/`.

| Артборд | Было в прототипе | Стало | Решение |
|---|---|---|---|
| `23-settings` | профиль-карточка, «Способы оплаты», «Выйти из аккаунта» | без них; в «Прочем» — Политика/Соглашение/Связаться + сегмент «Тема» | #237, #283, #521 |
| `18-wallet` | грид пресетов 3×2 + CTA «Положить» во вкладке | информационный таб: баланс, недельный чарт, превью истории; пополнение — money-пилюля в шапке | #233 |
| `19-deposit` | полноэкранный шаг, суммы 500/1000/2000/5000, выбор способа оплаты | bottom sheet поверх затемнённого кошелька, живые SKU 49/149/299/499/999 | #233 |
| `08-create-alarm` | плейсхолдер «напр. Будни, Спорт», цена мелким значением | плейсхолдер «Название · напр. Будни», свободный ввод суммы + пресеты, сегмент «Повтор» | #229, #231 |
| `10-alarm-edit` | одна карточка Цена/Прогрессив/Звук/Тема, «Удалить» в скролле | Звук/Тема/Вибрация + отдельные карточки цены и прогрессива, «Удалить» в фиксированном футере | #231 |

**Артборды вне MVP** (визуально валидны, но приложению не соответствуют ничему —
сверять по ним нечего): `20-withdraw`, `22-payment-methods`.

**Статистика (`27-stats`) не менялась:** блоки «Эта неделя» и «Время подъёма» в
прототипе были и раньше — их догнало приложение (#348). Обратная дельта осталась:
приложение показывает ещё карточки «ПО ДНЯМ НЕДЕЛИ» и «ДИНАМИКА ОТКЛАДЫВАНИЙ»,
которых на артборде нет. Первая близка к «По дням недели · среднее» из старого
`StatsScreen` (`SPMore.jsx`), у второй эталона нет вообще — обе ждут решения PM.

**Экраны `-uitour` без эталона:** `alarms-nobackend`, `firing-snoozed`,
`firing-progressive`, `periodpicker`. Для них артбордов в бандле нет; сверять их
пиксельно нельзя, находки по ним — не баги по умолчанию.

---


This is a **handoff bundle** from Claude Design (claude.ai/design).

A user mocked up designs in HTML/CSS/JS using an AI design tool, then exported this bundle so a coding agent can implement the designs for real.

## What you should do — IMPORTANT

**Read the chat transcripts first.** There are 1 chat transcript(s) in `snoozepay/chats/`. The transcripts show the full back-and-forth between the user and the design assistant — they tell you **what the user actually wants** and **where they landed** after iterating. Don't skip them. The final HTML files are the output, but the chat is where the intent lives.

**Read `snoozepay/project/SnoozePay - All Screens.html` in full.** The user had this file open when they triggered the handoff, so it's almost certainly the primary design they want built. Read it top to bottom — don't skim. Then **follow its imports**: open every file it pulls in (shared components, CSS, scripts) so you understand how the pieces fit together before you start implementing.

**If anything is ambiguous, ask the user to confirm before you start implementing.** It's much cheaper to clarify scope up front than to build the wrong thing.

## About the design files

The design medium is **HTML/CSS/JS** — these are prototypes, not production code. Your job is to **recreate them pixel-perfectly** in whatever technology makes sense for the target codebase (React, Vue, native, whatever fits). Match the visual output; don't copy the prototype's internal structure unless it happens to fit.

**Don't render these files in a browser or take screenshots unless the user asks you to.** Everything you need — dimensions, colors, layout rules — is spelled out in the source. Read the HTML and CSS directly; a screenshot won't tell you anything they don't.

## Bundle contents

- `snoozepay/README.md` — this file
- `snoozepay/chats/` — conversation transcripts (read these!)
- `snoozepay/project/` — the `SnoozePay` project files (HTML prototypes, assets, components)
