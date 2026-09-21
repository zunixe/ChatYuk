import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/mixins/voice_recorder_mixin.dart';
import 'package:chatyuk/providers/locale_provider.dart';

/// Harness minimal `VoiceRecorderMixin` — kontraknya mandiri (2 method).
/// Fokus: state machine timer/lock/pause/cancel, BUKAN plugin `record`
/// (plugin native tidak tersedia di test → method yang menyentuhnya diuji
/// lewat guard state, bukan pemanggilan nyata).
class VoiceHost extends StatefulWidget {
  const VoiceHost({super.key});
  @override
  State<VoiceHost> createState() => VoiceHostState();
}

class VoiceHostState extends State<VoiceHost> with VoiceRecorderMixin<VoiceHost> {
  int signals = 0;
  final List<String> finished = [];
  @override
  void voiceSendRecordingSignal() => signals++;
  @override
  Future<void> voiceFinishRecording(String path, int durationMs) async {
    finished.add('$path|$durationMs');
  }

  @override
  String voicePermissionMessage() => 'perm';
  @override
  String voiceTooShortMessage() => 'too short';

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<VoiceHostState> pumpVoice(WidgetTester tester) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<LocaleProvider>(
      create: (_) => LocaleProvider(),
      child: const MaterialApp(home: VoiceHost()),
    ),
  );
  return tester.state<VoiceHostState>(find.byType(VoiceHost));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceRecorderMixin — state machine', () {
    testWidgets('startVoiceTimer menaikkan detik + kirim sinyal tiap tick',
        (tester) async {
      final s = await pumpVoice(tester);
      expect(s.voiceSeconds, 0);

      s.startVoiceTimer();
      await tester.pump(const Duration(seconds: 1));
      expect(s.voiceSeconds, 1);
      expect(s.signals, 1, reason: 'tiap detik kirim sinyal "merekam"');

      await tester.pump(const Duration(seconds: 1));
      expect(s.voiceSeconds, 2);
      expect(s.signals, 2);

      // Bersihkan timer agar test tidak menggantung.
      s.voiceTimer?.cancel();
    });

    testWidgets('timer auto-stop di 59 detik (batas keras)', (tester) async {
      final s = await pumpVoice(tester);
      s.voiceSeconds = 58;
      s.startVoiceTimer();

      await tester.pump(const Duration(seconds: 1));
      // Tick berikutnya (59) memicu stopVoiceRecord(send:true) → tanpa file
      // nyata stop() mengembalikan null → tidak lanjut kirim. Yang penting:
      // timer berhenti & tidak error.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      s.voiceTimer?.cancel();
    });

    testWidgets('lockVoiceRecord mengunci bulatan', (tester) async {
      final s = await pumpVoice(tester);
      expect(s.voiceLocked, isFalse);

      s.lockVoiceRecord();
      await tester.pump();
      expect(s.voiceLocked, isTrue);
    });

    testWidgets('cancelVoiceRecord reset semua flag + hentikan timer',
        (tester) async {
      final s = await pumpVoice(tester);
      s.voiceRecording = true;
      s.voiceLocked = true;
      s.voicePaused = true;
      s.voicePickUp = true;
      s.startVoiceTimer();

      s.cancelVoiceRecord();
      await tester.pump();

      expect(s.voiceRecording, isFalse);
      expect(s.voiceLocked, isFalse);
      expect(s.voicePaused, isFalse);
      expect(s.voicePickUp, isFalse);
      expect(s.voiceTimer?.isActive ?? false, isFalse,
          reason: 'timer harus berhenti saat batal');
    });

    testWidgets('stopVoiceRecord saat TIDAK merekam = no-op (guard)',
        (tester) async {
      final s = await pumpVoice(tester);
      s.voiceRecording = false;

      await s.stopVoiceRecord(send: true);
      await tester.pump();
      expect(s.finished, isEmpty, reason: 'tidak boleh kirim bila tak merekam');
      expect(tester.takeException(), isNull);
    });

    testWidgets('flag awal bersih (state default benar)', (tester) async {
      final s = await pumpVoice(tester);
      expect(s.voiceRecording, isFalse);
      expect(s.voiceSeconds, 0);
      expect(s.voiceLocked, isFalse);
      expect(s.voicePaused, isFalse);
      expect(s.voicePickUp, isFalse);
    });
  });
}
