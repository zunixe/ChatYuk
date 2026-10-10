import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/active_call_model.dart';
import '../core/perf/rpc_probe.dart';
import '../utils.dart';

part 'admin_service_stats.dart';
part 'admin_service_chat.dart';
part 'admin_service_ops.dart';

const Duration _openTimeout = Duration(seconds: 10);
const Duration _excludedTtl = Duration(minutes: 5);

abstract class _AdminBase {
  final SupabaseClient? sb;
  final SupabaseClient _sb;

  /// Client opsional supaya test bisa menyuntik client palsu (pola sama
  /// dengan `PointsService`/`ChatProvider`). Produksi: tanpa argumen →
  /// `Supabase.instance.client`.
  _AdminBase([this.sb]) : _sb = sb ?? Supabase.instance.client;

  /// Set UID device yang dikecualikan dari notifikasi device-baru.
  /// Dipindah dari AdminProvider agar I/O lewat service (mudah di-mock).
  /// Memo 5 menit: dipanggil tiap deteksi device baru — daftar berubah
  /// jarang (hanya saat admin exclude/unexclude), jadi jangan tembak DB
  /// tiap kali. Hanya menunda SUPRESI notifikasi, bukan data list.
  Set<String>? _excludedCache;
  DateTime? _excludedAt;

  /// Bungkus `_sb.rpc` agar SEMUA RPC baca-tampil admin terukur otomatis
  /// (metrik `admin.<nama_rpc>`) tanpa perlu menyentuh 30+ call-site satu
  /// per satu. Saat `PERF_PROBE` tidak diset, ini no-op — nol overhead &
  /// perilaku identik. Dipakai untuk mencari tab admin mana yang lambat.
  Future<dynamic> _rpc(String fn, {Map<String, dynamic>? params}) =>
      measuredRpc(_sb, fn, params: params, label: 'admin.$fn');
}

class AdminService extends _AdminBase
    with _AdminStatsMx, _AdminChatMx, _AdminOpsMx {
  AdminService([super.sb]);
}
