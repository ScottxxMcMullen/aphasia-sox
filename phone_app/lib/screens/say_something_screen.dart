import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/audio_playback_service.dart';
import '../services/library_store.dart';
import '../theme/sox_tokens.dart';
import '../widgets/category_picker.dart';

/// Where a request has actually got to. Every value is set by a call
/// returning, never by a timer — see [_StagePanel].
enum _Stage { idle, reaching, generating, speaking, spoken }

/// Which half of the request failed. The two need different words: a failed
/// ping means go and wake a machine, a failed generation means something
/// else.
enum _Failure { unreachable, generation }

enum _RowState { done, active, pending }

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
  String? _lastText;
  String? _errorMessage;
  _Failure? _failure;

  _Stage _stage = _Stage.idle;
  Duration? _reachedIn;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  bool get _isBusy =>
      _stage == _Stage.reaching ||
      _stage == _Stage.generating ||
      _stage == _Stage.speaking;

  void _startTicker() {
    _ticker?.cancel();
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _stage = _Stage.reaching;
      _errorMessage = null;
      _failure = null;
      _reachedIn = null;
    });

    try {
      final reachedIn = await widget.apiClient.ping();
      if (!mounted) return;
      setState(() {
        _reachedIn = reachedIn;
        _stage = _Stage.generating;
      });
      _startTicker();

      final audio = await widget.apiClient.generateSpeech(text);
      final tempFile =
          File('${Directory.systemTemp.path}/say_something_preview.wav');
      await tempFile.writeAsBytes(audio);
      _ticker?.cancel();
      if (!mounted) return;
      setState(() => _stage = _Stage.speaking);

      await widget.audioPlaybackService.playFile(tempFile);
      if (!mounted) return;
      setState(() {
        _lastText = text;
        _stage = _Stage.spoken;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_stage == _Stage.reaching) {
          _failure = _Failure.unreachable;
          // Deliberately not the raw exception: on a phone it reads as a
          // page of socket detail. What a failed ping actually tells you is
          // this, and "may" is doing honest work — it could equally be the
          // phone that is off the tailnet.
          _errorMessage =
              'The laptop at home may be asleep or off the network.';
        } else {
          _failure = _Failure.generation;
          _errorMessage = e.message;
        }
        _stage = _Stage.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = _Failure.generation;
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _Stage.idle;
      });
    } finally {
      _ticker?.cancel();
    }
  }

  Future<void> _saveToLibrary(String category) async {
    final text = _lastText;
    if (text == null) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _failure = null;
    });
    try {
      final entry =
          await widget.apiClient.addPhrase(category: category, text: text);
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
        _failure = _Failure.generation;
        _errorMessage = 'Could not save: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = _Failure.generation;
        _errorMessage = 'Something went wrong. Please try again.';
      });
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

  void _reset() {
    setState(() {
      _textController.clear();
      _stage = _Stage.idle;
      _lastText = null;
      _errorMessage = null;
      _failure = null;
      _reachedIn = null;
    });
  }

  String get _speakLabel =>
      _stage == _Stage.spoken ? 'SAY SOMETHING ELSE' : 'SPEAK IT';

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Say Something')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'WHAT YOU WANT TO SAY',
              style: TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.3,
                color: SoxTokens.muted(ink),
              ),
            ),
            TextField(
              controller: _textController,
              minLines: 3,
              maxLines: null,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(hintText: 'Type it here'),
            ),
            const SizedBox(height: 24),
            if (_isBusy)
              _StagePanel(
                stage: _stage,
                reachedIn: _reachedIn,
                elapsed: _elapsed,
              ),
            if (_errorMessage != null)
              _ErrorPanel(failure: _failure!, detail: _errorMessage!),
            if (_stage == _Stage.spoken) ...[
              Container(
                width: double.infinity,
                color: SoxTokens.red,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Text(
                  'SPOKEN IN YOUR VOICE',
                  style: TextStyle(
                    fontFamily: SoxTokens.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: 0.2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Outlined, not filled: the red is spent on the bar above, and
              // one screen gets one solid accent.
              OutlinedButton(
                onPressed: _showSaveDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size.fromHeight(56),
                  side: BorderSide(
                    color: SoxTokens.majorRule(ink),
                    width: SoxTokens.ruleMajor,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text('Save to library'),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: SoxTokens.majorRule(ink),
              width: SoxTokens.ruleMajor,
            ),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 76,
          child: ElevatedButton(
            // Stays enabled after a failure so a retry needs no navigation.
            onPressed: _isBusy
                ? null
                : (_stage == _Stage.spoken ? _reset : _speak),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(76),
              textStyle: const TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: 0.22,
              ),
            ),
            child: Text(_speakLabel),
          ),
        ),
      ),
    );
  }
}

/// The three stages of a request, each one advanced only by the
/// corresponding call returning. No stage moves on a timer, and the bar is
/// indeterminate on purpose: the app cannot know when a cold engine load
/// will finish, so it must not draw something that implies it does.
class _StagePanel extends StatelessWidget {
  const _StagePanel({
    required this.stage,
    required this.reachedIn,
    required this.elapsed,
  });

  final _Stage stage;
  final Duration? reachedIn;
  final Duration elapsed;

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  _RowState _stateFor(_Stage row) {
    if (stage.index > row.index) return _RowState.done;
    if (stage.index == row.index) return _RowState.active;
    return _RowState.pending;
  }

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: SoxTokens.majorRule(ink),
          width: SoxTokens.ruleMajor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StageRow(
            label: 'Reached the laptop at home',
            meta: reachedIn == null ? '' : '${reachedIn!.inSeconds}s',
            state: _stateFor(_Stage.reaching),
          ),
          _StageRow(
            label: 'Building your voice',
            meta: stage == _Stage.generating ? _clock(elapsed) : '',
            state: _stateFor(_Stage.generating),
          ),
          _StageRow(
            label: 'Speaking',
            meta: '',
            state: _stateFor(_Stage.speaking),
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          // The most important copy on the screen: the difference between
          // waiting and deciding the app is broken.
          Text(
            'The first sentence after a quiet spell takes about a minute. '
            'Saved phrases still work while you wait.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.meta,
    required this.state,
  });

  final String label;
  final String meta;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = switch (state) {
      _RowState.done => ink,
      _RowState.active => Theme.of(context).colorScheme.error,
      // The real grey token, not an opacity: a pending stage still has to be
      // readable, and an alpha over this ground lands near 2.75:1.
      _RowState.pending => dark ? SoxTokens.greyOnDark : SoxTokens.greyOnPaper,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: state == _RowState.pending ? null : fg,
              border: Border.all(color: fg, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: fg,
              ),
            ),
          ),
          Text(meta, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A failure costs the speaker a new sentence, not their voice. The third
/// line is the point of this panel.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.failure, required this.detail});

  final _Failure failure;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final Color error = Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: error, width: SoxTokens.ruleMajor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure == _Failure.unreachable
                ? 'COULD NOT REACH THE LAPTOP'
                : 'SOMETHING WENT WRONG',
            style: TextStyle(
              fontFamily: SoxTokens.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.3,
              color: error,
            ),
          ),
          const SizedBox(height: 8),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            'Saved phrases still work — everything in your library plays '
            'from this phone.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
