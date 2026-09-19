import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Modul BERSAMA perekam voice note (private ↔ room).
///
/// State + timer + gesture lock/pause/resume identik di kedua screen (dulu
/// disalin): private di State layar, room di `_ChatInputState`. Sekarang satu
/// sumber; tiap pemakai menyediakan lanjutan setelah rekaman berhenti.
///
/// Kontrak implementor:
/// - [voiceSendRecordingSignal] kirim sinyal "sedang merekam" (private:
///   typing kind 'recording'; room: tanpa sinkron → no-op).
/// - [voiceFinishRecording] lanjutan setelah file tersedia & lolos cek
///   durasi minimal (upload + kirim / antre offline).
mixin VoiceRecorderMixin<T extends StatefulWidget> on State<T> {
  final AudioRecorder voiceRecorder = AudioRecorder();
  bool voiceRecording = false;
  Timer? voiceTimer;
  int voiceSeconds = 0;
  bool voiceLocked = false;
  bool voicePaused = false;
  // Bulatan lock sedang di-pick-up (ditekan + digeser) — menyembunyikan
  // tombol pause di composer dan menampilkan kembali "geser untuk batal".
  bool voicePickUp = false;

  void voiceSendRecordingSignal();
  Future<void> voiceFinishRecording(String path, int durationMs);

  void lockVoiceRecord() {
    if (mounted) setState(() => voiceLocked = true);
  }

  void startVoiceTimer() {
    voiceTimer?.cancel();
    voiceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (voiceSeconds >= 59) {
        stopVoiceRecord(send: true);
        return;
      }
      voiceSendRecordingSignal();
      setState(() => voiceSeconds++);
    });
  }

  Future<void> pauseVoiceRecord() async {
    try {
      await voiceRecorder.pause();
    } catch (_) {}
    voiceTimer?.cancel();
    if (mounted) setState(() => voicePaused = true);
  }

  Future<void> resumeVoiceRecord() async {
    try {
      await voiceRecorder.resume();
    } catch (_) {}
    if (mounted) setState(() => voicePaused = false);
    startVoiceTimer();
  }

  Future<void> startVoiceRecord() async {
    final hasPerm = await Permission.microphone.request();
    if (!hasPerm.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(voicePermissionMessage())),
        );
      }
      return;
    }
    try {
      if (!await voiceRecorder.hasPermission()) return;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: path,
      );
      setState(() {
        voiceRecording = true;
        voiceSeconds = 0;
        voiceLocked = false;
        voicePaused = false;
        voicePickUp = false;
      });
      voiceSendRecordingSignal();
      startVoiceTimer();
    } catch (_) {}
  }

  /// Stop + baca file. [send] false (mis. batal) → tidak lanjut kirim.
  /// Cek durasi minimal 2KB ditangani di sini; lanjutan kirim/antre diserahkan
  /// ke [voiceFinishRecording] supaya private & room bisa beda tujuan.
  Future<void> stopVoiceRecord({required bool send}) async {
    voiceTimer?.cancel();
    if (!voiceRecording) return;
    voiceLocked = false;
    voicePaused = false;
    voicePickUp = false;
    final path = await voiceRecorder.stop();
    setState(() => voiceRecording = false);
    if (!send || path == null) return;
    final f = File(path);
    if (!await f.exists()) return;
    final bytes = await f.readAsBytes();
    final recordedMs = voiceSeconds * 1000;
    if (bytes.length < 2000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(voiceTooShortMessage())),
        );
      }
      return;
    }
    await voiceFinishRecording(path, recordedMs);
  }

  void cancelVoiceRecord() {
    voiceTimer?.cancel();
    voiceRecorder.cancel();
    setState(() {
      voiceRecording = false;
      voiceLocked = false;
      voicePaused = false;
      voicePickUp = false;
    });
  }

  /// Dispose recorder — panggil dari `dispose()` pemakai.
  Future<void> disposeVoiceRecorder() async {
    voiceTimer?.cancel();
    voiceTimer = null;
    if (voiceRecording) {
      voiceRecording = false;
      try {
        await voiceRecorder.stop();
      } catch (_) {}
    }
    try {
      await voiceRecorder.dispose();
    } catch (_) {}
  }

  // Pesan error i18n — implementor mengembalikan string sesuai locale.
  String voicePermissionMessage();
  String voiceTooShortMessage();
}
