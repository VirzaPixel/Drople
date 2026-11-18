import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/peer.dart';
import '../services/drople_network.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Panel diagnostik koneksi (Wireless Debugging): menampilkan identitas peer,
/// alamat jaringan, status discovery, dan koneksi manual lewat multiaddr.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.network});

  final DropleNetwork network;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final TextEditingController _address = TextEditingController();
  NetworkDiagnostics? _info;
  List<String> _localIps = const [];
  String? _error;
  bool _dialing = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLocalIps();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  void _load() {
    try {
      final info = widget.network.diagnostics();
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _loadLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final ips = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && !address.address.startsWith('169.254.')) {
            ips.add(address.address);
          }
        }
      }
      if (!mounted) return;
      setState(() => _localIps = ips.toList());
    } catch (_) {}
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _toast(context.l10n.t('diagnostics.copied', {'label': label}));
  }

  Future<void> _dial() async {
    final l = context.l10n;
    final address = _address.text.trim();
    if (!address.startsWith('/')) {
      _toast(l.t('diagnostics.addressInvalid'));
      return;
    }
    setState(() => _dialing = true);
    try {
      widget.network.dialAddr(address);
      _toast(l.t('diagnostics.dialSent'));
      _load();
    } catch (e) {
      _toast(l.t('diagnostics.dialFailed'));
    } finally {
      if (mounted) setState(() => _dialing = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final info = _info;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('diagnostics.title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: () async {
                _load();
                await _loadLocalIps();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  SectionHeader(
                    title: l.t('diagnostics.title'),
                    subtitle: l.t('diagnostics.subtitle'),
                    trailing: IconButton(
                      tooltip: l.t('diagnostics.refresh'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    _errorCard(theme, _error!),
                  ],
                  const SizedBox(height: 12),
                  _localCard(theme, info),
                  const SizedBox(height: 12),
                  _connectCard(theme),
                  const SizedBox(height: 18),
                  SectionHeader(
                    title: l.t('diagnostics.peers'),
                    subtitle: l.t('diagnostics.peersCount', {
                      'count': '${info?.peers.length ?? 0}',
                    }),
                  ),
                  const SizedBox(height: 8),
                  if (info == null || info.peers.isEmpty)
                    _emptyPeers(theme)
                  else
                    ...info.peers.map(
                      (peer) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _peerCard(theme, peer),
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

  Widget _errorCard(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Text(
        error,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
      ),
    );
  }

  Widget _localCard(ThemeData theme, NetworkDiagnostics? info) {
    final l = context.l10n;
    final running = info?.running ?? false;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 18,
                color: running ? AppColors.primary : AppColors.danger,
              ),
              const SizedBox(width: 8),
              Text(
                running
                    ? l.t('diagnostics.statusRunning')
                    : l.t('diagnostics.statusStopped'),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _row(
            l.t('diagnostics.peerId'),
            info?.peerId ?? '—',
            copyLabel: 'Peer ID',
          ),
          _row(l.t('diagnostics.code'), info?.code ?? '—'),
          _row(
            l.t('diagnostics.fingerprint'),
            info?.fingerprint ?? '—',
            copyLabel: 'Fingerprint',
          ),
          const SizedBox(height: 10),
          Text(
            l.t('diagnostics.listenAddresses'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          if (info == null || info.listenAddrs.isEmpty)
            Text('—', style: theme.textTheme.bodySmall)
          else
            ...info.listenAddrs.map(
              (addr) => _addressTile(theme, addr, 'Listen'),
            ),
          const SizedBox(height: 10),
          Text(
            l.t('diagnostics.localNetwork'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          if (_localIps.isEmpty)
            Text('—', style: theme.textTheme.bodySmall)
          else
            ..._localIps.map((ip) => _addressTile(theme, ip, 'IP')),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {String? copyLabel}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (copyLabel != null && value != '—')
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              tooltip: context.l10n.t('diagnostics.copy'),
              onPressed: () => _copy(value, copyLabel),
              icon: const Icon(Icons.copy_rounded, size: 15),
            ),
        ],
      ),
    );
  }

  Widget _addressTile(ThemeData theme, String address, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.link_rounded,
            size: 14,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              address,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: context.l10n.t('diagnostics.copy'),
            onPressed: () => _copy(address, label),
            icon: const Icon(Icons.copy_rounded, size: 15),
          ),
        ],
      ),
    );
  }

  Widget _connectCard(ThemeData theme) {
    final l = context.l10n;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.t('diagnostics.manualConnect'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(l.t('diagnostics.manualHint'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l.t('diagnostics.addressHint'),
              prefixIcon: const Icon(Icons.lan_rounded, size: 19),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _dialing ? null : _dial,
              icon: _dialing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(l.t('diagnostics.connect')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPeers(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Text(
        context.l10n.t('diagnostics.noPeers'),
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Widget _peerCard(ThemeData theme, PeerEntry peer) {
    final l = context.l10n;
    final name = peer.name.trim().isEmpty
        ? l.t('peers.unnamed')
        : peer.name.trim();
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: peer.connected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (peer.code.isNotEmpty)
                Text(
                  peer.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.7,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            peer.id,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (peer.addresses.isEmpty)
            Text(
              l.t('diagnostics.noAddresses'),
              style: theme.textTheme.bodySmall,
            )
          else
            ...peer.addresses.map((addr) => _addressTile(theme, addr, 'Peer')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _address.dispose();
    super.dispose();
  }
}
