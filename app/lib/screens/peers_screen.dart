import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/peer.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../services/drople_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class PeersScreen extends StatefulWidget {
  const PeersScreen({
    super.key,
    required this.network,
    required this.sync,
    required this.files,
  });

  final DropleNetwork network;
  final DropleSync sync;
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
      final signature = '$code|${peers.map((p) => '${p.id}:${p.connected}:${p.name}:${p.code}:${p.lastSeen}').join(',')}';
      if (silent && signature == _lastSignature) return;
      _lastSignature = signature;
      if (!mounted) return;
      setState(() {
        _peers = peers;
        if (code.isNotEmpty) _code = code;
      });
    } catch (_) {}
  }

  List<String> _codeChars() {
    final code = _code.padRight(6, '-').substring(0, 6);
    return code.split('');
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kode pairing disalin')),
    );
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
                Text('Pindai untuk terhubung', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Buka Drople di perangkat lain, lalu pilih Pindai QR.',
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
                      color: AppColors.ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.ink,
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
                    label: const Text('Salin Kode'),
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
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );
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
    final code = _normalize(raw);
    if (code.length < 4) {
      _toast('Kode pairing tidak valid');
      return;
    }
    setState(() => _connecting = true);
    try {
      var attempt = 0;
      while (true) {
        try {
          await widget.network.connectPairing(code);
          break;
        } on StateError catch (e) {
          final notFound = e.message.contains('kode 16');
          if (notFound && attempt < 4) {
            attempt++;
            await Future<void>.delayed(const Duration(milliseconds: 650));
            continue;
          }
          rethrow;
        }
      }
      _toast('Permintaan pairing dikirim');
      _load(silent: false);
    } on StateError catch (e) {
      final message = e.message.contains('kode 16')
          ? 'Perangkat dengan kode $code belum terdeteksi. Pastikan Drople terbuka di perangkat tujuan dan berada di jaringan yang sama.'
          : 'Gagal terhubung. Periksa kode lalu coba lagi.';
      _toast(message);
    } catch (_) {
      _toast('Gagal terhubung ke perangkat');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _manualCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masukkan Kode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          ],
          style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(letterSpacing: 5),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: 'ABC123',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Hubungkan'),
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

  Future<void> _sync(PeerEntry peer) async {
    try {
      widget.sync.syncWithPeer(peer.id);
      _toast('Sinkronisasi dengan ${peer.name} dimulai');
    } catch (_) {
      _toast('Gagal memulai sinkronisasi');
    }
  }

  Future<void> _send(PeerEntry peer) async {
    try {
      final file = await FilePicker.pickFile();
      final path = file?.path;
      if (path == null) return;
      widget.files.sendFile(peer.id, path);
      _toast('Mengirim ${file!.name} ke ${peer.name}');
    } catch (_) {
      _toast('Gagal mengirim file');
    }
  }

  Future<void> _addRelay() async {
    final controller = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Relay'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/ip4/192.168.1.10/tcp/4001',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (addr != null && addr.trim().isNotEmpty) {
      try {
        await widget.network.addRelay(addr.trim());
        _toast('Relay ditambahkan');
      } catch (_) {
        _toast('Alamat relay tidak valid');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _peers.where((p) => p.connected).length;

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
                            Text('Perangkat', style: theme.textTheme.headlineMedium),
                            Text(
                              '${widget.network.deviceName ?? 'Perangkat ini'} · $connected terhubung',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tambah relay',
                        onPressed: _addRelay,
                        icon: const Icon(Icons.settings_ethernet_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _pairingCard(theme),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: 'Perangkat Terdekat',
                    subtitle: _peers.isEmpty
                        ? 'Mencari perangkat di jaringan yang sama…'
                        : 'Ditemukan otomatis lewat Wi-Fi lokal',
                  ),
                  if (_peers.isEmpty)
                    AppCard(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Menunggu perangkat lain', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'Buka Drople di perangkat lain. Kamu juga bisa memindai kode di atas.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(
                      _peers.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
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

  Widget _pairingCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            Color.lerp(theme.colorScheme.primary, Colors.black, 0.32)!,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: Colors.white70, size: 19),
              const SizedBox(width: 8),
              Text(
                'Kode Pairing Kamu',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _copyCode,
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: _codeChars()
                .map(
                  (c) => Container(
                    width: 42,
                    height: 54,
                    margin: const EdgeInsets.only(right: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      c,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'Masukkan kode ini di perangkat lain, atau bagikan lewat QR.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showQr,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.colorScheme.primary,
                  ),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Tampilkan QR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _connecting ? null : _scan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(_connecting ? 'Menghubungkan' : 'Pindai'),
                ),
              ),
            ],
          ),
          Center(
            child: TextButton(
              onPressed: _connecting ? null : _manualCode,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Masukkan kode manual'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peerCard(ThemeData theme, PeerEntry peer) {
    final initial = peer.name.trim().isEmpty ? '?' : peer.name.trim()[0].toUpperCase();
    final isOnline = peer.connected;
    return Pressable(
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isOnline
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                initial,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: isOnline ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          peer.name.trim().isEmpty ? 'Perangkat Tanpa Nama' : peer.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (peer.code.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            peer.code,
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 0.8,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isOnline ? AppColors.leaf : theme.colorScheme.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline
                            ? 'Terhubung${peer.latencyMs != null ? ' · ${peer.latencyMs} ms' : ''}'
                            : 'Terakhir ${formatRelative(peer.lastSeen)}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isOnline) ...[
              IconButton(
                tooltip: 'Sinkronkan catatan',
                onPressed: () => _sync(peer),
                icon: const Icon(Icons.sync_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Kirim file',
                onPressed: () => _send(peer),
                icon: const Icon(Icons.send_rounded, size: 19),
              ),
            ],
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

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Pindai QR Drople'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_rounded,
                        color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Kamera tidak dapat digunakan',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gunakan kode manual dari layar sebelumnya.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2.5),
                  borderRadius: BorderRadius.circular(24),
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
    _controller.dispose();
    super.dispose();
  }
}
