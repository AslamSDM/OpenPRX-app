library;

/// Low-level access to device memory info.
///
/// Uses platform channels for Android and a heuristic for iOS. The numbers are
/// approximate and are only used to sort/rank models in the catalog.
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class DeviceMemory {
  static const MethodChannel _channel = MethodChannel('openprx/memory');

  /// Total physical RAM in megabytes. Returns 0 if unavailable.
  static Future<int> totalMb() async {
    if (Platform.isAndroid) {
      try {
        final mb = await _channel.invokeMethod<int>('getTotalRamMb');
        return mb ?? 0;
      } catch (_) {
        return 0;
      }
    }
    if (Platform.isIOS) {
      // Conservative default for iOS until a platform-specific helper is added.
      // Most modern iPhones ship with >=4 GB; iPads may have more.
      return 4096;
    }
    return 4096;
  }
}
