import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/say_something_screen.dart';
import 'services/api_client.dart';
import 'services/audio_playback_service.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';
import 'services/sync_service.dart';
import 'theme/sox_theme.dart';
import 'theme/sox_tokens.dart';

/// The home server's address, supplied at build time rather than written
/// here, so the source carries no private hostname. Build with
/// `build-release.ps1`, which reads the gitignored `dart_defines.json`
/// (`dart_defines.example.json` shows its shape).
///
/// Built without it, the app still installs and every saved phrase still
/// plays. Only live speech and sync fail — and Say Something says so within
/// seconds rather than hanging.
const String kServerBaseUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:8420',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  final dataDir = Directory('${appDir.path}/aphasia_library');

  final apiClient = ApiClient(baseUrl: kServerBaseUrl);
  final libraryStore = LibraryStore(dataDir);
  final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
  final audioPlaybackService = AudioplayersPlaybackService();
  final settingsStore = SettingsStore();

  // Render immediately (Home shows "No phrases yet." while empty) rather
  // than blocking first paint on the first-launch sync, which can involve
  // dozens of sequential HTTP round trips (see SyncService.sync). The
  // sync-if-empty check itself now runs from AppShell.initState, un-awaited.
  runApp(AphasiaApp(
    apiClient: apiClient,
    libraryStore: libraryStore,
    syncService: syncService,
    audioPlaybackService: audioPlaybackService,
    settingsStore: settingsStore,
  ));
}

/// Syncs only when the local library is empty (first launch). Per the
/// spec, this app has no background/automatic sync — an existing local
/// library is left alone until the user taps "Sync library" on the
/// Library screen, or saves a phrase via Say Something or Library.
Future<void> syncIfLibraryEmpty(SyncService syncService, LibraryStore libraryStore) async {
  final existing = await libraryStore.manifest();
  if (existing.isNotEmpty) {
    return;
  }
  try {
    await syncService.sync();
  } catch (_) {
    // No local library yet and the server's unreachable at launch — the
    // Library screen's manual "Sync" button covers this once
    // connectivity is available.
  }
}

class AphasiaApp extends StatefulWidget {
  const AphasiaApp({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.syncService,
    required this.audioPlaybackService,
    required this.settingsStore,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;
  final AudioPlaybackService audioPlaybackService;
  final SettingsStore settingsStore;

  @override
  State<AphasiaApp> createState() => _AphasiaAppState();
}

class _AphasiaAppState extends State<AphasiaApp> {
  // Defaults to system until the stored choice arrives: the first frame must
  // not wait on disk.
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    widget.settingsStore.themeMode().then((mode) {
      if (mounted) {
        setState(() => _themeMode = mode);
      }
    });
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.settingsStore.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aphasia SOX',
      theme: soxLight(),
      darkTheme: soxDark(),
      themeMode: _themeMode,
      home: AppShell(
        apiClient: widget.apiClient,
        libraryStore: widget.libraryStore,
        syncService: widget.syncService,
        audioPlaybackService: widget.audioPlaybackService,
        settingsStore: widget.settingsStore,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
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
    required this.settingsStore,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;
  final AudioPlaybackService audioPlaybackService;
  final SettingsStore settingsStore;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

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
        title: const Text('Aphasia SOX'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Library',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LibraryScreen(
                    apiClient: widget.apiClient,
                    libraryStore: widget.libraryStore,
                    syncService: widget.syncService,
                    settingsStore: widget.settingsStore,
                    themeMode: widget.themeMode,
                    onThemeModeChanged: widget.onThemeModeChanged,
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
      // A bar rather than a FAB: a FAB overlaps the last row and hides part
      // of it, which matters now that the last row is a category rather than
      // dead space. The 2px top rule makes the region read as pinned instead
      // of floating over the list.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: SoxTokens.majorRule(Theme.of(context).colorScheme.onSurface),
              width: SoxTokens.ruleMajor,
            ),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 76,
          child: ElevatedButton.icon(
            onPressed: _openSaySomething,
            icon: const Icon(Icons.mic_none, size: 26),
            label: const Text('SAY SOMETHING'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(76),
              textStyle: const TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: 0.22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSaySomething() async {
    final categories = {
      for (final entry in await widget.libraryStore.manifest()) entry.category,
    }.toList()
      ..sort();
    if (!mounted) {
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
  }
}
