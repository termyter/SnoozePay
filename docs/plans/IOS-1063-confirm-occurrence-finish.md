# #1063 — confirm one occurrence without deleting weekly recurrence

Base: actual main `d8347841c8365667f9d812e6bdb9d886315726b9`.

PM approved error/retry on 2026-10-26: retain the firing screen on unconfirmed
native or local finish, record wake and show morning summary only after success.
Decision: https://github.com/termyter/SnoozePay/issues/1063#issuecomment-6426421152.
The policy is resolved. Actual iPhone/weekly recurrence acceptance remains held.

## Boundaries

- Root owns common framework-free types, firing VM/controller, catalog, shared
  test doubles and their semantic finish expectations. Native/facade author owns
  AlarmKitScheduler/AlarmScheduler and new adapter/facade tests. Session author
  owns AlarmSnoozeSessionStore and new scoped-ticket tests. Authors do not commit
  or switch the shared worktree; root integrates and commits after all edits.
- A durable optional finishRequests array in the existing session envelope is an
  operation quarantine, not a new billing occurrence/reset policy. Missing means
  empty; present null or malformed metadata is rejected. An older writer can
  drop this unknown field on downgrade, so lossless downgrade quarantine is not
  claimed. A ticket binds alarmID and optional exact latest token. Other unfinished
  sessions or stale attempts refuse cleanup. Retry reuses the ticket; no-op
  reads do not migrate data. Successful scoped commit alone releases quarantine.
- For an untracked ticket, resuming its existing operational request is allowed
  only when there is still no unfinished tracked session. A tracked ticket needs
  the same exact token; no age/calendar/ledger reconstruction. Corrupt data stays
  untouched and returns error. reserve and queued physical paid registrations
  refuse while a finish request remains. Pending callbacks retain their genuine
  charge/refund outcome and receipt; do not create a finish-specific refund.
  A live callback remains busy. Durable pending without a running callback has
  no confirmed receipt and therefore permits only checked derived absence;
  scoped commit settles its reserved/charged phases using the existing cancel
  semantics, preserving count, ledger, receipts and refund policy.
- The native adapter uses injected throwing stop/cancel and checked complete
  inventory projections. Weekly success requires exactly one matching original
  in scheduled state plus absent derived. One-shot success requires both absent.
  Unknown/duplicate/unreadable states fail. A fresh matching readback may prove
  already-finished after a native throw; a throw alone never proves success.
- Expected tracked receipt must match an existing derived fixed date before
  deletion. An exclusively untracked ticket may clean its own derived ID.
  Late success removes only derived; it never full-cancels weekly original.
  A pending schedule is busy until its callback and checked cleanup settle.
- On corrupt/unsafe context, best-effort stop only the known original; never
  destructively clean an unowned derived. Keep error/retry and no wake/summary.
- VM closes paid continuation immediately and holds its ticket through retry.
  Native confirmation, checked one-shot persistence and scoped session commit
  precede wake. Missing/deleted repository alarm is checked and benign; an
  explicitly disabled/deleted alarm expects both native IDs absent. Duplicate
  success returns alreadyCompleted and repeats no wake/summary/queue callback.
- Full cancel remains full for disable/delete/recovery. Existing #1007 pricing,
  identity, receipt and linked refund rules remain. No protected config/workflow,
  old CI allowance, local compiler/build/XCTest/Simulator or merge exception.

## Validation

Stateful native fixtures must preserve weekly original without rearm, distinguish
missing weekly/absent one-shot, exercise scheduled vs paused/countdown/unknown,
operation/read/partial/revoked failures and exact derived receipt. Store fixtures
must cover same-alarm stale attempt/B session, corrupt bytes, restart ticket,
cross-VM reserve quarantine, pending callback and successful scoped commit.
VM/controller tests cover early debit guard, success-only wake/summary/onUserStop,
busy/failed retry, duplicate completion, one-shot persistence and late tracked/
untracked cleanup with unchanged linked refund policy. Preserve every previous
test ID/timeout; replace only obsolete full-cancel expectations with stronger
weekly-preservation/derived-cleanup and honest pending-state expectations.

All code receives independent code/type, silent-failure and test reviews before
ordinary PR CI. The PR stays draft for UI/native device acceptance; hosted-unit
fixtures do not establish actual daemon readback timing or future audibility.

## Pre-publication source inventory

72 new methods:18native adapter,18facade,20scoped store,13VM and3controller.
Every2390baseline method ID remains; source2462 / expected selected2444, with
the same18paused UITour methods. Catalog adds3keys, all493previous entries
unchanged. No project/scheme/workflow/protected file changed. Local lint:
app0errors/109warnings; changed tests0errors/18warnings at inherited sites,
all5newtestfiles0warnings. No compiler or tests executed locally.

Eight existing test/support files changed for the new contract: consumer doubles
explicitly return configured finish outcomes (stateful adapter fixtures prove
native postconditions separately); denied mock backends retain local-audio
routing while permitting verified free finish; pending Stop tests retain the
error/no wake until explicit confirmed retry; full-cancel expectations become
derived-only cleanup plus preserved weekly original. Diagnostic prefix/error
level and corrupt bytes remain tested with the new typed failure. Old linked
refund, amount/count/timeout and unrelated routing assertions remain.

Independent source review before any CI found two P2 edges: verified weekly
finish must still sweep obsolete UN notifications, and a disabled snapshot must
not cancel a re-enabled weekly original. Both have dedicated regressions. The
legacy-only sweep follows verified native success and preserves unrelated
notifications and native recurrence. The stale enabled transition is refused
before ticket/native mutation. An extra Stop→late failure consumer row verifies
the existing linked refund and no wake until confirmed retry.
