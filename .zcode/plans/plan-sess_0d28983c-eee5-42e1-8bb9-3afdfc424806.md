Fix the framework-locked `notifyListeners` crash by removing the draft-flush from `dispose()` and instead flushing pending edits on pop via `PopScope`, when the widget tree is not locked.

File: `lib/views/ai/ai_api_config_page.dart`

1. Wrap the existing `Scaffold` in a `PopScope`:
   - `canPop: false`
   - `onPopInvokedWithResult: (didPop, _) async { if (didPop) return; _commitDebounce?.cancel(); await _commitDraft(); if (mounted) Navigator.of(context).pop(); }`
   The unconditional `Navigator.pop()` bypasses `canPop` so the callback doesn't re-enter itself.

2. Simplify `dispose()`:
   - Remove `_disposed = true;` and `unawaited(_commitDraft());`.
   - Keep `_commitDebounce?.cancel();` and the four controller `dispose()` calls.
   - This guarantees no `notifyListeners` fires during the unmount lock.

3. Remove the now-dead `_disposed` field and `_canSetState` getter; replace their uses in `_commitDraft` (lines 147, 159, 162) with plain `mounted` checks. `_commitDraft` only ever runs from the debounce timer (cancelled in dispose), the pop callback, `_saveNow`, and `_onPresetChanged` — all while mounted.

4. Leave `_scheduleCommit`, `_saveNow`, `_onPresetChanged`, `_clearCredentials`, `_restoreDefaults` and all build/UI code untouched.

Verification: `flutter analyze` clean; manually test back-within-500ms, back-after-debounce, and explicit 保存; confirm the `markNeedsBuild during lock` log is gone.