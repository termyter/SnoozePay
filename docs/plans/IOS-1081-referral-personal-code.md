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
