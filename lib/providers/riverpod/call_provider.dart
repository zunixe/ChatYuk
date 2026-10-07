import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../main.dart';
import '../../screens/incoming_call_screen.dart';
import '../../services/call_service.dart';
export '../../services/call_service.dart'
    show CallSession, CallPhase, CallEndReason, CallEndReasonMessage;
import '../../services/call_notification.dart';
import '../../services/call/call_ui_factory.dart';
import '../../utils.dart';

enum CallMode { fullscreen, chat }

/// Nama rute terdaftar di navigator — dipakai RouteTracker supaya banner
/// call & handler notifikasi tidak menumpuk layar chat/call duplikat.
const String kCallScreenRoute = 'call-screen';

String privateChatRoute(String chatId) => 'private-chat:$chatId';

/// Memantau rute bernama yang sedang aktif di stack navigator.
///
/// Mencatat setiap push/pop/replace ke logcat (`[NAV]`, release-safe via
/// debugPrint) — jejak ini dipakai mendiagnosa laporan "tombol back mati":
/// saat back ditekan, log menunjukkan apakah pop terjadi, di-veto PopScope,
/// atau tidak ada event sama sekali (UI thread macet).
class RouteTracker extends NavigatorObserver {
  final Set<String> active = {};

  bool contains(String name) => active.contains(name);

  static String _label(Route<dynamic>? route) {
    if (route == null) return '-';
    final n = route.settings.name;
    if (n != null && n.isNotEmpty) return n;
    return route.runtimeType.toString();
  }

  void _add(Route<dynamic> route) {
    final n = route.settings.name;
    if (n != null && n.isNotEmpty) active.add(n);
    debugPrint('[NAV] push ${_label(route)} stack=${active.toList()}');
  }

  void _remove(Route<dynamic> route) {
    final n = route.settings.name;
    if (n != null && n.isNotEmpty) active.remove(n);
    debugPrint('[NAV] pop ${_label(route)} stack=${active.toList()}');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _remove(oldRoute);
    if (newRoute != null) _add(newRoute);
    debugPrint(
        '[NAV] replace ${_label(oldRoute)} -> ${_label(newRoute)} stack=${active.toList()}');
  }
}

final RouteTracker routeTracker = RouteTracker();


/// CallProvider: pendengar global panggilan masuk + penanda call aktif.
/// Dipakai supaya panggilan masuk muncul sebagai screen overlay di mana pun
/// user berada (tanpa menunggu push), dan supaya user yang sedang di call
/// otomatis ditandai busy.
/// State call (immutable — yang di-watch widget).
class CallState {
  final String? activeCallId;
  final CallSession? activeSession;
  final CallMode? activeMode;
  final String? activeChatId;

  const CallState({
    this.activeCallId,
    this.activeSession,
    this.activeMode,
    this.activeChatId,
  });

  @override
  bool operator ==(Object other) =>
      other is CallState &&
      other.activeCallId == activeCallId &&
      other.activeSession == activeSession &&
      other.activeMode == activeMode &&
      other.activeChatId == activeChatId;

  @override
  int get hashCode =>
      Object.hash(activeCallId, activeSession, activeMode, activeChatId);

  bool get inCall => activeCallId != null;
}

class CallNotifier extends Notifier<CallState> {
  var _disposed = false;

  static CallUi _ui = createCallUi();

  /// UI panggilan SISTEM — di-inject di test via uiForTest.
  static CallUi get callUi => _ui;
  @visibleForTesting
  static set callUiForTest(CallUi ui) => _ui = ui;

  final CallService _service = CallService.instance;

  @override
  CallState build() {
    ref.onDispose(_disposeAll);
    _ui.onAccept = (callId) => _onSystemAccept(callId);
    _ui.onDecline = (callId) => _onSystemDecline(callId);
    _ui.onEnd = (callId) => _onSystemEnd(callId);
    return const CallState();
  }

  void _emit() {
    if (_disposed) return;
    state = CallState(
      activeCallId: _activeCallId,
      activeSession: _activeSession,
      activeMode: _activeMode,
      activeChatId: _activeChatId,
    );
  }

  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  StreamSubscription<dynamic>? _authSub;
  bool _listening = false;

  /// callId call yang sedang aktif (CallScreen / IncomingCallScreen terbuka).
  String? _activeCallId;
  String? get activeCallId => _activeCallId;

  bool get inCall => _activeCallId != null;

  /// Session panggilan aktif (shared) — dipakai CallScreen (fullscreen) maupun
  /// overlay video dalam chat. Kepemilikan session ada di provider ini, bukan
  /// di widget, supaya stream tetap hidup saat layar diganti (expand↔collapse).
  CallSession? _activeSession;
  CallSession? get activeSession => _activeSession;
  CallMode? _activeMode;
  CallMode? get activeMode => _activeMode;
  String? _activeChatId;
  String? get activeChatId => _activeChatId;

  /// Ganti mode panggilan aktif (fullscreen ⇄ chat) — dipakai saat
  /// expand/minimize supaya overlay & banner ikut bereaksi.

  // ── Passthrough (Fase 9b) — screen tidak import CallService ──
  String? get callUid => _service.uid;
  Future<String> startCall(String calleeUid, String callType) =>
      _service.startCall(calleeUid, callType);
  Future<void> updateCallStatus(String callId, String status) =>
      _service.updateStatus(callId, status);

  /// Akhiri panggilan dari UI dengan GARANSI bersih.
  ///
  /// `session.end()` bisa langsung no-op bila session sudah `_closed`
  /// (mis. lawan menutup lebih dulu / phase sudah ended) — tombol "Akhiri"
  /// lalu terasa "tidak jalan" karena overlay tetap tampil. Di sini selalu
  /// panggil end() (untuk signaling bila masih hidup) LALU paksa clearSession
  /// supaya UI pasti hilang, tanpa menunggu timer.
  Future<void> hangup() async {
    final sess = _activeSession;
    if (sess != null) {
      try {
        await sess.end();
      } catch (_) {}
    }
    await clearSession();
  }

  Future<Map<String, dynamic>?> getCall(String callId) => _service.getCall(callId);
  /// Riwayat panggilan user (masuk/keluar) — untuk halaman Panggilan Terbaru.
  Future<List<Map<String, dynamic>>> recentCalls({int limit = 50}) =>
      _service.listMyRecentCalls(limit: limit);

  /// Nama tampilan batch (uid → nickname) untuk riwayat panggilan.
  Future<Map<String, String>> lookupNames(List<String> uids) =>
      _service.lookupNicknames(uids);
  /// Gender batch (uid → gender) untuk mewarnai avatar riwayat panggilan.
  Future<Map<String, String>> lookupGenders(List<String> uids) =>
      _service.lookupGenders(uids);
  Future<String?> getNickname(String uid) => _service.getNickname(uid);
  Stream<String> onCallStatus(String callId) => _service.onCallStatus(callId);
  void releaseCallStatus(String callId) => _service.releaseCallStatus(callId);
  Future<void> sendCallSignal(String callId, String type, {Map<String, dynamic>? payload}) =>
      _service.sendSignal(callId, type, payload: payload);

  // CallNotification (notif foreground panggilan)
  Future<void> notifShowActive({
    required String body,
    required String channelName,
    required String channelDesc,
    required String chatId,
    required String otherUid,
    required String otherName,
  }) =>
      CallNotification.showActive(
        body: body,
        channelName: channelName,
        channelDesc: channelDesc,
        chatId: chatId,
        otherUid: otherUid,
        otherName: otherName,
      );
  Future<void> notifStartLive({required String text}) =>
      CallNotification.startLive(text: text);
  Future<void> notifStopLive() => CallNotification.stopLive();
  Future<void> notifCancel() => CallNotification.cancel();

  // ── Notif "panggilan aktif" (foreground service) ──
  // Metadata disimpan di provider supaya bisa DIPASANG ULANG saat app
  // dibuka kembali. Notif foreground service bisa hilang saat app keluar
  // (di-swipe) atau service di-restart OS — dulu tidak ada yang memasang
  // ulang sehingga tap-untuk-kembali-ke-panggilan lenyap padahal call masih
  // hidup.
  String? _notifBody;
  String? _notifChannel;
  String? _notifDesc;

  /// Pasang ulang notif panggilan aktif bila sesi masih hidup tapi notif
  /// hilang (mis. setelah app dibuka kembali dari recents). Idempoten:
  /// kalau service masih jalan hanya memperbarui notif; kalau mati → start.
  ///
  /// Best-effort: kegagalan notif tidak boleh mengganggu alur panggilan.
  Future<void> ensureActiveNotif() async {
    if (_activeSession == null) return;
    final body = _notifBody;
    if (body == null) return;
    try {
      await CallNotification.ensureActive(
        body: body,
        channelName: _notifChannel ?? body,
        channelDesc: _notifDesc ?? body,
        chatId: _activeChatId ?? '',
        otherUid: _activeSession!.remoteUid,
        otherName: _activeSession!.remoteName,
      );
    } catch (e) {
      dlog('[CallProvider] ensureActiveNotif error: $e');
    }
  }

  void setMode(CallMode mode) {
    if (_activeMode == mode) return;
    _activeMode = mode;
    _emit();
  }

  Timer? _clearTimer;

  /// Mulai mendengarkan panggilan masuk. Semua akun dengan profil (terdaftar,
  /// anon, dummy) menerima call — konsisten dengan toggle "call all users".
  /// Otomatis re-subscribe saat sesi berganti (dummy ⇄ admin / logout) supaya
  /// channel realtime menunjuk ke uid yang sedang aktif.
  void ensureListening({required bool registered}) {
    if (_listening) return;
    _listening = true;
    _subscribeIncoming();
    // Re-subscribe otomatis ketika sesi berubah — event signedIn/tokenRefreshed
    // ter-emit saat swap dummy (setSession) maupun login ulang.
    _authSub ??= SupabaseConfig.client.auth.onAuthStateChange.listen((_) {
      _subscribeIncoming();
    }, onError: (e) => dlog('[CallProvider] auth stream error: $e'));
  }

  void _subscribeIncoming() {
    _incomingSub?.cancel();
    _incomingSub = null;
    _incomingSub = _service.onIncomingCall().listen(
      _onIncoming,
      onError: (e) => dlog('[CallProvider] incoming stream error: $e'),
    );
    dlog('[CallProvider] listening incoming calls (uid=${_service.uid})');
  }

  void _onIncoming(Map<String, dynamic> row) {
    final callId = row['id'] as String?;
    if (callId == null) return;
    final callerUid = row['caller_id'] as String? ?? '';
    final callType = row['call_type'] as String? ?? 'video';

    if (_activeCallId != null) {
      // Sedang di call → tandai busy (caller melihat status busy).
      // Fire-and-forget: JANGAN tahan callback realtime — dulu `await` di
      // sini menunda semua event panggilan berikutnya.
      if (_activeCallId != callId) {
        unawaited(_service.updateStatus(callId, 'busy').catchError((_) {}));
      }
      return;
    }
    if (_activeCallId == callId) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _activeCallId = callId;
    // Layar Dart DULU (ring instan, tak menunggu network) — lalu lengkapi
    // UI panggilan SISTEM dengan nama pemanggil (fetch nickname 1×).
    nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callId: callId,
          callerUid: callerUid,
          callType: callType,
          chatId: row['chat_id'] as String? ?? '',
        ),
      ),
    );
    unawaited(
      _showSystemIncoming(
        callId: callId,
        callerUid: callerUid,
        callType: callType,
      ),
    );
  }

  Future<void> _showSystemIncoming({
    required String callId,
    required String callerUid,
    required String callType,
  }) async {
    // RESPONS CEPAT: tampilkan ring SISTEM dulu dengan nama seadanya, baru
    // perbarui dengan nama asli setelah fetch selesai. Dulu `await` nickname
    // (query network) MENAHAN ring sistem → layar kunci terasa lama muncul.
    var name = _pendingIncomingName ?? '';
    await CallNotifier.callUi.showIncoming(
      callId: callId,
      callerName: name.isEmpty ? 'ChatYuk' : name,
      callType: callType,
    );
    if (name.isNotEmpty) return;
    try {
      final fetched = await _service.getNickname(callerUid) ?? '';
      if (fetched.isEmpty) return;
      // Layar Dart sudah tampil → cukup pastikan nama di layar sistem ikut
      // benar bila masih panggilan yang sama.
      if (_activeCallId != callId) return;
      await CallNotifier.callUi.showIncoming(
        callId: callId,
        callerName: fetched,
        callType: callType,
      );
    } catch (_) {}
  }

  /// Nama pemanggil dari payload PUSH (kalau ada) — dipakai langsung supaya
  /// ring sistem tidak menunggu query. Diisi di jalur FCM/killed state.
  String? _pendingIncomingName;

  /// Simpan nama pemanggil dari payload push SEBELUM layar incoming dibuka
  /// (dipanggil dari jalur notifikasi di main.dart).
  void setPendingIncomingName(String name) {
    if (name.isEmpty) return;
    _pendingIncomingName = name;
  }

  /// Handler "terima" dari UI SISTEM (layar kunci/headset). Diteruskan ke
  /// IncomingCallScreen bila sedang terbuka; bila tidak ada layar (mis. app
  /// baru dibuka dari killed state), native sudah membuka MainActivity
  /// dengan intent accept → ditangani `_openFromData` di main.dart.
  Future<void> Function()? _screenAccept;
  Future<void> Function()? _screenDecline;

  /// Didaftarkan IncomingCallScreen selama layar itu hidup.
  void bindIncomingScreen({
    required String callId,
    required Future<void> Function() onAccept,
    required Future<void> Function() onDecline,
  }) {
    _screenCallId = callId;
    _screenAccept = onAccept;
    _screenDecline = onDecline;
  }

  void unbindIncomingScreen(String callId) {
    if (_screenCallId == callId) {
      _screenCallId = null;
      _screenAccept = null;
      _screenDecline = null;
    }
  }

  String? _screenCallId;

  Future<void> _onSystemAccept(String callId) async {
    if (_screenCallId == callId && _screenAccept != null) {
      await _screenAccept!();
      return;
    }
    // Tidak ada layar (app baru dibuka dari kondisi mati / notifikasi).
    // Ambil detail call dari DB lalu buka IncomingCallScreen mode
    // auto-accept — memakai alur terima yang sama, bukan duplikat.
    Map<String, dynamic>? row;
    try {
      row = await _service.getCall(callId);
    } catch (_) {}
    if (row == null) {
      dlog('[CallProvider] onAccept sistem: call $callId tidak ditemukan');
      return;
    }
    if (_activeCallId != null && _activeCallId != callId) {
      // Sudah ada call lain → tandai busy.
      try {
        await _service.updateStatus(callId, 'busy');
      } catch (_) {}
      return;
    }
    final status = row['status'] as String?;
    if (status == null || status == 'ended' || status == 'canceled' ||
        status == 'declined' || status == 'missed') {
      await CallNotifier.callUi.dismiss(callId);
      return;
    }
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _activeCallId = callId;
    nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callId: callId,
          callerUid: row!['caller_id'] as String? ?? '',
          callType: row['call_type'] as String? ?? 'video',
          chatId: row['chat_id'] as String? ?? '',
          autoAccept: true,
        ),
      ),
    );
  }

  Future<void> _onSystemDecline(String callId) async {
    if (_screenCallId == callId && _screenDecline != null) {
      await _screenDecline!();
      return;
    }
    // Tidak ada layar → tolak langsung ke DB + tutup UI sistem.
    try {
      await _service.updateStatus(callId, 'declined');
    } catch (_) {}
    await CallNotifier.callUi.dismiss(callId);
  }

  /// Sistem mengakhiri call (tombol end di UI sistem / headset).
  Future<void> _onSystemEnd(String callId) async {
    if (_activeCallId == callId && _activeSession != null) {
      await hangup();
      return;
    }
    await CallNotifier.callUi.dismiss(callId);
    if (_activeCallId == callId) {
      unregisterCall(callId);
      _emit();
    }
  }

  /// Register call yang sedang terbuka di UI (CallScreen / Incoming).
  void registerCall(String callId) {
    _activeCallId = callId;
  }


  /// Bersihkan saat call selesai / screen ditutup.
  void unregisterCall(String callId) {
    if (_activeCallId == callId) _activeCallId = null;
  }

  /// Buat + inisialisasi session panggilan, simpan sebagai active session
  /// (shared) yang dipakai CallScreen fullscreen maupun overlay video chat.
  /// Session tidak ditutup di sini — lihat [clearSession].
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
    final session = CallSession(
      callId: callId,
      remoteUid: remoteUid,
      remoteName: remoteName,
      callType: callType,
      isCaller: isCaller,
      myName: myName,
      myGender: myGender,
      pendingSignals: pendingSignals,
    );
    dlog(
      '[PROVIDER] startSession#${session.hashCode} call=$callId mode=$mode isCaller=$isCaller (prev=${_activeSession?.hashCode})',
    );
    _activeSession = session;
    _activeMode = mode;
    _activeChatId = chatId;
    _activeCallId = callId;
    _notifBody = notifBody;
    _notifChannel = notifChannel;
    _notifDesc = notifDesc;
    session.addListener(_onActiveSession);
    unawaited(session.init());
    // UI sistem: pindah dari "ringing" ke "in-call" (durasi/tombol end).
    unawaited(CallNotifier.callUi.setConnected(callId));
    unawaited(
      CallNotification.showActive(
        body: notifBody,
        channelName: notifChannel,
        channelDesc: notifDesc,
        chatId: chatId,
        otherUid: remoteUid,
        otherName: remoteName,
      ),
    );
    _emit();
    return session;
  }

  void _onActiveSession() {
    if (_activeSession?.phase == CallPhase.ended && _clearTimer == null) {
      _clearTimer = Timer(const Duration(milliseconds: 1000), () {
        _clearTimer = null;
        unawaited(clearSession());
      });
    }
  }

  /// Tutup session aktif + bersihkan state. Idempoten.
  Future<void> clearSession() async {
    if (_activeSession == null) return;
    _clearTimer?.cancel();
    _clearTimer = null;
    final sess = _activeSession!;
    dlog('[PROVIDER] clearSession#${sess.hashCode} call=${sess.callId}');
    _activeSession = null;
    _activeMode = null;
    _activeChatId = null;
    _activeCallId = null;
    _notifBody = null;
    _notifChannel = null;
    _notifDesc = null;
    sess.removeListener(_onActiveSession);
    // UI DULU: kosongkan state + notify SEKARANG (overlay/layar call langsung
    // hilang), baru jalankan cleanup WebRTC/notif di belakang. Dulu notify
    // di akhir setelah `await sess.close()` (tutup PC + renderer, lambat)
    // → tombol "Akhiri" terasa lama/hang.
    _emit();
    await CallNotification.cancel();
    // Tutup UI panggilan sistem (bila ada) — ring/in-call banner hilang.
    unawaited(CallNotifier.callUi.dismiss(sess.callId));
    try {
      await sess.close();
    } catch (_) {}
  }

  void _disposeAll() {
    _disposed = true;
    _incomingSub?.cancel();
    _incomingSub = null;
    _authSub?.cancel();
    _authSub = null;
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(CallNotifier.new);
