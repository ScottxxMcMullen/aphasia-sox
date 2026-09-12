import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/services/api_client.dart';

void main() {
  group('getLibrary', () {
    test('parses the phrase list from the server', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/library');
        return http.Response(
          jsonEncode([
            {'id': '1', 'category': 'Greetings', 'text': 'Hello.', 'checksum': 'x'},
          ]),
          200,
        );
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      final result = await client.getLibrary();

      expect(result, hasLength(1));
      expect(result.first.text, 'Hello.');
    });

    test('throws ApiException on a non-2xx response', () async {
      final mockClient = MockClient((request) async => http.Response('error', 500));
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.getLibrary(), throwsA(isA<ApiException>()));
    });

    test('throws ApiException on a connection error', () async {
      final mockClient = MockClient((request) async => throw Exception('refused'));
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.getLibrary(), throwsA(isA<ApiException>()));
    });

    test('throws ApiException on a malformed JSON response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/library');
        return http.Response('not json', 200);
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.getLibrary(), throwsA(isA<ApiException>()));
    });
  });

  group('getPhraseAudio', () {
    test('returns the raw audio bytes', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/library/audio/p1');
        return http.Response.bytes([1, 2, 3], 200);
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      final bytes = await client.getPhraseAudio('p1');

      expect(bytes, [1, 2, 3]);
    });
  });

  group('addPhrase', () {
    test('posts category and text, returns the saved entry', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/library/phrases');
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(sent, {'category': 'Needs', 'text': 'Help.'});
        return http.Response(
          jsonEncode({'id': 'p2', 'category': 'Needs', 'text': 'Help.', 'checksum': 'y'}),
          200,
        );
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      final entry = await client.addPhrase(category: 'Needs', text: 'Help.');

      expect(entry.id, 'p2');
    });

    test('throws ApiException on a malformed response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/library/phrases');
        return http.Response('invalid json', 200);
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.addPhrase(category: 'Needs', text: 'Help.'), throwsA(isA<ApiException>()));
    });
  });

  group('generateSpeech', () {
    test('posts text, returns raw audio bytes', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/generate');
        expect(jsonDecode(request.body), {'text': 'Hi there.'});
        return http.Response.bytes([9, 9], 200);
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      final bytes = await client.generateSpeech('Hi there.');

      expect(bytes, [9, 9]);
    });

    test('throws ApiException when the server returns 502', () async {
      final mockClient = MockClient((request) async => http.Response('bad', 502));
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.generateSpeech('Hi.'), throwsA(isA<ApiException>()));
    });
  });

  group('timeouts', () {
    // Generating speech blocks server-side until Voicebox finishes, which on a
    // cold engine load takes far longer than a normal request. The fast read
    // endpoints keep the short timeout so a genuinely unreachable server still
    // fails quickly.
    test('generateSpeech waits longer than the short request timeout', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response.bytes([1, 2, 3], 200);
      });
      final client = ApiClient(
        baseUrl: 'http://test',
        client: mockClient,
        timeout: const Duration(milliseconds: 50),
        generateTimeout: const Duration(seconds: 5),
      );

      final bytes = await client.generateSpeech('Hello.');

      expect(bytes, [1, 2, 3]);
    });

    test('addPhrase waits longer than the short request timeout', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response(
          jsonEncode({'id': 'p1', 'category': 'Needs', 'text': 'Help.', 'checksum': 'y'}),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://test',
        client: mockClient,
        timeout: const Duration(milliseconds: 50),
        generateTimeout: const Duration(seconds: 5),
      );

      final entry = await client.addPhrase(category: 'Needs', text: 'Help.');

      expect(entry.id, 'p1');
    });

    test('getLibrary still uses the short timeout', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('[]', 200);
      });
      final client = ApiClient(
        baseUrl: 'http://test',
        client: mockClient,
        timeout: const Duration(milliseconds: 50),
        generateTimeout: const Duration(seconds: 5),
      );

      expect(client.getLibrary(), throwsA(isA<ApiException>()));
    });
  });

  group('ping', () {
    test('hits /health and returns how long the round trip took', () async {
      final paths = <String>[];
      final mockClient = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{"status":"ok"}', 200);
      });
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      final elapsed = await client.ping();

      expect(paths, ['/health']);
      expect(elapsed, isA<Duration>());
      expect(elapsed.isNegative, isFalse);
    });

    test('throws when the server answers with an error status', () async {
      final mockClient =
          MockClient((request) async => http.Response('nope', 503));
      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      expect(client.ping(), throwsA(isA<ApiException>()));
    });

    test('gives up quickly — a ping is not the real work', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response('{"status":"ok"}', 200);
      });
      final client = ApiClient(
        baseUrl: 'http://test',
        client: mockClient,
        pingTimeout: const Duration(milliseconds: 50),
      );

      expect(client.ping(), throwsA(isA<ApiException>()));
    });

    test('its timeout is independent of the generation timeout', () async {
      final client = ApiClient(baseUrl: 'http://test');
      // The whole point of the split: a cold engine load may take a minute,
      // while an unreachable laptop should be known about in seconds.
      expect(client.pingTimeout, lessThan(client.generateTimeout));
      expect(client.pingTimeout, lessThanOrEqualTo(client.timeout));
    });
  });
}
