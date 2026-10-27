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


## Approved language and AppIntent engineering preparation

Starting full head:7c141f8d29578e75899acbbe0de4b1022a5b2032. Extend this existing draft only; keep the still-red referral child separate. The parent explicitly authorized this unpublished source preparation after the read-only release-frontier reconciliation. No original draft or physical/system-surface acceptance is closed.

Inputs:
- #1003 / #603 runtime language:0a57719201a79026d70275ebf0af447c9bcf27c6, exact nine-path delta against actual baseb337e4aeb7e57b4fd2faf75556d14fe2dedac3d2. All preimages match the starting full head. PBX changes are the four AppLanguageUITests registrations only; the shared scheme changes only TestAction language=ru/region=RU. Currency authority, POSIX formats, signing and production language policy remain unchanged.
- #1001 / #727 static AppIntent titles:d3816c922881365b3dd428650df6152d7a430a7b against the same actual base. Reconcile only title/resource/test/comment hunks into current files. Preserve all current session/attempt routing, openAppWhenRun, currency-aware priced helper APIs, unpriced nil-currency path and subminor regressions. Preserve all505 catalogue key/value records; update only the two existing intent comments.

Authority: #603 comment6273662657 (https://github.com/termyter/SnoozePay/issues/603#issuecomment-6273662657) permits the existing RU/EN runtime contract, while keeping metadata/purpose and physical gates. #727 comment6272404271 (https://github.com/termyter/SnoozePay/issues/727#issuecomment-6272404271) permits the static main-bundle title source without a new copy decision, with physical Shortcuts/Siri/AlarmKit acceptance retained. Ordinary fix/review/CI caps were removed by PM2026-10-27; this task itself stops at local source-ready commit/handback without push or CI.

Three deliberate test-contract ID migrations, recorded with full old/new method text, hashes, rationale and authority in /private/tmp/1077-locale-intent-id-migrations.json:
1. AlarmKitCopyTests/testIntentTitleLiteralsStillAgreeWithTheirCatalogueEntries -> testIntentTitlesResolveMainBundleCatalogueInRussianAndEnglish: move from fallback-literal agreement to actual static-key/main-bundle resources and independent RU/EN words.
2. LocalizableCatalogTests/testLocalizedResolvesToTheRussianBundle -> testLocalizedFollowsTheAppBundlesNegotiatedLanguage: the explicit RU/RU test fixture must negotiate Russian, retain actual bundle/resource reachability and noun checks without a production language pin.
3. PluralTests/testDisplayLocaleIsRussianForNow -> testDisplayLocaleTracksTheUsersRegionalPreferences: obsolete ru_RU production pin is replaced by actual autoupdating regional equality, while text still follows the explicit RU test fixture.

Parent reconciliation decision: retain the entire original testPluralVariationExampleSelectsRussianForms body, including its explicit AppLocale.display argument under the RU/RU scheme. This is the sole test-only preservation deviation from published #1003; its new independent cross-region text tests remain exact. Every other pre-existing test body/assertion/timeout outside the three mapped migrations must remain byte-identical. Keep every core/photo/mask/WAV/15combined test and all18paused IDs.

Add narrow combined unit oracles using existing production APIs only: all505 compiled RU keys and the matching EN table except the four intentionally absent optional few forms must be reachable through the new language selector; literal pending-finish/recovery/Photos messages must select RU/EN; decoded civil and legacy clocks must retain their different time authority under opposite text/region scenarios; nil-currency snooze resources must remain unpriced. These are source/resource/formatter checks, not process-restart, native Photos or physical AlarmKit proof. Do not mutate global language/defaults, introduce production test seams or duplicate native scheduling acceptance.

Validation remains static SwiftLint, diff, JSON/catalogue, XML and plutil plus complete method/blob preservation and explicit ID-migration accounting. No compiler/build/XCTest/Simulator. Freeze/review the actual final SHA and method inventory before the orchestrator chooses any future combined CI. Native E2E remains paused; the new native language test is retained but cannot be claimed executed by Unit-only CI. Exclude #1000/frozen alerts and #1002/purpose resources; do not change workflows, opt-in variable, dependencies, signing, knownRegions/developmentRegion, versions or the PM checkout/WIP.


The implemented prospective method set is2629source /2611selected /274unit-test/support blobs: starting2620 minus the three explicitly mapped IDs plus their three replacements, four AppLanguage methods, one additional published priced-resource method and four new combined methods. The18paused IDs are unchanged. The two new synced unit files are AppLanguageTests.swift and AlarmLifecycleLocaleIntegrationTests.swift; the native AppLanguageUITests method is additional native scope, not counted as selected Unit execution. All269 other original test blobs and23 surviving original method bodies in the three changed files remain byte-identical. These are source forecasts and preservation checks, not executed test results.


## Post-referral typed statistics and shared-title source preparation

Actual main ea8dbec33cc769cdb756b538f8ad0c4a3d3da89b contains the qualified referral child and has the exact aad24ec11046be82f9c504d9413e7959c2d96733 tree. It was fetched and normally merged into own3f60, producing 820a2034d7c8e7b23036e1cf05bfa2450853f3bf; all7 actual-main referral paths are byte-identical and locale/core/Photos/card/WAV remain. This does not re-merge individual1082, change its closed state, or claim the broader701/676 backend/programme/device policy is complete.

Before further source edits, apply the independent SOURCE_PREPARATION_READY contract for existing drafts1024/1026. Inputs are1024/669 head56abccb2da4d9d75aed33b77407d92182e2430f0 versus actuala65c8306fe36ef7b8e6fe2f653c6321f3a1c4a5b, and1026/724 head7af140fa78d939e54ac3b81f71950e5cc433dfcd versus actual154ef45f25f91dc624fced982dc10b5507fa236e. Recheck all hunks at the actual merged head and apply only the published typed read-only availability and identical common-title changes. Preserve child StatisticsViewController DEBUG factory and every current currency/savings argument; never replace a divergent whole controller/catalogue blob.

Authority: https://github.com/termyter/SnoozePay/issues/669#issuecomment-6360556906 covers typed display/no repair/no threshold changes; https://github.com/termyter/SnoozePay/issues/724#issuecomment-6360558867 covers the identical shared title. Independent preflight /private/tmp/1077-statistics-title-source-preflight.md distinguishes these leaf source changes from old frozen728/972 diagnostic/acceptance and forbids old-head reruns or frozen test/route/lifecycle/selector/timeout modifications.

Preserve WakeEventStore record/dedupe/retention/write APIs and all captured-snapshot first-wake/day/calendar/median5/14/400 rules; keep missing, unreadable, refused and short5-morning states distinct. No history/date repair, currency identity, paid-session/finish/recovery or new money policy. Retain all existing core/photo/card/WAV/4locale/15combined/5referral methods and the18paused bodies/IDs. Existing native E2E, physical statistics/layout/language/AlarmKit/Photos/travel/DST/backend holds stay open.

Catalogue composition is explicit: current505 +3 published wake-status keys -2 identical old data-title keys +1 common title =507RU/503EN. Preserve all other records, values, metadata and the two reconciled intent comments. Update only the new completeness expectation505->507 and extend the existing selected-language literal-copy rows with new wake/common copy; retain its no-echo/nonempty/EN-Cyrillic/optional-few assertions.

Published fourth contract-ID migration: StatisticsWakeTimeTests/testWakeTimeCard_refusedMedianShowsNoCopyRatherThanZeroMornings -> testWakeTimeCard_refusedMedianExplainsFailureRatherThanZeroMornings. Record complete before/after bodies, hashes, path and669 authority alongside the three locale migrations. Preserve no-zero-mornings/no-clamped-clock guards, document same-ID title-key/count/literal-row and two assertion-message wording changes separately, and reject any silent ID removal.

Before any extra combined method the source forecast is2643source /2625selected /276test-support blobs after the5 qualified referral methods. Enumerate actual source IDs/blobs rather than trusting arithmetic. Add only a narrow meaningful typed-history/confirmed-finish or read-projection integration if an actual existing API seam supports it; no new production seam, filler, global defaults or physical acceptance claim.

This batch ends at clean normal local source commit and author handback. Static SwiftLint(no-cache), JSON/catalogue, XML/plutil and diff checks only; no local Swift compiler/build/XCTest/Simulator. Do not push, dispatch CI, create/merge a PR, change main/PM/foreground checkout, relax freezes or alter signing/workflows/dependencies/purpose. Root owns final independent reviews, actual-main-base+4map forecast and one substantive future CI in existing draft1078.


Actual enumeration after this source composition is2644source /2626selected /277unit-test-support blobs, with the same18paused IDs. The published frontier contributes9 net methods; the one additional genuine combined method is AlarmLifecycleStatisticsIntegrationTests/testQuietFinishPublishesOnlyConfirmedActualWakeIntoTypedFiveMorningStatistics. It uses existing isolated fixtures, real quiet-finish/read-projection APIs and injected native inventory/clock/calendar, not a constructed native Alarm or physical proof. Four distinct prior calendar mornings use08:05; original civil clock remains07:04. A current-alerting proof leaves the pending ticket and four wake records unchanged; scheduled proof publishes one actual injected08:05 confirmation (next08:05 avoids backdating before the fixture ticket), producing5samples/485-minute median through typed Statistics. Raw-domain preservation is asserted separately around READS after each actual failure/success boundary, not across the legitimate finish write; ledger/balance/serialized alarm/native inventory stay unchanged. This does not change or promise recovery for the pre-existing future recordWake fallback write policy.

Six old test/support files change; all269 other old blobs remain byte-identical to post-referral820a. In those six files96 surviving original method bodies remain byte-identical; five same-ID small changes are explicitly mapped (catalogue507 count, four added locale-copy rows, actual controller shared-title expectation, two diagnostic-message-only changes). The fourth renamed wake-card method retains every old guard and adds one independent reason assertion. No timeout or frozen body changes. Author migration/evidence records are /private/tmp/1077-statistics-title-id-migrations.json and /private/tmp/1077-statistics-title-author-evidence.json; these are pending independent final-head approval, not reviewed/runtime forecasts.
