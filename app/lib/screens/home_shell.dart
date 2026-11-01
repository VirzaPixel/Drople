import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/drople_core.dart';
import '../services/drople_file.dart';
import '../services/drople_network.dart';
import '../services/drople_sync.dart';
import '../theme/app_theme.dart';
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
  final DropleSync _sync = DropleSync();
  final DropleFile _files = DropleFile();

  int _index = 0;
  bool _ready = false;
  String? _error;
  String? _networkWarning;

  static const _destinations = [
    _Destination('Catatan', Icons.edit_note_rounded, Icons.edit_note_outlined),
    _Destination('Perangkat', Icons.devices_rounded, Icons.devices_outlined),
    _Destination('File', Icons.folder_rounded, Icons.folder_outlined),
    _Destination('Backup', Icons.cloud_rounded, Icons.cloud_outlined),
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
        final receive = Directory('${docs.path}${Platform.pathSeparator}Drople');
        if (!await receive.exists()) {
          await receive.create(recursive: true);
        }
        _files.setDefaultReceiveDirectory(receive.path);
      } catch (_) {}

      try {
        await _network.start();
      } catch (e) {
        _networkWarning = 'Jaringan P2P belum aktif. Catatan tetap bisa dipakai offline.';
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

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: _Splash());
    }
    if (_error != null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Core gagal dimuat',
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
            label: const Text('Coba Lagi'),
          ),
        ),
      );
    }

    final pages = [
      NotesScreen(core: _core),
      PeersScreen(network: _network, sync: _sync, files: _files),
      FilesScreen(files: _files, network: _network),
      BackupScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final body = Column(
          children: [
            if (_networkWarning != null) _warningBanner(context),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: pages,
              ),
            ),
          ],
        );

        if (!wide) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations
                  .map(
                    (d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ),
                  )
                  .toList(),
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: BrandMark(size: 42),
                ),
                destinations: _destinations
                    .map(
                      (d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
              ),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
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
            const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _networkWarning!,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 11.5),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _networkWarning = null),
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
            'Menyiapkan ruang kerjamu',
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
