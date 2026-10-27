# Alarm rearm diagnostic — #744 partial

Base: `755afce6f619e81332b368a7be67d540d4737771` (current main verified remotely).

The authorized AlarmKit backend may have an unreadable alerting inventory. The
real `rescheduleAll` guard already preserves schedules and reports enabled alarms
as failed, but its diagnostic goes directly to Logger and has no logical routing
oracle. Route only that existing public constant through `AppLogger.emit`, with
the same Scheduler category, error severity, wording and control flow.

Add three focused XCTest methods calling the real scheduler with existing inert
notification/native doubles and a scoped sink:

1. Unknown inventory: two enabled alarms and one disabled alarm produce exactly
   one independently specified diagnostic and one completion reporting two;
   neither native nor legacy schedules are changed.
2. Healthy empty inventory: only the enabled original is cancelled/rearmed,
   completion reports zero, and no unavailable-state diagnostic is recorded.
   Keep the sink installed through the actual scheduler completion.
3. Disabled-only and empty input with unknown inventory: each completes once
   with zero, with no diagnostic or native/legacy activity.

Preserve every old test body, assertion, timeout and selection. Do not alter
AppLogger, authorization, currency, paid deadlines, default stores, StoreKit,
device behavior, project configuration or workflows. The frozen #728/#918/#997
scopes remain unchanged. This partial does not close #744 or prove production
unified-log emission, filtering, privacy projection or physical acceptance.

Validate with static SwiftLint, exact diff/body checks and source inventory only.
Commit normally on `codex/IOS-744-rearm-diagnostic`; the orchestrator owns later
independent review, prospective CI inventory and publication. No local compiler,
build, XCTest, Simulator, OSLog readback, push or CI is part of this handoff.
