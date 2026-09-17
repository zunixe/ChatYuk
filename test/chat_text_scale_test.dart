import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';

/// Uji skala font chat (slider di profil): clamp, normalisasi, persist,
/// dan token AppText.chatBody/chatTime ikut terskala.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ChatTextScale.setLocal(1.0));

  group('ChatTextScale.resolve', () {
    test('nilai normal dipertahankan', () {
      expect(ChatTextScale.resolve(1.0), 1.0);
      expect(ChatTextScale.ptOf(1.0), 16.0);
    });

    test('clamp ke [min,max]', () {
      expect(ChatTextScale.resolve(0.1), ChatTextScale.min);
      expect(ChatTextScale.resolve(9.0), ChatTextScale.max);
      expect(ChatTextScale.resolve(1.0), 1.0);
    });

    test('tick 0.5pt tidak rusak pembulatan', () {
      expect(ChatTextScale.resolve(0.90625), 0.90625);
    });
  });

  group('ChatTextScale.scale', () {
    test('multiplier diterapkan ke basis', () {
      ChatTextScale.setLocal(1.0);
      expect(ChatTextScale.scale(14), 14.0);
      ChatTextScale.setLocal(1.1);
      expect(ChatTextScale.scale(10), closeTo(11.0, 0.001));
    });

    test('nilai ekstrem tetap ter-clamp', () {
      ChatTextScale.setLocal(5.0); // resolve → max
      expect(ChatTextScale.scale(10), closeTo(10 * ChatTextScale.max, 0.001));
    });
  });

  group('AppText token ikut skala', () {
    test('chatBody membesar saat scale naik', () {
      ChatTextScale.setLocal(1.0);
      final base = AppText.chatBody.fontSize!;
      ChatTextScale.setLocal(ChatTextScale.max);
      final big = AppText.chatBody.fontSize!;
      expect(big, greaterThan(base));
      expect(big, closeTo(16 * ChatTextScale.max, 0.01));
    });

    test('chatTime = 11 × scale', () {
      ChatTextScale.setLocal(1.0);
      expect(AppText.chatTime.fontSize, 11.0);
    });

    test('percent + notifier sinkron', () {
      ChatTextScale.setLocal(1.0);
      expect(ChatTextScale.percent, 100);
      expect(ChatTextScale.notifier.value, 1.0);
    });
  });

  group('step ↔ pt (slider angka)', () {
    test('step 0 = pt terkecil (min), step terakhir = pt terbesar', () {
      expect(ChatTextScale.multOfStep(0), ChatTextScale.min);
      expect(ChatTextScale.multOfStep(ChatTextScale.steps), ChatTextScale.max);
      final lo = ChatTextScale.ptOf(ChatTextScale.multOfStep(0));
      final hi = ChatTextScale.ptOf(
        ChatTextScale.multOfStep(ChatTextScale.steps),
      );
      expect(lo, lessThan(hi));
    });

    test('ptOf monoton naik tiap step', () {
      var prev = 0.0;
      for (var i = 0; i <= ChatTextScale.steps; i++) {
        final pt = ChatTextScale.ptOf(ChatTextScale.multOfStep(i));
        expect(pt, greaterThanOrEqualTo(prev));
        prev = pt;
      }
    });

    test('tick 14–18 per 0.5 (9 tick)', () {
      const expected = [14.0, 14.5, 15.0, 15.5, 16.0, 16.5, 17.0, 17.5, 18.0];
      expect(ChatTextScale.steps, 8);
      for (var i = 0; i <= ChatTextScale.steps; i++) {
        expect(
          ChatTextScale.ptOf(ChatTextScale.multOfStep(i)),
          closeTo(expected[i], 0.001),
        );
      }
    });

    test('labelOf tanpa ".0" (mis. "16", "14.5")', () {
      expect(ChatTextScale.labelOf(1.0), '16');
      expect(ChatTextScale.labelOf(ChatTextScale.min), '14');
      expect(ChatTextScale.labelOf(ChatTextScale.max), '18');
      expect(
        ChatTextScale.labelOf(ChatTextScale.multOfStep(1)),
        '14.5',
      );
    });

    test('stepIndex round-trip dengan multOfStep', () {
      for (var i = 0; i <= ChatTextScale.steps; i++) {
        final m = ChatTextScale.multOfStep(i);
        expect(ChatTextScale.indexOf(m).round(), i);
      }
    });

    test('pt = 16 saat normal (mid mendekati 1.0)', () {
      ChatTextScale.setLocal(1.0);
      expect(ChatTextScale.pt, 16.0);
    });

    test('chatBodyAt(ukuran) mengikuti pt eksplisit', () {
      expect(AppText.chatBodyAt(18).fontSize, 18.0);
      expect(AppText.chatBodyAt(22).fontSize, 22.0);
    });
  });

  group('slider di batas min/max', () {
    test('multiplier min: chatBody/chatName/chatTime ikut mengecil', () {
      ChatTextScale.setLocal(ChatTextScale.min);
      expect(AppText.chatBody.fontSize,
          closeTo(16 * ChatTextScale.min, 0.001));
      expect(AppText.chatName.fontSize,
          closeTo(13 * ChatTextScale.min, 0.001));
      expect(AppText.chatTime.fontSize,
          closeTo(11 * ChatTextScale.min, 0.001));
    });

    test('multiplier max: chatBody/chatTime ikut membesar', () {
      ChatTextScale.setLocal(ChatTextScale.max);
      expect(AppText.chatBody.fontSize,
          closeTo(16 * ChatTextScale.max, 0.001));
      expect(AppText.chatTime.fontSize,
          closeTo(11 * ChatTextScale.max, 0.001));
    });

    test('setLocal di luar batas di-clamp, bukan dipakai mentah', () {
      ChatTextScale.setLocal(9.0);
      expect(ChatTextScale.current, ChatTextScale.max);
      ChatTextScale.setLocal(0.01);
      expect(ChatTextScale.current, ChatTextScale.min);
    });

    test('token non-chat tidak ikut slider (hanya chat*)', () {
      ChatTextScale.setLocal(ChatTextScale.max);
      expect(AppText.body.fontSize, 14);
      expect(AppText.bodySmall.fontSize, 12);
      expect(
        AppText.chatBody.fontSize,
        greaterThan(AppText.body.fontSize!),
        reason: 'bubble chat terskala, teks UI lain tidak',
      );
    });
  });

  group('token chat lengkap (isi percakapan)', () {
    test('semua token chat* bernilai normal pada skala 1.0', () {
      ChatTextScale.setLocal(1.0);
      expect(AppText.chatBody.fontSize, 16.0);
      expect(AppText.chatBodyStrong.fontSize, 16.0);
      expect(AppText.chatBodySmall.fontSize, 14.0);
      expect(AppText.chatName.fontSize, 13.0);
      expect(AppText.chatCaption.fontSize, 12.0);
      expect(AppText.chatTime.fontSize, 11.0);
      expect(AppText.chatCode.fontSize, 14.0);
    });

    test('semua token chat* ikut membesar pada skala maks', () {
      ChatTextScale.setLocal(ChatTextScale.max);
      expect(AppText.chatBody.fontSize, closeTo(16 * ChatTextScale.max, 0.001));
      expect(
        AppText.chatBodyStrong.fontSize,
        closeTo(16 * ChatTextScale.max, 0.001),
      );
      expect(
        AppText.chatBodySmall.fontSize,
        closeTo(14 * ChatTextScale.max, 0.001),
      );
      expect(AppText.chatName.fontSize, closeTo(13 * ChatTextScale.max, 0.001));
      expect(
        AppText.chatCaption.fontSize,
        closeTo(12 * ChatTextScale.max, 0.001),
      );
      expect(AppText.chatTime.fontSize, closeTo(11 * ChatTextScale.max, 0.001));
      expect(AppText.chatCode.fontSize, closeTo(14 * ChatTextScale.max, 0.001));
    });

    test('pasangan non-chat-nya tetap tidak terskala', () {
      ChatTextScale.setLocal(ChatTextScale.max);
      expect(AppText.bodyStrong.fontSize, 14);
      expect(AppText.caption.fontSize, 11);
      expect(AppText.micro.fontSize, 10);
      expect(AppText.label.fontSize, 12);
      expect(AppText.code.fontSize, 12);
    });
  });
}
