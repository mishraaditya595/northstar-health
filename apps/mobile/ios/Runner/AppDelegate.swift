import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private var exportResult: FlutterResult?
  private var exportDirectory: URL?

  private func purgeAbandonedExports() {
    let temporary = FileManager.default.temporaryDirectory
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: temporary, includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return }
    for entry in entries where entry.lastPathComponent.hasPrefix("beyondrep-export-") {
      // Only directories owned by this export workflow, never ObjectBox or
      // other temporary data. Cleanup is best effort if files are locked.
      try? FileManager.default.removeItem(at: entry)
    }
  }

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

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    // A sheet can be dismissed without documentPickerWasCancelled firing.
    if exportResult != nil { finishExport("cancelled") }
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

  private func prepareFile(result: @escaping FlutterResult) {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("beyondrep-export-\(UUID().uuidString)", isDirectory: true)
    let file = parent.appendingPathComponent("beyondrep-workouts.json")
    // Complete protection is set at creation; Dart truncates and streams into
    // this same file, which keeps its protection class.
    do {
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
      guard FileManager.default.createFile(
        atPath: file.path, contents: nil,
        attributes: [.protectionKey: FileProtectionType.complete]
      ) else { throw NSError(domain: "BeyondRepExport", code: 2) }
      result(file.path)
    } catch {
      try? FileManager.default.removeItem(at: parent)
      result(FlutterError(code: "export_unavailable", message: "Cannot prepare export", details: nil))
    }
  }

  private func saveFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    guard exportResult == nil,
          let args = call.arguments as? [String: Any],
          args["name"] as? String == "beyondrep-workouts.json",
          let path = args["path"] as? String
    else {
      result(FlutterError(code: "export_unavailable", message: "Cannot start document export", details: nil))
      return
    }
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let parent = file.deletingLastPathComponent()
    guard file.lastPathComponent == "beyondrep-workouts.json",
          parent.lastPathComponent.hasPrefix("beyondrep-export-"),
          parent.deletingLastPathComponent().pathComponents == temporary.pathComponents,
          let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
          size >= 2
    else {
      result(FlutterError(code: "export_unavailable", message: "Cannot start document export", details: nil))
      return
    }
    do {
      exportDirectory = parent
      guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })?.rootViewController else {
        throw NSError(domain: "BeyondRepExport", code: 1)
      }
      var presenter = root
      while let displayed = presenter.presentedViewController { presenter = displayed }
      let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      picker.delegate = self
      picker.presentationController?.delegate = self
      exportResult = result
      presenter.present(picker, animated: true) { [weak self, weak picker] in
        // UIKit may fail to present when a scene becomes inactive or another
        // controller takes ownership. Do not strand the Flutter completion.
        if picker?.presentingViewController == nil, self?.exportResult != nil {
          self?.finishExport("cancelled")
        }
      }
      // Presentation's completion can be skipped if the hosting scene becomes
      // inactive. A bounded watchdog also releases the waiting Flutter UI.
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak picker] in
        if self?.exportResult != nil, picker?.presentingViewController == nil {
          self?.finishExport("cancelled")
        }
      }
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
    purgeAbandonedExports()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "northstar/workout_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "prepareFile" {
        self?.prepareFile(result: result)
      } else if call.method == "saveFile" {
        self?.saveFile(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
