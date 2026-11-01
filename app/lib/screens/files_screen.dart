import 'package:flutter/material.dart';

import '../models/file_transfer.dart';
import '../models/peer.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _file = DropleFile();
  final _network = DropleNetwork();
  List<FileTransferItem> _transfers = const [];
  List<PeerEntry> _connectedPeers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    try {
      final list = _file.listTransfers();
      List<PeerEntry> peers = const [];
      try {
        peers = _network.listPeers().where((p) => p.connected).toList();
      } catch (_) {}
      setState(() {
        _transfers = list;
        _connectedPeers = peers;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendFile() async {
    if (_connectedPeers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada peer terhubung. Sambungkan dulu di menu Perangkat.'),
        ),
      );
      return;
    }

    String selectedPeer = _connectedPeers.first.id;
    final pathCtrl = TextEditingController();

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Kirim File ke Peer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedPeer,
                decoration: const InputDecoration(labelText: 'Tujuan Peer'),
                items: _connectedPeers.map((p) {
                  final label = p.name.isEmpty ? p.shortId : p.name;
                  return DropdownMenuItem(value: p.id, child: Text(label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedPeer = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Path File Lengkap',
                  hintText: '/path/ke/dokumen.pdf',
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
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );

    if (sent == true) {
      final path = pathCtrl.text.trim();
      if (path.isEmpty) return;
      try {
        _file.sendFile(selectedPeer, path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengiriman file dijadwalkan')),
          );
        }
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengirim: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer File'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sendFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('Kirim File'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transfers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Belum ada riwayat transfer file.\nFile masuk dari peer otomatis tersimpan ke folder Download.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _transfers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = _transfers[i];
                    return ListTile(
                      leading: Icon(
                        item.isSend ? Icons.arrow_upward : Icons.arrow_downward,
                        color: item.isCompleted
                            ? Colors.green
                            : item.isFailed
                                ? Colors.red
                                : Colors.blue,
                      ),
                      title: Text(item.fileName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.direction.toUpperCase()} • ${item.status}'
                            '${item.localPath != null ? ' • ${item.localPath}' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (item.isActive) ...[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: item.percent),
                          ],
                        ],
                      ),
                      trailing: Text(
                        '${(item.fileSize / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    );
                  },
                ),
    );
  }
}
