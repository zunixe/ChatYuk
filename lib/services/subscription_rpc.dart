import 'package:supabase_flutter/supabase_flutter.dart';

/// RPC langganan creator (berbayar) — SATU sumber supaya tidak ada dua
/// salinan wrapper dengan semantik yang bisa berbeda diam-diam.
///
/// Dipakai `SocialService.subscribeCreator` (graf sosial) dan
/// `PointsService.subscribeCreator` (dompet, refreshWallet di provider).
Future<Map<String, dynamic>> subscribeCreatorRpc(
  SupabaseClient sb,
  String creatorUid, {
  int periods = 1,
}) async {
  final res = await sb.rpc(
    'subscribe_creator',
    params: {'p_creator': creatorUid, 'p_periods': periods},
  );
  return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
}
