import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/phone_verify_service.dart';

/// Status verifikasi nomor HP diri sendiri.
class PhoneVerifyState {
  final bool verified;
  final String phone;
  final bool busy;
  final String? error;
  const PhoneVerifyState({
    this.verified = false,
    this.phone = '',
    this.busy = false,
    this.error,
  });

  PhoneVerifyState copyWith({
    bool? verified,
    String? phone,
    bool? busy,
    String? error,
    bool clearError = false,
  }) =>
      PhoneVerifyState(
        verified: verified ?? this.verified,
        phone: phone ?? this.phone,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Provider verifikasi nomor HP: mulai sesi, buka Telegram, polling status.
class PhoneVerifyNotifier extends Notifier<PhoneVerifyState> {
  final PhoneVerifyService _svc = PhoneVerifyService();
  Timer? _poll;
  int _pollTicks = 0;

  @override
  PhoneVerifyState build() {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    return const PhoneVerifyState();
  }

  Future<void> refresh() async {
    final res = await _svc.status();
    state = state.copyWith(
      verified: res['verified'] == true,
      phone: '${res['phone'] ?? ''}',
    );
  }

  /// Mulai verifikasi: buat token, buka deep-link Telegram, lalu polling
  /// status. Return kode hasil untuk pesan ke user: 'opened' | 'rate_limited'
  /// | 'phone_empty' | 'error'.
  Future<String> startAndOpen() async {
    state = state.copyWith(busy: true, clearError: true);
    final res = await _svc.start();
    if (res['ok'] != true) {
      final reason = '${res['reason'] ?? ''}';
      state = state.copyWith(busy: false);
      if (reason.contains('rate_limited')) return 'rate_limited';
      if (reason.contains('phone_empty')) return 'phone_empty';
      return 'error';
    }
    final url = '${res['url'] ?? ''}';
    state = state.copyWith(busy: false);
    if (url.isNotEmpty) {
      try {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        debugPrint('[PhoneVerify] launch error: $e');
      }
    }
    _startPolling();
    return 'opened';
  }

  void _startPolling() {
    _poll?.cancel();
    _pollTicks = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      _pollTicks++;
      final res = await _svc.status();
      if (res['verified'] == true) {
        t.cancel();
        _poll = null;
        state = state.copyWith(verified: true);
        return;
      }
      // Berhenti otomatis setelah ~2 menit (40 tick) untuk hemat kuota.
      if (_pollTicks >= 40) {
        t.cancel();
        _poll = null;
      }
    });
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }
}

final phoneVerifyProvider =
    NotifierProvider<PhoneVerifyNotifier, PhoneVerifyState>(
  PhoneVerifyNotifier.new,
);
