import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Controller rekam suara WA-style — SATU sumber logika dipakai
/// PrivateChatScreen & RoomChatScreen (dulu: duplikat ~130 baris identik
/// di kedua screen; bug fix satu sisi tidak otomatis ke sisi lain).
class VoiceRecorderController {
  final AudioRecorder _record = AudioRecorder();

  bool _recording = false;
  bool _locked = false;
  bool _paused = false;
  int _seconds = 0;
  Timer? _timer;
  String? _path;

  bool get isRecording => _recording;
  bool get isLocked => _locked;
  bool get isPaused => _paused;
  int get seconds => _seconds;
  String? get path => _path;

  /// Callback per detik (sinyal "merekam" ke lawan bicara + UI timer).
  void Function(int seconds)? onTick;
  /// Dipanggil saat durasi maksimum (60s) tercapai — auto kirim.
  VoidCallback? onMaxDuration;
  /// Dipanggil kalau start gagal (izin/exception).
  void Function(String error)? onError;

  Future<bool> start() async {
    final hasPerm = await Permission.microphone.request();
    if (!hasPerm.isGranted) {
      onError?.call('permission');
      return false;
    }
    try {
      if (!await _record.hasPermission()) {
        onError?.call('permission');
        return false;
      }
      final dir = await getTemporaryDirectory();
      _path =
          '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _record.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: _path!,
      );
      _recording = true;
      _locked = false;
      _paused = false;
      _seconds = 0;
      onTick?.call(0);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_seconds >= 59) {
          onMaxDuration?.call();
          return;
        }
        _seconds++;
        onTick?.call(_seconds);
      });
      return true;
    } catch (e) {
      debugPrint('[VoiceRecorder] start error: $e');
      onError?.call('$e');
      return false;
    }
  }

  void lock() => _locked = true;

  Future<void> pause() async {
    try {
      await _record.pause();
    } catch (_) {}
    _timer?.cancel();
    _paused = true;
  }

  Future<void> resume() async {
    try {
      await _record.resume();
    } catch (_) {}
    _paused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds >= 59) {
        onMaxDuration?.call();
        return;
      }
      _seconds++;
      onTick?.call(_seconds);
    });
  }

  /// Stop & return path file (null jika tidak merekam).
  Future<String?> stop() async {
    if (!_recording) return null;
    _timer?.cancel();
    final p = await _record.stop();
    _recording = false;
    _locked = false;
    _paused = false;
    return p;
  }

  /// Batalkan rekaman — hapus file parsial.
  Future<void> cancel() async {
    _timer?.cancel();
    if (_recording) {
      try {
        await _record.cancel();
      } catch (_) {}
    }
    final p = _path;
    _recording = false;
    _locked = false;
    _paused = false;
    _seconds = 0;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    _path = null;
  }

  void dispose() {
    _timer?.cancel();
    if (_recording) {
      try {
        _record.cancel();
      } catch (_) {}
    }
    _record.dispose();
  }
}
