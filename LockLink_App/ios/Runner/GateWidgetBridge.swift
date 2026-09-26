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
        } catch {
            result(FlutterError(code: "widget_setup", message: "Widget setup failed. Check App Group signing and try again.", details: nil))
        }
    }
}
