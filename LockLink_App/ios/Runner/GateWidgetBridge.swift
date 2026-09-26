import Flutter
import WidgetKit

final class GateWidgetBridge: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.locklink/widgets", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(GateWidgetBridge(), channel: channel)
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
