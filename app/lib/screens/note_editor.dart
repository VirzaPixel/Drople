import 'dart:async';

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/drople_core.dart';
import '../theme/app_theme.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.core,
    this.note,
    required this.onSaved,
  });

  final DropleCore core;
  final NoteSummary? note;
  final VoidCallback onSaved;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  Timer? _autoSave;
  bool _favorite = false;
  bool _dirty = false;
  bool _saved = false;
  String? _noteId;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _noteId = note?.id;
    _favorite = (note?.isFavorite ?? 0) == 1;
    if (note != null) {
      final data = widget.core.getNote(note.id);
      _title = TextEditingController(text: data.title);
      _content = TextEditingController(text: data.content);
    } else {
      _title = TextEditingController();
      _content = TextEditingController();
    }
    _title.addListener(_markDirty);
    _content.addListener(_markDirty);
  }

  void _markDirty() {
    if (_dirty) return;
    _dirty = true;
    _saved = false;
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 900), _save);
  }

  void _save() {
    final title = _title.text.trim();
    final content = _content.text;
    if (title.isEmpty && content.trim().isEmpty) return;

    try {
      final existing = _noteId;
      if (existing == null) {
        final id = widget.core.createNote(title, content);
        _noteId = id;
        widget.core.setFavorite(id, _favorite);
      } else {
        widget.core.updateNote(existing, title, content);
        widget.core.setFavorite(existing, _favorite);
      }
      _dirty = false;
      _saved = true;
      widget.onSaved();
    } catch (_) {}
  }

  Future<void> _close() async {
    _autoSave?.cancel();
    if (_dirty) _save();
    _dirty = false;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.note == null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _autoSave?.cancel();
          _save();
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _close,
          ),
          title: Text(isNew ? 'Catatan Baru' : 'Sunting Catatan'),
          actions: [
            IconButton(
              tooltip: _favorite ? 'Hapus dari favorit' : 'Tandai favorit',
              onPressed: () {
                setState(() => _favorite = !_favorite);
                _dirty = true;
                _autoSave?.cancel();
                _autoSave = Timer(const Duration(milliseconds: 300), _save);
              },
              icon: Icon(
                _favorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _favorite ? AppColors.amber : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: () {
                  _autoSave?.cancel();
                  _save();
                  Navigator.of(context).pop();
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _saved ? 'Tersimpan' : 'Simpan',
                    key: ValueKey(_saved),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _title,
                      autofocus: isNew,
                      style: theme.textTheme.displaySmall?.copyWith(fontSize: 30),
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Judul catatan',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _content,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: 'Mulai menulis. Perubahan tersimpan otomatis.',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }
}
