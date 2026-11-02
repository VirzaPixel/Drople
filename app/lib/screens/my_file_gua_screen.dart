import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../l10n/l10n.dart';
import '../services/my_file_gua.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class MyFileGuaScreen extends StatefulWidget {
  const MyFileGuaScreen({super.key});

  @override
  State<MyFileGuaScreen> createState() => _MyFileGuaScreenState();
}

class _MyFileGuaScreenState extends State<MyFileGuaScreen> {
  List<File> _files = const [];
  List<MyFileGuaMessage> _messages = const [];
  bool _loading = true;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        MyFileGua.listFiles(),
        MyFileGua.listMessages(),
      ]);
      if (!mounted) return;
      setState(() {
        _files = results[0] as List<File>;
        _messages = results[1] as List<MyFileGuaMessage>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFiles() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    try {
      final added = await MyFileGua.addFiles(picked);
      for (final file in added) {
        await MyFileGua.addAttachmentMessage(file.uri.pathSegments.last);
      }
      await _load();
      if (mounted) _toast(context.l10n.t('myfile.saved'));
    } catch (_) {
      if (mounted) _toast(context.l10n.t('myfile.failed'));
    }
  }

  Future<void> _open(File file) async {
    final result = await OpenFilex.open(file.path);
    if (!mounted) return;
    if (result.type != ResultType.done) _toast(result.message);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await MyFileGua.addMessage(text);
    await _load();
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showFiles() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MyFileGuaFilesScreen()),
    );
    await _load();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHighest,
          content: Text(
            message,
            style: const TextStyle(color: AppColors.onSurface),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('peers.archiveTitle')),
        actions: [
          IconButton(
            tooltip: l.t('myfile.viewFiles'),
            onPressed: _showFiles,
            icon: Badge(
              label: Text('${_files.length}'),
              isLabelVisible: _files.isNotEmpty,
              child: const Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                            children: [
                              SectionHeader(
                                title: l.t('myfile.chatTitle'),
                                subtitle: l.t('myfile.chatSubtitle'),
                              ),
                              if (_messages.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 28,
                                  ),
                                  child: Text(
                                    l.t('myfile.chatEmpty'),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                  ),
                                )
                              else
                                ..._messages.map(_messageBubble),
                            ],
                          ),
                        ),
                ),
                _composer(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(MyFileGuaMessage message) {
    final theme = Theme.of(context);
    final attachmentFile = message.attachmentName == null
        ? null
        : _findFile(message.attachmentName!);
    final time = TimeOfDay.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(message.createdAt),
    ).format(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.attachmentName != null)
              InkWell(
                onTap: attachmentFile == null
                    ? null
                    : () => _open(attachmentFile),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      color: attachmentFile == null
                          ? AppColors.amber
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.attachmentName!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: attachmentFile == null
                              ? AppColors.amber
                              : AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.attachmentName != null && attachmentFile == null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.t('myfile.fileMissing'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.amber,
                  ),
                ),
              ),
            if (message.text.isNotEmpty) ...[
              if (message.attachmentName != null) const SizedBox(height: 6),
              Text(
                message.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 3),
            Text(
              time,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  File? _findFile(String name) {
    for (final file in _files) {
      if (file.uri.pathSegments.last == name) return file;
    }
    return null;
  }

  Widget _composer(L10n l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: const Border(
          top: BorderSide(color: AppColors.surfaceContainerHigh),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: l.t('myfile.attach'),
            onPressed: _addFiles,
            icon: const Icon(Icons.attach_file_rounded),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: l.t('myfile.messageHint'),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: l.t('myfile.send'),
            onPressed: _sendMessage,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class MyFileGuaFilesScreen extends StatefulWidget {
  const MyFileGuaFilesScreen({super.key});

  @override
  State<MyFileGuaFilesScreen> createState() => _MyFileGuaFilesScreenState();
}

class _MyFileGuaFilesScreenState extends State<MyFileGuaFilesScreen> {
  List<File> _files = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await MyFileGua.listFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _open(File file) async {
    final result = await OpenFilex.open(file.path);
    if (!mounted || result.type == ResultType.done) return;
    _toast(result.message);
  }

  Future<void> _delete(File file) async {
    final name = file.uri.pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.t('myfile.deleteTitle')),
        content: Text(ctx.l10n.t('myfile.deleteMessage', {'file': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.t('myfile.cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.t('myfile.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MyFileGua.deleteFile(file);
    await _load();
  }

  IconData _icon(File file) {
    final name = file.path.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(name)) {
      return Icons.image_outlined;
    }
    if (RegExp(r'\.(zip|rar|7z)$').hasMatch(name)) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHighest,
          content: Text(
            message,
            style: const TextStyle(color: AppColors.onSurface),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('myfile.viewFiles'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                ? EmptyState(
                    icon: Icons.folder_outlined,
                    title: l.t('myfile.emptyTitle'),
                    message: l.t('myfile.emptyMessage'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      SectionHeader(
                        title: l.t('myfile.viewFiles'),
                        subtitle: l.t('myfile.subtitle', {
                          'count': '${_files.length}',
                        }),
                      ),
                      ..._files.map((file) {
                        final name = file.uri.pathSegments.last;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: Icon(
                                _icon(file),
                                color: AppColors.primary,
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_size(file.lengthSync())),
                              onTap: () => _open(file),
                              trailing: IconButton(
                                tooltip: l.t('myfile.delete'),
                                onPressed: () => _delete(file),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
