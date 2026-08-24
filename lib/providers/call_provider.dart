import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/incoming_call_screen.dart';
import '../services/call_service.dart';
import '../services/call_notification.dart';

enum CallMode { fullscreen, chat }

/// CallProvider: pendengar global panggilan masuk + penanda call aktif.
/// Dipakai supaya panggilan masuk muncul sebagai screen overlay di mana pun
/// user berada (tanpa menunggu push), dan supaya user yang sedang di call
/// otomatis ditandai busy.
class CallProvider extends ChangeNotifier {
  static final CallProvider instance = CallProvider._();
  CallProvider._();

  final CallService _service = CallService.instance;
  StreamSubscription<Map<String, dynamic>>? _incomingSub;

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
  void setMode(CallMode mode) {
    if (_activeMode == mode) return;
    _activeMode = mode;
    notifyListeners();
  }

  Timer? _clearTimer;

  /// Mulai mendengarkan panggilan masuk — hanya untuk user terdaftar
  /// (anon tidak menerima call sama sekali).
  void ensureListening({required bool registered}) {
    if (!registered) return;
    if (_incomingSub != null) return;
    _incomingSub = _service.onIncomingCall().listen(_onIncoming);
    debugPrint('[CallProvider] listening incoming calls');
  }

  void _onIncoming(Map<String, dynamic> row) async {
    final callId = row['id'] as String?;
    if (callId == null) return;
    final callerUid = row['caller_id'] as String? ?? '';
    final callType = row['call_type'] as String? ?? 'video';

    if (_activeCallId != null) {
      // Sedang di call → tandai busy (caller melihat status busy).
      try {
        await _service.updateStatus(callId, 'busy');
      } catch (_) {}
      return;
    }
    if (_activeCallId == callId) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _activeCallId = callId;
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
    _activeSession = session;
    _activeMode = mode;
    _activeChatId = chatId;
    _activeCallId = callId;
    session.addListener(_onActiveSession);
    unawaited(session.init());
    unawaited(CallNotification.showActive(
      body: notifBody,
      channelName: notifChannel,
      channelDesc: notifDesc,
      chatId: chatId,
      otherUid: remoteUid,
      otherName: remoteName,
    ));
    notifyListeners();
    return session;
  }

  void _onActiveSession() {
    if (_activeSession?.phase == CallPhase.ended && _clearTimer == null) {
      _clearTimer = Timer(const Duration(milliseconds: 2200), () {
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
    _activeSession = null;
    _activeMode = null;
    _activeChatId = null;
    _activeCallId = null;
    sess.removeListener(_onActiveSession);
    await CallNotification.cancel();
    await sess.close();
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _incomingSub = null;
    super.dispose();
  }
}