import 'package:supabase_flutter/supabase_flutter.dart';

/// Service top-up coin via iPaymu (Redirect Payment).
/// - `packages()` ambil katalog paket dari DB.
/// - `createOrder()` panggil Edge Function `ipaymu-create` → dapat session_id
///   & redirect_url (halaman checkout iPaymu) untuk dibuka di browser.
/// - `myOrders()` riwayat order (untuk cek status setelah bayar).
class TopupService {
  final SupabaseClient _sb;
  TopupService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  /// Daftar paket aktif: [{id, coins, price_idr, bonus_label, sort_order}].
  Future<List<Map<String, dynamic>>> packages() async {
    final res = await _sb.rpc('list_topup_packages');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Buat order + minta URL checkout iPaymu. Return {order_id, session_id,
  /// redirect_url, coins, price_idr}. Lempar exception dgn pesan server.
  Future<Map<String, dynamic>> createOrder(String packageId) async {
    final res = await _sb.functions.invoke(
      'ipaymu-create',
      body: {'package_id': packageId},
    );
    final data = res.data;
    if (data is Map && data['redirect_url'] != null) {
      return Map<String, dynamic>.from(data);
    }
    // Edge function mengembalikan {error: ...}
    final msg = (data is Map ? data['error'] : null) ?? 'Top-up failed';
    throw Exception(msg.toString());
  }

  /// Riwayat order top-up sendiri (untuk polling status setelah bayar).
  Future<List<Map<String, dynamic>>> myOrders({int limit = 20}) async {
    final res = await _sb.rpc('get_my_topup_orders', params: {'row_limit': limit});
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Cek status satu order (dipakai polling setelah user selesai bayar).
  Future<String?> orderStatus(String orderId) async {
    final rows = await myOrders(limit: 50);
    for (final o in rows) {
      if (o['id'] == orderId) return o['status'] as String?;
    }
    return null;
  }
}
