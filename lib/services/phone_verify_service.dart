import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils.dart';

/// Service verifikasi nomor HP via Telegram.
///
/// Semua panggilan lewat edge function `telegram-verify` (JWT user) dan RPC
/// `verified_uids` (badge user lain). Screen DILARANG memanggil langsung —
/// selalu lewat provider (patuh boundary AGENTS.md).
class PhoneVerifyService {
  final SupabaseClient _sb;
  PhoneVerifyService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  /// Mulai sesi verifikasi. Return `{ok, token, url, expires_at}` atau
  /// `{ok:false, reason}` (mis. `rate_limited` / `phone_empty`).
  Future<Map<String, dynamic>> start() async {
    try {
      final res = await _sb.functions.invoke(
        'telegram-verify',
        body: {'action': 'start'},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      dlog('[PhoneVerify] start error: $e');
    }
    return {'ok': false};
  }

  /// Status verifikasi diri sendiri: `{phone, verified, verified_at}`.
  Future<Map<String, dynamic>> status() async {
    try {
      final res = await _sb.functions.invoke(
        'telegram-verify',
        body: {'action': 'status'},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      dlog('[PhoneVerify] status error: $e');
    }
    return {'verified': false};
  }

  /// Daftar uid terverifikasi (untuk badge user lain). Return set kosong bila
  /// gagal — badge cukup tidak tampil, tidak mengganggu UI.
  Future<Set<String>> verifiedUids(List<String> uids) async {
    if (uids.isEmpty) return <String>{};
    try {
      final res = await _sb.rpc('verified_uids', params: {'p_uids': uids});
      if (res is List) {
        return res.map((e) => '$e').where((e) => e.isNotEmpty).toSet();
      }
    } catch (e) {
      dlog('[PhoneVerify] verifiedUids error: $e');
    }
    return <String>{};
  }
}
