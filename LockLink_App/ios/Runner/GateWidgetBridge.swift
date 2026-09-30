import Flutter
import WidgetKit
import UIKit

final class GateWidgetBridge: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.locklink/widgets", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(GateWidgetBridge(), channel: channel)
        let homeChannel = FlutterMethodChannel(name: "com.locklink/home_apps", binaryMessenger: registrar.messenger())
        homeChannel.setMethodCallHandler { call, result in
            guard call.method == "open" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let ecosystem = args["ecosystem"] as? String else {
                result("unavailable")
                return
            }
            // Best-effort app entry points; no undocumented accessory-page URL
            // or pairing secret is passed. Keep manual setup steps in Flutter.
            let schemes: [String]
            switch ecosystem {
            case "apple": schemes = ["com.apple.Home://"]
            case "google": schemes = ["googlehome://"]
            case "alexa": schemes = ["alexa://", "amazonalexa://"]
            default:
                result("unavailable")
                return
            }
            DispatchQueue.main.async { openHome(schemes, result: result) }
        }
    }

    @MainActor private static func openHome(_ schemes: [String], result: @escaping FlutterResult) {
        guard let first = schemes.first, let url = URL(string: first) else {
            result("unavailable")
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if opened { result("opened") }
            else { openHome(Array(schemes.dropFirst()), result: result) }
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "configure":
                guard let args = call.arguments as? [String: Any],
                      let address = args["address"] as? String,
                      let key = args["signingKey"] as? String else {
                    throw GateWidgetError.message("Invalid widget settings.")
                }
                // Some IPA installation tools strip extensions. Saving credentials
                // alone must not tell the user that this build has a usable widget.
                guard let plugins = Bundle.main.builtInPlugInsURL,
                      FileManager.default.fileExists(atPath: plugins
                        .appendingPathComponent("LockLinkWidgets.appex").path) else {
                    throw GateWidgetError.extensionUnavailable
                }
                try GateWidgetStore.save(GateWidgetConfiguration(address: address, signingKey: key))
                WidgetCenter.shared.reloadTimelines(ofKind: GateWidgetStore.kind)
                result(nil)
            case "clear":
                GateWidgetStore.clear()
                WidgetCenter.shared.reloadTimelines(ofKind: GateWidgetStore.kind)
                result(nil)
            case "requestPin": result(false) // iOS widgets are added by the user in the gallery.
            default: result(FlutterMethodNotImplemented)
            }
        } catch let error as GateWidgetError {
            // Keep only the numeric OS status for diagnostics, never credentials.
            let details: Any?
            if case .keychain(let status) = error { details = ["osStatus": status] }
            else { details = nil }
            result(FlutterError(code: error.code, message: error.text, details: details))
        } catch {
            result(FlutterError(code: "widget_storage", message: "Could not save widget settings.", details: nil))
        }
    }
}
