import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/timeline_provider.dart';
import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/timeline_service.dart';
import 'package:chatyuk/widgets/post_card.dart';

import 'test_helper.dart';

/// Fase 5 — PostCard: render + perilaku kunci (logic-only, tanpa jaringan).
class MockTimelineService extends Mock implements TimelineService {}

class MockAuthService extends Mock implements AuthService {}

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
      // Avatar inline PNG kecil → _AuthorAvatar resolve SINKRON (tak
      // fallback ke ProfileAvatar yang menjadwalkan timer retry 300ms).
      'authorAvatar':
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  late MockTimelineService timeline;
  late MockAuthService auth;

  setUpAll(() async {
    await initSupabaseForTest();
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

  Future<void> pump(WidgetTester tester, Map<String, dynamic> post) async {
    final locale = LocaleProvider();
    final tp = TimelineProvider(service: timeline, autoInit: false);
    final ap = AuthProvider(authService: auth, autoInit: false);
    addTearDown(() {
      tp.dispose();
      ap.dispose();
      locale.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: locale),
          ChangeNotifierProvider.value(value: tp),
          ChangeNotifierProvider.value(value: ap),
        ],
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
}
