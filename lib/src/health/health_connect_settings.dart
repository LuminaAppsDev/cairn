import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('cairn/health_connect');

/// Opens Health Connect's settings (Android; `MainActivity`), where the user
/// can reach Cairn's permissions. Returns whether it could — `false`
/// elsewhere, or where Health Connect offers no such screen.
///
/// The way left to grant a permission once Health Connect stops showing its
/// request sheet, which it does after repeated denials.
Future<bool> openHealthConnectPermissions() async {
  try {
    return await _channel.invokeMethod<bool>('openPermissions') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false; // iOS: no such channel, and no such permission
  }
}
