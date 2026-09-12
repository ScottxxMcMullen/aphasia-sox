import 'package:flutter/material.dart';

import '../models/phrase_entry.dart';
import '../services/api_client.dart';
import '../services/library_store.dart';
import '../services/sync_service.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({
    super.key,
    required this.apiClient,
    required this.libraryStore,
    required this.syncService,
  });

  final ApiClient apiClient;
  final LibraryStore libraryStore;
  final SyncService syncService;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  final _categoryController = TextEditingController();
  final _textController = TextEditingController();
  late Future<List<PhraseEntry>> _manifestFuture;
  String? _statusMessage;
  bool _isBusy = false;

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

  Future<void> _addPhrase() async {
    final category = _categoryController.text.trim();
    final text = _textController.text.trim();
    if (category.isEmpty || text.isEmpty) {
      return;
    }
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final entry = await widget.apiClient.addPhrase(category: category, text: text);
      final audio = await widget.apiClient.getPhraseAudio(entry.id);
      await widget.libraryStore.saveEntry(entry, audio);
      if (!mounted) return;
      _categoryController.clear();
      _textController.clear();
      setState(() {
        _statusMessage = 'Added "${entry.text}" to $category.';
      });
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not add phrase: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.libraryStore.markDeleted(id);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _sync() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final added = await widget.syncService.sync();
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Sync complete: $added new phrase(s).';
      });
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Sync failed: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(labelText: 'Phrase text'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isBusy ? null : _addPhrase,
              child: const Text('Add phrase'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isBusy ? null : _sync,
              child: const Text('Sync library'),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(_statusMessage!),
            ],
            const Divider(height: 32),
            Expanded(
              child: FutureBuilder<List<PhraseEntry>>(
                future: _manifestFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snapshot.data!;
                  return ListView(
                    children: [
                      for (final entry in entries)
                        ListTile(
                          title: Text(entry.text),
                          subtitle: Text(entry.category),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(entry.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
