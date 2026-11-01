import 'package:flutter/material.dart';

import '../models/peer.dart';
import '../services/drople_network.dart';
import '../services/drople_sync.dart';
import '../widgets/pairing_dialog.dart';
import 'files_screen.dart';

class PeersScreen extends StatefulWidget {
  const PeersScreen({super.key});

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  final _network = DropleNetwork();
  final _sync = DropleSync();
  List<PeerEntry> _peers = const [];
  bool _loading = true;
  String? _error;
  String? _localPeerId;
  String? _localFingerprint;
  bool _networkStarted = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _network.start();
      _networkStarted = true;
      setState(() {
        _localPeerId = _network.localPeerId();
        try {
          _localFingerprint = _network.localFingerprint();
        } catch (_) {}
        _loading = false;
      });
      _refreshPeers();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _refreshPeers() {
    setState(() {
      _peers = _network.listPeers();
    });
  }

  Future<void> _startPairing() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => PairingDialog(
        network: _network,
        onConnected: (_) => _refreshPeers(),
      ),
    );
    if (result == true && mounted) {
      _refreshPeers();
    }
  }

  void _triggerSync(PeerEntry peer) {
    try {
      _sync.syncWithPeer(peer.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkronisasi diminta ke ${peer.shortId}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perangkat P2P & Sync'),
        actions: [
          IconButton(
            tooltip: 'Transfer File',
            icon: const Icon(Icons.folder_shared),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FilesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _networkStarted ? _refreshPeers : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Gagal memulai jaringan:\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _bootstrap,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
          : Column(
              children: [
                _buildInfoCard(),
                Expanded(
                  child: _peers.isEmpty
                      ? const Center(
                          child: Text('Belum ada perangkat terdeteksi'),
                        )
                      : ListView.separated(
                          itemCount: _peers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final peer = _peers[i];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(peer.shortId.substring(0, 1)),
                              ),
                              title: Text(
                                peer.name.isEmpty ? peer.shortId : peer.name,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${peer.statusText} • ${peer.addresses.length} alamat'
                                    '${peer.latencyMs != null ? ' • ${peer.latencyMs}ms' : ''}',
                                  ),
                                  if (peer.fingerprint.isNotEmpty)
                                    Text(
                                      'Fingerprint: ${peer.fingerprint}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (peer.connected) ...[
                                    IconButton(
                                      tooltip: 'Sinkronisasi Catatan',
                                      icon: const Icon(Icons.sync, color: Colors.blue),
                                      onPressed: () => _triggerSync(peer),
                                    ),
                                  ],
                                  Icon(
                                    peer.connected
                                        ? Icons.wifi_tethering
                                        : Icons.wifi_off,
                                    color: peer.connected
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Pairing',
        onPressed: _networkStarted ? _startPairing : null,
        child: const Icon(Icons.qr_code),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Peer ID Lokal',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            SelectableText(
              _localPeerId ?? '-',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            if (_localFingerprint != null) ...[
              const SizedBox(height: 8),
              const Text('Fingerprint Kunci Publik',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              SelectableText(
                _localFingerprint!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _networkStarted
                      ? Icons.circle
                      : Icons.radio_button_unchecked,
                  size: 12,
                  color: _networkStarted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _networkStarted ? 'Jaringan aktif (mDNS & Relay)' : 'Jaringan mati',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _network.stop();
    super.dispose();
  }
}
