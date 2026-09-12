import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/phrase_entry.dart';

class LibraryStore {
  LibraryStore(this.dataDir);

  final Directory dataDir;

  File get _manifestFile => File('${dataDir.path}/manifest.json');
  File get _deletedIdsFile => File('${dataDir.path}/deleted_ids.json');
  Directory get _audioDir => Directory('${dataDir.path}/audio');

  Future<List<PhraseEntry>> manifest() async {
    if (!await _manifestFile.exists()) {
      return [];
    }
    try {
      final contents = await _manifestFile.readAsString();
      final list = jsonDecode(contents) as List<dynamic>;
      return list
          .map((e) => PhraseEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Treat corrupt or malformed manifest as empty library
      return [];
    }
  }

  Future<void> saveEntry(PhraseEntry entry, Uint8List audioBytes) async {
    await _audioDir.create(recursive: true);
    final audioFile = File('${_audioDir.path}/${entry.id}.wav');
    await audioFile.writeAsBytes(audioBytes);

    final entries = await manifest();
    final withoutExisting = entries.where((e) => e.id != entry.id).toList();
    withoutExisting.add(entry);

    await _writeManifest(withoutExisting);
  }

  Future<void> deleteEntry(String id) async {
    final entries = await manifest();
    await _writeManifest(entries.where((e) => e.id != id).toList());

    final audioFile = File('${_audioDir.path}/$id.wav');
    if (await audioFile.exists()) {
      await audioFile.delete();
    }
  }

  /// Reassigns one phrase to [category], rewriting it in place so the
  /// manifest keeps its existing order. The audio file is untouched — a
  /// category is only a label on the entry, so a move costs nothing and
  /// leaves the phrase playable offline throughout.
  ///
  /// Unknown ids are ignored, matching [deleteEntry].
  ///
  /// Like deletion, this is local-only. Sync is add-only (it skips any id
  /// already present, see [SyncService.sync]), so a move survives every
  /// later sync — but the server never learns about it, and a reinstall
  /// re-downloads the phrase under its original category.
  Future<void> moveEntry(String id, String category) async {
    final entries = await manifest();
    final index = entries.indexWhere((e) => e.id == id);
    if (index == -1) {
      return;
    }
    final existing = entries[index];
    entries[index] = PhraseEntry(
      id: existing.id,
      category: category,
      text: existing.text,
      checksum: existing.checksum,
    );
    await _writeManifest(entries);
  }

  /// Atomic write: write to a temp file, then rename over the manifest, so
  /// an interrupted write can never leave a half-written manifest behind.
  Future<void> _writeManifest(List<PhraseEntry> entries) async {
    await _manifestFile.parent.create(recursive: true);
    final tempFile = File('${_manifestFile.path}.tmp');
    await tempFile.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    await tempFile.rename(_manifestFile.path);
  }

  /// Removes an entry's manifest record and audio file, then records its id
  /// as a tombstone so a later [SyncService.sync] doesn't re-download it
  /// (the server has no concept of deletion; sync diffs its list against
  /// the local manifest purely by id, so without a tombstone a deleted
  /// phrase would silently reappear on the next sync). Use [deleteEntry]
  /// directly instead when tombstone tracking isn't wanted (e.g. tests
  /// exercising deletion in isolation).
  Future<void> markDeleted(String id) async {
    await deleteEntry(id);
    final ids = await deletedIds();
    ids.add(id);
    await _writeDeletedIds(ids);
  }

  /// Returns the set of ids that have been [markDeleted], i.e. deletions
  /// that should not be undone by a future sync. Empty if nothing has been
  /// deleted (or the tombstone file doesn't exist yet).
  Future<Set<String>> deletedIds() async {
    if (!await _deletedIdsFile.exists()) {
      return {};
    }
    try {
      final contents = await _deletedIdsFile.readAsString();
      final list = jsonDecode(contents) as List<dynamic>;
      return list.map((e) => e as String).toSet();
    } catch (e) {
      // Treat a corrupt or malformed tombstone file as no tombstones,
      // consistent with manifest()'s handling of corrupt JSON.
      return {};
    }
  }

  Future<void> _writeDeletedIds(Set<String> ids) async {
    await _deletedIdsFile.parent.create(recursive: true);
    final tempFile = File('${_deletedIdsFile.path}.tmp');
    await tempFile.writeAsString(jsonEncode(ids.toList()));
    await tempFile.rename(_deletedIdsFile.path);
  }

  File? audioFileFor(String id) {
    final file = File('${_audioDir.path}/$id.wav');
    return file.existsSync() ? file : null;
  }
}
