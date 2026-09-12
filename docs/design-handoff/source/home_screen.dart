import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
import 'category_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.libraryStore,
    required this.audioPlaybackService,
  });

  final LibraryStore libraryStore;
  final AudioPlaybackService audioPlaybackService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<PhraseEntry>> _manifestFuture;

  @override
  void initState() {
    super.initState();
    _manifestFuture = widget.libraryStore.manifest();
  }

  void _reload() {
    setState(() {
      _manifestFuture = widget.libraryStore.manifest();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PhraseEntry>>(
      future: _manifestFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final categories = <String>{
          for (final entry in snapshot.data!) entry.category,
        }.toList()
          ..sort();

        if (categories.isEmpty) {
          return const Center(child: Text('No phrases yet.'));
        }

        return GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(16),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            for (final category in categories)
              _CategoryTile(
                category: category,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CategoryScreen(
                        category: category,
                        libraryStore: widget.libraryStore,
                        audioPlaybackService: widget.audioPlaybackService,
                      ),
                    ),
                  );
                  _reload();
                },
              ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            category,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
