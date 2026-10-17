import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/providers/riverpod/timeline_provider.dart';
import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/social_service.dart';
import 'package:chatyuk/services/timeline_service.dart';
import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/widgets/post_card.dart';
import 'package:chatyuk/widgets/post/post_photo_grid.dart';

import 'test_helper.dart';

/// Fase 5 — PostCard: render + perilaku kunci (logic-only, tanpa jaringan).
class MockTimelineService extends Mock implements TimelineService {}

class MockAuthService extends Mock implements AuthService {}

class MockSocialService extends Mock implements SocialService {}

class TestAuth extends AuthNotifier {
  TestAuth(MockAuthService svc) : super(authService: svc);
  @override
  AuthData build() => const AuthData(uid: 'me', loading: false);
  @override
  String? get uid => 'me';
}

class TestSocial extends SocialNotifier {
  final SocialState preset;
  TestSocial(this.preset);
  @override
  SocialState build() => preset;
}

Map<String, dynamic> _post({
  String id = 'p1',
  String author = 'Budi',
  String text = 'Halo dunia',
  int likes = 0,
  int comments = 0,
  int shares = 0,
  bool boosted = false,
  bool friend = false,
  bool liked = false,
  List<String>? images,
  int imageW = 0,
  int imageH = 0,
}) =>
    {
      'id': id,
      'authorId': 'a1',
      'authorName': author,
      'text': text,
      'likeCount': likes,
      'commentCount': comments,
      'shareCount': shares,
      'isBoosted': boosted,
      'isFriend': friend,
      'isLiked': liked,
      'isFollowing': false,
      if (images != null) 'images': images, // ignore: use_null_aware_elements
      if (imageW > 0) 'imageW': imageW,
      if (imageH > 0) 'imageH': imageH,
      // Avatar inline PNG kecil → _AuthorAvatar resolve SINKRON (tak
      // fallback ke ProfileAvatar yang menjadwalkan timer retry 300ms).
      'authorAvatar':
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

/// PNG 1×1 transparan (base64) untuk uji thumb foto.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

/// Bytes PNG 1×1 (untuk downloader palsu di test gagal-load).
final Uint8List _pngBytes = base64Decode(_pngBase64);

void main() {
  late MockTimelineService timeline;
  late MockAuthService auth;

  setUpAll(() async {
    await initSupabaseForTest();
    // Prewarm cache media — avatar komentar (ProfileAvatar → AvatarB64Service
    // → MediaDiskCache.waitReady) tidak boleh menjadwalkan timer pending yang
    // menggagalkan test ("Pending timers" saat teardown).
    await prewarmMediaForTest();
    // Sheet komentar memakai AppText (Poppins via google_fonts) — pakai font
    // sistem di test supaya tidak unduh/bundel font (tanpa jaringan).
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<String>[]);
  });

  tearDownAll(resetFontForTest);

  setUp(() {
    timeline = MockTimelineService();
    auth = MockAuthService();
    when(() => timeline.watchNewPosts())
        .thenAnswer((_) => const Stream.empty());
    when(() => timeline.pricing()).thenAnswer((_) async => {});
    when(() => timeline.comments(any())).thenAnswer((_) async => []);
    when(() => auth.uid).thenReturn('me');
    when(() => auth.currentUser).thenReturn(null);
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.isAnonymous).thenReturn(false);
    when(() => auth.onMyProfileUpdates())
        .thenAnswer((_) => const Stream.empty());
  });

  Future<void> pump(WidgetTester tester, Map<String, dynamic> post,
      {SocialState socialState = const SocialState()}) async {
    final container = ProviderContainer(
      overrides: [
        socialProvider.overrideWith(() => TestSocial(socialState)),
        timelineProvider.overrideWith(
          () => TimelineNotifier(service: timeline, autoInit: false),
        ),
        authProvider.overrideWith(() => TestAuth(auth)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PostCard(post: post)),
          ),
        ),
      ),
    );
    await tester.pump();
    // Buang timer yang mungkin dijadwalkan provider/widget (anti-invariant).
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('render menampilkan nama author & teks post', (tester) async {
    await pump(tester, _post(author: 'Budi', text: 'Isi postingan uji'));
    expect(find.text('Budi'), findsOneWidget);
    expect(find.textContaining('Isi postingan uji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menampilkan jumlah like/komentar/share', (tester) async {
    await pump(tester, _post(likes: 7, comments: 3, shares: 2));
    expect(find.text('7'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('post tanpa teks tetap render tanpa error', (tester) async {
    final p = _post(text: '');
    await pump(tester, p);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post boosted & friend menampilkan badge tanpa error',
      (tester) async {
    await pump(tester, _post(boosted: true, friend: true));
    expect(tester.takeException(), isNull);
  });

  // REGRESI: post dari realtime TIDAK membawa `isFriend` (computed di RPC
  // list_posts, bukan kolom tabel). Dulu TimelineProvider._mapRow hardcode
  // 'isFriend': false → badge Teman hilang sampai feed di-refresh. Badge harus
  // muncul dari SocialProvider.isFriend(authorId) walau post['isFriend']=false.
  testWidgets('badge Teman muncul dari SocialProvider walau post.isFriend=false',
      (tester) async {
    // post.isFriend = false (seperti payload realtime yang tak punya field ini).
    await pump(tester, _post(friend: false),
        socialState: const SocialState(friends: {'a1'}));
    expect(tester.takeException(), isNull);
    expect(
      find.byIcon(Icons.people_alt_rounded),
      findsWidgets,
      reason: 'badge Teman harus muncul dari SocialProvider, bukan post map',
    );
  });

  testWidgets('tanpa friend (bukan teman) → badge Teman tidak muncul',
      (tester) async {
    await pump(tester, _post(friend: false));
    expect(find.byIcon(Icons.people_alt_rounded), findsNothing);
  });

  testWidgets('foto single 1:1 → lebar penuh kolom konten ala Threads', (
    tester,
  ) async {
    await pump(
      tester,
      _post(images: [_pngBase64], imageW: 1000, imageH: 1000),
    );
    expect(tester.takeException(), isNull);
    // Layar 800 − (16 item + 40 avatar + 10 gap) − 16 gutter = 718.
    final f = find.byKey(const ValueKey('photo_placeholder'));
    expect(f, findsOneWidget, reason: 'ada kotak foto placeholder');
    final size = tester.getSize(f);
    expect(size.width, closeTo(718, 3),
        reason: 'foto single = lebar kolom konten (gutter kanan 16)');
    expect(size.height, closeTo(718, 3), reason: 'rasio 1:1 → tinggi = lebar');
  });

  testWidgets('foto single 9:16 portrait → lebar penuh, tinggi sesuai rasio',
      (tester) async {
    await pump(
      tester,
      _post(images: [_pngBase64], imageW: 1080, imageH: 1920),
    );
    expect(tester.takeException(), isNull);
    final f = find.byKey(const ValueKey('photo_placeholder'));
    expect(f, findsOneWidget);
    final s = tester.getSize(f);
    expect(s.width, closeTo(718, 3));
    // 9:16 (0.5625) di bawah batas 4:5 (0.8) → dipotong (crop) ke 4:5.
    expect(s.height, closeTo(718 / 0.8, 3),
        reason: 'tinggi memenuhi batas 4:5 (paling tinggi), bukan memanjang');
  });

  testWidgets('multi-foto → baris horizontal, beberapa foto sekaligus',
      (tester) async {
    // 3 foto 9:16 (1200x2670) seperti post SimpleMe.
    await pump(
      tester,
      _post(
        images: [_pngBase64, _pngBase64, _pngBase64],
        imageW: 1200,
        imageH: 2670,
      ),
    );
    expect(tester.takeException(), isNull);
    // Carousel: tinggi seragam 240; lebar = 240 × rasio (dibatasi 3:4…4:3).
    // Rasio 1200/2670 ≈ 0.449 di bawah batas 0.75 → dipakai 0.75 → 180.
    final f = find.byKey(const ValueKey('photo_placeholder'));
    expect(f, findsOneWidget);
    final s = tester.getSize(f);
    expect(s.width, closeTo(180, 3),
        reason: 'lebar item = 240 × rasio (min 3:4 = 0.75)');
    expect(s.height, closeTo(240, 1), reason: 'tinggi seragam carousel 240');
  });

  testWidgets('post foto tanpa imageW/H (post lama) → fallback aman',
      (tester) async {
    await pump(tester, _post(images: [_pngBase64]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  // REGRESI: "aplikasi mati saat buka timeline". Post multi-foto dengan
  // foto di TENGAH gagal-load → thumb difilter sehingga list viewer lebih
  // pendek dari jumlah foto. Tap foto terakhir memakai index asli (di luar
  // rentang list terfilter) → PageController(initialPage: outOfRange) +
  // paths[i] → RangeError. Viewer WAJIB tidak melempar exception.
  testWidgets('multi-foto: buka viewer walau ada foto gagal-load (anti RangeError)',
      (tester) async {
    mockPathProvider();
    // 3 foto; foto ke-2 (index 1) GAGAL (downloader → null) → thumb-nya
    // tak terisi → loadedPaths di viewer jadi lebih pendek.
    const paths = ['posts/regresi/ok0.jpg', 'posts/regresi/gagal1.jpg', 'posts/regresi/ok2.jpg'];
    PostPhotoCache.downloader = (p) async =>
        p.contains('gagal1') ? null : _pngBytes;
    addTearDown(() => PostPhotoCache.downloader = null);

    await pump(
      tester,
      _post(images: paths, imageW: 1200, imageH: 2670),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: 'render awal aman');

    // Tap foto terakhir di DALAM carousel (index 2) — inilah yang dulu crash
    // karena list viewer terfilter hanya berisi [ok0, ok2] (length 2).
    // Cari GestureDetector khusus media (bukan badge follow/avatar) supaya
    // tidak salah tap elemen lain.
    final mediaTap = find.descendant(
      of: find.byKey(const ValueKey('photo_multi')),
      matching: find.byType(GestureDetector),
    );
    if (mediaTap.evaluate().isNotEmpty) {
      await tester.tap(mediaTap.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull,
        reason: 'buka viewer tidak boleh crash karena index di luar rentang');
  });

  testWidgets('author id == uid sendiri dirender (isAuthor)', (tester) async {
    final p = _post()..['authorId'] = 'me';
    await pump(tester, p);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap tombol like → delegasi toggleLike ke TimelineProvider',
      (tester) async {
    when(() => timeline.toggleLike('p1')).thenAnswer(
      (_) async => {'liked': true, 'likeCount': 8},
    );
    await pump(tester, _post(likes: 7));

    // Tap ikon hati (aksi pertama) — cari InkWell pertama di baris aksi.
    await tester.tap(find.byIcon(PhosphorIconsRegular.heart).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => timeline.toggleLike('p1')).called(1);
  });

  testWidgets('like OPTIMISTIK: tak menunggu network (anti delay)',
      (tester) async {
    // toggleLike MENGGANTUNG (belum selesai) — membuktikan _like sudah
    // memanggil toggleLike & TIDAK memblok UI (tidak ada exception),
    // lalu aman saat jawaban server datang.
    final completer = Completer<Map<String, dynamic>>();
    when(() => timeline.toggleLike('p1')).thenAnswer((_) => completer.future);
    await pump(tester, _post(likes: 7, liked: false));

    await tester.tap(find.byIcon(PhosphorIconsRegular.heart).first);
    await tester.pump(); // 1 frame — belum ada jawaban server
    verify(() => timeline.toggleLike('p1')).called(1);
    expect(tester.takeException(), isNull,
        reason: 'UI tidak boleh error/menunggu network saat like');

    completer.complete({'liked': true, 'likeCount': 8});
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

/// Buang channel + putuskan socket realtime milik test ini dari client
/// bersama — kalau tidak, loop reconnect socket (URL dummy tak tersambung)
/// + disconnect tertunda 2×heartbeat (50 dtk) membuat test gagal invariant
/// "Timer masih pending".
/// Fire-and-forget (jangan await): leave-ack menunggu timer fake yang hanya
/// berjalan saat pump → await di sini deadlock.
void _cleanupTestChannels() {
  try {
    final realtime = Supabase.instance.client.realtime;
    unawaited(Supabase.instance.client.removeAllChannels());
    unawaited(realtime.disconnect());
  } catch (_) {}
}

  testWidgets('kirim komentar → sheet tetap terbuka + langsung tampil',
      (tester) async {
    when(() => timeline.addComment(any(), any())).thenAnswer(
      (_) async => {
        'id': 99,
        'postId': 'p1',
        'parentId': 0,
        'text': 'Halo komen uji',
        'authorId': 'me',
        'authorName': 'Saya',
        'authorGender': '',
        'likeCount': 0,
        'shareCount': 0,
        'isLiked': false,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await pump(tester, _post());

    // Buka sheet komentar.
    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Ketik + kirim.
    await tester.enterText(find.byType(TextField), 'Halo komen uji');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Sheet TIDAK tertutup + komentar langsung tampil (optimistic/server).
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.text('Halo komen uji'), findsOneWidget);
    verify(() => timeline.addComment('p1', 'Halo komen uji')).called(1);

    // Tutup sheet + buang semua timer (auto-dismiss snackbar 4
    // detik + reconnect realtime ke URL dummy yang tak pernah tersambung).
    // Dua pump: exit butuh 1 frame untuk mulai + 1 frame untuk lepas route.
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsNothing, reason: 'sheet harus tertutup');
    _cleanupTestChannels();
    await tester.pump(const Duration(seconds: 120));
    expect(
      Supabase.instance.client.realtime.channels,
      isEmpty,
      reason: 'channel realtime harus bersih',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet komentar dikunci 70% layar saat komentar banyak',
      (tester) async {
    when(() => timeline.comments(any())).thenAnswer(
      (_) async => [
        for (var i = 0; i < 30; i++)
          {
            'id': 100 + i,
            'postId': 'p1',
            'parentId': 0,
            'text': 'Komentar $i dengan isi agak panjang',
            'authorId': 'u$i',
            'authorName': 'User $i',
            'authorGender': '',
            'likeCount': 0,
            'shareCount': 0,
            'isLiked': false,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
      ],
    );
    await pump(tester, _post());

    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Viewport test 600px → sheet tidak boleh lebih dari 420px (70%).
    final h = tester.getSize(find.byType(BottomSheet)).height;
    expect(h, lessThanOrEqualTo(420.0));

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    _cleanupTestChannels();
    await tester.pump(const Duration(seconds: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hapus komentar sendiri: ikon hanya di milikku + terhapus',
      (tester) async {
    Map<String, dynamic> cmt(int id, String authorId, String text) => {
          'id': id,
          'postId': 'p1',
          'parentId': 0,
          'text': text,
          'authorId': authorId,
          'authorName': authorId == 'me' ? 'Saya' : 'Orang',
          'authorGender': '',
          'likeCount': 0,
          'shareCount': 0,
          'isLiked': false,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
    when(() => timeline.comments(any())).thenAnswer(
      (_) async => [cmt(42, 'me', 'Komen saya'), cmt(43, 'other', 'Komen orang')],
    );
    when(() => timeline.deleteComment(any())).thenAnswer((_) async {});
    await pump(tester, _post());

    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Hanya 1 tombol hapus (komentar milik sendiri).
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Tap hapus → dialog konfirmasi → Hapus → komentar hilang.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hapus komentar?'), findsOneWidget);
    await tester.tap(find.text('Hapus').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => timeline.deleteComment(42)).called(1);
    expect(find.text('Komen saya'), findsNothing);
    expect(find.text('Komen orang'), findsOneWidget);

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    _cleanupTestChannels();
    await tester.pump(const Duration(seconds: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('balas komentar: chip muncul + kirim memakai parentId',
      (tester) async {
    when(() => timeline.comments(any())).thenAnswer(
      (_) async => [
        {
          'id': 77,
          'postId': 'p1',
          'parentId': 0,
          'text': 'Komentar asal',
          'authorId': 'other',
          'authorName': 'Orang',
          'authorGender': '',
          'likeCount': 0,
          'shareCount': 0,
          'isLiked': false,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    );
    when(() => timeline.replyComment(any(), any(), any()))
        .thenAnswer((_) async => {'ok': true, 'id': 88});
    await pump(tester, _post());

    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap tombol balas pada komentar → chip "Balas Orang" muncul.
    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Balas Orang'), findsWidgets);

    // Ketik lalu kirim → replyComment dipanggil dengan parentId=77.
    await tester.enterText(find.byType(TextField).last, 'balasanku');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => timeline.replyComment('p1', 77, 'balasanku')).called(1);

    // Tutup sheet + buang semua timer (pola sama test "kirim komentar").
    Navigator.of(tester.element(find.byType(TextField).last)).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsNothing, reason: 'sheet harus tertutup');
    _cleanupTestChannels();
    await tester.pump(const Duration(seconds: 120));
    expect(
      Supabase.instance.client.realtime.channels,
      isEmpty,
      reason: 'channel realtime harus bersih',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mengetik di composer tidak menghapus baris komentar (list utuh)',
      (tester) async {
    when(() => timeline.comments(any())).thenAnswer(
      (_) async => [
        for (var i = 0; i < 3; i++)
          {
            'id': 200 + i,
            'postId': 'p1',
            'parentId': 0,
            'text': 'Komen $i',
            'authorId': 'u$i',
            'authorName': 'Nama $i',
            'authorGender': '',
            'likeCount': 0,
            'shareCount': 0,
            'isLiked': false,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
      ],
    );
    await pump(tester, _post());

    await tester.tap(find.byIcon(PhosphorIconsRegular.chatCircle).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Komen 0'), findsOneWidget);
    expect(find.textContaining('Komen 2'), findsOneWidget);

    // Ketik banyak karakter ke composer → list komentar tetap utuh
    // (state tidak ikut ter-reset oleh rebuild ketikan).
    await tester.enterText(find.byType(TextField).last, 'halo mengetik cepat');
    await tester.pump();

    expect(find.textContaining('Komen 0'), findsOneWidget);
    expect(find.textContaining('Komen 2'), findsOneWidget);
    expect(find.text('halo mengetik cepat'), findsOneWidget);

    Navigator.of(tester.element(find.byType(TextField).last)).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsNothing, reason: 'sheet harus tertutup');
    _cleanupTestChannels();
    await tester.pump(const Duration(seconds: 120));
    expect(tester.takeException(), isNull);
  });

  // ── REDESIGN TIMELINE (ala Threads) ──
  group('Redesign Timeline ala Threads', () {
    testWidgets('badge "+ ikuti" tampil di avatar (belum follow & bukan sendiri)',
        (tester) async {
      await pump(tester, _post());
      expect(find.byIcon(Icons.add), findsOneWidget,
          reason: 'badge follow di avatar harus tampil');
      expect(tester.takeException(), isNull);
    });

    testWidgets('badge "+ ikuti" TIDAK tampil untuk post sendiri',
        (tester) async {
      final p = _post()..['authorId'] = 'me';
      await pump(tester, p);
      expect(find.byIcon(Icons.add), findsNothing,
          reason: 'post sendiri tak punya tombol ikuti');
    });

    testWidgets('teks "· Ikuti" & label Publik HILANG dari feed',
        (tester) async {
      await pump(tester, _post());
      // "Ikuti" (label tombol) & "Publik" tidak muncul sebagai teks di kartu.
      expect(find.textContaining('Ikuti'), findsNothing);
      expect(find.textContaining('Publik'), findsNothing);
    });

    testWidgets('angka 0 TIDAK ditampilkan di baris aksi', (tester) async {
      await pump(tester, _post(likes: 0, comments: 0, shares: 0));
      expect(find.text('0'), findsNothing);
      // Ikon aksi tetap ada (hati/komentar/kirim).
      expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.chatCircle), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.paperPlaneTilt), findsOneWidget);
    });

    testWidgets('angka besar diringkas (1200 → 1,2rb)', (tester) async {
      await pump(tester, _post(likes: 1200));
      expect(find.text('1,2rb'), findsOneWidget);
    });

    testWidgets('multi media → carousel horizontal (bukan grid)',
        (tester) async {
      // Uji langsung widget grid (deterministik, tanpa IO).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: PostPhotoGrid(
                thumbs: [_pngBytes, _pngBytes, _pngBytes],
                aspects: const [1.0, 1.0, 1.0],
                onOpenViewer: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final carousel = find.byKey(const ValueKey('photo_multi'));
      expect(carousel, findsOneWidget);
      final lv = find.descendant(
        of: carousel,
        matching: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(lv, findsOneWidget, reason: 'carousel = ListView horizontal');
      expect(tester.takeException(), isNull);
    });

    testWidgets('media tunggal → kotak (bukan carousel) + rasio dibatasi',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: PostPhotoGrid(
                // Rasio 9:16 (0.5625) → dibatasi ke 4:5 (0.8).
                thumbs: [_pngBytes],
                aspects: const [0.5625],
                onOpenViewer: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final single = find.byKey(const ValueKey('photo_single'));
      expect(single, findsOneWidget);
      final size = tester.getSize(single);
      // rightInset default 16 → lebar = 300 − 16 = 284; tinggi = 284 / 0.8.
      expect(size.width, closeTo(284, 1));
      expect(size.height, closeTo(284 / 0.8, 1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('tanpa overflow di layar sempit 360 (checklist desain)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      _post(
        author: 'Nama Panjang Sekali Biar Terpotong Ellipsis',
        text: 'Teks panjang ' * 20,
        images: [_pngBase64, _pngBase64],
        imageW: 1200,
        imageH: 900,
        likes: 1200,
        comments: 5,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Overflow memunculkan exception di test → harus null.
    expect(tester.takeException(), isNull);
    expect(find.byType(PostCard), findsOneWidget);
  });

  group('helper media (rasio ala Threads)', () {
    test('singleMediaAspect dibatasi 4:5 … 1.91:1', () {
      expect(singleMediaAspect(0, 0), 1.0);
      expect(singleMediaAspect(1000, 1000), 1.0);
      expect(singleMediaAspect(1000, 2000), closeTo(0.8, 0.0001));
      expect(singleMediaAspect(2000, 1000), closeTo(1.91, 0.0001));
      expect(singleMediaAspect(1200, 1600), closeTo(0.8, 0.0001));
    });

    test('carouselItemWidth dibatasi 3:4 … 4:3 pada tinggi 240', () {
      expect(carouselItemWidth(1000, 1000), 240);
      expect(carouselItemWidth(1000, 2000), closeTo(180, 0.0001));
      expect(carouselItemWidth(2000, 1000), closeTo(319.2, 0.01));
    });
  });
}
