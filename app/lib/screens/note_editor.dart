import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/drople_core.dart';
import '../theme/app_theme.dart';
import '../widgets/markdown_editor.dart';

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
  late final MarkdownEditingController _content;
  final FocusNode _contentFocus = FocusNode();
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
      _content = MarkdownEditingController(text: data.content);
    } else {
      _title = TextEditingController();
      _content = MarkdownEditingController();
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

  void _setContent(String newText, int start, int end) {
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentFocus.requestFocus();
    });
  }

  void _wrapSelection(String before, String after) {
    final value = _content.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = text.substring(start, end);
    final body = selected.isEmpty
        ? context.l10n.t('editor.placeholder')
        : selected;
    final insert = '$before$body$after';
    final newText = text.replaceRange(start, end, insert);
    final bodyStart = start + before.length;
    _setContent(newText, bodyStart, bodyStart + body.length);
  }

  void _applyLinePrefix(String? prefix) {
    final value = _content.value;
    final text = value.text;
    final selection = value.selection;
    final cursor = selection.isValid ? selection.start : text.length;
    final lineStart = cursor > 0 ? text.lastIndexOf('\n', cursor - 1) + 1 : 0;
    final lineBreak = text.indexOf('\n', cursor);
    final lineEnd = lineBreak == -1 ? text.length : lineBreak;
    final line = text.substring(lineStart, lineEnd);
    final indent = RegExp(r'^\s*').firstMatch(line)!.group(0) ?? '';
    var body = line.substring(indent.length);

    const prefixes = [
      '### ',
      '## ',
      '# ',
      '- [ ] ',
      '- [x] ',
      '> ',
      '- ',
      '* ',
    ];
    String? current;
    for (final candidate in prefixes) {
      if (body.startsWith(candidate)) {
        current = candidate;
        break;
      }
    }

    if (current != null) body = body.substring(current.length);
    final newLine = current == prefix
        ? '$indent$body'
        : '$indent${prefix ?? ''}$body';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    final delta = newLine.length - line.length;
    final newCursor = (cursor + delta).clamp(
      lineStart,
      lineStart + newLine.length,
    );
    _setContent(newText, newCursor, newCursor);
  }

  Widget _formatBar(ThemeData theme) {
    final l = context.l10n;
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: theme.colorScheme.onSurfaceVariant,
        icon: Icon(icon),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            action(
              Icons.format_bold_rounded,
              l.t('editor.bold'),
              () => _wrapSelection('**', '**'),
            ),
            action(
              Icons.format_italic_rounded,
              l.t('editor.italic'),
              () => _wrapSelection('*', '*'),
            ),
            action(
              Icons.code_rounded,
              l.t('editor.code'),
              () => _wrapSelection('`', '`'),
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: theme.colorScheme.outlineVariant,
            ),
            action(
              Icons.title_rounded,
              l.t('editor.heading'),
              () => _applyLinePrefix('## '),
            ),
            action(
              Icons.format_list_bulleted_rounded,
              l.t('editor.list'),
              () => _applyLinePrefix('- '),
            ),
            action(
              Icons.checklist_rounded,
              l.t('editor.checklist'),
              () => _applyLinePrefix('- [ ] '),
            ),
            action(
              Icons.format_quote_rounded,
              l.t('editor.quote'),
              () => _applyLinePrefix('> '),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
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
          title: Text(isNew ? l.t('editor.new') : l.t('editor.edit')),
          actions: [
            IconButton(
              tooltip: _favorite
                  ? l.t('editor.favoriteOn')
                  : l.t('editor.favoriteOff'),
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
                    _saved ? l.t('editor.saved') : l.t('editor.save'),
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
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                      ),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: l.t('editor.titleHint'),
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
                        focusNode: _contentFocus,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: l.t('editor.contentHint'),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    _formatBar(theme),
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
    _contentFocus.dispose();
    super.dispose();
  }
}
