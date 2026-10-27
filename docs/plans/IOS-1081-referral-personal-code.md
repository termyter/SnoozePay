# #1081 — owned personal referral code (#701 partial)

Base: `9e31c2c3fbe1edacec3a5c752949d42dbcfec1ec` on `codex/IOS-1081-referral-personal-code`.

Correct only the source of the standalone referral screen's own code. The existing
`ReferralService.getMyCode()` owns the persisted local identity and writes on first
read. The feature stays disabled; entry-point visibility, apply/friend placeholders,
bonus policy, backend, prototypes, catalogue, router and protected configuration stay unchanged.

Implementation:

- Inject a lazy code provider defaulting to `ReferralService.shared.getMyCode()`;
  resolve once per controller and use that exact snapshot for label, copy and share.
- Inject an owned pasteboard and activity-controller factory for real-button tests;
  preserve production haptics, localized text, amount, popover anchor and presentation.
- Add one DEBUG instance child factory on Statistics, preserving its existing flag
  and navigation. Inject fixed code providers in every direct/indirect test mount:
  ReferralOnboardingCopy, NavigationBarSymmetry (both factory loops and actual main
  tab graph), and ReferralEntryPointVisibility's hosted button.
- Add focused tests for lazy/per-controller ownership, actual label/copy/share
  consistency, isolated-service persistence, and no applied-code/financial mutation.
  Tests use owned suites/named pasteboards; never seed/reset standard defaults or
  inspect the real clipboard. Preserve all existing test IDs/assertions/timeouts.
- A read-only app persistent-domain snapshot surrounds injected construction,
  rendering and real copy/share actions; report changed key names only. No shared
  keys/domain are seeded, restored, swapped or removed.

Validation: changed-file SwiftLint and static diff/inventory checks only. No local
compiler/build/XCTest/Simulator. Commit normally without hook bypass; root performs
independent review and any push/PR/CI. This is source preparation, not full #701
completion, backend acceptance or permission to enable the programme. Old explicit
#728/#918/#997 freezes and all PM/no-touch/device holds remain.

Corrective scope after the initial committed head `fdfee0f` ran 2386 cases with
three failures at the post-presentation sourceView identity assertion:

- Keep the production anchor assignments and original animated presentation;
  inject a main-actor presenter/activity forwarder solely to observe their handoff.
- The real activity factory in tests explicitly uses popover style and seeds an
  owned wrong anchor/rect. Require the app to overwrite both before real present.
- Record actual weak presenter/activity/sourceView, value rect and call count;
  require strict presence/identity/rect/count outside nonthrowing callbacks.
  Forward real present once and log passive post-SDK fixture diagnostics.
- Retain all IDs, identity/cache/payload/domain/money/mount oracles and timeouts.
  No production style, feature/apply/backend/policy change or bare CI rerun.

Second corrective scope after run 40516891073 still found a missing captured
source view at `e4fcb27`: keep every production byte unchanged and repair only
the focused four-test harness. Require an actual active scene, key owned window,
real navigation viewDidAppear and strict hierarchy readiness with new bounded
five-second observations. Wait for real Share presentation/dismissal completion
before another owned host; unwind hosts in reverse and restore prior key windows.
Freeze a strong local actual getter's presence/identity/type/window/scene before
real present, plus public sourceItem and seed/handoff popover identities; retain
only weak object back-references. Log no nil/nil comparison as a positive match.
Keep the wrong-anchor control, strict sourceView/rect/activity/presenter/count,
data/domain/money assertions, all IDs and old timeouts. The scene deficiency is
concrete; its causal relationship to the failure still needs new runtime evidence.

Valid-scene run 40523614366 still observed an actual nil source getter, so scene,
weak-capture and post-read-only explanations do not explain that run. Independent
QA found that the wrong source control was still detached when the factory first
configured it. Keep production entirely unchanged: attach the SAME owned 40×40
wrongAnchor inside the appeared root before Share, require its exact window/scene,
nonhidden finite geometry and contained unchanged wrongRect, and record valid
factory input. Keep it through actual completion and defer-remove only that view.
All strict root/rect/controller/count and data/store assertions, IDs and waits stay.
This repairs a seed-context difference; its causality/success remain unproven.

Attached-seed b0 run 40528696327 still failed its seed and final source identities.
Calibrate separately before changing production: add one pure-UIKit test with a
generic real host, five fixed view/controller cells and two fresh fixed write
orders each. Freeze value-only phases after each write and a fresh getter before
assertions. A cell requires one entire exact nonnil view/rect configuration on
both configured receiver and fresh getter; log every order/stage and working list.
Keep the original four method bodies, all old oracles and waits untouched. The
factory only gains immediate value-only seed afterView/afterRect observations;
its setter order and old weak identity assertion stay. No production lifetime,
sourceItem, traits, timing, device or broader matrix change is part of calibration.
Store the identical value-only phase/order/cell trace as a keepAlways XCTAttachment
before assertions as well as literal stdout, so XPC interleaving cannot erase it.
Keep each captured calibration PC alive through its fresh getter, and qualify the
actual intended detached/attached/root input against the frozen owned host before
each order. Record inputReady without repairing/skipping invalid input; a working
order additionally requires inputReady. Attached frames must stay inside the
computed available safe-root intersection. These are test-control validity only.
