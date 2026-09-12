import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
import '../theme/sox_tokens.dart';
import '../widgets/category_picker.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.category,
    required this.libraryStore,
    required this.audioPlaybackService,
  });

  final String category;
  final LibraryStore libraryStore;
  final AudioPlaybackService audioPlaybackService;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  // The whole manifest, not just this category's phrases: moving a phrase
  // needs the full list of categories to offer as destinations.
  late Future<List<PhraseEntry>> _manifestFuture;

  /// Moving a phrase used to be a long press on the tile that speaks it.
  /// That put the two apart by 500ms — Flutter's long-press threshold — and
  /// when the long press won, the tap was rejected, so holding a beat too
  /// long spoke nothing and opened a filing dialog instead. Pressing firmly
  /// is what people do under stress, and the screen this happened on most
  /// dangerously was Emergency.
  ///
  /// So moving is a mode now, entered deliberately from the app bar. In
  /// speaking mode a tile does exactly one thing however long it is held.
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _manifestFuture = widget.libraryStore.manifest();
  }

  Future<void> _play(PhraseEntry entry) async {
    final file = widget.libraryStore.audioFileFor(entry.id);
    if (file == null) {
      return;
    }
    await widget.audioPlaybackService.playFile(file);
  }

  Future<void> _move(PhraseEntry entry, List<String> categories) async {
    final destination = await showCategoryPicker(
      context: context,
      categories: categories,
      title: 'Move to which category?',
      exclude: widget.category,
    );
    if (destination == null || !mounted) {
      return;
    }
    await widget.libraryStore.moveEntry(entry.id, destination);

    // One read serves both the "did this empty the category?" check and the
    // rebuild below, so the screen never goes back to disk for something it
    // already has in hand.
    final entries = await widget.libraryStore.manifest();
    final remaining = entries.where((e) => e.category == widget.category);
    if (!mounted) {
      return;
    }
    // After a move the phrase vanishes from the grid the user was looking at.
    // Naming the destination is what makes that legible.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved "${entry.text}" to $destination.')),
    );
    if (remaining.isEmpty) {
      // Categories exist only as labels on phrases, so emptying one deletes
      // it — its tile is already gone from the grid behind this screen.
      // Staying here would leave the user on a dead end.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _manifestFuture = Future.value(entries);
      // One move per visit to the mode. Leaving it on would put the screen
      // one stray tap away from moving a second phrase.
      _moving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text(_moving ? 'Move a phrase' : widget.category),
        actions: [
          IconButton(
            icon: Icon(_moving ? Icons.close : Icons.drive_file_move_outline),
            tooltip: _moving ? 'Done moving' : 'Move a phrase',
            onPressed: () => setState(() => _moving = !_moving),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_moving)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: SoxTokens.majorRule(ink),
                    width: SoxTokens.ruleMajor,
                  ),
                ),
              ),
              child: Text(
                'Tap a phrase to move it. Nothing will be spoken.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PhraseEntry>>(
              future: _manifestFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                final phrases =
                    entries.where((e) => e.category == widget.category).toList();
                final categories = <String>{for (final e in entries) e.category}
                    .toList()
                  ..sort();

                return GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.all(16),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    for (final entry in phrases)
                      _PhraseTile(
                        entry: entry,
                        hasAudio:
                            widget.libraryStore.audioFileFor(entry.id) != null,
                        moving: _moving,
                        onTap: _moving
                            ? () => _move(entry, categories)
                            : () => _play(entry),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhraseTile extends StatelessWidget {
  const _PhraseTile({
    required this.entry,
    required this.hasAudio,
    required this.moving,
    required this.onTap,
  });

  final PhraseEntry entry;
  final bool hasAudio;
  final bool moving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A missing local audio file means an interrupted sync — grey the tile
    // out and disable it rather than silently doing nothing on tap (per the
    // spec's error handling for this case). It stays tappable while moving:
    // it is a real phrase in the manifest, and filing it correctly shouldn't
    // wait on a resync.
    final bool enabled = moving || hasAudio;

    return Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: hasAudio
                  ? null
                  : TextStyle(color: Theme.of(context).disabledColor),
            ),
          ),
        ),
      ),
    );
  }
}
