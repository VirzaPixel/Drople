import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/file_transfer.dart';
import '../models/peer.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../services/storage_info.dart';
import '../theme/app_theme.dart';
import '../widgets/qr_scanner_screen.dart';
import '../widgets/ui.dart';

enum _FileFilter { all, incoming, outgoing }

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.files, required this.network});

  final DropleFile files;
  final DropleNetwork network;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<FileTransferItem> _transfers = const [];
  _FileFilter _filter = _FileFilter.all;
  Timer? _ticker;
  Timer? _storageTicker;
  ({int free, int total})? _storage;
  double _lanSpeed = 0;
  final Map<String, int> _lastTransferProgress = {};
  DateTime _lastSpeedAt = DateTime.now();
  String _lastSignature = '';
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load(silent: false);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _load());
    _loadStorage();
    _storageTicker = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadStorage(),
    );
  }

  Future<void> _loadStorage() async {
    final info = await StorageInfo.read();
    if (!mounted || info == null) return;
    setState(() => _storage = info);
  }

  void _load({bool silent = true}) {
    try {
      final transfers = widget.files.listTransfers();
      final now = DateTime.now();
      final elapsed = now.difference(_lastSpeedAt).inMilliseconds;
      var deltaBytes = 0;
      final currentProgress = <String, int>{};
      for (final transfer in transfers.where((item) => item.isActive)) {
        currentProgress[transfer.id] = transfer.progress;
        final previous = _lastTransferProgress[transfer.id];
        if (previous != null && transfer.progress >= previous) {
          deltaBytes += transfer.progress - previous;
        }
      }
      _lastTransferProgress
        ..clear()
        ..addAll(currentProgress);
      final speed = elapsed > 0 ? deltaBytes * 1000 / elapsed : 0.0;
      _lastSpeedAt = now;
      final signature = transfers
          .map((t) => '${t.id}:${t.status}:${t.progress}:${t.completedAt}')
          .join('|');
      if (silent && signature == _lastSignature && speed == _lanSpeed) return;
      _lastSignature = signature;
      if (!mounted) return;
      setState(() {
        _transfers = transfers;
        _lanSpeed = speed;
      });
    } catch (_) {}
  }

  List<FileTransferItem> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _transfers.where((t) {
      final matchFilter = switch (_filter) {
        _FileFilter.all => true,
        _FileFilter.incoming => !t.isSend,
        _FileFilter.outgoing => t.isSend,
      };
      if (!matchFilter) return false;
      return query.isEmpty || t.fileName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _pickAndSend() async {
    final l = context.l10n;
    final peers = widget.network.listPeers().where((p) => p.connected).toList();
    if (peers.isEmpty) {
      _toast(l.t('files.connectFirst'));
      return;
    }
    final peer = await _choosePeer(peers);
    if (peer == null) return;

    final file = await FilePicker.pickFile();
    if (file == null || file.path == null) return;
    try {
      widget.files.sendFile(peer.id, file.path!);
      _toast(l.t('files.sending', {'file': file.name, 'peer': peer.name}));
      _load(silent: false);
    } catch (_) {
      _toast(l.t('files.startFailed'));
    }
  }

  Future<void> _scanConnect() async {
    final l = context.l10n;
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _toast(l.t('files.scanAndroid'));
      return;
    }
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (scanned == null || scanned.trim().isEmpty) return;
    try {
      await widget.network.connectPairing(scanned.trim());
      _toast(l.t('files.pairSent'));
    } catch (_) {
      _toast(l.t('files.connectFailed'));
    }
  }

  IconData _fileIcon(FileTransferItem item) {
    final name = item.fileName.toLowerCase();
    if (item.isFailed) return Icons.error_outline_rounded;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.apk')) return Icons.android_rounded;
    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        name.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    }
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    return item.isSend ? Icons.north_east_rounded : Icons.south_west_rounded;
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
                Text(
                  ctx.l10n.t('files.choosePeer'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  ctx.l10n.t('files.choosePeerHint'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                ...peers.map(
                  (peer) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: theme.colorScheme.primary,
                      child: Text(
                        peer.name.trim().isEmpty
                            ? '?'
                            : peer.name.trim()[0].toUpperCase(),
                      ),
                    ),
                    title: Text(peer.name),
                    subtitle: Text(
                      peer.code.isEmpty
                          ? peer.shortId
                          : ctx.l10n.t('files.code', {'code': peer.code}),
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
    final l = context.l10n;
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: () async => _load(silent: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  SectionHeader(
                    title: l.t('files.title'),
                    subtitle: l.t('files.subtitle'),
                  ),
                  _actionRow(),
                  const SizedBox(height: 12),
                  _statsRow(theme),
                  const SizedBox(height: 12),
                  _tabs(theme),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l.t('files.searchHint'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: _search.text.trim().isEmpty
                          ? l.t('files.emptyTitle')
                          : l.t('files.emptySearch'),
                      message: _search.text.trim().isEmpty
                          ? l.t('files.emptyMessage')
                          : l.t('files.searchMessage'),
                      action: _search.text.trim().isEmpty
                          ? FilledButton.icon(
                              onPressed: _pickAndSend,
                              icon: const Icon(Icons.upload_file_rounded),
                              label: Text(l.t('files.pickFile')),
                            )
                          : null,
                    )
                  else
                    ...List.generate(
                      visible.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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

  Widget _actionRow() {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            label: l.t('files.sendFile'),
            icon: Icons.upload_file_rounded,
            height: 48,
            onTap: _pickAndSend,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          height: 48,
          child: OutlinedButton(
            onPressed: _scanConnect,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: AppColors.surfaceContainer.withValues(
                alpha: 0.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              size: 21,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statsRow(ThemeData theme) {
    final storage = _storage;
    final used = storage == null ? 0 : storage.total - storage.free;
    final percent = storage == null || storage.total <= 0
        ? 0.0
        : (used / storage.total).clamp(0.0, 1.0);

    final received = _transfers
        .where((t) => !t.isSend && t.isCompleted)
        .fold<int>(0, (sum, t) => sum + t.fileSize);
    final receivedFiles = _transfers
        .where((t) => !t.isSend && t.isCompleted)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final speedCard = _speedCard(theme);
        final receivedCard = _receivedCard(theme, received, receivedFiles);
        final storageCard = _storageCard(theme, storage, used, percent);
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: speedCard),
                  const SizedBox(width: 8),
                  Expanded(child: receivedCard),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: storageCard),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: speedCard),
            const SizedBox(width: 8),
            Expanded(child: receivedCard),
            const SizedBox(width: 8),
            Expanded(child: storageCard),
          ],
        );
      },
    );
  }

  Widget _receivedCard(ThemeData theme, int received, int files) {
    final l = context.l10n;
    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.download_rounded,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l.t('files.receivedTotal'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatBytes(received),
              style: inter(18, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              l.t('files.filesCount', {'count': '$files'}),
              style: inter(
                10,
                weight: FontWeight.w500,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardShell(Widget child) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: child,
    );
  }

  Widget _speedCard(ThemeData theme) {
    final l = context.l10n;
    final speed = (_lanSpeed / (1024 * 1024)).toStringAsFixed(1);
    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.speed_rounded,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l.t('files.wifiSpeed'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(speed, style: inter(18, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 9),
          Text(
            'MB/s',
            style: inter(
              10,
              weight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageCard(
    ThemeData theme,
    ({int free, int total})? storage,
    int used,
    double percent,
  ) {
    final l = context.l10n;
    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storage_rounded,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  l.t('files.storage'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                ),
              ),
              Text(
                storage == null ? '—' : '${(percent * 100).round()}%',
                style: inter(
                  10,
                  weight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: storage == null ? '—' : formatBytes(used),
              style: inter(18, weight: FontWeight.w700),
              children: [
                TextSpan(
                  text: storage == null
                      ? ''
                      : ' / ${formatBytes(storage.total)}',
                  style: inter(10.5, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 12,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: storage == null ? 0 : percent,
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceContainerHighest,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs(ThemeData theme) {
    final l = context.l10n;
    final labels = [
      l.t('files.all'),
      l.t('files.incoming'),
      l.t('files.outgoing'),
    ];
    final values = [
      _FileFilter.all,
      _FileFilter.incoming,
      _FileFilter.outgoing,
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _filter = values[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _filter == values[i]
                        ? AppColors.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[i],
                    style: inter(
                      11,
                      weight: _filter == values[i]
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: _filter == values[i]
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _transferCard(ThemeData theme, FileTransferItem item) {
    final l = context.l10n;
    final isActive = item.status == 'active' || item.status == 'pending';
    final isDone = item.isCompleted;
    final isFailed = item.isFailed;
    final accent = isFailed
        ? AppColors.danger
        : isDone
        ? AppColors.primary
        : theme.colorScheme.primary;
    final peer = _peerName(item.peerId);

    final direction = l.t(item.isSend ? 'files.to' : 'files.from');
    final String meta;
    if (isFailed) {
      meta = l.t('files.failedMeta', {'size': formatBytes(item.fileSize)});
    } else if (isDone) {
      meta = '${formatBytes(item.fileSize)} • $direction $peer';
    } else {
      meta =
          '${formatBytes(item.progress)} / ${formatBytes(item.fileSize)} • $direction $peer';
    }

    final String actionLabel;
    if (isDone) {
      actionLabel = l.t('files.open');
    } else if (isFailed) {
      actionLabel = l.t('files.failed');
    } else {
      actionLabel = l.t('files.processing');
    }

    return AppCard(
      padding: const EdgeInsets.all(12),
      color: isFailed ? AppColors.danger.withValues(alpha: 0.06) : null,
      onTap: isDone ? () => _open(item) : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isFailed
                  ? AppColors.danger.withValues(alpha: 0.14)
                  : AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _fileIcon(item),
              size: 20,
              color: isFailed ? AppColors.danger : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: inter(
                    10.5,
                    weight: FontWeight.w500,
                    color: isFailed
                        ? AppColors.danger
                        : AppColors.onSurfaceVariant,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: item.percent == 0 ? null : item.percent,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(item.percent * 100).toStringAsFixed(0)}%',
                      style: inter(10, weight: FontWeight.w600, color: accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 82,
            height: 36,
            child: OutlinedButton(
              onPressed: isDone ? () => _open(item) : null,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: isFailed
                    ? AppColors.danger.withValues(alpha: 0.12)
                    : AppColors.surfaceContainerLowest,
                side: BorderSide(
                  color: isFailed
                      ? AppColors.danger.withValues(alpha: 0.3)
                      : AppColors.surfaceContainerHigh,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                actionLabel,
                style: inter(
                  11,
                  weight: FontWeight.w600,
                  color: isFailed
                      ? AppColors.danger
                      : isDone
                      ? AppColors.onSurface
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _storageTicker?.cancel();
    _search.dispose();
    super.dispose();
  }
}
