import 'dart:async';

/// Aksi yang datang dari UI panggilan SISTEM (ConnectionService Android /
/// CallKit iOS) — dijembatani ke Dart lewat MethodChannel.
///
/// Dipakai supaya `CallProvider` tidak perlu tahu platform: kalau tidak ada
/// jembatan native (iOS/web/desktop/test), [CallUiStub] membuat semuanya
/// no-op dan perilaku app persis seperti sebelumnya (layar Dart).
abstract class CallUi {
  /// Tampilkan panggilan masuk di UI sistem.
  /// [callId] juga dipakai untuk menutup ([dismiss]).
  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String callType,
  });

  /// Panggilan sudah tersambung — pindahkan dari UI "ringing" ke UI
  /// "in-call" milik sistem (durasi berjalan, tombol end).
  Future<void> setConnected(String callId);

  /// Tutup UI sistem untuk [callId] (ditolak, dibatalkan, atau berakhir).
  Future<void> dismiss(String callId);

  /// Callback dari UI sistem. Native memanggil ini saat pengguna menekan
  /// terima/tolak dari layar kunci/headset, ATAU saat sistem mengakhiri call.
  set onAccept(FutureOr<void> Function(String callId)? cb);
  set onDecline(FutureOr<void> Function(String callId)? cb);
  set onEnd(FutureOr<void> Function(String callId)? cb);

  /// Lepas channel (dipanggil saat dispose/test).
  Future<void> dispose();
}

/// Implementasi no-op — dipakai di semua platform yang tidak punya UI
/// panggilan sistem (iOS saat ini, web, desktop) dan di unit test.
class CallUiStub implements CallUi {
  @override
  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String callType,
  }) async {}

  @override
  Future<void> setConnected(String callId) async {}

  @override
  Future<void> dismiss(String callId) async {}

  @override
  set onAccept(FutureOr<void> Function(String callId)? cb) {}

  @override
  set onDecline(FutureOr<void> Function(String callId)? cb) {}

  @override
  set onEnd(FutureOr<void> Function(String callId)? cb) {}

  @override
  Future<void> dispose() async {}
}
