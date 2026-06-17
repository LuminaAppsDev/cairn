import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register plugins for the background isolate so the sync task can use
    // health / path_provider / secure storage when launched headless.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Opportunistic background sync (DESIGN §4.4). The identifier must match
    // backgroundSyncTask in background_sync.dart and Info.plist's
    // BGTaskSchedulerPermittedIdentifiers; the OS decides actual timing.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "io.github.theflipside.cairn.sync",
      frequency: NSNumber(value: 6 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
