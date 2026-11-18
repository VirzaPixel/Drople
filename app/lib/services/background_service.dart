import 'dart:io';

import 'package:flutter/services.dart';

/// Menjaga proses aplikasi tetap hidup di Android lewat foreground service,
/// sehingga transfer file P2P tetap berjalan saat aplikasi di latar belakang.
class DropleBackgroundService {
  DropleBackgroundService._();

  static const MethodChannel _channel = MethodChannel(
    'com.drople.drople/background',
  );

  static bool get isSupported => Platform.isAndroid;

  static Future<void> start() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      // Foreground service tidak tersedia (mis. izin ditolak). Jaringan tetap
      // berjalan selama proses aplikasi masih hidup.
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
