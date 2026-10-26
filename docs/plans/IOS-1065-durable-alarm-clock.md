# #1065 — durable alarm clock with explicit legacy retiming

Base: actual main `d8347841c8365667f9d812e6bdb9d886315726b9`.
PM decision, 2026-10-26: preserve legacy behavior until the user explicitly changes the alarm time. New alarms save the selected civil hour/minute. Opening, renaming, toggling, changing weekdays/theme/price and cancelling edit do not adopt a civil interpretation of legacy data.

## Implementation contract

- Retain the shipped `time: Date` wire field. Add optional validated `clockTime: TimeOfDay`; absence is legacy. New app-created alarms and explicit time changes populate it. Invalid present values (including null/partial/out-of-range) fail decoding and preserve the existing repository corruption/backup/write-lock behavior. Read/fetch never writes a migration.
- Add one shared resolution boundary: explicit clockTime wins; legacy extracts hour/minute using the reader's calendar. Copy operations preserve authority. `with(time:)` establishes a civil clock only when raw hour/minute actually change in the supplied calendar; identical Date or date/seconds-only changes retain existing authority. An explicit clockTime argument remains authoritative. Codable retains every existing property/key assertion and adds literal new-clock fixtures. Older builds can read the retained Date; writing through an older encoder drops the new field and returns the record to legacy interpretation on reopen. This limitation is tested and not described as recovered original intent or lossless semantic downgrade.
- Editor keeps legacy authority on unrelated saves. A real minute/hour selection establishes civil authority; a no-op callback, configuration or cancellation does not. Use a fixed UTC calendar only as a temporary picker bridge so a DST gap cannot normalize the chosen civil clock. Legacy display components are projected into that bridge without changing stored data. A captured editor calendar interprets legacy input consistently while editing; reopening uses the new current calendar.
- List, sort, scheduled firing hero, transaction caption, delete copy and native original schedule consume the same clock authority. Preserve locale/hour-cycle formatting, #1060 clock sort/ties, weekly/never mapping and #1061 alerting/rearm protections. Paid snooze deadlines, live current-time displays, wake history, wallet/ledger/session ownership and stop/cancel policy remain unchanged.
- Keep the pure immutable TimeOfDay value explicitly nonisolated and Sendable; its read-only Alarm resolver is nonisolated for the existing native mapper. The target's default MainActor setting stays unchanged.

## Owned source groups

1. Model/schema: Alarm.swift, TimeOfDay.swift, model/coding fixtures and new clock-persistence tests.
2. Editor: CreateAlarmViewModel.swift, TimePickerCell.swift, CreateAlarmViewController+Sections.swift and editor/picker tests.
3. Consumers/integration: WallClockFormatter and AlarmFiringTimeFormatter, list/hero/caption/delete copy, AlarmRepository clock sort, AlarmKitScheduler original mapping and integration tests.

No project/workflow/dependency/permission/signing change. #1070 recovery remains an independent draft; do not copy it into this patch. Preserve all actual-main2390 source method IDs, existing assertions/timeouts and18previouslypaused UITour methods. Add focused literal decode, legacy/no-op/explicit edit, fixed-offset/restart, DST-component, formatting/sort/native, unknown-field/old-writer and corrupt-store tests with injected calendars; never mutate process-global timezone. Native DST firing/audibility and UI acceptance remain unverified until their actual gates execute.

## Validation/publication

Static SwiftLint/diff/catalog/source-inventory checks, independent code/type, test and silent-failure/comment reviews of exact head, then one ordinary initial PR CI. No local compiler/build/XCTest/Simulator, frozen retry renewal, selector/timeout/assertion weakening or hook bypass. Publish honest draft if UI/device gates remain held. The previous one-time merge exception applied only to1066–1068 and is not renewed here.
