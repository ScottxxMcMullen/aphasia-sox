import 'dart:typed_data';

import 'api_client.dart';
import 'library_store.dart';

class SyncService {
  SyncService({required this.apiClient, required this.libraryStore});

  final ApiClient apiClient;
  final LibraryStore libraryStore;

  /// Fetches the server's phrase library and downloads any entries not
  /// already present locally (diffed by id). Returns the number of newly
  /// downloaded phrases. Entries the user has locally deleted (tracked via
  /// [LibraryStore.markDeleted]/[LibraryStore.deletedIds]) are skipped even
  /// though the server still lists them, since deletion is local-only and
  /// the server has no way to know it happened.
  Future<int> sync() async {
    final remoteEntries = await apiClient.getLibrary();
    final localEntries = await libraryStore.manifest();
    final localIds = localEntries.map((e) => e.id).toSet();
    final deletedIds = await libraryStore.deletedIds();

    var downloaded = 0;
    for (final entry in remoteEntries) {
      if (localIds.contains(entry.id) || deletedIds.contains(entry.id)) {
        continue;
      }
      final Uint8List audio = await apiClient.getPhraseAudio(entry.id);
      await libraryStore.saveEntry(entry, audio);
      downloaded++;
    }
    return downloaded;
  }
}
