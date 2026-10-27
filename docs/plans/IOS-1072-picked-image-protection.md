# #1072 — preserve images picked during launch cleanup

Base: actual main `d8347841c8365667f9d812e6bdb9d886315726b9`.

The asynchronous launch sweep can hold an old alarm snapshot while the UI writes
a new photo. Serializing deletion with writes alone still deletes an unsaved
selection written before the snapshot. Protect successful new image writes for
the lifetime of this process, atomically with the write under the same lock as
the sweep's protection check and deletion. A later process reclaims abandoned
selections normally. Keep the checked alarm read outside this file lock: it must
not hold a filesystem lock across repository code or an injected checked-read
callback. The injected filesystem removal runs under the lock deliberately.

Change only `AlarmThemeImageStore.swift` and a focused new test file. A small
session object owns the lock and protected URLs; injectable directory/session
arguments isolate disk fixtures and simulate the next process. Existing APIs
retain their production defaults. Do not change cache location, JPEG encoding,
UUID naming, theme UI/copy or repository/scheduling policy.

Regression coverage: new unsaved image before read; image written after a stale
snapshot, including subsequently saving a real alarm; referenced image and old
orphan behavior; checked-read failure; failed image write; fresh-session cleanup;
a writer beginning during a controlled per-file deletion and the next sweep.
Retain all previous IDs/assertions/timeouts. Lint locally; compilation and XCTest
run only in ordinary PR CI. No local build/Simulator, workflow changes, old frozen
allowance renewal or merge-guard exception.
