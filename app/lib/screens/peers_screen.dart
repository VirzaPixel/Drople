import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/l10n.dart';
import '../models/peer.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../theme/app_theme.dart';
import '../widgets/qr_scanner_screen.dart';
import '../widgets/ui.dart';
import 'my_file_gua_screen.dart';

IconData _peerIconFor(PeerEntry peer) {
  final platform = peer.platform.toLowerCase();
  if (platform.contains('android') || platform == 'ios') {
    return Icons.phone_android_rounded;
  }
  if (platform == 'linux' || platform == 'macos' || platform == 'windows') {
    return Icons.laptop_rounded;
  }

  final name = peer.name.toLowerCase();
  bool hasName(List<String> keys) => keys.any(name.contains);

  if (hasName([
    'macbook',
    'imac',
    'thinkpad',
    'laptop',
    'notebook',
    'desktop',
    'ubuntu',
    'debian',
    'fedora',
    'linux',
    'mint',
    'manjaro',
    'opensuse',
    'kali',
    'zorin',
    'elementary',
    'raspberry',
    'windows',
    'pc',
    'workstation',
    'server',
    'lenovo',
    'dell',
    'asus',
    'acer',
    'msi',
    'toshiba',
    'surface',
  ])) {
    return Icons.laptop_rounded;
  }
  if (hasName([
    'iphone',
    'ipad',
    'galaxy',
    'pixel',
    'android',
    'phone',
    'redmi',
    'poco',
    'xiaomi',
    'oppo',
    'vivo',
    'realme',
    'infinix',
    'tecno',
    'oneplus',
    'motorola',
    'huawei',
    'honor',
    'sm-',
  ])) {
    return Icons.phone_android_rounded;
  }
  return Icons.devices_other_rounded;
}

class PeersScreen extends StatefulWidget {
  const PeersScreen({super.key, required this.network, required this.files});

  final DropleNetwork network;
  final DropleFile files;

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  List<PeerEntry> _peers = const [];
  String _code = '------';
  Timer? _ticker;
  String _lastSignature = '';
  bool _connecting = false;
  bool _codeOpen = false;
  final Set<String> _approvalDialogs = {};

  @override
  void initState() {
    super.initState();
    _load(silent: false);
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  void _load({bool silent = true}) {
    try {
      final peers = widget.network.listPeers();
      final code = widget.network.localShortCode();
      final signature =
          '$code|${peers.map((p) => '${p.id}:${p.connected}:${p.name}:${p.code}:${p.lastSeen}').join(',')}';
      if (!mounted) return;
      for (final notification in widget.network.takePairingNotifications()) {
        if (notification.accepted) continue;
        final peer = peers.where((item) => item.id == notification.peerId);
        final device = peer.isEmpty ? notification.peerId : peer.first.name;
        _toast(context.l10n.t('peers.pairRejected', {'device': device}));
      }
      _checkPairingRequests();
      if (silent && signature == _lastSignature) return;
      _lastSignature = signature;
      if (!mounted) return;
      setState(() {
        _peers = peers;
        if (code.isNotEmpty) _code = code;
      });
    } catch (_) {}
  }

  void _checkPairingRequests() {
    try {
      for (final request in widget.network.pendingApprovals()) {
        if (_approvalDialogs.add(request.id)) {
          _showPairingRequest(request.id, request.name);
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _showPairingRequest(String peerId, String name) async {
    final l = context.l10n;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.devices_rounded),
        title: Text(l.t('peers.pairRequestTitle')),
        content: Text(
          l.t('peers.pairRequestMessage', {
            'device': name.trim().isEmpty ? peerId : name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('peers.pairReject')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('peers.pairAccept')),
          ),
        ],
      ),
    );
    try {
      if (accepted == true) {
        widget.network.approvePairing(peerId);
      } else {
        widget.network.rejectPairing(peerId);
      }
    } catch (_) {}
    _approvalDialogs.remove(peerId);
    _load(silent: false);
  }

  List<String> _codeChars() {
    final code = _code.padRight(6, '-').substring(0, 6);
    return code.split('');
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.t('peers.codeCopied'))));
  }

  void _showQr() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctx.l10n.t('peers.qrTitle'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  ctx.l10n.t('peers.qrHint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: QrImageView(
                    data: 'DRO1:$_code',
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.surfaceContainerLowest,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.surfaceContainerLowest,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SelectableText(
                  _code,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: 6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyCode();
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(ctx.l10n.t('peers.copyCode')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _scan() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      await _manualCode();
      return;
    }
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (scanned != null && scanned.isNotEmpty && mounted) {
      await _connect(scanned);
    }
  }

  String _normalize(String raw) {
    final trimmed = raw.trim();
    final withoutPrefix = trimmed.toUpperCase().startsWith('DRO1:')
        ? trimmed.substring(5)
        : trimmed;
    final compact = withoutPrefix
        .replaceAll(RegExp(r'[\s-]'), '')
        .toUpperCase();
    // Kode pendek dinormalisasi; payload panjang (legacy base64) dibiarkan utuh.
    return compact.length <= 10 ? compact : trimmed;
  }

  Future<void> _connect(String raw) async {
    final l = context.l10n;
    final code = _normalize(raw);
    if (code.length < 4) {
      _toast(l.t('peers.invalidCode'));
      return;
    }
    setState(() => _connecting = true);
    try {
      await widget.network.connectPairing(code);
      _toast(l.t('peers.toastSent'));
      _load(silent: false);
    } on StateError catch (e) {
      final message = e.message.contains('kode 16')
          ? l.t('peers.toastNotFound', {'code': code})
          : l.t('peers.toastConnectFailed');
      _toast(message);
    } catch (_) {
      _toast(l.t('peers.toastConnectError'));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _manualCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.t('peers.dialogTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
            TextInputFormatter.withFunction((oldValue, newValue) {
              final upper = newValue.text.toUpperCase();
              return newValue.copyWith(
                text: upper,
                selection: newValue.selection,
                composing: TextRange.empty,
              );
            }),
          ],
          style: Theme.of(
            ctx,
          ).textTheme.headlineSmall?.copyWith(letterSpacing: 4),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'ABC123',
            hintStyle: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
              letterSpacing: 4,
              color: AppColors.onSurfaceVariant,
            ),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.t('peers.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(ctx.l10n.t('peers.connectAction')),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) await _connect(code);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(PeerEntry peer) async {
    final l = context.l10n;
    try {
      final file = await FilePicker.pickFile();
      final path = file?.path;
      if (path == null) return;
      widget.files.sendFile(peer.id, path);
      _toast(l.t('peers.sending', {'file': file!.name, 'peer': peer.name}));
    } catch (_) {
      _toast(l.t('peers.sendFailed'));
    }
  }

  void _disconnectPeer(PeerEntry peer) {
    try {
      widget.network.disconnectPeer(peer.id);
      _toast(
        context.l10n.t('peers.disconnected', {
          'device': peer.name.trim().isEmpty
              ? context.l10n.t('peers.unnamed')
              : peer.name.trim(),
        }),
      );
      _load(silent: false);
    } catch (_) {
      _toast(context.l10n.t('peers.disconnectFailed'));
    }
  }

  Future<void> _connectPeer(PeerEntry peer) async {
    if (peer.code.isNotEmpty) {
      await _connect(peer.code);
    } else {
      await _manualCode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final connected = _peers.where((p) => p.connected).length;

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
                  _archiveCard(theme),
                  const SizedBox(height: 18),
                  SectionHeader(
                    title: l.t('nav.devices'),
                    subtitle: l.t('peers.subtitle', {
                      'device':
                          widget.network.deviceName ?? l.t('peers.thisDevice'),
                      'count': '$connected',
                    }),
                  ),
                  _codeCard(theme),
                  const SizedBox(height: 10),
                  _useCodeCard(theme),
                  const SizedBox(height: 10),
                  _RadarCard(
                    peers: _peers,
                    onRefresh: () => _load(silent: false),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: l.t('peers.nearby'),
                    subtitle: _peers.isEmpty
                        ? l.t('peers.searchingNetwork')
                        : l.t('peers.foundAuto'),
                  ),
                  if (_peers.isEmpty)
                    _emptyPeers(theme)
                  else
                    ...List.generate(
                      _peers.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: StaggeredEntry(
                          index: i,
                          child: _peerCard(theme, _peers[i]),
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

  Widget _archiveCard(ThemeData theme) {
    final l = context.l10n;
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MyFileGuaScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              _IconTile(icon: Icons.inventory_2_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('peers.archiveTitle'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.t('peers.archiveSubtitle'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MyFileGuaScreen(),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(l.t('peers.archiveOpen')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyPeers(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.devices_other_rounded,
              size: 20,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('peers.emptyTitle'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.t('peers.emptyMessage'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _load(silent: false),
            child: Text(context.l10n.t('peers.scan')),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(ThemeData theme) {
    final chars = _codeChars();
    return Material(
      color: AppColors.surfaceContainer.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _codeOpen = !_codeOpen),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.surfaceContainerHigh),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _IconTile(icon: Icons.key_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t('peers.codeTitle'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _codeOpen
                              ? context.l10n.t('peers.codeHide')
                              : context.l10n.t('peers.codeShow'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _codeOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _codeOpen
                    ? Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.only(top: 14),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppColors.surfaceContainerHigh,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: Row(
                                children: [
                                  for (var i = 0; i < chars.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 7),
                                    Expanded(
                                      child: Container(
                                        height: 46,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color:
                                                AppColors.surfaceContainerHigh,
                                          ),
                                        ),
                                        child: Text(
                                          chars[i],
                                          style: inter(
                                            18,
                                            weight: FontWeight.w700,
                                            color: AppColors.primary,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PillButton(
                                  icon: Icons.content_copy_rounded,
                                  label: context.l10n.t('peers.copyCode'),
                                  onTap: _copyCode,
                                ),
                                const SizedBox(width: 8),
                                _PillButton(
                                  icon: Icons.qr_code_rounded,
                                  label: context.l10n.t('peers.showQr'),
                                  onTap: _showQr,
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _useCodeCard(ThemeData theme) {
    return Material(
      color: AppColors.surfaceContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _connecting ? null : _manualCode,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceContainerHigh),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.dialpad_rounded,
                size: 19,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.t('peers.useCode'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: context.l10n.t('peers.scanQr'),
                onPressed: _connecting ? null : _scan,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peerCard(ThemeData theme, PeerEntry peer) {
    final l = context.l10n;
    final name = peer.name.trim().isEmpty
        ? l.t('peers.unnamed')
        : peer.name.trim();
    final isOnline = peer.connected;
    final subtitle = isOnline
        ? '${l.t('peers.connected')}${peer.latencyMs != null ? ' · ${peer.latencyMs} ms' : ''}'
        : l.t('peers.lastSeen', {
            'time': formatRelative(peer.lastSeen, english: l.isEnglish),
          });

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _peerIconFor(peer),
                  size: 20,
                  color: isOnline
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (peer.code.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              peer.code,
                              style: inter(
                                9,
                                weight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => isOnline ? _send(peer) : _connectPeer(peer),
                  icon: Icon(
                    isOnline ? Icons.send_rounded : Icons.link_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isOnline ? l.t('peers.sendFile') : l.t('peers.connect'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    backgroundColor: AppColors.surfaceContainerLowest,
                    side: const BorderSide(
                      color: AppColors.surfaceContainerHigh,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (isOnline) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _disconnectPeer(peer),
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: Text(l.t('peers.disconnect')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      backgroundColor: AppColors.surfaceContainerLowest,
                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: AppColors.primary),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarCard extends StatefulWidget {
  const _RadarCard({required this.peers, required this.onRefresh});

  final List<PeerEntry> peers;
  final VoidCallback onRefresh;

  @override
  State<_RadarCard> createState() => _RadarCardState();
}

class _RadarCardState extends State<_RadarCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  static const _spots = [
    Alignment(-0.72, -0.64),
    Alignment(-0.62, 0.68),
    Alignment(0.68, 0.58),
  ];

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  Widget _ring(Color color) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color),
    ),
  );

  Widget _node(PeerEntry peer) {
    final l = context.l10n;
    final icon = _peerIconFor(peer);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 82,
          child: Text(
            peer.name.trim().isEmpty ? l.t('peers.radarDevice') : peer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: inter(
              9,
              weight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final nodes = widget.peers.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('peers.detect'), style: theme.textTheme.titleMedium),
              const SizedBox(width: 7),
              const Icon(
                Icons.wifi_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const Spacer(),
              Text(
                l.t('peers.online', {
                  'count': '${widget.peers.where((p) => p.connected).length}',
                }),
                style: theme.textTheme.labelSmall,
              ),
              IconButton(
                tooltip: l.t('peers.rescan'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: widget.onRefresh,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 278),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedBuilder(
                          animation: _ping,
                          builder: (context, _) {
                            final p = math.min(_ping.value / 0.75, 1.0);
                            final e = const Cubic(0, 0, 0.2, 1).transform(p);
                            return Transform.scale(
                              scale: 1 + e,
                              child: _ring(
                                AppColors.primary.withValues(
                                  alpha: 0.32 * (1 - e),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: _ring(
                          AppColors.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(64),
                        child: _ring(
                          AppColors.surfaceContainerHighest.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(96),
                        child: _ring(AppColors.surfaceContainerHighest),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.2),
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.smartphone_rounded,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                    for (var i = 0; i < nodes.length; i++)
                      Align(
                        alignment: _spots[i % _spots.length],
                        child: _node(nodes[i]),
                      ),
                    if (nodes.isEmpty)
                      Positioned(
                        bottom: 10,
                        child: Text(
                          l.t('peers.searchingNearby'),
                          style: theme.textTheme.labelSmall,
                        ),
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
}
