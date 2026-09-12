import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/phrase_entry.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => 'ApiException: $message';
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.generateTimeout = const Duration(seconds: 90),
    this.pingTimeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Applies to the fast read endpoints, so a genuinely unreachable server
  /// fails quickly instead of leaving the user waiting.
  final Duration timeout;

  /// Applies to the two endpoints that block server-side until Voicebox has
  /// finished generating speech. Warm, generation takes about a second; on a
  /// cold engine load it can take a minute, which the short timeout would cut
  /// off even though the server goes on to succeed.
  final Duration generateTimeout;

  /// Applies to [ping] only. Deliberately short: a ping is not the real work,
  /// and its whole purpose is to fail fast when the laptop is not there.
  final Duration pingTimeout;

  /// Cheap round-trip check, so the screen can tell "the laptop is asleep"
  /// apart from "the model is still loading". The two need different words:
  /// one is fixed by going and waking a machine, the other by waiting.
  ///
  /// Returns how long the round trip took, which is worth showing — it is a
  /// real measurement rather than a guess at progress.
  Future<Duration> ping() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response =
          await _client.get(Uri.parse('$baseUrl/health')).timeout(pingTimeout);
      _checkStatus(response, '/health');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('request to /health failed: $e');
    }
    return stopwatch.elapsed;
  }

  Future<List<PhraseEntry>> getLibrary() async {
    try {
      final response = await _get('/library');
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => PhraseEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('failed to parse /library response: $e');
    }
  }

  Future<Uint8List> getPhraseAudio(String id) async {
    final response = await _get('/library/audio/$id');
    return response.bodyBytes;
  }

  Future<PhraseEntry> addPhrase({required String category, required String text}) async {
    try {
      final response = await _post(
        '/library/phrases',
        body: jsonEncode({'category': category, 'text': text}),
        timeoutOverride: generateTimeout,
      );
      return PhraseEntry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('failed to parse /library/phrases response: $e');
    }
  }

  Future<Uint8List> generateSpeech(String text) async {
    final response = await _post(
      '/generate',
      body: jsonEncode({'text': text}),
      timeoutOverride: generateTimeout,
    );
    return response.bodyBytes;
  }

  Future<http.Response> _get(String path) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl$path')).timeout(timeout);
      _checkStatus(response, path);
      return response;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('request to $path failed: $e');
    }
  }

  Future<http.Response> _post(
    String path, {
    required String body,
    Duration? timeoutOverride,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeoutOverride ?? timeout);
      _checkStatus(response, path);
      return response;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('request to $path failed: $e');
    }
  }

  void _checkStatus(http.Response response, String path) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('server returned ${response.statusCode} for $path');
    }
  }
}
