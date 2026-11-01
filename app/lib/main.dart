import 'package:flutter/material.dart';

import 'models/note.dart';
import 'screens/backup_screen.dart';
import 'screens/files_screen.dart';
import 'screens/peers_screen.dart';
import 'services/drople_core.dart';

void main() {
  runApp(const DropleApp());
}

class DropleApp extends StatelessWidget {
  const DropleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drople',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C6FFF)),
        useMaterial3: true,
      ),
      home: const NotesScreen(),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _core = DropleCore();
  List<NoteSummary> _notes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _core.init();
      _refresh();
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _refresh() {
    setState(() {
      _notes = _core.listNotes();
      _loading = false;
      _error = null;
    });
  }

  Future<void> _openEditor({NoteSummary? note}) async {
    final titleCtrl = TextEditingController(text: note?.title ?? '');
    final contentCtrl = TextEditingController();
    if (note != null) {
      contentCtrl.text = _core.getNote(note.id).content;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(note == null ? 'Catatan Baru' : 'Edit Catatan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(labelText: 'Isi'),
              minLines: 3,
              maxLines: 6,
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
      final title = titleCtrl.text.trim();
      final content = contentCtrl.text;
      if (title.isEmpty && content.isEmpty) return;
      if (note == null) {
        _core.createNote(title, content);
      } else {
        _core.updateNote(note.id, title, content);
      }
      _refresh();
    }
  }

  Future<void> _delete(NoteSummary note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text(note.title.isEmpty ? '(tanpa judul)' : note.title),
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
    if (ok == true) {
      _core.deleteNote(note.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drople'),
        actions: [
          IconButton(
            tooltip: 'Transfer File',
            icon: const Icon(Icons.folder_shared),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FilesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Backup Cloud',
            icon: const Icon(Icons.cloud_sync),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Perangkat & Sync',
            icon: const Icon(Icons.devices),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PeersScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: _error == null
          ? FloatingActionButton(
              onPressed: () => _openEditor(),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Gagal memuat core:\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _notes.isEmpty
                  ? const Center(child: Text('Belum ada catatan'))
                  : ListView.separated(
                      itemCount: _notes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final note = _notes[i];
                        return ListTile(
                          title: Text(
                            note.title.isEmpty ? '(tanpa judul)' : note.title,
                          ),
                          subtitle: Text(
                            DateTime.fromMillisecondsSinceEpoch(note.updatedAt)
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                          ),
                          trailing: Icon(
                            note.isSynced
                                ? Icons.cloud_done
                                : note.isConflict
                                    ? Icons.warning
                                    : Icons.sync,
                            size: 16,
                            color: note.isSynced ? Colors.green : Colors.orange,
                          ),
                          onTap: () => _openEditor(note: note),
                          onLongPress: () => _delete(note),
                        );
                      },
                    ),
    );
  }
}
