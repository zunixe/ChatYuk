import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/providers/riverpod/location_provider.dart';
import 'package:chatyuk/widgets/location_picker_sheet.dart';

/// Service palsu: mengembalikan urutan emisi yang bisa dikendalikan test,
/// tanpa pernah menyentuh platform channel GPS.
class _FakeLocationService extends LocationService {
  _FakeLocationService({
    this.permitted = true,
    this.cached,
    this.fixes = const [],
  }) : super(_NoopSupabase());

  final bool permitted;
  final LocationFix? cached;
  final List<LocationFix> fixes;
  int positionStreamCalls = 0;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  LocationFix? cachedFix({Duration maxAge = const Duration(hours: 12)}) =>
      cached;

  @override
  Stream<LocationFix> positionStream() {
    positionStreamCalls++;
    return Stream<LocationFix>.fromIterable(fixes);
  }

  @override
  Stream<NearbyData> nearbyData(
    double lat,
    double lng, {
    int radiusM = 400,
    int limit = 8,
  }) async* {
    // Emisi 1: alamat saja (pola asli: cepat, tanpa menunggu Overpass).
    yield const NearbyData(address: 'Jl. Uji No. 1');
    // Emisi 2: alamat + POI.
    yield NearbyData(
      address: 'Jl. Uji No. 1',
      places: [
        NearbyPlace(name: 'Jl. Uji No. 1', lat: lat, lng: lng),
        const NearbyPlace(name: 'Masjid Uji', lat: -6.9, lng: 107.6),
      ],
      placesDone: true,
    );
  }
}

/// Tidak dipakai (semua method yang butuh Supabase di-override), tapi
/// konstruktor induk butuh instance — dibuat malas & tidak pernah diakses.
class _NoopSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Supabase tidak boleh dipakai di test');
}

Widget _host(LocationService svc) {
  return ProviderScope(
    overrides: [
      locationProvider.overrideWithValue(
        LocationNotifier(location: svc, geo: GeoService()),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showLocationPickerSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final s = S(isId: true);

  testWidgets('sheet TAMPIL INSTAN walau tidak ada koordinat sama sekali', (
    tester,
  ) async {
    // Regresi utama: dulu sheet baru muncul SETELAH GPS fix (20s+ tanpa
    // spinner). Sekarang frame pertama sudah berisi peta.
    final svc = _FakeLocationService(
      cached: null,
      fixes: const [], // GPS tidak pernah memberi fix.
    );
    await tester.pumpWidget(_host(svc));
    await tester.tap(find.text('open'));
    await tester.pump(); // satu frame: animasi sheet mulai
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'peta harus sudah mount tanpa menunggu GPS');
    // Tanpa koordinat: status "Mendeteksi lokasi..." + aksi kirim disabled.
    expect(find.text(s.locFetching), findsWidgets);
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNull,
        reason: 'kirim lokasi harus disabled sampai ada koordinat');
    // JANGAN pumpAndSettle: tanpa koordinat ada CircularProgressIndicator
    // yang beranimasi terus → settle tidak akan pernah selesai.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache fix dipakai lebih dulu → peta langsung bertitik', (
    tester,
  ) async {
    final svc = _FakeLocationService(
      cached: const LocationFix(
        -6.9,
        107.6,
        accuracyM: 50,
        source: FixSource.cache,
        at: null,
      ),
      fixes: const [],
    );
    await tester.pumpWidget(_host(svc));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FlutterMap), findsOneWidget);
    // Dengan cache: tombol kirim AKTIF sejak awal.
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNotNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('fix GPS menyusul mengaktifkan kirim & menampilkan alamat', (
    tester,
  ) async {
    final svc = _FakeLocationService(
      cached: null,
      fixes: const [
        LocationFix(-6.91, 107.61, accuracyM: 8, source: FixSource.gps),
      ],
    );
    await tester.pumpWidget(_host(svc));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(svc.positionStreamCalls, 1, reason: 'stream mulai di initState');
    // Biarkan stream + nearbyData mengalir.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNotNull, reason: 'GPS fix = boleh kirim');
    // Alamat dari emisi pertama nearbyData tampil sebagai subtitle.
    expect(find.text('Jl. Uji No. 1'), findsWidgets);
    // POI final → skeleton hilang & "Masjid Uji" muncul.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Masjid Uji'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('POI kosong → pesan "tidak ada tempat terdekat"', (tester) async {
    final svc = _EmptyPoiService();
    await tester.pumpWidget(_host(svc));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(s.locNoPlaces), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('izin ditolak → sheet tidak dibuka, snackbar muncul', (
    tester,
  ) async {
    final svc = _DeniedService();
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationProvider.overrideWithValue(
            LocationNotifier(location: svc, geo: GeoService()),
          ),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => pickChatLocation(
                  ctx,
                  messenger: messengerKey.currentState!,
                ),
                child: const Text('pick'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FlutterMap), findsNothing,
        reason: 'tanpa izin tidak ada peta yang dibuka');
    expect(find.text(s.locPermissionDenied), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hasil sheet berisi koordinat fix yang aktif', (tester) async {
    final svc = _FakeLocationService(
      cached: const LocationFix(
        -6.9,
        107.6,
        accuracyM: 12,
        source: FixSource.cache,
        at: null,
      ),
      fixes: const [],
    );
    ChatLocation? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationProvider.overrideWithValue(
            LocationNotifier(location: svc, geo: GeoService()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await showLocationPickerSheet(ctx);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    // Tap opsi "Kirim lokasi saat ini".
    await tester.tap(find.byIcon(Icons.my_location_rounded).last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.lat, closeTo(-6.9, 1e-6));
    expect(result!.lng, closeTo(107.6, 1e-6));
    expect(result!.accuracyM, 12);
    expect(result!.live, isFalse);
  });
}

/// Semua POI gagal → hanya titik pusat (dianggap "tidak ada tempat").
class _EmptyPoiService extends _FakeLocationService {
  _EmptyPoiService()
      : super(
          cached: const LocationFix(
            -6.9,
            107.6,
            accuracyM: 10,
            source: FixSource.cache,
            at: null,
          ),
          fixes: const [],
        );

  @override
  Stream<NearbyData> nearbyData(
    double lat,
    double lng, {
    int radiusM = 400,
    int limit = 8,
  }) async* {
    yield const NearbyData(address: 'Jl. Sepi');
    yield NearbyData(
      address: 'Jl. Sepi',
      places: [NearbyPlace(name: 'Jl. Sepi', lat: lat, lng: lng)],
      placesDone: true,
    );
  }
}

class _DeniedService extends _FakeLocationService {
  _DeniedService() : super(permitted: false);

  @override
  Future<bool> requestPermission() async => false;
}
