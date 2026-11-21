import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'log_service.dart';

/// Looping alarm sound played by the app itself.
abstract interface class AlarmSound {
  Future<void> start();
  Future<void> stop();
}

/// Bundled `assets/sounds/alarm.wav` in a loop at full player volume.
///
/// Not used on Android: there the notification itself rings on the alarm
/// stream with the system alarm-clock sound (`NotificationService`), which
/// also works with the app closed. Playing both would double the sound.
class AudioAlarmSound implements AlarmSound {
  AudioAlarmSound({required this.log});

  final LogService log;
  AudioPlayer? _player;

  static bool get isNeeded => !Platform.isAndroid;

  @override
  Future<void> start() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      // iOS: the default audio context is the `playback` session category,
      // which keeps playing with the silent switch on while the app is open.
      await player.play(AssetSource('sounds/alarm.wav'), volume: 1);
    } catch (e, st) {
      log.error('Alarm sound failed to start', e, st);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (e, st) {
      log.error('Alarm sound failed to stop', e, st);
    }
  }
}

/// For Android, where the notification channel provides the sound.
class SilentAlarmSound implements AlarmSound {
  const SilentAlarmSound();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
