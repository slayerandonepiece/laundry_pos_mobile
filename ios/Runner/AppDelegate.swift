import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // TestFlight installs carry a sandbox receipt; App Store and Xcode builds do not.
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "Distribution")?.messenger() {
      FlutterMethodChannel(name: "klenpos/distribution", binaryMessenger: messenger)
        .setMethodCallHandler { call, result in
          if call.method == "isTestFlight" {
            result(Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt")
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
