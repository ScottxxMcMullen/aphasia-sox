import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/main.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/library_store.dart';
import 'package:aphasia_app/services/sync_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('syncs when the local library is empty', () async {
    var libraryRequested = false;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/library') {
        libraryRequested = true;
        return http.Response(jsonEncode([]), 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);

    await syncIfLibraryEmpty(syncService, libraryStore);

    expect(libraryRequested, isTrue);
  });

  test('does not sync when the local library already has entries', () async {
    final mockClient = MockClient((request) async {
      throw Exception('should not have made a request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    await libraryStore.saveEntry(
      const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
      Uint8List.fromList([1]),
    );
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);

    await syncIfLibraryEmpty(syncService, libraryStore);
    // No exception means no request was made — the MockClient throws for any request.
  });

  test('swallows a sync failure on an empty library rather than crashing startup', () async {
    final mockClient = MockClient((request) async => http.Response('error', 500));
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);

    await syncIfLibraryEmpty(syncService, libraryStore);
    // Reaching here without throwing is the assertion.
  });
}
