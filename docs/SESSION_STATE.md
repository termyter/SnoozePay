# SnoozePay — Session State (2026-02-28)

## Процесс работы (СТРОГО соблюдать)

1. Ветка `feature/IOS-XXX-description` от main
2. Dev пишет код + unit тесты
3. Push → PR с описанием (что сделано, тесты, скриншоты)
4. Lead делает code review + дизайн-ревью (Figma) + проверка вёрстки
5. Замечания в PR → Dev отвечает reply что и как пофиксил
6. Цикл ревью пока Lead не одобрит
7. Lead одобрил → Trello → Review → **ждём ОК от Ивана**
8. **Иван даёт ОК → merge в main → Trello → Done**
9. **БЕЗ финального ОК от Ивана — НЕ мержить!**
10. Trello: Dev двигает In Progress ↔ Review. Done — только после merge.
11. **Никаких упоминаний Claude/AI/Anthropic/Co-Authored-By на GitHub**

---

## Открытые баги и замечания

### Баг 1 (критический) — IOS-026
**Будильник не работает при заблокированном экране.**
- Сейчас приходит как обычное уведомление
- Нужно: Critical Alerts + непрерывный звук + fullscreen notification на lock screen
- iOS 26.3
- Проблема: Personal Development Team не поддерживает Critical Alerts entitlement
- Нужно: запросить у Apple через https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/
- Entitlement добавлен в код но закомментирован (SnoozePay.entitlements)
- Fallback: используется `.timeSensitive` interruption level

### Баг 2 (UI) — IOS-027
**Toggle активности будильника не обновляется в реалтайме.**
- Переключение toggle визуально не отражается до перезагрузки экрана
- Нужно: обновлять cell UI при переключении в AlarmsListViewController

---

## Статус задач

### Фаза 0 — Дизайн (завершена)
| Задача | Статус | PR |
|--------|--------|-----|
| DESIGN-001–010 | ✅ Done | — |

### Фаза 1 — iOS (в работе)
| Задача | Описание | Статус | PR |
|--------|----------|--------|-----|
| IOS-001 | Xcode проект + модели | ✅ Done | #1 |
| IOS-002 | Главный экран — список будильников | ✅ Done | #1 |
| IOS-003 | Экран создания/редактирования | ✅ Done | #1 |
| IOS-004 | Логика будильника (scheduling) | ✅ Done | #1 |
| IOS-005 | Экран сработавшего будильника | ✅ Done | #1 |
| IOS-006 | StoreKit 2 — пополнение баланса | ✅ Done | #1 |
| IOS-007 | Статистика + графики | ✅ Done | #1 |
| IOS-008 | Настройки + история транзакций | ✅ Done | #1 |
| IOS-009 | Тёмная/светлая тема | ✅ Done | #1 |
| IOS-010 | Unit тесты | ✅ Done | #1 |
| IOS-011 | Alarm sound + vibration + critical alerts | ✅ Done | #3, #6 |
| IOS-012 | Sound preview в редакторе | ✅ Done | #4 |
| IOS-013 | Alarm card → Figma | ✅ Done | #8 |
| IOS-014 | Swift Charts для статистики | ✅ Done | #5 |
| IOS-015 | Streak bug fix (366) | ✅ Done | #2 |
| IOS-016 | Snooze stepper layout fix | ✅ Done | #2 |
| IOS-017 | Онбординг из Figma | ✅ Done | #11 |
| IOS-018 | Все экраны → Figma макеты | ✅ Done | #8-11 |
| IOS-019 | Fallback звук (синтетический тон) | ✅ Done | #7 |
| IOS-020 | AudioService compile fix | ✅ Done | #12 |
| IOS-021 | Disable non-repeating alarm after dismiss | ✅ Done | #13 |
| IOS-022 | Critical alerts entitlement | ✅ Done | #14 |
| IOS-023 | Theme selector (Light/Dark/System) | ✅ Done | #15 |
| IOS-024 | Build fixes (critical alerts fallback) | ✅ Done | #16 |
| IOS-025 | 10 Public Domain alarm sounds | ✅ Done | #17 |
| IOS-026 | 🔴 Баг: lock screen alarm | 📋 To Do | — |
| IOS-027 | 🟡 Баг: toggle не обновляется | 📋 To Do | — |

---

## Архитектурные решения

### Стек
- **Swift 5.9+, UIKit, MVVM** (NO SwiftUI кроме Charts)
- **UserDefaults + Codable** для персистенции (НЕ Core Data)
- **AlarmScheduler**: UNUserNotificationCenter с critical alerts fallback
- **AudioService**: Singleton, AVAudioPlayer, синтетический тон если файлов нет
- **BalanceService**: Singleton, UserDefaults key `"user_balance"`
- **StoreKit 2**: Consumable IAP (49₽, 149₽, 299₽, 499₽, 999₽)

### Ключевые файлы
```
SnoozePay/
├── Models/
│   └── Alarm.swift              # Codable struct, penalty calculation
├── Services/
│   ├── AlarmScheduler.swift     # UNNotification scheduling
│   ├── AlarmRepository.swift    # UserDefaults CRUD
│   ├── AudioService.swift       # Sound playback + synthetic tone
│   └── BalanceService.swift     # Balance management
├── ViewModels/
│   ├── AlarmsListViewModel.swift
│   ├── AlarmFiringViewModel.swift
│   ├── CreateAlarmViewModel.swift
│   └── StatisticsViewModel.swift
├── ViewControllers/
│   ├── Alarms/
│   │   ├── AlarmsListViewController.swift
│   │   ├── AlarmCell.swift
│   │   ├── AlarmFiringViewController.swift
│   │   ├── CreateAlarmViewController.swift
│   │   └── SoundPickerViewController.swift
│   ├── Statistics/StatisticsViewController.swift
│   ├── Settings/
│   │   ├── SettingsViewController.swift
│   │   ├── TopUpViewController.swift
│   │   └── TransactionHistoryViewController.swift
│   └── Onboarding/OnboardingViewController.swift
├── Resources/Sounds/            # 10 Public Domain .caf files
├── Info.plist                   # NSCriticalAlertUsageDescription, UIBackgroundModes
└── SnoozePay.entitlements       # critical-alerts (закомментирован)
```

### UserDefaults ключи
- `"saved_alarms"` — [Alarm] Codable array
- `"user_balance"` — Double
- `"transactions"` — [Transaction] Codable array
- `"preferred_theme"` — "system" | "light" | "dark"
- `"onboarding_completed"` — Bool

### Звуки
10 файлов Public Domain (SoundBible.com) в формате CAF:
dawn, radar, drops, piano, guitar, bell, waves, birds, classic, jazz + default_alarm

---

## Внешние сервисы

### GitHub
- Repo: https://github.com/termyter/SnoozePay (private)
- 17 PRs merged to main

### Trello
- Board: mvTZuW7S (https://trello.com/b/mvTZuW7S)
- API Key: 2030ff9df5dc92683cde53097c6706c7
- Token: ATTAdf1a6f61fd9c6eb5d77cea26e892fb6cabaafbf321b2a1a57d2cb1eeda3db7cf1C9CEA17
- Lists: Backlog=69a2039ba2859c4123fd046d, To Do=69a203a12748e541f6151fcf, In Progress=69a203a840c2c9aa7925f6cc, Review=69a203ae0519f213c486fdff, Done=69a203b284eee0b93e1e6b58

### Figma
- File: https://www.figma.com/design/DU3IMT4uEiw8rua0r3uy1D/
- MCP подключён

### Apple Developer
- Dev Team: 8ZKDC782V4 (Personal)
- Bundle ID: Ivan-Emelyanov.SnoozePay
- Critical Alerts entitlement НЕ одобрен — нужно запросить

---

## Следующая сессия — план

1. Прочитать этот файл + MEMORY.md
2. Проверить Trello (mvTZuW7S) — статус карточек
3. Работать над IOS-026 (lock screen alarm) и IOS-027 (toggle UI)
4. **Помнить**: не мержить без ОК Ивана!
