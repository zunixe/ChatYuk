import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/core/map_tile_provider.dart';
import 'package:chatyuk/widgets/location_bubble.dart';

/// Regresi: bubble chat memakai LocationBubble non-interaktif
/// (InteractiveFlag.none). Kalau mode ini gagal render (map hilang di
/// bubble walau preview composer tampil), test ini merah.
void main() {
  Widget host(LocationBubble b) =>  ProviderScope(child: MaterialApp(home: Scaffold(body: Center(child: b))));

  testWidgets('LocationBubble non-interaktif render tanpa error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LocationBubble(
          location: ChatLocation(lat: -6.9, lng: 107.6),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LocationBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LocationBubble interaktif (preview composer) render', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LocationBubble(
          location: ChatLocation(lat: -6.9, lng: 107.6),
          width: double.infinity,
          height: 150,
          interactive: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LocationBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'peta LANGSUNG tampil saat cold start (tanpa tap dulu)',
    (tester) async {
      // Regresi keluhan user 2026-10-14: kartu peta abu & harus diklik dulu
      // baru tampil. Sekarang FlutterMap di-mount sejak frame pertama.
      await tester.pumpWidget(
        host(
          const LocationBubble(
            location: ChatLocation(lat: -6.9, lng: 107.6),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(FlutterMap),
        findsOneWidget,
        reason: 'peta harus sudah mount sebelum tap apa pun',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tap bubble non-interaktif MEMICU aksi (regresi FlutterMap serap gesture)',
    (tester) async {
      // Dulu FlutterMap menyerap pointer walau InteractiveFlag.none →
      // GestureDetector luar tak dapat tap → Maps tak pernah terbuka.
      var taps = 0;
      await tester.pumpWidget(
        host(
          LocationBubble(
            location: const ChatLocation(lat: -6.9, lng: 107.6),
            onTapOverride: () => taps++,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(LocationBubble));
      await tester.pump();
      expect(taps, 1, reason: 'tap harus sampai ke pembungkus');
    },
  );

  testWidgets(
    'TileLayer memakai provider BERSAMA (cache) & errorTileCallback diam',
    (tester) async {
      // Regresi 2026-10-14: dua widget memakai URL template sendiri-sendiri
      // tanpa cache → scroll ulang histori chat mengunduh tile berulang.
      await tester.pumpWidget(
        host(
          const LocationBubble(
            location: ChatLocation(lat: -6.9, lng: 107.6),
          ),
        ),
      );
      await tester.pump();
      final tile = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tile.urlTemplate, osmTileUrl);
      expect(
        identical(tile.tileProvider, basicMapTiles),
        isTrue,
        reason: 'harus instance yang sama supaya cache-nya dipakai bersama',
      );
      expect(tile.errorTileCallback, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('badge lokasi live hidup (ticker 1 menit)', (tester) async {
    await tester.pumpWidget(
      host(
        LocationBubble(
          location: ChatLocation(
            lat: -6.9,
            lng: 107.6,
            live: true,
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LocationBubble), findsOneWidget);
    // Majukan 1 menit: ticker rebuild tanpa error, label ikut berubah.
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });
}
