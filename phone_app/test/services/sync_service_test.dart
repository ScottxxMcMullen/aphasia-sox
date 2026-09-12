import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/library_store.dart';
import 'package:aphasia_app/services/sync_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_service_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloads entries missing locally and skips ones already present', () async {
    final requestedAudioIds = <String>[];
    final mockClient = MockClient((request) async {
      if (request.url.path == '/library') {
        return http.Response(
          jsonEncode([
            {'id': 'p1', 'category': 'Greetings', 'text': 'Hello.', 'checksum': 'a'},
            {'id': 'p2', 'category': 'Needs', 'text': 'Help.', 'checksum': 'b'},
          ]),
          200,
        );
      }
      if (request.url.path.startsWith('/library/audio/')) {
        requestedAudioIds.add(request.url.pathSegments.last);
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });

    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    await libraryStore.saveEntry(
      const PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
      Uint8List.fromList([0]),
    );

    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
    final downloaded = await syncService.sync();

    expect(downloaded, 1);
    expect(requestedAudioIds, ['p2']);
    final manifest = await libraryStore.manifest();
    expect(manifest.map((e) => e.id).toSet(), {'p1', 'p2'});
  });

  test('returns 0 and makes no audio requests when everything is already synced', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/library') {
        return http.Response(
          jsonEncode([
            {'id': 'p1', 'category': 'Greetings', 'text': 'Hello.', 'checksum': 'a'},
          ]),
          200,
        );
      }
      throw Exception('unexpected request: ${request.url}');
    });

    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    await libraryStore.saveEntry(
      const PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
      Uint8List.fromList([0]),
    );

    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
    final downloaded = await syncService.sync();

    expect(downloaded, 0);
  });

  test('does not re-download an entry the user has locally deleted', () async {
    final requestedAudioIds = <String>[];
    final mockClient = MockClient((request) async {
      if (request.url.path == '/library') {
        return http.Response(
          jsonEncode([
            {'id': 'p1', 'category': 'Greetings', 'text': 'Hello.', 'checksum': 'a'},
          ]),
          200,
        );
      }
      if (request.url.path.startsWith('/library/audio/')) {
        requestedAudioIds.add(request.url.pathSegments.last);
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });

    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final libraryStore = LibraryStore(tempDir);
    await libraryStore.saveEntry(
      const PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
      Uint8List.fromList([0]),
    );
    // The user deleted it locally -- the server still lists it, since
    // deletion is local-only and the server has no way to know it happened.
    await libraryStore.markDeleted('p1');

    final syncService = SyncService(apiClient: apiClient, libraryStore: libraryStore);
    final downloaded = await syncService.sync();

    expect(downloaded, 0);
    expect(requestedAudioIds, isEmpty);
    expect(await libraryStore.manifest(), isEmpty);
  });
}
