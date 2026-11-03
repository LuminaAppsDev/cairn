package com.luminaapps.cairn

import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by the `health`
// package for Health Connect on Android 14+.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens Health Connect's settings: the way left to grant a permission
        // once Health Connect stops showing its request sheet after repeated
        // denials. (The per-app MANAGE_HEALTH_PERMISSIONS page would be closer,
        // but launching it needs a privileged permission apps don't hold.)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cairn/health_connect")
            .setMethodCallHandler { call, result ->
                if (call.method != "openPermissions") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                } catch (e: SecurityException) {
                    result.success(false)
                }
            }
    }
}
