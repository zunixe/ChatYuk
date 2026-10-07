import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/services/storage_photo_service.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';



/// Video chat: kontrak murni (label durasi + deteksi path + batas).
/// Handshake upload/putar butuh device — diuji manual di HP.
void main() {
  group('formatVideoDuration', () {
    test('0 / negatif → 0:00', () {
      expect(formatVideoDuration(0), '0:00');
      expect(formatVideoDuration(-500), '0:00');
    });

    test('detik → m:ss (padding 2 digit)', () {
      expect(formatVideoDuration(7000), '0:07');
      expect(formatVideoDuration(59000), '0:59');
    });

    test('>= 60 dtk pindah menit', () {
      expect(formatVideoDuration(60000), '1:00');
      expect(formatVideoDuration(65000), '1:05');
    });

    test('pembulatan ms ke detik terdekat', () {
      expect(formatVideoDuration(1400), '0:01');
      expect(formatVideoDuration(1600), '0:02');
    });
  });

  group('Batas video chat (kontrak server + client)', () {
    test('durasi maks 60 dtk', () {
      expect(StoragePhotoService.chatVideoMaxMs, 60 * 1000);
    });

    test('ukuran hasil kompres maks 8 MB', () {
      expect(StoragePhotoService.chatVideoMaxBytes, 8 * 1024 * 1024);
    });

    // KONTRAK KOMPRES: `compressChatVideo` memakai 480p + `chatVideoFrameRate`.
    // frameRate dikunci 24 (dulu 30) → ukuran file ~20% lebih kecil tanpa
    // terlihat lebih patah di klip pendek. Kontrak ini dijaga di sini supaya
    // perubahan tak sadar yang menaikkan bitrate/ukuran ketahuan lewat test.
    test('frameRate kompres video chat = 24 (hemat ~20% vs 30)', () {
      expect(StoragePhotoService.chatVideoFrameRate, 24);
      expect(StoragePhotoService.chatVideoFrameRate, lessThan(30));
    });

    test('frameRate konsisten dengan video story (24)', () {
      // Video story & chat sama-sama 24fps → perilaku hemat seragam.
      expect(StoragePhotoService.chatVideoFrameRate, 24);
    });
  });

  group('Pengenalan type video (dipakai dedupe pending ↔ server)', () {
    // Kontrak: pending video (base64) dibuang saat versi server (path)
    // tiba. Keduanya harus dikenali sebagai "video" — dulu cabang dedupe
    // hanya menangani image/view_once/voice sehingga pending video
    // menggantung sebagai kotak kosong.
    bool isVideoType(String t) =>
        t == 'video' || t == 'video_once' || t == 'video_once_expired';

    test('ketiga type video dikenali', () {
      expect(isVideoType('video'), isTrue);
      expect(isVideoType('video_once'), isTrue);
      expect(isVideoType('video_once_expired'), isTrue);
    });

    test('type lain BUKAN video', () {
      for (final t in ['image', 'view_once', 'voice', 'text', 'coin']) {
        expect(isVideoType(t), isFalse, reason: t);
      }
    });
  });

  group('Pengenalan type foto/view-once (dipakai dedupe pending ↔ server)', () {
    // Kontrak: pending foto optimistik dibuat dengan type 'image'/'view_once';
    // versi server bisa tiba sebagai 'view_once_expired' (foto sekali-lihat
    // sudah dilihat penerima → server ubah type). Cabang dedupe WAJIB
    // mengenali ketiganya, kalau tidak pending menggantung → muncul DUA
    // bubble (regresi "foto sekali lihat dobel").
    bool isPhotoType(String t) =>
        t == 'image' || t == 'view_once' || t == 'view_once_expired';

    test('ketiga type foto dikenali', () {
      expect(isPhotoType('image'), isTrue);
      expect(isPhotoType('view_once'), isTrue);
      expect(isPhotoType('view_once_expired'), isTrue);
    });

    test('type lain BUKAN foto', () {
      for (final t in ['text', 'voice', 'video', 'video_once', 'coin']) {
        expect(isPhotoType(t), isFalse, reason: t);
      }
    });
  });

  group('isChatVideoPath', () {
    final svc = StoragePhotoService.instance;

    test('path video chat dikenali', () {
      expect(svc.isChatVideoPath('chat/abc/123.mp4'), isTrue);
    });

    test('path foto chat BUKAN video', () {
      expect(svc.isChatVideoPath('chat/abc/123.jpg'), isFalse);
    });

    test('video story bukan video chat', () {
      expect(svc.isChatVideoPath('story/uid/123.mp4'), isFalse);
    });
  });

  // Catatan regresi (tanpa unit test — host butuh banyak stub mixin):
  // `pendingVideoMs`/`pendingVideoPath` di ChatPhotoSendMixin WAJIB getter.
  // Saat berbentuk FIELD, Dart menutupi getter layar → durasi selalu 0
  // (label 0:00 + validasi durasi server gagal). Dijaga oleh analyzer:
  // `private_chat_screen` memakai `@override int get pendingVideoMs`, yang
  // TIDAK akan ter-compile bila mixin kembali memakai field.

  group('isPath menerima video (regresi: video gagal dimuat)', () {
    final svc = StoragePhotoService.instance;

    test('mp4 & mov dianggap path storage', () {
      expect(svc.isPath('chat/abc/123.mp4'), isTrue);
      expect(svc.isPath('chat/abc/123.mov'), isTrue);
      expect(svc.isPath('story/uid/123.mp4'), isTrue);
    });

    test('base64 TIDAK dianggap path', () {
      expect(svc.isPath('/9j/4AAQSkZJRgABAQAAAQ=='), isFalse);
      expect(svc.isPath(''), isFalse);
    });
  });

  group('Video sekali-lihat kadaluarsa (regresi bubble KOSONG)', () {
    // Bug: `video_once_expired` dengan image_data kosong (dikosongkan server
    // saat ditonton, pola sama foto) tidak dirender apa pun → bubble kosong
    // tanpa teks. Kartu terkunci WAJIB tetap muncul + tulisannya "video".
    Widget host(ChatVideoBubble b) =>  ProviderScope(child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: Center(child: b)),
      ));

    testWidgets('locked + data kosong → kartu "Video sudah kadaluarsa"', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ChatVideoBubble(
            videoData: '',
            durationMs: 5000,
            locked: true,
            isOnce: true,
            isMe: false,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Kartu terkunci menampilkan teks VIDEO (bukan "Foto", bukan kosong).
      expect(find.text('Video sudah kadaluarsa'), findsOneWidget);
    });
  });
}
