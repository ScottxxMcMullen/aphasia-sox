import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/main.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/library_store.dart';
import 'package:aphasia_app/services/settings_store.dart';
import 'package:aphasia_app/services/sync_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    await syncIfLibraryEmpty(syncService, libraryStore, SettingsStore());

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

    await syncIfLibraryEmpty(syncService, libraryStore, SettingsStore());
    // No exception means no request was made — the MockClient throws for any request.
  });

  test('swallows a sync failure on an empty library rather than crashing startup', () async {
    final mockClient = MockClient((request) async => http.Response('error', 500));
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);

    await syncIfLibraryEmpty(syncService, libraryStore, SettingsStore());
    // Reaching here without throwing is the assertion.
  });

  test('a first-launch sync is recorded, so the Library does not claim never',
      () async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/library') {
        return http.Response(
          jsonEncode([
            {'id': '1', 'category': 'Greetings', 'text': 'Hello.', 'checksum': 'a'},
          ]),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
    final settings = SettingsStore();

    expect(await settings.lastSyncedAt(), isNull);

    await syncIfLibraryEmpty(syncService, libraryStore, settings);

    // The bug this pins: the automatic first-launch sync used to leave no
    // trace, so the Library reported "Never synced" over a library that had
    // plainly just synced.
    expect(await settings.lastSyncedAt(), isNotNull);
    expect((await libraryStore.manifest()), hasLength(1));
  });

  test('a failed first-launch sync records nothing', () async {
    final mockClient = MockClient((request) async => http.Response('error', 500));
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
    final settings = SettingsStore();

    await syncIfLibraryEmpty(syncService, libraryStore, settings);

    // "Never synced" is the truth here, and must stay the truth.
    expect(await settings.lastSyncedAt(), isNull);
  });
}
