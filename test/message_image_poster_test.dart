import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/chat_poster_cache.dart';
import 'package:chatyuk/widgets/message/message_image.dart';
import 'package:chatyuk/widgets/message/poster_grid.dart';

import 'test_helper.dart';

/// Mengunci: POSTER (grid RGBA, sinkron) DILUKIS di frame-1 → tidak ada
/// kotak kosong / spinner sebelum foto tajam (anti-kedip). Poster v2 TIDAK
/// memakai `Image` (decode async = kosong 1 frame = kedip).
void main() {
  final posterBytes = Uint8List(ChatPosterCache.byteLength)
    ..fillRange(0, ChatPosterCache.byteLength, 120);

  setUp(() {
    mockPathProvider();
    ChatPosterCache.instance.clearMemOnly();
  });

  tearDown(() {
    ChatPosterCache.instance.clearMemOnly();
  });

  /// IO nyata (prewarm/save) HARUS di runAsync — di fake-async akan menggantung.
  Future<void> warmPoster(WidgetTester t) async {
    await t.runAsync(() async {
      await ChatPosterCache.instance.prewarm();
      await ChatPosterCache.instance.save('m-poster', posterBytes);
    });
  }

  Future<void> pumpTile(WidgetTester t, {required bool fill, String id = 'm-poster'}) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: MessageImage(
                  // Kosong = belum ada data (jalur placeholder), TANPA
                  // jaringan → test deterministik.
                  imageData: '',
                  chatKey: '',
                  messageId: id,
                  fill: fill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tile album: poster tampil frame-1, tanpa spinner',
      (tester) async {
    await warmPoster(tester);
    await pumpTile(tester, fill: true);
    // Frame PERTAMA (tanpa pump tambahan) sudah melukis poster.
    expect(find.byType(PosterGrid), findsOneWidget, reason: 'poster frame-1');
    expect(find.byType(Image), findsNothing, reason: 'tanpa decode async');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('foto tunggal: poster tampil frame-1, tanpa spinner',
      (tester) async {
    await warmPoster(tester);
    await pumpTile(tester, fill: false);
    expect(find.byType(PosterGrid), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('COLD START: poster dibaca dari DISK (RAM kosong) di frame-1',
      (tester) async {
    // Simulasikan proses BARU: file poster ada di disk, RAM kosong.
    await warmPoster(tester);
    ChatPosterCache.instance.clearMemOnly(); // RAM kosong = cold start
    await pumpTile(tester, fill: true);
    expect(find.byType(PosterGrid), findsOneWidget,
        reason: 'poster harus dibaca sinkron dari disk & dilukis frame-1');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('tanpa poster: placeholder senyap (tetap tanpa spinner frame-1)',
      (tester) async {
    // id UNIK (belum pernah di-save) → benar-benar tanpa poster (disk/RAM).
    await pumpTile(tester, fill: true, id: 'm-noposter');
    expect(find.byType(PosterGrid), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}
