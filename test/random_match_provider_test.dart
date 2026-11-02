import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/random_match.dart';
import 'package:chatyuk/providers/riverpod/call_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/random_match_provider.dart';
import 'package:chatyuk/services/points_service.dart';
import 'package:chatyuk/services/random_match_service.dart';

class MockRandomMatchService extends Mock implements RandomMatchService {}

/// Sesi media palsu — startSession butuh mengembalikan CallSession; mock
/// interface saja (tidak menyentuh WebRTC).
class MockCallSession extends Mock implements CallSession {}

class MockPointsService extends Mock implements PointsService {}

/// PointsProvider palsu — trackMission versi asli menembak RPC (Supabase
/// belum init di test). No-op supaya alur match bisa diuji sampai inCall.
/// NB: ctor induk menuntut PointsService (default-nya menyentuh
/// Supabase.instance) → inject mock.
class _FakePoints extends PointsNotifier {
  _FakePoints() : super(service: MockPointsService());

  @override
  PointsState build() => const PointsState();

  @override
  void trackMission(String missionKey, {int increment = 1}) {}
}

/// CallProvider palsu: tidak menyentuh WebRTC, hanya mencatat pemanggilan.
class _FakeCall extends CallNotifier {
  int startSessionCalls = 0;
  int hangupCalls = 0;

  /// Bila diisi, startSession "berhasil" mengembalikan sesi ini (default
  /// melempar supaya test lama menguji jalur error tanpa sesi riil).
  CallSession? session;

  @override
  CallState build() => const CallState();

  @override
  Future<CallSession> startSession({
    required String callId,
    required String remoteUid,
    required String remoteName,
    required String callType,
    required bool isCaller,
    required CallMode mode,
    required String myName,
    required String myGender,
    required String notifBody,
    required String notifChannel,
    required String notifDesc,
    required String chatId,
    List<Map<String, dynamic>> pendingSignals = const [],
  }) async {
    startSessionCalls++;
    if (session != null) return session!;
    throw StateError('stop-here');
  }

  @override
  Future<void> hangup() async {
    hangupCalls++;
  }
}

/// Kontrak fitur Random Video Call:
/// - Match → `waiting` = fase searching (bukan inCall).
/// - Server bilang matched → sesi dimulai & fase inCall.
/// - Error server (mis. FEATURE_DISABLED) → kembali idle + kode error.
/// - Next → akhiri call lalu masuk antrean lagi.
/// - Keluar layar → keluar antrean.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRandomMatchService svc;
  final containers = <ProviderContainer>[];
  late _FakeCall fakeCall;

  setUp(() {
    svc = MockRandomMatchService();
    fakeCall = _FakeCall();
    when(() => svc.leave()).thenAnswer((_) async {});
    when(() => svc.watchQueue()).thenAnswer((_) => const Stream<void>.empty());
    when(() => svc.stats()).thenAnswer(
      (_) async => (waiting: 0, online: 0, sample: const <RandomRadarUser>[]),
    );
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
  });

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [
        randomMatchServiceProvider.overrideWithValue(svc),
        callProvider.overrideWith(() => fakeCall),
        pointsProvider.overrideWith(_FakePoints.new),
      ],
    );
    containers.add(c);
    return c;
  }

  Map<String, dynamic> matchedPayload() => {
    'status': 'matched',
    'call_id': 'call-1',
    'is_caller': true,
    'partner': {
      'uid': 'u2',
      'nickname': 'Rina',
      'gender': 'female',
      'age': 22,
      'city': 'Bandung',
      'avatar': '',
      'distance_km': 3.4,
    },
  };

  test('join → waiting = fase searching (belum masuk call)', () async {
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    expect(c.read(randomMatchProvider).phase, RandomMatchPhase.searching);
    expect(c.read(randomMatchProvider).partner, isNull);
  });

  test('join → matched = sesi dimulai & fase inCall + data lawan', () async {
    when(() => svc.join(any())).thenAnswer((_) async => matchedPayload());
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    final st = c.read(randomMatchProvider);
    // _FakeCall melempar setelah mencatat → provider menandai error media,
    // tapi pemanggilan startSession membuktikan sesi benar-benar diminta.
    expect(fakeCall.startSessionCalls, 1);
    expect(st.partner?.nickname, 'Rina');
    expect(st.partner?.distanceKm, 3.4);
    expect(st.callId, 'call-1');
  });

  test('join → no_funds = idle + MATCH_NEED_COIN (fee saat pair, bukan klik)',
      () async {
    // Charge-on-match (2026-10-31): server mengembalikan 'no_funds' untuk
    // male yang tak mampu bayar SEBELUM masuk antrean — koin tidak hangus
    // saat menunggu. Provider memetakan ke MATCH_NEED_COIN → dialog top-up.
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'no_funds'});
    final c = make();
    await c.read(randomMatchProvider.notifier).start();
    final st = c.read(randomMatchProvider);
    expect(st.phase, RandomMatchPhase.idle);
    expect(st.errorCode, 'MATCH_NEED_COIN');
    expect(st.partner, isNull);
  });

  test('fitur belum aktif → idle + errorCode FEATURE_DISABLED', () async {
    when(() => svc.join(any())).thenThrow(Exception('FEATURE_DISABLED'));
    final c = make();
    await c.read(randomMatchProvider.notifier).start();
    final st = c.read(randomMatchProvider);
    expect(st.phase, RandomMatchPhase.idle);
    expect(st.errorCode, 'FEATURE_DISABLED');
  });

  test('sedang di panggilan lain → errorCode ALREADY_IN_CALL', () async {
    when(() => svc.join(any())).thenThrow(Exception('ALREADY_IN_CALL'));
    final c = make();
    await c.read(randomMatchProvider.notifier).start();
    expect(c.read(randomMatchProvider).errorCode, 'ALREADY_IN_CALL');
  });

  test('batal mencari → idle + leave dipanggil', () async {
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    await n.cancel();
    expect(c.read(randomMatchProvider).phase, RandomMatchPhase.idle);
    verify(() => svc.leave()).called(greaterThanOrEqualTo(1));
  });

  test('Next → hangup lalu masuk antrean lagi', () async {
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    await n.next();
    expect(fakeCall.hangupCalls, 1);
    expect(c.read(randomMatchProvider).phase, RandomMatchPhase.searching);
  });

  test('lawan menutup call → idle + partnerEnded (TANPA auto-cari)',
      () async {
    // Regresi UX: sebelumnya layar hanya muter2 selamanya. Sekarang sesi
    // berakhir dari sisi lawan → banner "X keluar" + user pencet Next.
    fakeCall.session = MockCallSession();
    when(() => svc.join(any())).thenAnswer((_) async => matchedPayload());
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    expect(c.read(randomMatchProvider).phase, RandomMatchPhase.inCall);

    clearInteractions(svc);
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    await n.onRemoteEnded();

    final st = c.read(randomMatchProvider);
    expect(st.phase, RandomMatchPhase.idle);
    expect(st.partnerEnded, isTrue);
    expect(fakeCall.hangupCalls, 1);
    verifyNever(() => svc.join(any())); // tidak auto-mencari

    // Next setelah itu → flag dibersihkan + masuk antrean lagi.
    await n.next();
    final st2 = c.read(randomMatchProvider);
    expect(st2.partnerEnded, isFalse);
    expect(st2.phase, RandomMatchPhase.searching);
    verify(() => svc.join(any())).called(1);
  });

  test('keluar layar → keluar antrean + state reset', () async {
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    await n.leaveScreen();
    expect(c.read(randomMatchProvider).phase, RandomMatchPhase.idle);
    verify(() => svc.leave()).called(greaterThanOrEqualTo(1));
  });

  test('ganti filter gender saat mencari → join ulang dengan filter baru',
      () async {
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    final c = make();
    final n = c.read(randomMatchProvider.notifier);
    await n.start();
    clearInteractions(svc);
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    n.setWantGender('female');
    await Future<void>.delayed(Duration.zero);
    verify(() => svc.join('female')).called(1);
  });
}
