import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:path_provider/path_provider.dart';

class StorageInfo {
  StorageInfo._();

  static Future<({int free, int total})?> read() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final unix = await _unix();
      if (unix != null) return unix;
    }
    try {
      final disk = DiskSpacePlus();
      final free = await disk.getFreeDiskSpace;
      final total = await disk.getTotalDiskSpace;
      if (free == null || total == null || total <= 0) return null;
      return (free: free.round(), total: total.round());
    } catch (_) {
      return null;
    }
  }

  static Future<({int free, int total})?> _unix() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final result = await Process.run('df', ['-kP', dir.path]);
      if (result.exitCode != 0) return null;
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final fields = lines.last.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) return null;
      final total = int.tryParse(fields[1]);
      final free = int.tryParse(fields[3]);
      if (total == null || free == null || total <= 0) return null;
      return (free: free * 1024, total: total * 1024);
    } catch (_) {
      return null;
    }
  }
}
