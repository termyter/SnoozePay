# #1077 — Compose civil clock, occurrence finish and alarm-store recovery

Status: engineering integration preparation. The individual PRs stay draft and retain real UI/native-device acceptance. No new product, money, legacy-history or publication policy.

Inputs:
- Main: a3313658b632825f3af9dba1058320fa1095703e.
- #1071 civil clock: d02064d48f643ed2f613dfc1c8a637e09a38a3bc.
- #1076 confirmed finish/quiet recovery: a623bd011c96d13dffe2234b9b1c9bcc68756619.
- #1070 checked destructive recovery: c9d8f8253191a1b57013942d2f3ea4b542d071ef.
- Their common implementation base is d8347841c8365667f9d812e6bdb9d886315726b9.
- Immutable input patches and hashes: /private/tmp/snoozepay-1077-integration-inputs/manifest.json.

Accepted contracts remain unchanged: legacy alarms retain old Date behavior until explicit retime; unconfirmed finish retains error/retry and no wake/summary; quiet finish is read-only natively and exact-ticket scoped; destructive recovery commits only after checked complete native cancellation and verification.

Implementation:
1. Compose all three diffs on current main without moving its branch or the PM checkout. Preserve every source/test API and literal catalogue entry.
2. Resolve the four native-scheduler and three scheduler conflict blocks by keeping the union of defaults, injected readers/stopper, recovery inventory and occurrence projection seams, initializer labels and assignments.
3. Add clockTime to normal finish stale-snapshot comparison. Keep quiet full-Alarm rechecks, authoritative civil native mapping, legacy no-op edit semantics and persist-only one-shot disable.
4. Preserve both registration and finish/session callback lifetimes through genuine receipt/refund/late cleanup/caller completion, including every early failure.
   A tracked receipt can settle and release the store's running flag before its caller returns. Normal and quiet finish must also check that alarm's registration lifetime and global recovery state; an unrelated alarm's registration must remain independent. Late scoped cleanup remains permitted inside the callback.
5. If ordinary recovery preflight reports healthy but strict snapshot validity fails for wrong-type or duplicate identities, return a typed unavailable/failure outcome while preserving all raw bytes, backup, tickets and native registrations. Do not introduce a new destructive interpretation for ambiguous legacy data. Existing explicit decode-corruption recovery keeps its approved checked full-sweep contract.
6. Add combined regressions for clock-only stale capture, quiet intervening clock edit, persist-only one-shot/civil sort, strict-store unavailable refusal, full-sweep verification, registration/late callback overlap and real quiet UI refresh/modal ownership where existing fixtures support them.

Validation:
- No local compiler/build/XCTest/Simulator. Static SwiftLint/diff/catalogue checks only.
- Before new combined tests the expected source-method union is2582 (main2398 +finish131 +clock39 +recovery14), selected2564 with the exact18previously paused IDs. Prove this union; do not trim observed IDs to fit it.
- Preserve all individual IDs, previous assertions/timeouts and all493main catalogue entries; combined feature keys are a union, never overwrite silently.
- Independent code/type, silent-failure and test/inventory review after integration. Normal commit/push/draft CI only when source is reviewable.
- Freeze final head/currentbase/selected-ID/test-blob expectation after commit before push. Record actual runner merge SHA/parents/tree separately. Raw terminal audit must retain literal split recovery evidence and unknown outcomes honestly.

Exclusions: #1064 historical-day semantics; #1007 original-occurrence/pricing; new money/refund/identity rules; physical acceptance; entitlements/signing/dependencies/workflows/publication; old explicitly frozen #728/#918/#997 and related scope. No main merge or superseding the original draft PRs is part of this engineering preparation.

Authority: PM2026-10-27 unattended autopilot permits substantive fix/review/push/CI without per-round approval. This is a concrete composition task with confirmed text and semantic conflicts, not a duplicate scope for a frozen budget.

## Full source candidate after renewed unattended request

The three-core composition was verified at680a071 by CI40499005441:2578passed plus one existing skip; all199 additions, including15combined regressions, passed with complete literal ID/checkout evidence. Preserve that immutable evidence before advancing this existing draft.

Compose two additional prepared inputs in the same PR, retaining their original drafts and acceptance holds:
- #1075 Photos ownership:674e8014960f22d929ee008804b2860a556a4ccf, exact three-path delta fromd8347841c8365667f9d812e6bdb9d886315726b9.
- #1069 shared card-row geometry:16881cf1e4f5ee095f56489becf15d9e0a180ae6, exact two-path delta from its actual older base7a1da86da6818fbbd25f64b469d615ca9ba49de3.

Both modified preimages equal680a071 and all three added files are absent there. The five incoming paths are disjoint from the core delta and from each other. Apply only those exact deltas; do not import old branch project/model/history changes. All core production,15combined tests, old callback corrections, catalogue505 entries and existing assertions/timeouts stay unchanged.

New useful evidence is the first run containing all five source inputs: Photos callback/editor/civil-clock persistence, shared card geometry on editor/recovery surfaces, and UIKit scene/key-window fixture lifetime in one host. No source defect at those boundaries is asserted in advance. Keep the real five-second waits and mask positive/negative pixel oracles; diagnose actual failures without weakening them.

The two additions contribute17photo and4mask methods. The prospective full inventory is2618source /2600selected with the same18paused IDs and271test/support blobs. Freeze the final committed head/currentbase/blob inventory before normal push; bind actual runner checkout and audit every terminal after CI. No duplicate integration PR or rerun of unchanged individual heads is needed.

All five original drafts and this full candidate remain subject to real iPhone/AlarmKit/Photos/UI/design/travel/DST/recovery acceptance. E2E remains paused by existing PM configuration; do not change the workflow, selector, or opt-in variable. Source CI is not physical acceptance. The explicit exclusions above remain unchanged.

The independent, explicitly engineer-authorized #820 header partial is now prepared as child#1079 at0fa71b8f1e01350d56f27fa222405ec05336d5e5 against maina331. Include its exact two-path delta in this candidate before the full run, so the future QA build contains every currently prepared source fix. The single44100Hz renderer rate now reaches WAV header fields; PCM formula/envelope/gain/clamping and player error handling are unchanged. The parent clipping/loudness decision remains held. Its two header/default-player tests yield a final prospective inventory of2620source /2602selected with272test/support blobs,220five-draft additions plus2WAV additions relative to main, and the same15combined regressions /18paused IDs. Preserve the earlier full-five2618/2600 forecast separately; it was not pushed or run. No extra CI is justified for that intermediate unpublished head.
