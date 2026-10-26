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

## Restart recovery correction after initial CI

Initial CI40403898468 compiled and observed2444complete terminals:2442passed,
one old fixture failure and one old skip; all72new passed. The old repeat-mode
fixture used the real shared native scheduler. Local commit1de526a isolates
both repository/VM with an explicit consumer outcome, preserves old assertions
and adds success-result assertions. It is not pushed or runtime-proven yet.

Independent post-publication source review found a separate blocking path:
tracked finish ticket survives cold start but RAM presentation does not; a new
original firing routes nil-token and correctly cannot resume the old ticket.
The previous exact-head source APPROVE is superseded by REQUEST_CHANGES. Fix
reachability without weakening ownership or linking the old token to a new ring.

- Add checked durable ticket enumeration. Discovery validates exact ticket/
  latest attempt and preserves bytes; it never creates a session or wake.
- Use a scoped strict alarm snapshot for both normal finish and recovery:
  distinguish missing from a non-Data value, reject duplicate IDs, preserve
  corrupt evidence. Unknown storage must not become checked-missing permission.
- Add native read-only confirmation plus a facade entry accepting the checked
  current alarm or checked missing row and exact ticket. Require fresh complete
  inventory, matching scheduled weekly original and absent derived; for explicit
  one-shot/disabled/missing context require both IDs absent. Any active/unknown/
  mismatched original, any derived, duplicate/read failure refuses. No native
  stop/cancel/register/rearm or best-effort original stop on any resume branch.
- Add a dedicated quiet recovery use case, not a firing VM/controller or queue
  presentation. Validate exact persisted ticket, latest token, no other owner/
  running callback; prove native state; recheck local model and use the existing
  scoped ticket commit. For a confirmed one-shot use a checked persist-only
  disable with exact captured-model/readback guards and no scheduler calls.
- Render a persistent quiet action from the Alarms screen's normal load and
  foreground refresh, including valid tickets whose alarm row is now missing.
  Use existing list header/streak behavior unchanged when no pending state.
  Error retains the action after restart. A new firing's error can expose the
  separate previous-ticket retry without replacing its token, dismissing the
  firing screen, touching audio or consuming a presenter queue record.
- Explicit successful retry keeps current confirmation-time wake semantics.
  No automatic/backdated wake or invented historical morning/billing summary.
  A quiet confirmation acknowledges completion. New firing remains its own
  flow. No new debit/refund/reset/count or #1007 identity policy.
- Add meaningful store/repository/native/facade/use-case/entry regressions,
  including cold-start enumeration with no alert, exact tracked resume,
  active-new-original refusal with zero native/audio/queue mutations, corrupt/
  stale/latest/busy and persistence refusal, missing/one-shot paths and repeats.
  Preserve all prior IDs/assertions/timeouts and frozen scopes. Source review
  must converge before the sole ordinary corrective push; initial evidence
  remains attached and no naked rerun is allowed. Device/UI holds remain.

The existing separate ticket-commit→wake-write crash window is not an atomic
transaction; exactly-once wake across a second process death is not claimed.
Future1071 integration still needs civil-clock ownership comparison before the
normal finish ticket/native path; no combined source/runtime approval here.

## Corrective source handoff

Restart recovery is now implemented as the separate quiet use case/entry above,
with explicit current-confirmation-time acknowledgement. The isolated firing
initializer does not read shared recovery state; the production convenience
initializer wires it explicitly. Recovery alert callbacks verify exact alert
and ticket ownership before dismissal/proof. Discovery also handles a checked
missing alarm, and strict snapshots prevent wrong-type storage becoming absence.

52 additional methods cover native5, facade8, storage16, VM1, use-case13 and
entry9. Total124new relative to actual main; all2390baseline and72initial IDs
retained, source2514 / expected2496selected, same18paused methods. The72initial
method bodies/timeouts are unchanged. Six additional RU/ENkeys preserve all496
initial entries (502total). Full app and17changed test files lint with zero
errors,109inherited app warnings and19test warnings (18inherited plus one
facade test-file length warning). No suppressions or test weakening.

All author handoffs are source-only. Final independent exact-head review and
the sole corrective CI remain required; no runtime success or UI/native-device
acceptance is claimed by this checkpoint.

The corrective source review caught and fixed a stale list row after one-shot
success: recovery now reloads the list VM through its ordinary callbacks and a
real retry-button→datasource/switch regression asserts OFF, no native cancel and
unchanged money. The malformed-data fixture explicitly expects the existing
exact corrupt backup while comparing the entire domain and preserving source
alarm/session/ledger/wake evidence; backup behavior is not suppressed.
Refresh can itself present a repository-error alert; quiet recovery rechecks
the current modal afterward and a regression preserves that alert without
stacking or dismissing it.
