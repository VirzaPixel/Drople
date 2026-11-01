import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/drople_network.dart';

/// Dialog untuk menampilkan pairing code (QR + teks) dan menerima input kode pairing.
class PairingDialog extends StatefulWidget {
  final DropleNetwork network;
  final String? initialCode; // jika sudah ada kode dari startPairing
  final ValueChanged<String>? onConnected;

  const PairingDialog({
    super.key,
    required this.network,
    this.initialCode,
    this.onConnected,
  });

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  String? _pairingCode;
  final _codeController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pairingCode = widget.initialCode;
    if (_pairingCode != null) return;
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _error = null;
      _connecting = true;
    });
    try {
      final code = await widget.network.startPairing();
      setState(() {
        _pairingCode = code;
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  Future<void> _connect() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await widget.network.connectPairing(code);
      if (widget.onConnected != null) {
        widget.onConnected!(code);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pairing Perangkat'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pairingCode != null) ...[
              const Text('Kode pairing Anda (tampilkan QR ke perangkat lain):',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              QrImageView(
                data: _pairingCode!,
                version: QrVersions.auto,
                size: 180.0,
                gapless: false,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _pairingCode!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text('Atau masukkan kode dari perangkat lain:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
            ] else ...[
              const Text('Masukkan pairing code:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                hintText: 'DRO1:...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 1,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text('$_error',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        if (_pairingCode == null)
          TextButton(
            onPressed: _connecting ? null : _generate,
            child: const Text('Buat Kode Baru'),
          ),
        if (_pairingCode != null)
          TextButton(
            onPressed: _connecting ? null : _generate,
            child: const Text('Refresh'),
          ),
        FilledButton(
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Hubungkan'),
        ),
      ],
    );
  }
}
