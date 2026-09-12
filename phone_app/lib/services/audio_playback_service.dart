import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

abstract class AudioPlaybackService {
  Future<void> playFile(File file);
}

class AudioplayersPlaybackService implements AudioPlaybackService {
  AudioplayersPlaybackService() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playFile(File file) async {
    await _player.play(DeviceFileSource(file.path));
  }
}
