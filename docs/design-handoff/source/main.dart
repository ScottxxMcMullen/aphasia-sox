import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'screens/manage_screen.dart';
import 'screens/say_something_screen.dart';
import 'services/api_client.dart';
import 'services/audio_playback_service.dart';
import 'services/library_store.dart';
import 'services/sync_service.dart';

const String kServerBaseUrl = 'http://your-machine.your-tailnet.ts.net:8420';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  final dataDir = Directory('${appDir.path}/aphasia_library');

  final apiClient = ApiClient(baseUrl: kServerBaseUrl);
  final libraryStore = LibraryStore(dataDir);
  final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
  final audioPlaybackService = AudioplayersPlaybackService();

  // Render immediately (Home shows "No phrases yet." while empty) rather
  // than blocking first paint on the first-launch sync, which can involve
  // dozens of sequential HTTP round trips (see SyncService.sync). The
  // sync-if-empty check itself now runs from AppShell.initState, un-awaited.
  runApp(AphasiaApp(
    apiClient: apiClient,
    libraryStore: libraryStore,
    syncService: syncService,
    audioPlaybackService: audioPlaybackService,
  ));
}

/// Syncs only when the local library is empty (first launch). Per the
/// spec, this app has no background/automatic sync — an existing local
/// library is left alone until the user taps "Sync library" on the
/// Manage screen, or saves a phrase via Say Something/Manage-add.
Future<void> syncIfLibraryEmpty(SyncService syncService, LibraryStore libraryStore) async {
  final existing = await libraryStore.manifest();
  if (existing.isNotEmpty) {
    return;
  }
  try {
    await syncService.sync();
  } catch (_) {
    // No local library yet and the server's unreachable at launch — the
    // Manage screen's manual "Sync library" button covers this once
    // connectivity is available.
  }
}

class AphasiaApp extends StatelessWidget {
  const AphasiaApp({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.syncService,
    required this.audioPlaybackService,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;
  final AudioPlaybackService audioPlaybackService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aphasia App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: AppShell(
        apiClient: apiClient,
        libraryStore: libraryStore,
        syncService: syncService,
        audioPlaybackService: audioPlaybackService,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.syncService,
    required this.audioPlaybackService,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;
  final AudioPlaybackService audioPlaybackService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Bumped whenever Home's data might be stale (after returning from Manage
  // or Say Something, or after the initial sync-if-empty completes) so that
  // keying HomeScreen with it below forces a full reinitialize, including
  // its initState's manifest() call.
  int _libraryRevision = 0;

  @override
  void initState() {
    super.initState();
    // Un-awaited: this is the one-time first-launch sync-if-empty check,
    // moved here from main() so it no longer blocks first paint. Its own
    // "only sync when empty" logic still lives in syncIfLibraryEmpty.
    syncIfLibraryEmpty(widget.syncService, widget.libraryStore).then((_) {
      if (!mounted) return;
      setState(() => _libraryRevision++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aphasia App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Manage',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManageScreen(
                    apiClient: widget.apiClient,
                    libraryStore: widget.libraryStore,
                    syncService: widget.syncService,
                  ),
                ),
              );
              if (mounted) {
                setState(() => _libraryRevision++);
              }
            },
          ),
        ],
      ),
      body: HomeScreen(
        key: ValueKey(_libraryRevision),
        libraryStore: widget.libraryStore,
        audioPlaybackService: widget.audioPlaybackService,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.mic),
        label: const Text('Say Something'),
        onPressed: () async {
          final categories = {
            for (final entry in await widget.libraryStore.manifest()) entry.category,
          }.toList()
            ..sort();
          if (!context.mounted) {
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SaySomethingScreen(
                apiClient: widget.apiClient,
                libraryStore: widget.libraryStore,
                audioPlaybackService: widget.audioPlaybackService,
                categories: categories,
              ),
            ),
          );
          if (mounted) {
            setState(() => _libraryRevision++);
          }
        },
      ),
    );
  }
}
