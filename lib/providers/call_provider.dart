import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../screens/incoming_call_screen.dart';
import '../services/call_service.dart';

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

  @override
  void dispose() {
    _incomingSub?.cancel();
    _incomingSub = null;
    super.dispose();
  }
}