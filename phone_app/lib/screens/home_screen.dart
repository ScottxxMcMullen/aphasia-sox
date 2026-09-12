import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
import '../theme/sox_tokens.dart';
import 'category_screen.dart';

/// Emergency is not ranked with the others — it is pinned above the scroll.
const String kEmergency = 'Emergency';

/// Row metrics by phrase count. Five steps: the ramp is a rank, not a
/// measurement. A continuous scale would produce sizes a point apart, which
/// reads as a mistake rather than an order.
({double fontSize, double minHeight}) rowMetrics(int count) {
  if (count >= 9) return (fontSize: 36, minHeight: 104);
  if (count == 8) return (fontSize: 32, minHeight: 96);
  if (count == 7) return (fontSize: 29, minHeight: 88);
  if (count == 6) return (fontSize: 27, minHeight: 82);
  return (fontSize: 25, minHeight: 76);
}

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

  Future<void> _openCategory(BuildContext context, String category) async {
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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PhraseEntry>>(
      future: _manifestFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final Map<String, int> counts = <String, int>{};
        for (final entry in snapshot.data!) {
          counts.update(entry.category, (n) => n + 1, ifAbsent: () => 1);
        }

        if (counts.isEmpty) {
          return const Center(child: Text('No phrases yet.'));
        }

        final bool hasEmergency = counts.containsKey(kEmergency);
        // Ties break alphabetically so the order is stable across syncs —
        // several categories sit at the same count, and they must not shuffle
        // when the library reloads.
        final List<MapEntry<String, int>> ranked = counts.entries
            .where((e) => e.key != kEmergency)
            .toList()
          ..sort((a, b) {
            final int byCount = b.value.compareTo(a.value);
            return byCount != 0 ? byCount : a.key.compareTo(b.key);
          });

        return Column(
          children: [
            if (hasEmergency)
              _EmergencyBar(onTap: () => _openCategory(context, kEmergency)),
            Expanded(
              // builder rather than a children list: the row list is short
              // today but the library grows, and the pinned bar means the
              // scroll view no longer sizes itself.
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: ranked.length,
                itemBuilder: (context, i) => _CategoryRow(
                  // Names the row for tests: a category's name also appears
                  // as a subtitle on the Library screen, so text alone cannot
                  // tell the two apart while a route transition has both in
                  // the tree.
                  key: ValueKey('category-${ranked[i].key}'),
                  category: ranked[i].key,
                  count: ranked[i].value,
                  onTap: () => _openCategory(context, ranked[i].key),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Emergency: a solid block directly under the app bar, above the scroll,
/// always on screen. With eleven categories an alphabetical grid put it
/// second by accident and gave it the same weight as Small Talk.
class _EmergencyBar extends StatelessWidget {
  const _EmergencyBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color paper = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: SoxTokens.red,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'EMERGENCY',
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1,
                  letterSpacing: -0.32,
                  color: paper,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward, size: 26, color: paper),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.count,
    required this.onTap,
  });

  final String category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = rowMetrics(count);
    final Color ink = Theme.of(context).colorScheme.onSurface;

    // The row carries its own Material so the ink splash does not depend on
    // an ancestor it has no say over — the tile this replaced got one from
    // its Card. Transparent, so the ground still shows through.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.minHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: SoxTokens.majorRule(ink),
                width: SoxTokens.ruleMajor,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  style: TextStyle(
                    fontFamily: SoxTokens.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: metrics.fontSize,
                    height: 1.02,
                    letterSpacing: -0.02 * metrics.fontSize,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Information for whoever maintains the library, not for the
              // speaker. It must never compete with the name.
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: SoxTokens.muted(ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
