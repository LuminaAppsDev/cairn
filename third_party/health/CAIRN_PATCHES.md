# Vendored `health` plugin

Cairn ships a patched copy of the [`health`](https://pub.dev/packages/health)
Flutter plugin (MIT, see `LICENSE`), used through a path dependency in the root
`pubspec.yaml`.

- **Upstream version:** 13.3.1, the pub.dev archive with sha256
  `2d9e119f3a1d281139f93149b41032b9f80b759960875bc784c5a25dd3c17524`. That is
  the hash the lockfile pinned before vendoring.
- **Copied:** `lib/`, `android/`, `ios/`, `LICENSE`, `pubspec.yaml`,
  `README.md`, `CHANGELOG.md` and `analysis_options.yaml`.
- **Left out:** `example/`, `test/` and `tools/`. Nothing here builds them.

## Patches

### 1. Report failed reads instead of returning an empty list

`android/src/main/kotlin/cachet/plugins/health/HealthDataReader.kt`, in the
outer `catch` of `getData`:

```diff
-                result.success(emptyList<Map<String, Any?>>()) // Return empty list instead of null
+                // Cairn patch: report the failure instead of an empty list, which
+                // callers cannot tell apart from "no data" (see CAIRN_PATCHES.md).
+                // (…)
+                val platformError =
+                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
+                        generateSequence<Throwable>(e) { it.cause }
+                            .take(8) // a cause cycle must not hang the reply
+                            .filterIsInstance<HealthConnectException>()
+                            .firstOrNull()
+                            ?.errorCode
+                    } else {
+                        null
+                    }
+                result.error(
+                    "HEALTH_READ_FAILED",
+                    "${e.javaClass.simpleName}: ${e.message}",
+                    mapOf("exception" to e.javaClass.simpleName, "platformError" to platformError),
+                )
```

Plus the imports `android.health.connect.HealthConnectException` and
`android.os.Build`.

Upstream swallows every exception a Health Connect read throws: a rate limit,
a revoked permission, or a background read without the background permission.
It returns an empty list instead. Cairn cannot tell that empty list from "no
data in this window", so its ingest moved the sync anchor past data it never
read, and anything older than the reconcile window was never read again.

The error message is the exception's class name and message, and it ends up in
Cairn's logs (logcat). Health Connect's own exceptions carry framework text. A
fault in the plugin's record converter could quote a record value in its
message, but upstream's `Log.e` stack trace just above already writes that
same text to logcat, so Cairn's log adds no new exposure. Re-check on every
upgrade.

The details let Cairn classify the failure (`HealthPackageRepository`): a rate
limit ends the run, and a plugin fault is reported as a bug. They hold the
exception's class name and, on Android 14+, the platform's
`HealthConnectException.errorCode`. On the platform path, the client's
`ExceptionConverterKt` keeps only four codes apart as distinct Kotlin classes:
3 → `IllegalArgumentException`, 4 → `IOException`, 5 → `SecurityException`
and 6 → `RemoteException`. Every other code becomes an
`IllegalStateException`, among them 7, the rate limit. So the class alone
can't tell a rate limit from, say, a sync in progress. The code is taken from
the first `HealthConnectException` in the cause chain, which today is the
direct cause. The version check keeps the platform class unloaded below API 34,
since the plugin's own minSdk is 26. There the code is always null, but Cairn's
minSdk is 34.

With this patch the failure arrives in Dart as a `PlatformException`.
`HealthPackageRepository` turns it into a `HealthReadException`, and the anchor
stays where it was. The workout handler has no `catch` of its own, so this one
hunk covers every exception on every type Cairn reads. Upstream 13.3.2 doesn't
change this path, so the patch is worth offering upstream.

### 2. Report a missing read permission instead of returning an empty list

Same file and method, just before the `authorizedTypeMap[dataType]?.let`:

```diff
+                // Cairn patch: a supported type whose read permission is missing at read
+                // time (revoked mid-run) is a failure, not "no data" (see CAIRN_PATCHES.md).
+                if (dataType in HealthConstants.mapToType && dataType !in authorizedTypeMap) {
+                    Handler(context.mainLooper).run {
+                        result.error("HEALTH_READ_NOT_AUTHORIZED", dataType, null)
+                    }
+                    return@launch
+                }
```

Upstream filters the requested type against the permissions granted *at read
time*. If the permission is missing, nothing is read and an empty list comes
back: the same ambiguity patch 1 removes, reached without an exception. Cairn
checks permissions before each refresh, so this only happens when a permission
is revoked mid-run, for example during a long catch-up. A type that isn't in
`mapToType` at all (unsupported) still returns an empty list, as upstream does.

### 3. Don't crash on a failed background-read status check

`android/src/main/kotlin/cachet/plugins/health/HealthDataOperations.kt`,
`isHealthDataInBackgroundAvailable` and `isHealthDataInBackgroundAuthorized`:
upstream runs the Health Connect call inside `scope.launch` with no `catch`.
Cairn calls both on every background run and every foreground refresh, so a
binder failure (for example while Health Connect updates) would go uncaught
on the main thread and crash the process. Each body is now wrapped in
`try`/`catch`, which replies `result.error("HEALTH_STATUS_FAILED", …)`. The
plugin's Dart side maps that to `false`, so a failed check reads as "not
granted" and fails closed: the background run skips reading instead of
risking a read without the permission.

### 4. Formatting (no behaviour change)

The repo's format gate runs `dart format .` over everything, including this
directory. Even with upstream's own `formatter: page_width: 120`, it reformats
four files: `lib/health.g.dart`, `lib/src/health_changes.dart`,
`lib/src/health_plugin.dart` and `lib/src/health_value_types.dart`. The
changes are line wrapping and trailing-comma placement only. With whitespace
and trailing commas stripped, the files match upstream token for token. The
root `analysis_options.yaml` excludes `third_party/**`, so upstream's lint
choices don't meet Cairn's stricter set.

This directory's `analysis_options.yaml` also drops upstream's `include:
package:flutter_lints/flutter.yaml`. Nothing resolves that package here, and
an unresolvable include makes `dart format` ignore the whole file, including
`page_width: 120`. On a fresh checkout it would then wrap nine files at 80
columns and fail CI's format gate.

## Known upstream quirks, deliberately left alone

These were found in review. Neither is made worse by the patches, and fixing
them would widen the diff against upstream.

- **`Handler(context.mainLooper).run { … }` isn't `post`.** It is Kotlin's
  `run` scope function, so every reply (upstream's `success` and the patched
  `error`) runs on the coroutine's thread rather than the main thread. That
  works in practice.
- **A theoretical double reply.** If `result.success` itself threw (a codec
  error), the outer `catch` would reply a second time. Upstream had the same
  shape with `success`. The effect is a logged "reply already submitted", not a
  crash.

## Upgrading

1. Replace everything here except this file with the new release's copied
   paths (list above).
2. Re-apply patches 1–3, or drop those upstream has made unnecessary.
3. Run `dart format .`, then the full gate: `dart analyze --fatal-infos
   --fatal-warnings`, `flutter test`, and `flutter build apk` to compile the
   Kotlin.
4. Update the version and sha256 above.
5. Re-check the plugin README for Android manifest drift
   (`docs/DEVELOPMENT.md` §3.3).
