import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var exportResult: FlutterResult?
  private var exportDirectory: URL?

  private func clearExport() {
    if let directory = exportDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    exportDirectory = nil
    exportResult = nil
  }

  private func finishExport(_ state: String) {
    let callback = exportResult
    clearExport()
    callback?(state)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishExport("cancelled")
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finishExport(urls.isEmpty ? "cancelled" : "saved")
  }

  private func saveJson(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard exportResult == nil,
          let args = call.arguments as? [String: Any],
          args["name"] as? String == "northstar-workouts.json",
          let json = args["json"] as? String,
          json.hasPrefix("{"), json.hasSuffix("}"),
          let bytes = json.data(using: .utf8)
    else {
      result(FlutterError(code: "export_unavailable", message: "Cannot start document export", details: nil))
      return
    }
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("northstar-export-\(UUID().uuidString)", isDirectory: true)
    let file = parent.appendingPathComponent("northstar-workouts.json")
    do {
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
      exportDirectory = parent
      try bytes.write(to: file, options: [.atomic])
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: file.path
      )
      guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })?.rootViewController else {
        throw NSError(domain: "NorthstarExport", code: 1)
      }
      var presenter = root
      while let displayed = presenter.presentedViewController { presenter = displayed }
      let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      picker.delegate = self
      exportResult = result
      presenter.present(picker, animated: true)
    } catch {
      clearExport()
      result(FlutterError(code: "export_failed", message: "Could not open document picker", details: nil))
    }
  }

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
    let channel = FlutterMethodChannel(
      name: "northstar/workout_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "saveJson" {
        self?.saveJson(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
