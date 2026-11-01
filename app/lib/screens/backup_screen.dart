import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/backup_item.dart';
import '../services/drople_backup.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backup = DropleBackup();
  String? _recoveryKey;
  bool _connected = false;
  List<BackupItem> _backups = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    try {
      final key = _backup.getOrCreateRecoveryKey();
      final connected = _backup.isConnected();
      List<BackupItem> list = const [];
      if (connected) {
        try {
          list = _backup.listBackups();
        } catch (_) {}
      }
      setState(() {
        _recoveryKey = key;
        _connected = connected;
        _backups = list;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _backupNow() async {
    if (!_connected) {
      _showSnack('Hubungkan Google Drive terlebih dahulu');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = _backup.backupNow();
      _showSnack('Backup berhasil dibuat (id: $id)');
      _refresh();
    } catch (e) {
      _showSnack('Gagal backup: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text(
          'Data dari snapshot ${item.date.toLocal().toString().split('.').first} '
          'akan digabungkan (CRDT merge) dengan catatan lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      _backup.restore(item.id);
      _showSnack('Restore berhasil disinkronkan ke catatan lokal');
    } catch (e) {
      _showSnack('Gagal restore: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus file backup dari Drive?'),
        content: Text(item.id),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      _backup.delete(item.id);
      _showSnack('Backup dihapus dari Drive');
      _refresh();
    } catch (e) {
      _showSnack('Gagal menghapus: $e', isError: true);
    }
  }

  Future<void> _changeRecoveryKey() async {
    final ctrl = TextEditingController(text: _recoveryKey ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atur Recovery Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan 12 kata mnemonic valid untuk mendekripsi snapshot backup lama.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'word1 word2 word3 ... word12',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final text = ctrl.text.trim();
      try {
        _backup.setRecoveryKey(text);
        _showSnack('Recovery key diperbarui');
        _refresh();
      } catch (e) {
        _showSnack('Recovery key tidak valid: $e', isError: true);
      }
    }
  }

  Future<void> _enterTokenManually() async {
    final accessCtrl = TextEditingController();
    final refreshCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hubungkan Google Drive (OAuth Token)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: accessCtrl,
              decoration: const InputDecoration(labelText: 'Access Token'),
            ),
            TextField(
              controller: refreshCtrl,
              decoration: const InputDecoration(labelText: 'Refresh Token'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final a = accessCtrl.text.trim();
      final r = refreshCtrl.text.trim();
      if (a.isEmpty) return;
      try {
        final expiresAt =
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        _backup.setGoogleDriveToken(
          accessToken: a,
          refreshToken: r,
          expiresAt: expiresAt,
        );
        _showSnack('Token Google Drive tersimpan');
        _refresh();
      } catch (e) {
        _showSnack('Gagal: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Cloud'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildRecoveryCard(),
                const SizedBox(height: 12),
                _buildDriveCard(),
                const SizedBox(height: 16),
                const Text(
                  'Daftar Snapshot di Cloud',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (_backups.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _connected
                            ? 'Belum ada snapshot backup di Google Drive.'
                            : 'Hubungkan Google Drive untuk melihat snapshot cloud.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._backups.map(
                    (b) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.cloud_done, color: Colors.green),
                        title: Text(
                          b.date.toLocal().toString().split('.').first,
                        ),
                        subtitle: Text('${b.sizeFormatted} • ${b.id}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.restore),
                              onPressed: _busy ? null : () => _restore(b),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy ? null : () => _delete(b),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildRecoveryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'E2EE Recovery Key (12 Kata)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Ubah / Pulihkan dari Kata',
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: _changeRecoveryKey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _recoveryKey ?? '-',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    if (_recoveryKey != null) {
                      Clipboard.setData(ClipboardData(text: _recoveryKey!));
                      _showSnack('Recovery key disalin ke clipboard');
                    }
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Salin'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Simpan kata-kata ini! Backup di cloud dienkripsi secara lokal.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  color: _connected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _connected
                      ? 'Google Drive Terhubung'
                      : 'Google Drive Belum Terhubung',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Snapshot dienkripsi di perangkat (XChaCha20-Poly1305) sebelum diunggah ke appDataFolder Google Drive.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_connected) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: const Text('Backup Sekarang'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      _backup.disconnect();
                      _showSnack('Google Drive diputuskan');
                      _refresh();
                    },
                    child: const Text('Putus'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _enterTokenManually,
                    icon: const Icon(Icons.login),
                    label: const Text('Atur Token OAuth'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
