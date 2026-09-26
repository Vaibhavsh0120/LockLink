import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Optional feedback that must never delay or fail a device command.
class AppHaptics {
  // Stay silent until the saved preference has loaded.
  bool enabled = false;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void tap() => unawaited(_play(HapticFeedback.lightImpact));
  void selection() => unawaited(_play(HapticFeedback.selectionClick));
  void success() => unawaited(_play(HapticFeedback.successNotification));
  void error() => unawaited(_play(HapticFeedback.errorNotification));

  Future<void> _play(Future<void> Function() feedback) async {
    if (!enabled ||
        !supported ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await feedback();
    } on PlatformException {
      // Haptics are best effort; the visible UI still reports the result.
    } on MissingPluginException {
      // Some devices and test hosts do not implement platform feedback.
    }
  }
}
