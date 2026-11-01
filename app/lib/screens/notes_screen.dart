import 'dart:async';

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/drople_core.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'note_editor.dart';

enum _NoteFilter { all, favorite, pending }

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
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _load(silent: true));
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
        _NoteFilter.pending => !note.isSynced,
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
        builder: (_) => NoteEditorScreen(
          core: widget.core,
          note: note,
          onSaved: _load,
        ),
      ),
    );
    _load();
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
        title: const Text('Hapus catatan?'),
        content: Text(
          note.title.trim().isEmpty ? 'Catatan tanpa judul' : note.title,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Hapus'),
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
    final visible = _visible;
    final favoriteCount = _notes.where((n) => n.isFavorite == 1).length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  sliver: SliverToBoxAdapter(child: _header(theme, favoriteCount)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Cari judul atau isi catatan',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => _search.clear(),
                              ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
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
                          ? 'Belum ada catatan'
                          : 'Tidak ada hasil',
                      message: _notes.isEmpty
                          ? 'Mulai catatan pertama. Semua tersimpan offline dan bisa disinkronkan lewat perangkat terdekat.'
                          : 'Coba kata kunci lain atau ubah filter.',
                      action: _notes.isEmpty
                          ? FilledButton.icon(
                              onPressed: () => _open(),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Buat Catatan'),
                            )
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width >= 820 ? 2 : 1;
                        if (columns == 1) {
                          return SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => StaggeredEntry(
                              index: i,
                              child: _noteCard(theme, visible[i], i),
                            ),
                          );
                        }
                        return SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            mainAxisExtent: 176,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => StaggeredEntry(
                              index: i,
                              child: _noteCard(theme, visible[i], i),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catatan'),
      ),
    );
  }

  Widget _header(ThemeData theme, int favorites) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const BrandMark(size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drople', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                _notes.isEmpty
                    ? 'Ruang tenang untuk pikiranmu'
                    : '${_notes.length} catatan · $favorites favorit · tersimpan lokal',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_tethering_rounded,
                  size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'P2P',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters(ThemeData theme) {
    Widget chip(String label, _NoteFilter value) {
      final selected = _filter == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        showCheckmark: false,
        avatar: selected
            ? Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.primary)
            : null,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Semua', _NoteFilter.all),
          const SizedBox(width: 8),
          chip('Favorit', _NoteFilter.favorite),
          const SizedBox(width: 8),
          chip('Perlu Sinkron', _NoteFilter.pending),
        ],
      ),
    );
  }

  Widget _noteCard(ThemeData theme, NoteSummary note, int index) {
    final title = note.title.trim().isEmpty ? 'Tanpa judul' : note.title.trim();
    final favorite = note.isFavorite == 1;
    final accents = [
      theme.colorScheme.primary,
      AppColors.amber,
      const Color(0xFF5B6FA8),
      const Color(0xFFA8607A),
    ];
    final accent = accents[index % accents.length];

    return Pressable(
      onTap: () => _open(note: note),
      onLongPress: () => _delete(note),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 26,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => _toggleFavorite(note),
                  icon: Icon(
                    favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 20,
                    color: favorite ? AppColors.amber : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                note.preview.trim().isEmpty
                    ? 'Catatan kosong. Ketuk untuk mulai menulis.'
                    : note.preview.trim().replaceAll('\n', ' '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: note.preview.trim().isEmpty
                      ? theme.colorScheme.outline
                      : theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SyncBadge(status: note.syncStatus),
                const Spacer(),
                Text(
                  formatRelative(note.updatedAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 10.5,
                  ),
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
