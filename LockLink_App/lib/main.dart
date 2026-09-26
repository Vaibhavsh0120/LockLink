import 'package:flutter/material.dart';

import 'app/locklink_app.dart';
import 'services/device_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = DeviceSettings();
  var themeMode = ThemeMode.system;
  try {
    themeMode = await settings.loadThemeMode();
  } catch (_) {
    // Keep the app usable if preference storage is temporarily unavailable.
  }
  runApp(LockLinkApp(settings: settings, initialThemeMode: themeMode));
}
