import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
import '../widgets/category_picker.dart';

class SaySomethingScreen extends StatefulWidget {
  const SaySomethingScreen({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.audioPlaybackService,
    required this.categories,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final AudioPlaybackService audioPlaybackService;
  final List<String> categories;

  @override
  State<SaySomethingScreen> createState() => _SaySomethingScreenState();
}

class _SaySomethingScreenState extends State<SaySomethingScreen> {
  final _textController = TextEditingController();
  Uint8List? _lastAudio;
  String? _lastText;
  String? _errorMessage;
  bool _isBusy = false;

  Future<void> _speak() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final audio = await widget.apiClient.generateSpeech(text);
      final tempFile = File('${Directory.systemTemp.path}/say_something_preview.wav');
      await tempFile.writeAsBytes(audio);
      await widget.audioPlaybackService.playFile(tempFile);
      if (!mounted) return;
      setState(() {
        _lastAudio = audio;
        _lastText = text;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not reach the server: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _saveToLibrary(String category) async {
    final text = _lastText;
    if (text == null) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final entry = await widget.apiClient.addPhrase(category: category, text: text);
      final audio = await widget.apiClient.getPhraseAudio(entry.id);
      await widget.libraryStore.saveEntry(entry, audio);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $category.')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not save: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _showSaveDialog() async {
    final category = await showCategoryPicker(
      context: context,
      categories: widget.categories,
      title: 'Save to which category?',
    );
    if (category == null || !mounted) {
      return;
    }
    await _saveToLibrary(category);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Say Something')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              decoration: const InputDecoration(hintText: 'Type what you want to say'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isBusy ? null : _speak,
              // A cold Voicebox engine load can take the better part of a
              // minute. Without this the button just goes dead and the app
              // reads as broken.
              child: _isBusy
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Working...'),
                      ],
                    )
                  : const Text('Speak'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            if (_lastAudio != null && _errorMessage == null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isBusy ? null : _showSaveDialog,
                child: const Text('Save to library'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
