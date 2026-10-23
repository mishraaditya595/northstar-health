import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ObjectBox's default Flutter directory is Documents/objectbox.
    // Create/protect and exclude it BEFORE Flutter opens the Store.
    // Never delete or relocate existing user data on error.
    do {
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      var database = documents.appendingPathComponent("objectbox", isDirectory: true)
      try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try database.setResourceValues(values)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: database.path
      )
    } catch {
      // Fail closed: Flutter must not open a DB without the decided policy.
      // Avoid reporting paths, user records, or exception contents.
      return false
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
