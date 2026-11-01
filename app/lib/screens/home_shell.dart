import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../services/drople_core.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';
import '../widgets/ui.dart';
import 'backup_screen.dart';
import 'files_screen.dart';
import 'notes_screen.dart';
import 'peers_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final DropleCore _core = DropleCore();
  final DropleNetwork _network = DropleNetwork.shared;
  final DropleFile _files = DropleFile();

  int _index = 0;
  bool _ready = false;
  String? _error;
  bool _networkWarning = false;

  static const _destinations = [
    _Destination('nav.devices', Icons.radar_outlined, Icons.radar_rounded),
    _Destination('nav.files', Icons.folder_outlined, Icons.folder_rounded),
    _Destination(
      'nav.notes',
      Icons.edit_note_outlined,
      Icons.edit_note_rounded,
    ),
    _Destination('nav.backup', Icons.cloud_outlined, Icons.cloud_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _core.init();

      try {
        final docs = await getApplicationDocumentsDirectory();
        final receive = Directory(
          '${docs.path}${Platform.pathSeparator}Drople',
        );
        if (!await receive.exists()) {
          await receive.create(recursive: true);
        }
        _files.setDefaultReceiveDirectory(receive.path);
      } catch (_) {}

      try {
        await _network.start();
      } catch (e) {
        _networkWarning = true;
      }

      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _ready = true;
      });
    }
  }

  Future<void> _selectDestination(int index) async {
    if (index == 3) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final l = context.l10n;
          return AlertDialog(
            icon: Icon(
              Icons.cloud_sync_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text(l.t('home.backupTitle')),
            content: Text(l.t('home.backupMessage')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.t('home.gotIt')),
              ),
            ],
          );
        },
      );
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: _Splash());
    }
    if (_error != null) {
      final l = context.l10n;
      return Scaffold(
        appBar: const AppHeader(),
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: l.t('home.coreError'),
          message: _error!,
          action: FilledButton.icon(
            onPressed: () {
              setState(() {
                _error = null;
                _ready = false;
              });
              _bootstrap();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.t('home.retry')),
          ),
        ),
      );
    }

    final pages = [
      PeersScreen(network: _network, files: _files),
      FilesScreen(files: _files, network: _network),
      NotesScreen(core: _core),
      BackupScreen(),
    ];

    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final body = Column(
          children: [
            if (_networkWarning) _warningBanner(context),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        );

        if (!wide) {
          return Scaffold(
            appBar: const AppHeader(),
            body: body,
            bottomNavigationBar: AppBottomNav(
              items: [
                for (final d in _destinations.take(3))
                  NavItemData(
                    d.icon,
                    l.t(d.label),
                    selectedIcon: d.selectedIcon,
                  ),
              ],
              currentIndex: _index <= 2 ? _index : 0,
              onTap: _selectDestination,
            ),
          );
        }

        return Scaffold(
          appBar: const AppHeader(),
          body: Row(
            children: [
              AppSideNav(
                items: [
                  for (final d in _destinations)
                    NavItemData(
                      d.icon,
                      l.t(d.label),
                      selectedIcon: d.selectedIcon,
                    ),
                ],
                currentIndex: _index,
                onTap: _selectDestination,
              ),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }

  Widget _warningBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.amber.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppColors.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.t('home.networkWarning'),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 11.5),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _networkWarning = false),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(size: 78),
          const SizedBox(height: 22),
          Text('Drople', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('home.preparing'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 26),
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
