import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
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
    // A long-press is easy to trigger by accident, and after a move the
    // phrase simply vanishes from the grid he was looking at. Naming the
    // destination is what makes that legible.
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: FutureBuilder<List<PhraseEntry>>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          final phrases = entries.where((e) => e.category == widget.category).toList();
          final categories = <String>{for (final e in entries) e.category}.toList()..sort();

          return GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              for (final entry in phrases)
                _PhraseTile(
                  entry: entry,
                  hasAudio: widget.libraryStore.audioFileFor(entry.id) != null,
                  onTap: () => _play(entry),
                  onLongPress: () => _move(entry, categories),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhraseTile extends StatelessWidget {
  const _PhraseTile({
    required this.entry,
    required this.hasAudio,
    required this.onTap,
    required this.onLongPress,
  });

  final PhraseEntry entry;
  final bool hasAudio;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        // A missing local audio file means an interrupted sync — grey the
        // tile out and disable it rather than silently doing nothing on
        // tap (per the spec's error handling for this case).
        onTap: hasAudio ? onTap : null,
        // Long-press still works on a silent tile: it is a real phrase in
        // the manifest, and filing it correctly shouldn't wait on a resync.
        onLongPress: onLongPress,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: hasAudio ? null : TextStyle(color: Theme.of(context).disabledColor),
            ),
          ),
        ),
      ),
    );
  }
}
