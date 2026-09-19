import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils.dart';
import 'call_ui.dart';

/// Jembatan ke UI panggilan sistem Android (ConnectionService).
///
/// Channel `com.chatyuk.chatyuk/call_ui`:
/// - Dart ke native: `showIncoming`, `setConnected`, `dismiss`
/// - native ke Dart: `onAccept`, `onDecline`, `onEnd` (pengguna menekan
///   tombol di layar kunci / headset / system call UI).
///
/// Tidak ada logika WebRTC di sini — ConnectionService hanya menangani
/// ring + tombol jawab/tolak. Media tetap milik `CallSession` di Dart.
class CallUiChannel implements CallUi {
  CallUiChannel._() {
    _channel.setMethodCallHandler(_handleNative);
  }

  static final CallUiChannel _instance = CallUiChannel._();
  static CallUiChannel get instance => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.chatyuk.chatyuk/call_ui');

  FutureOr<void> Function(String callId)? _onAccept;
  FutureOr<void> Function(String callId)? _onDecline;
  FutureOr<void> Function(String callId)? _onEnd;

  /// Aksi yang datang SEBELUM callback terpasang (race saat cold start:
  /// native kirim "accept" tak lama setelah engine hidup, sementara
  /// CallProvider belum selesai bind). Disimpan lalu diputar saat callback
  /// siap — tanpa ini, jawab dari system UI saat app mati bisa hilang.
  final List<(String, String)> _pending = [];

  void _dispatch(String method, String callId) {
    final cb = switch (method) {
      'onAccept' => _onAccept,
      'onDecline' => _onDecline,
      'onEnd' => _onEnd,
      _ => null,
    };
    if (cb == null) {
      _pending.add((method, callId));
      return;
    }
    cb(callId);
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    final items = List.of(_pending);
    _pending.clear();
    for (final (method, callId) in items) {
      _dispatch(method, callId);
    }
  }

  @override
  set onAccept(FutureOr<void> Function(String callId)? cb) {
    _onAccept = cb;
    _flushPending();
  }

  @override
  set onDecline(FutureOr<void> Function(String callId)? cb) {
    _onDecline = cb;
    _flushPending();
  }

  @override
  set onEnd(FutureOr<void> Function(String callId)? cb) {
    _onEnd = cb;
    _flushPending();
  }

  /// Handler panggilan dari native. Dipakai juga oleh unit test lewat
  /// `TestDefaultBinaryMessenger` (invoke method `onAccept` dll).
  Future<dynamic> _handleNative(MethodCall call) async {
    final callId = '${call.arguments ?? ''}';
    switch (call.method) {
      case 'onAccept':
      case 'onDecline':
      case 'onEnd':
        _dispatch(call.method, callId);
    }
    return null;
  }

  Future<void> _invoke(String method, Map<String, dynamic> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      // Jangan pernah menggagalkan alur panggilan karena UI sistem tidak
      // tersedia (mis. izin Telecom ditolak) — layar Dart tetap jadi
      // fallback.
      dlog('[CALL_UI] $method error: $e');
    }
  }

  @override
  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String callType,
  }) =>
      _invoke('showIncoming', {
        'callId': callId,
        'callerName': callerName,
        'callType': callType,
      });

  @override
  Future<void> setConnected(String callId) =>
      _invoke('setConnected', {'callId': callId});

  @override
  Future<void> dismiss(String callId) =>
      _invoke('dismiss', {'callId': callId});

  @override
  bool get usesSystemUi => true;

  /// Pasang ulang handler (test yang memanggil `dispose` lalu ingin
  /// mengirim method lagi). Tidak dipakai di produksi.
  @visibleForTesting
  void reattach() {
    _pending.clear();
    _channel.setMethodCallHandler(_handleNative);
  }

  @override
  Future<void> dispose() async {
    _onAccept = null;
    _onDecline = null;
    _onEnd = null;
    _pending.clear();
    _channel.setMethodCallHandler(null);
  }
}
