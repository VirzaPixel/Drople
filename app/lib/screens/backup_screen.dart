import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/backup_item.dart';
import '../services/drople_backup.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

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
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                      children: [
                        Row(
                          children: [
                            const BrandMark(size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Backup', style: theme.textTheme.headlineMedium),
                                  Text(
                                    'Cadangan terenkripsi di Google Drive',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Muat ulang',
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildRecoveryCard(theme),
                        const SizedBox(height: 14),
                        _buildDriveCard(theme),
                        const SizedBox(height: 24),
                        SectionHeader(
                          title: 'Snapshot Cloud',
                          subtitle: _backups.isEmpty
                              ? 'Belum ada cadangan tersimpan'
                              : '${_backups.length} snapshot terenkripsi',
                        ),
                        if (_backups.isEmpty)
                          EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: _connected
                                ? 'Belum ada snapshot'
                                : 'Google Drive belum terhubung',
                            message: _connected
                                ? 'Buat backup pertama. Snapshot dienkripsi sebelum diunggah.'
                                : 'Hubungkan Google Drive lewat token OAuth untuk mulai mencadangkan.',
                          )
                        else
                          ...List.generate(
                            _backups.length,
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: StaggeredEntry(
                                index: i,
                                child: _snapshotCard(theme, _backups[i]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryCard(ThemeData theme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.key_rounded, size: 20, color: AppColors.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recovery Key', style: theme.textTheme.titleMedium),
                    Text('12 kata untuk membuka backup', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ubah recovery key',
                onPressed: _changeRecoveryKey,
                icon: const Icon(Icons.edit_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SelectableText(
              _recoveryKey ?? '-',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.7,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  if (_recoveryKey != null) {
                    Clipboard.setData(ClipboardData(text: _recoveryKey!));
                    _showSnack('Recovery key disalin ke clipboard');
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Simpan kata-kata ini. Tanpa kunci, backup tidak bisa dibuka.',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriveCard(ThemeData theme) {
    final statusColor = _connected ? AppColors.leaf : theme.colorScheme.outline;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.cloud_rounded, size: 20, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Google Drive', style: theme.textTheme.titleMedium),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _connected ? 'Terhubung' : 'Belum terhubung',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_connected)
                TextButton(
                  onPressed: () {
                    _backup.disconnect();
                    _showSnack('Google Drive diputuskan');
                    _refresh();
                  },
                  child: const Text('Putuskan'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Snapshot dienkripsi di perangkat dengan XChaCha20-Poly1305 sebelum diunggah ke appDataFolder.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _connected
                ? FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_busy ? 'Membuat backup…' : 'Backup Sekarang'),
                  )
                : FilledButton.icon(
                    onPressed: _enterTokenManually,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Hubungkan Google Drive'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotCard(ThemeData theme, BackupItem item) {
    final date = item.date.toLocal();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.leaf.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2_rounded, size: 20, color: AppColors.leaf),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}.${date.minute.toString().padLeft(2, '0')}',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.sizeFormatted} · ${item.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: _busy ? null : () => _restore(item),
            icon: const Icon(Icons.restore_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Hapus',
            onPressed: _busy ? null : () => _delete(item),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
