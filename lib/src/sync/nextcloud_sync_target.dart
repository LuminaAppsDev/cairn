import 'package:flutter/foundation.dart';

/// One entry returned by [NextcloudSyncTarget.list] — a child file or
/// collection found under a WebDAV directory (DESIGN.md §6).
@immutable
class RemoteResource {
  /// Creates a remote resource descriptor.
  const new({
    required this.path,
    required this.isCollection,
    this.etag,
    this.size,
  });

  /// Server-relative WebDAV path of the resource (e.g.
  /// `/remote.php/dav/files/alice/Cairn/steps/2026/2026-06-14.jsonl`).
  final String path;

  /// Whether this resource is a collection (directory) rather than a file.
  final bool isCollection;

  /// The resource ETag, used to detect remote changes. `null` if the server
  /// omitted it.
  final String? etag;

  /// The content length in bytes, or `null` for collections / when omitted.
  final int? size;

  /// The final path segment (file or directory name), unescaped.
  String get name {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    return Uri.decodeComponent(
      slash < 0 ? trimmed : trimmed.substring(slash + 1),
    );
  }
}

/// What kind of failure a [NextcloudSyncException] describes.
///
/// The exception's [NextcloudSyncException.message] is an English diagnostic
/// for logs and bug reports; this enum is what the UI switches on to pick a
/// translated sentence, so no server-facing string ever reaches the screen.
enum SyncErrorKind {
  /// The user typed (or the server returned) a non-`https` address.
  hostNotHttps,

  /// The server could not be reached — DNS, socket or connection failure.
  network,

  /// The server accepted the connection but did not answer in time.
  timedOut,

  /// A Login Flow v2 step was refused by the server.
  loginFailed,

  /// The response was not the JSON/XML shape the protocol requires.
  malformedResponse,

  /// The server refused the request with an unexpected HTTP status.
  serverRejected,

  /// The requested file does not exist on the server.
  notFound,

  /// A download exceeded the size ceiling before it finished.
  tooLarge,

  /// The device's secure storage refused to hold the app password.
  credentialStorage,

  /// Anything else — reported to the user as a plain "sync failed".
  unknown,
}

/// Base class for failures talking to the Nextcloud WebDAV endpoint.
class NextcloudSyncException implements Exception {
  /// Creates a sync exception with a human-readable [message] and optional
  /// HTTP [statusCode]. Set [retryable] for transient failures (a timeout or
  /// network/DNS blip) that a polling caller may retry rather than abort on.
  /// [kind] is what the UI translates; [message] stays English, for logs.
  const new(
    this.message, {
    this.kind = SyncErrorKind.unknown,
    this.statusCode,
    this.retryable = false,
  });

  /// English description of what failed — for logs and bug reports, never for
  /// display. Use [kind] to pick a translated message instead.
  final String message;

  /// The machine-readable category, which the UI maps to a translated string.
  final SyncErrorKind kind;

  /// The offending HTTP status code, if the failure was an HTTP response.
  final int? statusCode;

  /// Whether the failure is transient and worth retrying (network/DNS/timeout).
  final bool retryable;

  @override
  String toString() => statusCode == null
      ? 'NextcloudSyncException: $message'
      : 'NextcloudSyncException($statusCode): $message';
}

/// Thrown when a WebDAV `GET`/`PROPFIND` targets a path the server reports as
/// `404 Not Found`.
class NextcloudNotFoundException extends NextcloudSyncException {
  /// Creates a not-found exception for [path].
  const new(String path)
    : super('Not found: $path', kind: SyncErrorKind.notFound, statusCode: 404);
}

/// Remote Nextcloud target for the `/Cairn/` file tree, spoken over WebDAV on
/// top of a permissive HTTP client (DESIGN.md §6).
///
/// Implemented directly rather than via the AGPL-licensed `nextcloud` Dart
/// client, to keep the app under the MIT licence.
abstract interface class NextcloudSyncTarget {
  /// Uploads [bytes] to [remotePath] (WebDAV `PUT`), creating parent
  /// collections as needed. Returns the stored resource's ETag if the server
  /// provided one. [remotePath] is relative to the account's WebDAV root
  /// (e.g. `Cairn/steps/2026/2026-06-14.jsonl`).
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  });

  /// Lists the immediate children of [remoteDir] (WebDAV `PROPFIND`,
  /// `Depth: 1`). [remoteDir] is relative to the account's WebDAV root. The
  /// directory's own entry is excluded.
  Future<List<RemoteResource>> list(String remoteDir);

  /// Downloads the file at [remotePath] (WebDAV `GET`). Throws
  /// [NextcloudNotFoundException] if the server returns `404`.
  ///
  /// When [maxBytes] is set, the body is streamed and the download is aborted
  /// (throwing [NextcloudSyncException]) as soon as it would exceed that many
  /// bytes — so a hostile or misconfigured server can't force an unbounded
  /// in-memory buffer before a caller's own size check runs.
  Future<Uint8List> getFile(String remotePath, {int? maxBytes});
}
