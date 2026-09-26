import 'package:supabase_flutter/supabase_flutter.dart';

import 'perf_probe.dart';

/// Wrapper RPC ber-instrumentasi — SATU jalur untuk semua service
/// (admin & user) supaya metrik seragam dan bisa dibandingkan.
///
/// Saat `PERF_PROBE` menyala: mencatat `PerfProbe.timed('rpc.<fn>')`
/// (atau [label] bila diberikan, mis. `admin.<fn>` agar doc lama tetap
/// valid). Saat mati: nol overhead, perilaku identik.
Future<dynamic> measuredRpc(
  SupabaseClient sb,
  String fn, {
  Map<String, dynamic>? params,
  String? label,
}) {
  if (!PerfProbe.measuring) return sb.rpc(fn, params: params);
  return PerfProbe.timed(label ?? 'rpc.$fn', () => sb.rpc(fn, params: params));
}
