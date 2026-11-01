import 'package:flutter_test/flutter_test.dart';

import 'package:drople/models/backup_item.dart';
import 'package:drople/models/file_transfer.dart';
import 'package:drople/models/note.dart';
import 'package:drople/models/peer.dart';

void main() {
  group('Models roundtrip', () {
    test('NoteSummary parse json', () {
      final note = NoteSummary.fromJson({
        'id': 'n1',
        'title': 'Catatan Rapat',
        'updated_at': 1700000000000,
        'is_favorite': 1,
        'sync_status': 'synced',
      });
      expect(note.id, 'n1');
      expect(note.title, 'Catatan Rapat');
      expect(note.isSynced, isTrue);
      expect(note.isPending, isFalse);
    });

    test('PeerEntry parse json with fingerprint', () {
      final peer = PeerEntry.fromJson({
        'id': '12D3KooWtest',
        'name': 'Device-A',
        'last_seen': 1700000000000,
        'connected': true,
        'latency_ms': 42,
        'addresses': ['/ip4/127.0.0.1/tcp/4001'],
        'fingerprint': 'A1B2 C3D4',
      });
      expect(peer.id, '12D3KooWtest');
      expect(peer.fingerprint, 'A1B2 C3D4');
      expect(peer.connected, isTrue);
      expect(peer.statusText, 'Terhubung');
    });

    test('FileTransferItem percent calculation', () {
      final transfer = FileTransferItem.fromJson({
        'id': 't1',
        'peer_id': 'p1',
        'file_name': 'test.bin',
        'file_size': 1000,
        'file_hash': 'sha256',
        'status': 'active',
        'direction': 'send',
        'created_at': 1700000000000,
        'progress': 500,
      });
      expect(transfer.percent, 0.5);
      expect(transfer.isActive, isTrue);
      expect(transfer.isSend, isTrue);
    });

    test('BackupItem size formatting and date', () {
      final b1 = BackupItem.fromJson({
        'id': 'drive-123',
        'created_at': 1700000000000,
        'size': 2048,
        'status': 'completed',
      });
      expect(b1.sizeFormatted, '2.0 KB');
      expect(b1.date.millisecondsSinceEpoch, 1700000000000);
    });
  });
}
