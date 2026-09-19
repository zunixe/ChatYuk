import 'dart:async';

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

  @override
  set onAccept(FutureOr<void> Function(String callId)? cb) => _onAccept = cb;

  @override
  set onDecline(FutureOr<void> Function(String callId)? cb) =>
      _onDecline = cb;

  @override
  set onEnd(FutureOr<void> Function(String callId)? cb) => _onEnd = cb;

  /// Handler panggilan dari native. Dipakai juga oleh unit test lewat
  /// `TestDefaultBinaryMessenger` (invoke method `onAccept` dll).
  Future<dynamic> _handleNative(MethodCall call) async {
    final callId = '${call.arguments ?? ''}';
    switch (call.method) {
      case 'onAccept':
        await _onAccept?.call(callId);
      case 'onDecline':
        await _onDecline?.call(callId);
      case 'onEnd':
        await _onEnd?.call(callId);
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
  Future<void> dispose() async {
    _onAccept = null;
    _onDecline = null;
    _onEnd = null;
    _channel.setMethodCallHandler(null);
  }
}
