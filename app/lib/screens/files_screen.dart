import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/file_transfer.dart';
import '../models/peer.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

enum _FileFilter { all, incoming, outgoing }

class FilesScreen extends StatefulWidget {
  const FilesScreen({
    super.key,
    required this.files,
    required this.network,
  });

  final DropleFile files;
  final DropleNetwork network;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<FileTransferItem> _transfers = const [];
  _FileFilter _filter = _FileFilter.all;
  Timer? _ticker;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _load(silent: false);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  void _load({bool silent = true}) {
    try {
      final transfers = widget.files.listTransfers();
      final signature = transfers
          .map((t) => '${t.id}:${t.status}:${t.progress}:${t.completedAt}')
          .join('|');
      if (silent && signature == _lastSignature) return;
      _lastSignature = signature;
      if (!mounted) return;
      setState(() => _transfers = transfers);
    } catch (_) {}
  }

  List<FileTransferItem> get _visible {
    return _transfers.where((t) {
      return switch (_filter) {
        _FileFilter.all => true,
        _FileFilter.incoming => !t.isSend,
        _FileFilter.outgoing => t.isSend,
      };
    }).toList();
  }

  Future<void> _pickAndSend() async {
    final peers = widget.network.listPeers().where((p) => p.connected).toList();
    if (peers.isEmpty) {
      _toast('Hubungkan perangkat terlebih dahulu di tab Perangkat');
      return;
    }
    final peer = await _choosePeer(peers);
    if (peer == null) return;

    final file = await FilePicker.pickFile();
    if (file == null || file.path == null) return;
    try {
      widget.files.sendFile(peer.id, file.path!);
      _toast('Mengirim ${file.name} ke ${peer.name}');
      _load(silent: false);
    } catch (_) {
      _toast('Gagal memulai pengiriman');
    }
  }

  Future<PeerEntry?> _choosePeer(List<PeerEntry> peers) {
    return showModalBottomSheet<PeerEntry>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kirim ke perangkat', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Pilih tujuan transfer file.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 14),
                ...peers.map(
                  (peer) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      foregroundColor: theme.colorScheme.primary,
                      child: Text(
                        peer.name.trim().isEmpty
                            ? '?'
                            : peer.name.trim()[0].toUpperCase(),
                      ),
                    ),
                    title: Text(peer.name),
                    subtitle: Text(
                      peer.code.isEmpty ? peer.shortId : 'Kode ${peer.code}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, peer),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(FileTransferItem item) async {
    final error = await widget.files.openTransfer(item);
    if (error.isNotEmpty) _toast(error);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _peerName(String peerId) {
    for (final peer in widget.network.listPeers()) {
      if (peer.id == peerId) return peer.name;
    }
    return peerId.length > 10 ? peerId.substring(0, 10) : peerId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final active = _transfers.where((t) => t.isActive || t.status == 'pending').length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: () async => _load(silent: false),
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
                            Text('File', style: theme.textTheme.headlineMedium),
                            Text(
                              '${_transfers.length} transfer · ${active == 0 ? 'tidak ada proses aktif' : '$active sedang berjalan'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Kirim file',
                        onPressed: _pickAndSend,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _dropZone(theme),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<_FileFilter>(
                          segments: const [
                            ButtonSegment(
                              value: _FileFilter.all,
                              label: Text('Semua'),
                            ),
                            ButtonSegment(
                              value: _FileFilter.incoming,
                              label: Text('Masuk'),
                            ),
                            ButtonSegment(
                              value: _FileFilter.outgoing,
                              label: Text('Keluar'),
                            ),
                          ],
                          selected: {_filter},
                          showSelectedIcon: false,
                          onSelectionChanged: (value) =>
                              setState(() => _filter = value.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'Belum ada transfer',
                      message:
                          'Pilih file lewat tombol di atas. File yang diterima bisa langsung dibuka atau dipasang dari sini.',
                      action: FilledButton.icon(
                        onPressed: _pickAndSend,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Pilih File'),
                      ),
                    )
                  else
                    ...List.generate(
                      visible.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: StaggeredEntry(
                          index: i,
                          child: _transferCard(theme, visible[i]),
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

  Widget _dropZone(ThemeData theme) {
    return Pressable(
      onTap: _pickAndSend,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.upload_file_rounded,
                color: theme.colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kirim file tanpa internet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih file dari perangkat, lalu tentukan tujuan.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _transferCard(ThemeData theme, FileTransferItem item) {
    final isActive = item.status == 'active' || item.status == 'pending';
    final isDone = item.isCompleted;
    final isFailed = item.isFailed;
    final accent = isFailed
        ? AppColors.danger
        : isDone
            ? AppColors.leaf
            : theme.colorScheme.primary;
    final peer = _peerName(item.peerId);

    final String subtitle;
    if (isFailed) {
      subtitle = 'Gagal · ${formatBytes(item.fileSize)}';
    } else if (isDone) {
      subtitle = 'Selesai · ${formatBytes(item.fileSize)} · ${formatRelative(item.completedAt ?? item.createdAt)}';
    } else {
      subtitle = '${formatBytes(item.progress)} dari ${formatBytes(item.fileSize)}';
    }

    return Pressable(
      onTap: isDone ? () => _open(item) : null,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                item.isSend ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: accent,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.5),
                        ),
                      ),
                      if (isDone)
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: theme.colorScheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.isSend ? 'Ke' : 'Dari'} $peer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 8),
                  if (isActive) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: item.percent == 0 ? null : item.percent,
                        minHeight: 5,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                        ),
                      ),
                      if (isActive)
                        Text(
                          '${(item.percent * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
