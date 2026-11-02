import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/drople_core.dart';
import '../theme/app_theme.dart';
import '../widgets/markdown_editor.dart';
import '../widgets/ui.dart';
import 'note_editor.dart';

enum _NoteFilter { all, favorite }

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.core});

  final DropleCore core;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _search = TextEditingController();
  List<NoteSummary> _notes = const [];
  _NoteFilter _filter = _NoteFilter.all;
  Timer? _ticker;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
    _ticker = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _load(silent: true),
    );
  }

  void _load({bool silent = false}) {
    try {
      final notes = widget.core.listNotes();
      final signature = notes
          .map((n) => '${n.id}:${n.updatedAt}:${n.isFavorite}:${n.syncStatus}')
          .join('|');
      if (silent && signature == _lastSignature) return;
      _lastSignature = signature;
      if (!mounted) return;
      setState(() => _notes = notes);
    } catch (_) {}
  }

  List<NoteSummary> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _notes.where((note) {
      final matchFilter = switch (_filter) {
        _NoteFilter.all => true,
        _NoteFilter.favorite => note.isFavorite == 1,
      };
      if (!matchFilter) return false;
      if (query.isEmpty) return true;
      return note.title.toLowerCase().contains(query) ||
          note.preview.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _open({NoteSummary? note}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NoteEditorScreen(core: widget.core, note: note, onSaved: _load),
      ),
    );
    _load();
  }

  Future<void> _copy(NoteSummary note) async {
    final l = context.l10n;
    try {
      final data = widget.core.getNote(note.id);
      await Clipboard.setData(ClipboardData(text: data.content));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.t('notes.copied'))));
    } catch (_) {}
  }

  Future<void> _toggleFavorite(NoteSummary note) async {
    final next = note.isFavorite != 1;
    try {
      widget.core.setFavorite(note.id, next);
      _load();
    } catch (_) {}
  }

  Future<void> _delete(NoteSummary note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.t('notes.deleteTitle')),
        content: Text(
          note.title.trim().isEmpty
              ? ctx.l10n.t('notes.untitledNote')
              : note.title,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.t('notes.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(ctx.l10n.t('notes.delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.core.deleteNote(note.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final visible = _visible;
    final favoriteCount = _notes.where((n) => n.isFavorite == 1).length;
    final countText = l.t('notes.count', {'count': '${_notes.length}'});
    final favoriteText = l.t('notes.favoriteCount', {
      'count': '$favoriteCount',
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: l.t('notes.title'),
                      subtitle: favoriteCount > 0
                          ? '$countText · $favoriteText'
                          : countText,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            decoration: InputDecoration(
                              hintText: l.t('notes.searchHint'),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 19,
                              ),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () => _search.clear(),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PrimaryButton(
                          label: l.t('notes.add'),
                          icon: Icons.add_rounded,
                          onTap: () => _open(),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  sliver: SliverToBoxAdapter(child: _filters(theme)),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: _notes.isEmpty
                          ? Icons.edit_note_rounded
                          : Icons.search_off_rounded,
                      title: _notes.isEmpty
                          ? l.t('notes.emptyTitle')
                          : l.t('notes.noResults'),
                      message: _notes.isEmpty
                          ? l.t('notes.emptyMessage')
                          : l.t('notes.searchMessage'),
                      action: _notes.isEmpty
                          ? FilledButton.icon(
                              onPressed: () => _open(),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(l.t('notes.create')),
                            )
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width >= 820 ? 2 : 1;
                        if (columns == 1) {
                          return SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) => StaggeredEntry(
                              index: i,
                              child: _noteCard(theme, visible[i]),
                            ),
                          );
                        }
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                mainAxisExtent: 184,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => StaggeredEntry(
                              index: i,
                              child: _noteCard(theme, visible[i]),
                            ),
                            childCount: visible.length,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters(ThemeData theme) {
    final l = context.l10n;
    Widget chip(String label, _NoteFilter value) {
      final selected = _filter == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        showCheckmark: false,
        avatar: selected
            ? Icon(
                Icons.check_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              )
            : null,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(l.t('notes.all'), _NoteFilter.all),
          const SizedBox(width: 8),
          chip(l.t('notes.favorite'), _NoteFilter.favorite),
        ],
      ),
    );
  }

  Widget _noteCard(ThemeData theme, NoteSummary note) {
    final l = context.l10n;
    final title = note.title.trim().isEmpty
        ? l.t('notes.untitled')
        : note.title.trim();
    final preview = stripMarkdown(note.preview);
    final favorite = note.isFavorite == 1;

    return Pressable(
      onTap: () => _open(note: note),
      onLongPress: () => _delete(note),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: l.t('notes.copyTooltip'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => _copy(note),
                  icon: const Icon(
                    Icons.content_copy_rounded,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => _toggleFavorite(note),
                  icon: Icon(
                    favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 18,
                    color: favorite
                        ? AppColors.amber
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.surfaceContainerHigh.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
                child: Text(
                  preview.isEmpty ? l.t('notes.emptyPreview') : preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: preview.isEmpty
                        ? theme.colorScheme.outline
                        : theme.colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  Icons.smartphone_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  l.t('notes.deviceThis'),
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  formatRelative(note.updatedAt, english: l.isEnglish),
                  style: theme.textTheme.labelSmall,
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
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }
}
