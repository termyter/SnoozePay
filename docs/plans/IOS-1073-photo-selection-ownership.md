# #1073 — ownership of asynchronous photo selections

Base: actual main `d8347841c8365667f9d812e6bdb9d886315726b9`.

- Own only `AlarmThemePickerViewController.swift`, a new controller regression test file, and this plan. Another checkout owns #1072 and image-store reconciliation; do not modify its storage policy.
- Give each selected photo a request ID. On the main queue, require that ID and the active picker lifetime before saving, reporting a selection, showing a write error, or navigating. Both load entry and queued completion also require the picker to be the actual navigation controller's top screen: lifecycle flags alone do not prove ownership after a pop. Consume a valid completion once. Invalidate on another Photos request, cancellation, preset, Done, and actual navigation/dismissal; a temporary Photos cover alone is not an exit.
- Inject only external photo loading, JPEG saving, and Photos presentation closures. Keep production permission/configuration, UI, copy, and valid-selection behavior unchanged. Tests drive the controller's provider callback boundary because `PHPickerResult` has no public constructor.
- Add deterministic A/B ordering, queued result versus preset/back/Done/cancel or another pushed navigation owner, temporary cover, invalid load, write failure, stale failure, and duplicate-completion tests. Retain every existing test/assertion/timeout, including the original Back regression.

Validation is changed-file SwiftLint and static diff review only. Compiler, build, XCTest, Simulator, CI, push, PR and merge are explicitly outside this author's run. Actual Photos/UI acceptance remains pending; no frozen retry budget or paused UI test is renewed.
