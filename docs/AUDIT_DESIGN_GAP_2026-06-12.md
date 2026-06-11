# Design-Gap Audit — 2026-06-12

Source of truth: Claude Design handoff (`docs/design/v2-handoff/` — JSX prototypes + 7 chat transcripts), per PM directive 2026-06-12.
Method: 6 parallel read-only agents (tokens / alarms / firing / wallet / stats-settings-onboarding / business rules) + live simulator smoke pass.
Severity: **P1** visibly broken or contradicts core business promise · **P2** clear mismatch vs design · **P3** polish.

Status legend: `tracked:#N` — already covered by an open issue; `NEW` — needs an issue.

---

## Area: Alarm Firing family (firing / snoozed / no-balance / top-up sheet / woke-morning)

### P1
1. **P1 | Snoozed state (whole screen)** | SPFiringThemeSnoozed.jsx:18-199, chat5.md:311-355 | AlarmFiringViewController+ViewLifecycle.swift:45-63 | Design: after «Поспать ещё» screen stays alive and flips to snoozed state — live countdown replaces clock, bell tile dimmed 0.7 with zZ badge, «Будни · отложено до 07:05», 4-step charge scale, fly-up «−50 ₽» on balance pill — code dismisses immediately after snooze; no snoozed state exists | tracked:#226
2. **P1 | No-balance V3 (whole state)** | SPFiringNoBalanceThemes.jsx:26-194; chat6.md:342-442 | AlarmFiringViewController+NoBalance.swift (V2-based) | Per-theme drained backgrounds, red breathing glow, grayscale snooze card, green «Пополнить · 500 ₽» (no Apple Pay branding), glass wake w/ accent border, no bell/name, IconCoinOff pills — code: V2 drained dawn only, warn card α0.45, «Apple Pay»+applelogo, ghost wake, shield.fill, bell+name visible | tracked:#227
3. **P1 | WokeMorning screen missing entirely** | SPWokeMorning.jsx:20-168, SPDawnV3.jsx:267-296, chat5.md:243-292 | AlarmFiringViewController.swift:485-488, AlarmFiringViewModel.swift:214-227 | «Я встал» should lead to mint-green morning summary (clean/recovered variants); code dismisses straight to app | tracked:#228
4. **P1 | Penalty progression has no cap — business rule** | SPDawnV3.jsx:149-152 (`prices=[50,100,200,400]`, idx=min), :242 («максимум — дальше только встать»), chat1.md:256 | Alarm.swift:283-287 (`pow(2,count-1)` unbounded), AlarmFiringViewController.swift:410-418 | Design caps progressive at 4 steps (base ×8) with max-step copy; code doubles forever (…800→1600→3200) | **NEW**

### P2
5. **P2 | Snooze CTA copy+icon** | SPDawnV3.jsx:82-85, SPThemedFiring.jsx:179-182 | SPSnoozePrice.swift:113,143 | «Спать ещё N мин» + clock glyph 14 vs code «Поспать ещё N мин», no icon | **NEW**
6. **P2 | Progressive CTA tone** | SPDawnV3.jsx:153-155, chat1.md:354,394 | AlarmFiringViewController.swift:377-382, SPSnoozePrice.swift:196-234 | V3: CTA stays gold on all steps (escalation via bg+indicator); code reddens CTA gradient | **NEW**
7. **P2 | Firing top-up sheet presets layout** | SPTopUp.jsx:105-175 | FiringTopUpBottomSheetViewController.swift:39-43,134-142,400-413 | Vertical full-width rows with h4 «+1 откладывание/+несколько/+неделя» + hint + money-md + warn check vs 3-up horizontal tiles, labels dropped | **NEW** (#240 covers only SKU lineup)
8. **P2 | Top-up sheet header** | SPTopUp.jsx:135-142 | FiringTopUpBottomSheetViewController.swift:96-109,293-306,603-615 | Pulsing warn dot + caps «Будильник на паузе · 00:54» + h2 «Пополнить баланс» vs caps «ПОПОЛНИТЬ», no h2, no dot | **NEW**
9. **P2 | Progressive indicator before first snooze** | SPDawnV3.jsx:216 (`snoozes > 0`) | +Layout.swift:58-66, +Progressive.swift:20-73 | Design hides pain pill until first snooze; code shows from fire moment | **NEW**

### P3
10. **P3 | Progressive pill copy** | SPDawnV3.jsx:219-221 | +Progressive.swift:79-80 | «Прогрессив · {n+1}-й поспать ещё» vs «N-е откладывание» | NEW (active screen; #226 covers snoozed only)
11. **P3 | History ticker presentation** | SPDawnV3.jsx:114-136 | +Progressive.swift:44-54,82-99 | Colored mini-pills + «·» in center vs mono fg3 line with arrows above CTA | NEW
12. **P3 | Dawn glow geometry+cadence** | SPDawnV3.jsx:2-3,30-35 | SPDawnBackgroundView.swift:107-117, +ViewLifecycle.swift:32-41 | 480pt/8s vs 320pt/4s | NEW
13. **P3 | Calm base gradient mid-stop** | SPDawnV3.jsx:20 (55%) | SPDawnBackgroundView.swift:138-143 (0.6) | trivial | NEW
14. **P3 | Drained dawn base is V2 recipe** | SPDawnV3.jsx:22 | SPDawnBackgroundView.swift:184-191 | tracked:#227
15. **P3 | «Я встал» styling** | SPThemedFiring.jsx:188-203 | AlarmFiringViewController.swift:163-168, SPButton.swift:279-284 | 1.5pt border + ✓ icon vs hairline ghost, no icon | NEW
16. **P3 | Tense-background threshold** | SPDawnV3.jsx:185 (price ≥200) | AlarmFiringViewController.swift:454-462 (intensity ≥0.5) | reddens one snooze later | NEW
17. **P3 | Top-up pay button + footer** | SPTopUp.jsx:178-193 | FiringTopUpBottomSheetViewController.swift:418-430,152-161 | Black Pay-style button + «3D Secure не нужен» footer vs green SPButton + other copy; needs same PM ruling as #227 re Apple Pay branding | NEW
18. **P3 | Top-up default selection** | SPTopUp.jsx:104 (200 ₽) | FiringTopUpBottomSheetViewController.swift:206-212 (500 ₽ popular) | NEW
19. **P3 | Extra «Выбрать другую сумму» link in no-balance** | SPFiringNoBalanceThemes.jsx:137-190 (3 actions only) | +NoBalance.swift:175-189 | NEW (adjacent #227)
20. **P3 | Balance pill structure** | SPDawnV3.jsx:97-109 | AlarmFiringViewController.swift:423-449 | two-tier label/value flattened to one string; fly-up tracked:#226 | NEW (typography part)
21. **P3 | Clock mount animation** | SPDawnV3.jsx:48-67 | AlarmFiringViewController.swift:109-124 | 800ms fade+blur+rise not implemented | NEW
22. **P3 | Top-up sheet surface token** | SPTopUp.jsx:127 (bg-1) | FiringTopUpBottomSheetViewController.swift:251 (bg2) | trivial | NEW
23. **P3 | Snooze hint capitalization** | SPDawnV3.jsx:241 lowercase | AlarmFiringViewController.swift:417 | trivial | NEW

**Verified matching:** AlarmFiringThemePalette vs FIRING_THEMES — all 6 themes exact (bg/scrim/accent/accentSoft/pill/bellGrad/timeShadow, stops). Clock 96pt ultralight mono, date «Пт · 27 апр», hero order, eyebrow flip, pain pill flip at 0, insets, bell tile 72/r22, refund-on-schedule-failure.

Counts: P1 ×4 (1 NEW), P2 ×5 (all NEW), P3 ×14 (12 NEW). Total 23, NEW 17.

---

## Area: Alarms List + Create/Edit + Pickers

### P2
1. **P2 | List header settings button** | SPScreensV2.jsx:316-333, chat3.md:1688-1694 | AlarmsListViewController.swift:124-149 | Design: 40×40 whiteOverlay06 gear INSIDE header title row next to money «+», no nav bar — code keeps visible UINavigationBar with gear as leftBarButtonItem (extra empty bar above header) | NEW
2. **P2 | List empty state** | SPMore.jsx:415-445 | SPAlarmsListEmptyState.swift:32-89 | Design: 84×84 whiteOverlay06 tile + bell fg3, h2 «Ни одного будильника», body «Создайте первый — выставите время, цену откладывания и положите баланс.», money-lg «Создать будильник» — code: 96×96 WARN-gradient tile, caps «ПОКА ПУСТО», другой body, «Создать первый» | NEW
3. **P2 | Confirm-delete body copy — semantically wrong** | SPMore2.jsx:377-379 | ConfirmDeleteAlarmViewController.swift:130, call site CreateAlarmViewController+Pickers.swift:19 | Design reassures «Баланс 840 ₽ останется на месте — он привязан к аккаунту» + alarm context; code claims «Деньги с баланса не вернутся. Это безвозвратно.» — удаление будильника баланс НЕ трогает | NEW
4. **P2 | Snooze price card** | SPComponents.jsx:155-213, chat3.md:1196-1366 | Cells/PenaltyCell.swift:18-150 | free numeric input (moneyLg 32 warn400) + min 1 ₽/no max + quick chips vs preset-only chips 20/50/100/200/500 | tracked:#230
5. **P2 | Create/Edit section header copy** | SPMore2.jsx:268-269, SPDawnV3.jsx:587-588 | CreateAlarmViewController.swift:335-336 | In-card captions «Длительность откладывания»/«Цена откладывания» + hints vs table headers «ВРЕМЯ ОТКЛАДЫВАНИЯ»/«ШТРАФ ЗА ОТКЛАДЫВАНИЕ» («штраф» в дизайне не встречается), hints dropped | NEW (overlaps #230 partially)
6. **P2 | Time picker** | SPScreensV2.jsx:700-706 | Cells/TimePickerCell.swift:12-50 | caps «Подъём» + clock-XL 96pt mono display vs stock UIDatePicker wheels, hardcoded `.secondarySystemBackground` | NEW
7. **P2 | Volume row unreachable** | SPMore2.jsx:466-498 | CreateAlarmViewController.swift:48-59 | tracked:#270

### P3 (19)
8. Balance pill value 14px mono vs moneyMd 20pt — SPScreensV2.jsx:364-369 vs SPAlarmsListHeader.swift:233-243 | NEW
9. Balance pill icon IconWallet vs creditcard.fill — SPAlarmsListHeader.swift:215 | NEW
10. Invented third "low ≤100 ₽" warn pill tone — not in design (only normal+zero) — SPAlarmsListHeader.swift:93-111,443-447 | NEW
11. Sound pill on enabled card lost 12px icon — AlarmCell.swift:269-272 | NEW
12. Disabled cards keep pill icons (design: plain neutral, no icons) — AlarmCell.swift:252-267 | NEW
13. h1 kern −0.32 vs spec −0.64 (−.02em @32px) — SPAlarmsListHeader.swift:125 | NEW
14. Edit nav title «РЕДАКТИРОВАТЬ» vs caps «Будильник» — CreateAlarmViewController.swift:89,159 | NEW
15. Name field h3-in-card vs h1 32pt + bottom hairline + warn caret — Cells/NameCell.swift:14-32 | NEW
16. Day chips stretched fillEqually ovals vs seven 36×36 circles gap 6 centered — Cells/DayPickerCell.swift:17-71 | NEW
17. New-alarm default days: code `[]` («Единожды») vs prototypes Пн–Пт preselected — CreateAlarmViewModel.swift:49 | NEW (prototype-only evidence)
18. Default sound "radar" vs design "Soft Dawn/Рассвет" — CreateAlarmViewModel.swift:54 | NEW
19. Snooze slider: «мин» not dimmed, endpoint labels «1 мин/15 мин» missing, thumb money vs warn — Cells/SnoozeSliderCell.swift:34-84 | NEW
20. Delete footer: content should scroll UNDER fixed button + top drop-shadow — CreateAlarmViewController.swift:193-222 | NEW
21. Confirm-delete scrim: blur(2px)+.55 vs ultraThinMaterialDark+.55 (much stronger) — ConfirmDeleteAlarmViewController.swift:37-49 | NEW
22. Sound picker structure: single card list + icon tiles + descriptive subtitles + Превью player + «Готово» vs floating rows with play buttons, durations, auto-pop — SoundPickerViewController.swift | NEW
23. Sound catalogue: 6 design entries incl. «Своя мелодия» vs 10 system sounds, no custom slot — CreateAlarmViewModel.swift:206-217 | NEW
24. Theme picker: 3-col 1:1.2 grid, overlay name+subtitle, checkmark badge top-right, «Готовые темы», «Готово» vs 2-col 16:9, opaque footer band, no subtitles — AlarmThemePickerViewController.swift:218-248, AlarmThemeTileCell.swift:62-133 | NEW
25. Theme gradients vertical vs 135° diagonal (ThemeRowCell does it right) — AlarmThemePickerViewController.swift:207-208, AlarmThemeTileCell.swift:211-212 | NEW
26. Volume picker copy: «ГРОМКОСТЬ» vs «Текущий уровень», fade copy, Critical-Alerts row absent — VolumePickerViewController.swift:39-51,186-203 | NEW (reachability tracked:#270)
27. List can't distinguish weekly vs one-shot with days set: «БУДНИ · ПН–ПТ» shown for repeatMode .never — AlarmsListViewModel.swift:492-522 | NEW (edge case)

**Verified matching:** default penalty 50 ₽, snooze 9 (1–15), repeat default/hints per chat5, progressive chain ×2/×4/×8 coloring, settings card Звук/Тема/Вибрация, theme lineup, zero-balance pill (#232), long-name wrap (#232), streak banner, paddings 20/r20/gap12, confirm-delete structure.

Counts: P1 ×0, P2 ×7 (5 NEW), P3 ×19 (18 NEW). Total 26.

---

## Area: Design-system tokens & shared components

### P1
1. **P1 | Brand fonts not bundled** | tokens.css:148-150 | AppFonts.swift:125 | Design: Manrope + JetBrains Mono for ALL roles — code has `brandFontsAvailable = false`, no .ttf/.otf in repo; весь апп рендерится SF/SF Mono fallback | **NEW**

### P2
2. **P2 | lg button radius 16 vs 20** | components.css:18 | SPButton.swift:62-68 (comment claims sp-r-md — that's md spec, not lg) | NEW
3. **P2 | legacy card surface** | tokens.css:44 | UIView+CardStyle.swift:22,178,213 | `applyCardStyle()`/`styleAsCardRow()` paint `secondarySystemBackground` (iOS grey) вместо brand bg1/bg2 — живо на Settings, TransactionCell, CreateAlarm, ProgressiveScaleCell | NEW (possible #243 overlap)
4. **P2 | Pill force-uppercase** | components.css:74-84 (no text-transform; "Soft Dawn" mixed case) | SPPill.swift:93-105 | каждый pill капсится | NEW
5. **P2 | Preset value font 18px vs moneyMd 20** | components.css:122 | SPAmountPreset.swift:111-131 | NEW
6. **P2 | Tab bar — stock, без кастомизации** | components.css:241-258 + SPComponents.jsx:300-320 | SceneDelegate.swift:120-153 | Design: rgba(14,19,32,.85) blur, top hairline, 28pt top corners, active money-400, labels 600 11px — code: дефолтный UITabBarController, systemBlue active | NEW
7. **P2 | Header balance 14px mono vs 20pt** | SPScreensV2.jsx:364-369 | SPAlarmsListHeader.swift:233-243 | NEW (дубль с alarms-аудитом)
8. **P2 | Empty state другой** | SPMore.jsx:415-444 | SPAlarmsListEmptyState.swift:32-89 | NEW (дубль с alarms-аудитом)
9. **P2 | Legacy firing literals** | tokens.css:30 | AppColors.swift:146 (`alarmFiringSnooze=#E8A838` off-token) + legacy aliases | tracked:#226/#227
10. **P2 | SnoozePriceCard missing** | SPComponents.jsx:155-215 | slider-based SnoozeSliderCell | tracked:#230

### P3 (24, все NEW кроме отмеченных)
- clock-xl weight 200 vs ultraLight 100 — AppFonts.swift:51,75,87
- Per-role letter-spacing (display/h1/h2/money/clock) не реализован — только capsKerning 0.12em — AppColors.swift:261-327
- h1 kern вдвое меньше — SPAlarmsListHeader.swift:125 (дубль)
- legacy `sectionHeader` recipe — второй источник правды для caps — AppColors.swift:322-326
- Button shadow blur 22/-6 spread vs 16/(0,8); pain opacity .45 vs .40 — SPButton.swift:303-308
- Ghost border 1px vs hairline 0.33pt — SPButton.swift:281-283
- Suffix: лишняя alpha .85, не прижат к trailing (margin-left:auto) — SPButton.swift:219-222
- SPCard: лишний stroke в dark mode (дизайн — без бордера) — SPCard.swift:149-195
- Raised card: shadow2 vs наследуемый shadow1 — SPCard.swift:153-163
- Legacy card radius 12 vs 20/16 — UIView+CardStyle.swift:21,73,171
- `AppRadius.card=16` мёртвый и противоречит .sp-card 20 — AppColors.swift:250-252
- Pill tracking 0.14em vs default — SPPill.swift:97-103
- SPSnoozePrice copy «ПОСПАТЬ ЕЩЁ» vs component-spec «Отложить на N мин» (spec vs DawnV3 разошлись) — SPSnoozePrice.swift:113,143
- `.progressive(intensity:)` lerp-тон отсутствует в спеке (дизайн — дискретно) — SPSnoozePrice.swift:15-24
- BalanceCard caps 18px vs 12pt — SPBalanceCard.swift:130-137
- BalanceCard value без -.02em — SPBalanceCard.swift:100-144
- Preset selected tint money500 vs money400 — SPAmountPreset.swift:183-191
- Popular badge: flat fill vs gradient, капс+kern лишние — SPAmountPreset.swift:150-162
- Segmented: gap 0 vs 2px, indicator r8 vs 10, shadow слабее — SPSegmented.swift:66-96
- Switch: сток UISwitch flat money500 vs 52×32 капсула + градиент + spring — SPSwitch.swift:12-31
- Input focus ring: money500 blur vs money400 hard 4pt — SPInput.swift:147-259
- SPNavBar primitive отсутствует — системные UIBarButtonItem вперемешку с кастомными хедерами
- Gear в nav bar вместо 40×40 white-06 в header row (дубль)
- AlarmCell: 1pt border + без тени vs SPCard shadow recipe; clock без -.04em — AlarmCell.swift:32-39,280-284
- Stats hero radius 28 vs 24 — StatisticsViewController+Cards.swift:19
- Hardcoded warn400 в 3 файлах (AlarmFiring:118, Splash:37-38, OnboardingPages:80-81); warn600 literal в ReferralViewController:279; swipe-delete systemRed vs pain500 — AlarmsListViewController:429
- Spring easing (cubic-bezier .34,1.56,.64,1) нигде не реализован — SPSupport.swift:99-104
- SPIcons: портировано 6 из 20+ иконок, остальное SF Symbols с другой метрикой
- SPPill.applyCustomColors — code-only API (tracked:#226 consumer)

**Verified matching:** все hex-шкалы money/pain/warn/info, bg0-4, fg1-4, overlays/strokes, 3 градиента, spacing grid, радиусы, shadow recipes, motion durations, MoneyFormatter port, SPRow, SPInput geometry, pill tone fills, SPFiringBellTile, 6 theme-палитр, SPBalanceCard geometry, header pill geometry, referral garden.

Counts: P1 ×1 (NEW), P2 ×10, P3 ×24. Total 35 (31 NEW).

---

## Area: Wallet + Top-Up + TxHistory

### P1
1. **P1 | Onboarding step 3 — first deposit CTA is a no-op** | SPMore.jsx:116-188, SPTopUpSE.jsx:33-44 | OnboardingViewController+Pages.swift:340-347, OnboardingViewController.swift:29-33 | Design: «Пополнить 250/500/1000 ₽» запускает реальную первую покупку; code: CTA только ставит `onboarding_completed`, `firstTopUpDoneKey` пишется но НИГДЕ не читается — вся first-top-up логика мертва | **NEW** (related #195/#240)
2. **P1 | Firing top-up: показанная сумма ≠ списываемой** | SPTopUp.jsx:105-109 | FiringTopUpBottomSheetViewController.swift:39-43,504-519 | Плитка «200 ₽» мапится на SKU `balance.149` — юзер видит 200, App Store списывает 149-продукт, кредитится 149 (debug fallback 200 — ещё и расходится) | tracked:#240 (но конкретный mislabel там не описан)

### P2
3. Deposit sheet пресеты: дизайн 50/250(popular)/400/500/700/1000 default 250 vs код 49/149(popular+default)/299/499/999, 5 SKU + спейсер — DepositPresets.swift:27-38, StoreKitService.swift:13-28 | tracked:#240
4. TxHistory: фильтр-чипы «Все/Списания/Поступления» отсутствуют полностью — SPMore3.jsx:142-152 vs WalletTransactionHistoryViewController.swift:91-118 | NEW
5. Charge-строки без контекста будильника: дизайн «Поспать ещё · Будни 07:00», код голое «Поспать ещё» (alarmID в модели есть!) — WalletTransactionHistoryViewController.swift:324-336, WalletTransactionPreview.swift:50-53 | NEW
6. «Пополнить» на табе будильников открывает legacy V1 TopUpViewController (2×2, 49/149/299/999, «Кошелёк», Cancel) вместо Deposit bottom sheet — AlarmsListViewController.swift:344-348 | NEW
7. Top-up CTA: гибрид «зелёная кнопка + applelogo» не соответствует ни SPTopUp (чёрный Pay), ни V3-решению «без Apple Pay branding»; риск HIG/marks — FiringTopUpBottomSheet:144-147, TopUpViewControllerFactory:67-77 | tracked:#227 (firing) / NEW (legacy TopUp)
8. Referral: дизайн «+200 обоим после 7 дней друга», код кредитует мгновенно и только вводящему — ReferralService.swift:24,106-151 | tracked:#243

### P3 (12)
9. Promotion-строка: 3 разных рендера одного типа (превью «Промо-зачисление»+gift / история «Бонус: продержались 7 дней»+checkmark / дизайн plus-icon) — WalletTransactionPreview.swift:59-62 | NEW
10. «Бонус: продержались 7 дней» хардкод для всех .promotion — единственный минтер это мгновенный реферал: копи врёт — WalletTransactionHistoryViewController.swift:330-335 | NEW (related #243)
11. Period chip lowercase «январь 2026» vs capitalize — TxHistoryPeriod.swift:104-106 | NEW
12. Weekly chart: бары ~2/3 высоты от спеки, empty-stub без dimming .5 — WalletWeeklyChartView.swift:22-30,203-223 | NEW
13. Wallet: лишний nav bar + gear (в дизайне gear только на Alarms) — WalletViewController.swift:68-80 | NEW
14. Tab icon creditcard vs IconWallet — SceneDelegate.swift:134-141 | NEW
15. Deposit/PeriodPicker scrim: stock pageSheet без blur(2px) — DepositBottomSheetViewController.swift:136-151 | NEW
16. Affordability «при текущей цене» захардкожен 50 ₽ — WalletViewController.swift:174, WalletHints.swift:22-28 | NEW (compounds #230)
17. Дублирующая legacy история в Settings («История транзакций»+«Баланс» → старый VC без V3) — SettingsViewController+Sections.swift:15-34 | NEW
18. PaymentMethodsViewController — мёртвый код, не соответствует ни контенту дизайна, ни V2-оверлею de-scope — tracked:#243
19. TxHistory top bar: системный nav vs кастомный ряд (вероятно осознанно, #237) — NEW (low-confidence)
20. TopUpSE (375×667) экран не реализован — tracked:#241/#244

**Verified:** one-way stake чисто (нет withdraw-кода), бонусы исключены из «Пополнения», ledger-first crediting/dedup превосходит требования дизайна.

Counts: P1 ×2, P2 ×6, P3 ×12. Total 20 (15 NEW).

---

## Area: Statistics + Streak + Settings + Onboarding/Permissions/Splash

### Root cause #269 (по запросу)
`OnboardingViewController+Pages.swift:59-69` — makePage1() прибивает стек ТОЛЬКО неравенствами (leading ≥ +16, trailing ≤ −16, width ≤ 320) + centerY, без centerX-равенства и width-равенства → солвер схлопывает ширину до ~1 глифа. Страницы 2/3 используют равенства и не страдают. Фикс: `centerX ==` + `width == container − 32` (prio 999), cap ≤320 оставить.

### P1
1. Onboarding page 1 collapse — tracked:#269 (root cause выше)

### P2
2. **Streak (бизнес-правило)**: дизайн «дни с прорывом привычки с последнего срыва», код `computeStreak` (TransactionRepository.swift:146-166) считает ЛЮБОЙ день без списаний до первой транзакции — дни без будильника и без пробуждения инкрементят серию, «сегодня» засчитывается до звонка; WakeEventStore не консультируется | NEW
3. Streak hero 56pt money-xl mono vs moneyLg 32pt — StatisticsViewController.swift:36-43 | NEW
4. Settings: секция «Звук и уведомления» (Громкость/Critical Alerts/Вибрация) отсутствует — SPMore4.jsx:367-375 | NEW (related #270)
5. Settings: секция «Правила» (Прогрессивная цена/Бонус за серию/Защита от скуки switches) отсутствует — SPMore4.jsx:377-385 | NEW
6. Settings/Финансы: ряд «Длительность откладывания · 9 мин» отсутствует — SPMore4.jsx:363 | NEW
7. Referral reward condition — tracked:#243 (дубль wallet-аудита)
8. Onboarding page 3 CTA без оплаты — tracked:#195/#240 (дубль)
9. SE-варианты онбординга — tracked:#244

### P3 (16)
10. Heatmap tooltip swatch: flat tone vs градиент — StatisticsHeatmapView.swift:355-356 | NEW
11. Stats hero: radius 28/padding 24 vs 24/20h — StatisticsViewController+Cards.swift:19 | NEW
12. Stats header: system large-title vs page-title block + hairline — StatisticsViewController.swift:136-137 | NEW
13. Stats empty state «Пока нечего считать» не реализован — SPMore.jsx:447-480 | NEW
14. Streak modal side inset 12 vs 16 (chat3 spacing audit) — StreakModalViewController.swift:307-308 | NEW
15. Streak modal: pip gap 4 vs 6; «вовремя» vs дизайн «во время» (код грамматически прав) — StreakModalViewController.swift:217,205-206 | NEW (cosmetic)
16. Settings: legacy секции АККАУНТ/ОФОРМЛЕНИЕ не из дизайна; version footer «1.0.0 · build 142» отсутствует — SettingsViewController.swift:40-47 | NEW
17. ThemeSegmentCell: сток UISegmented + info500 (фича вне дизайна, но не в токенах) | NEW
18. SettingsIconRowCell: iOS-чипы 30×30 vs bare tinted icons — SPMore4.jsx:362-420 | NEW
19. Referral caption/код-формат: «За каждого друга…» vs «Ваш код · поделиться…», без «WAKEUP-» префикса — SettingsViewController+Referral.swift:74, ReferralService.swift:84-97 | NEW (related #243)
20. Default-price row не тапается (дизайн: chevron → редактирование) — SettingsViewController+Sections.swift:50-62 | NEW (related #230)
21. Permissions granted icon: flat money500 vs grad-money — PermissionCardView.swift:188 | NEW
22. Onboarding dots→CTA gap 16 vs 24 (стр. 1/2) — OnboardingViewController+Pages.swift:276-280 | NEW
23. Onboarding «−50 ₽» pill: sans vs mono — OnboardingComponents.swift:70 | NEW
24. Splash: bg0 vs bg1, subtitle gap 12 vs 20 — SplashViewController.swift:119,141,152 | NEW
25. Referral/AlarmOffWarning DEBUG-only + хардкод −750 ₽ — tracked:#243

**Verified:** heatmap семантика/сетка/тултип, weekday card, trend card, streak modal де-монетизация (#236), копирайт онбординга 1-3, permissions copy, статистика третьим табом.

Counts: P1 ×1, P2 ×8, P3 ×16. Total 25 (19 NEW).

---

## Area: Business model & product rules (по 7 чатам дизайн-фазы)

Канон (последнее решение в чатах побеждает): one-way stake без вывода; «Баланс» везде, без жаргона «снуз»; цена откладывания — свободный ввод, мин 1 ₽ без максимума, чипы 20/50/100/200/500, дефолт 50; прогрессив ×2, CTA золотая с постепенным покраснением; длительность 1–15 мин per-alarm; ноль на балансе → будильник звонит, snooze disabled, зелёная «Пополнить 500 ₽» (IconWallet, БЕЗ Apple Pay branding); top-up пресеты финально 250/500/1000 popular 500 (chat6); сумма выбирается только в bottom sheet/SE-экране; referral, care-screen, payment-methods, mid-firing top-up sheet = V2 de-scope; streak де-монетизирован; stats только поведенческая; табы Будильники/Кошелёк/Статистика + gear→Settings; темы 6 + своё фото; повтор Никогда/Еженедельно дефолт weekly; дизайн кросс-платформенный.

### P1
1. Top-up tile 200 ₽ → SKU 149 ₽ (mislabel на денежном действии) — FiringTopUpBottomSheetViewController.swift:39-43 | tracked:#240, сам mislabel NEW
2. No-balance CTA: «Apple Pay»+логотип вместо решённого «Пополнить 500 ₽»+IconWallet; показывает 500 при SKU 499 — +NoBalance.swift:25-31,136-140 | tracked:#227
3. Onboarding deposit CTA не покупает (см. wallet-аудит) | tracked:#195, gap NEW

### P2
4. Deposit lineup legacy 49–999 vs финальное 250/500/1000 popular 500 — tracked:#240
5. Два разных пикера суммы (full-screen TopUp 4 пресета без 499 vs sheet 5 пресетов) при решении «единственное место выбора — sheet» — TopUpViewController.swift:54-57 | tracked:#240 + NEW
6. Цена не редактируется свободно — tracked:#230
7. Referral живёт в MVP вопреки V2 de-scope (реальные 200 ₽ в экономику) — ReferralService.swift:17-24 | tracked:#243
8. Mid-firing top-up sheet вшит в MVP flow вопреки V2 de-scope — chooseAmountLink → sheet | tracked:#243
9. Firing snoozed-state V3 отсутствует — tracked:#226
10. WokeMorning отсутствует — tracked:#228
11. Volume/fade-in вход потерян — tracked:#270
12. Кросс-платформенность не решена — tracked:#241

### P3
13. Запрещённый жаргон «снуз» в продакшн-копи: SPAlarmsListEmptyState.swift:71 («за каждый снуз»), ReferralViewController.swift:463 («Снузь меньше…») vs chat1.md:986-998 | NEW
14. «Бонус: продержались 7 дней» для всех .promotion при единственном минтере — мгновенном реферале | NEW
15. snoozeMinutesRange 1...30 в модели по stale SPEC vs решённые 1–15 (UI клампит, но decode/validating пропускает 16–30) — Alarm.swift:50 | NEW
16. Мёртвые V2-экраны: PaymentMethods, AlarmOffWarning (DEBUG), дублирующий TransactionHistoryViewController в Settings | tracked:#243 / NEW (дубль истории)
17. **SPEC.md устарел против чатов** (штраф 10–1000, пакеты 49–999, табы с «Настройки», глобальный snooze, money-stats, zero-balance без CTA) — код уже следует дизайну, SPEC — аутлаер; нужно обновить документ | NEW
18. SE-варианты — tracked:#244

**Соответствует канону (проверено):** вывод отсутствует полностью (#242 в коде выполнен), one-way-stake дисклеймеры на местах, прогрессив ×2 и превью 50→100→200→400, zero/low пороги, streak modal де-монетизирован, поведенческая статистика, история с 3 колонками и period picker, табы+gear, 6 тем+фото, repeat mode, онбординг-пресеты 250/500/1000 популярно 500, словарь «+N минут · −X ₽».

Counts: P1 ×3, P2 ×9, P3 ×6. Total 18.

---

# Сводка

| Область | Находок | NEW |
|---|---|---|
| Firing family | 23 | 17 |
| Alarms list + Create/Edit + пикеры | 26 | 23 |
| Дизайн-токены и компоненты | 35 | 31 |
| Wallet + TopUp + TxHistory | 20 | 15 |
| Stats + Settings + Onboarding | 25 | 19 |
| Бизнес-правила | 18 | 7 |
| **Итого (с дублями между областями)** | **147** | **~112 уникальных NEW** |

## Топ-кластеры для фиксов
1. **Шрифты бренда** (1 фикс — глобальный эффект на каждый экран): bundle Manrope+JBM, UIAppFonts, включить brandFontsAvailable, добить per-role letter-spacing.
2. **Денежная честность (P1)**: суммы на плитках = реальные цены SKU; прогрессивный потолок ×8; onboarding CTA (ждёт #195/#240 PM).
3. **Бизнес-правила**: streak по WakeEventStore; confirm-delete копи; «бонус 7 дней» копи; «снуз» jargon; snoozeMinutes 1...15 в модели.
4. **Хром приложения**: таб-бар V3, gear в хедеры, nav bar убрать, IconWallet.
5. **Деталки экранов**: empty states, time picker «Подъём», sound/theme пикеры, Settings секции, TxHistory фильтры+контекст будильника.
6. **Токен-полировка**: радиусы/тени кнопок, pill casing, segmented/switch/input, хардкоды цветов.
7. **SPEC.md** обновить до канона чатов.

