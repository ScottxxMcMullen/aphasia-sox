import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/api_client.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';
import '../services/sync_service.dart';
import '../theme/sox_tokens.dart';
import '../widgets/category_picker.dart';

/// The caregiver's maintenance screen. Density is deliberately higher here
/// than anywhere else in the app — 15px rows, 12px headers — because this is
/// the one screen read at a desk rather than mid-sentence in a restaurant.
/// The speaking screens' size floors do not apply.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.syncService,
    required this.settingsStore,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;
  final SettingsStore settingsStore;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// How long ago the library last synced, in words. Built from the stored
  /// timestamp, never a placeholder — "Never synced" is a real state.
  static String relativeSyncFor(DateTime? at) {
    if (at == null) return 'Never synced';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'Synced just now';
    if (d.inMinutes < 60) return 'Synced ${d.inMinutes} min ago';
    if (d.inHours < 24) {
      return 'Synced ${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    }
    return 'Synced ${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  late Future<List<PhraseEntry>> _manifestFuture;
  String _query = '';
  String? _statusMessage;
  bool _isBusy = false;
  DateTime? _lastSyncedAt;

  @override
  void initState() {
    super.initState();
    _manifestFuture = widget.libraryStore.manifest();
    widget.settingsStore.lastSyncedAt().then((at) {
      if (mounted) {
        setState(() => _lastSyncedAt = at);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _manifestFuture = widget.libraryStore.manifest();
    });
  }

  /// Category name -> its phrases, ordered by count descending then
  /// alphabetically — the same ranking the home screen uses, so the two
  /// screens never disagree about which category comes first.
  Map<String, List<PhraseEntry>> _grouped(List<PhraseEntry> entries) {
    final q = _query.trim().toLowerCase();
    // Searching matches the category name as well as the phrase, so typing
    // "emerg" finds the whole category rather than nothing.
    final filtered = q.isEmpty
        ? entries
        : entries
            .where((e) =>
                e.text.toLowerCase().contains(q) ||
                e.category.toLowerCase().contains(q))
            .toList();

    final Map<String, List<PhraseEntry>> groups = {};
    for (final entry in filtered) {
      groups.putIfAbsent(entry.category, () => []).add(entry);
    }

    final keys = groups.keys.toList()
      ..sort((a, b) {
        final byCount = groups[b]!.length.compareTo(groups[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return {for (final k in keys) k: groups[k]!};
  }

  Future<void> _addPhrase() async {
    final text = await _promptForPhrase();
    if (text == null || !mounted) {
      return;
    }
    // The existing picker, not a second category input: it already folds
    // "church" into an existing "Church" and offers "New category...".
    final categories = <String>{
      for (final e in await widget.libraryStore.manifest()) e.category,
    }.toList()
      ..sort();
    if (!mounted) return;
    final category = await showCategoryPicker(
      context: context,
      categories: categories,
      title: 'Save to which category?',
    );
    if (category == null || !mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final entry =
          await widget.apiClient.addPhrase(category: category, text: text);
      final audio = await widget.apiClient.getPhraseAudio(entry.id);
      await widget.libraryStore.saveEntry(entry, audio);
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Added "${entry.text}" to $category.';
      });
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not add phrase: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<String?> _promptForPhrase() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a phrase'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'What it should say'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _delete(String id) async {
    try {
      await widget.libraryStore.markDeleted(id);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _sync() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final added = await widget.syncService.sync();
      await widget.settingsStore.markSynced();
      final at = await widget.settingsStore.lastSyncedAt();
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Sync complete: $added new phrase(s).';
        _lastSyncedAt = at;
      });
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Sync failed: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: FutureBuilder<List<PhraseEntry>>(
                future: _manifestFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final entries = snapshot.data!;
                  final categories =
                      entries.map((e) => e.category).toSet().length;
                  return Text(
                    '${entries.length} phrases · $categories categories',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, ink),
          Expanded(
            child: FutureBuilder<List<PhraseEntry>>(
              future: _manifestFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final groups = _grouped(snapshot.data!);
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      // Deliberately not Home's "No phrases yet.": this is
                      // the caregiver's screen, and the two are told apart
                      // both by whoever is reading and by the tests.
                      _query.trim().isEmpty
                          ? 'The library is empty. Sync or add a phrase.'
                          : 'No phrases match "${_query.trim()}".',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                // One flat ListView of interleaved headers and rows rather
                // than nested scrollables.
                final children = <Widget>[];
                var first = true;
                for (final group in groups.entries) {
                  children.add(_CategoryHeader(
                    category: group.key,
                    count: group.value.length,
                    isFirst: first,
                  ));
                  first = false;
                  for (final entry in group.value) {
                    children.add(_PhraseRow(
                      entry: entry,
                      hasAudio:
                          widget.libraryStore.audioFileFor(entry.id) != null,
                      onDelete: () => _delete(entry.id),
                    ));
                  }
                }
                children.add(_AppearanceBlock(
                  mode: widget.themeMode,
                  onChanged: widget.onThemeModeChanged,
                ));

                return ListView(children: children);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Color ink) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: SoxTokens.majorRule(ink),
            width: SoxTokens.ruleMajor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search phrases',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // The one filled button on the screen.
              ElevatedButton(
                onPressed: _isBusy ? null : _addPhrase,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Add a phrase'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isBusy ? null : _sync,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size(0, 48),
                  side: BorderSide(
                    color: SoxTokens.majorRule(ink),
                    width: SoxTokens.ruleMajor,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text('Sync'),
              ),
              const Spacer(),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      LibraryScreen.relativeSyncFor(_lastSyncedAt),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_statusMessage != null)
                      Text(
                        _statusMessage!,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.count,
    required this.isFirst,
  });

  final String category;
  final int count;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: dark
          ? SoxTokens.darkInk.withValues(alpha: 0.06)
          : SoxTokens.ink.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      foregroundDecoration: BoxDecoration(
        border: Border(
          top: isFirst
              ? BorderSide.none
              : BorderSide(
                  color: SoxTokens.majorRule(ink),
                  width: SoxTokens.ruleMajor,
                ),
          bottom: BorderSide(
            color: SoxTokens.minorRule(ink),
            width: SoxTokens.ruleMinor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            category.toUpperCase(),
            style: TextStyle(
              fontFamily: SoxTokens.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1.2,
              color: ink,
            ),
          ),
          const Spacer(),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.entry,
    required this.hasAudio,
    required this.onDelete,
  });

  final PhraseEntry entry;
  final bool hasAudio;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color grey = dark ? SoxTokens.greyOnDark : SoxTokens.greyOnPaper;
    final Color error = Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: SoxTokens.minorRule(ink),
            width: SoxTokens.ruleMinor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: hasAudio ? ink : grey),
            ),
          ),
          if (!hasAudio) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: error, width: SoxTokens.ruleMinor),
              ),
              child: Text(
                'no audio',
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.4,
                  color: error,
                ),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 22),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// At the bottom on purpose: set once and never again, and it must not take
/// space above the library it is a footnote to.
class _AppearanceBlock extends StatelessWidget {
  const _AppearanceBlock({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final Color ground = Theme.of(context).colorScheme.surface;

    Widget option(String label, ThemeMode value) {
      final bool selected = mode == value;
      return Expanded(
        child: Material(
          color: selected ? ink : null,
          type: selected ? MaterialType.canvas : MaterialType.transparency,
          child: InkWell(
            onTap: () => onChanged(value),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: ink, width: SoxTokens.ruleMajor),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.4,
                  color: selected ? ground : ink,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: SoxTokens.majorRule(ink),
            width: SoxTokens.ruleMajor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'APPEARANCE',
            style: TextStyle(
              fontFamily: SoxTokens.fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1.3,
              color: SoxTokens.muted(ink),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              option('Light', ThemeMode.light),
              option('Dark', ThemeMode.dark),
              option('System', ThemeMode.system),
            ],
          ),
        ],
      ),
    );
  }
}
