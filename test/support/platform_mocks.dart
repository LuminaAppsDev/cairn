import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Installs fakes so widget tests can build the app shell, which resolves
/// directories via `path_provider` and reads `flutter_secure_storage` — neither
/// of which has a real platform in a unit test.
///
/// [docsDir] backs the app directories; the secure store behaves as empty.
void installPlatformMocks(Directory docsDir) {
  PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => switch (call.method) {
          'readAll' => <String, String>{},
          _ => null,
        },
      );
}

/// Removes the secure-storage mock installed by [installPlatformMocks].
void removePlatformMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
}
