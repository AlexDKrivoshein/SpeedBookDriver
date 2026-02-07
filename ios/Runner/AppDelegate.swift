import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.speedbook.taxidriver/config"
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      let controller = window?.rootViewController as! FlutterViewController
      let channel = FlutterMethodChannel(name: "com.speedbook.taxidriver/config",
                                         binaryMessenger: controller.binaryMessenger)

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getGoogleMapsApiKey":
          if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String {
            result(apiKey)
          } else {
            result(FlutterError(code: "PLIST_ERROR", message: "GOOGLE_MAPS_API_KEY not found", details: nil))
          }
        case "getGoogleGeoApiKey":
          if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_GEO_API_KEY") as? String {
            result(apiKey)
          } else {
            result(FlutterError(code: "PLIST_ERROR", message: "GOOGLE_GEO_API_KEY not found", details: nil))
          }
        case "getApiUrl":
          if let apiUrl = Bundle.main.object(forInfoDictionaryKey: "API_URL") as? String {
            result(apiUrl)
          } else {
            result(FlutterError(code: "PLIST_ERROR", message: "API_URL not found", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
