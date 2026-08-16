import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Layanan KYC (verifikasi identitas untuk pencairan).
class KycService {
  KycService._();
  static final KycService instance = KycService._();

  SupabaseClient get _sb => SupabaseConfig.client;

  /// Status KYC user sendiri. Return map {status, ...} atau {status:'none'}.
  Future<Map<String, dynamic>> myStatus() async {
    try {
      final res = await _sb.rpc('get_my_kyc');
      return res is Map ? Map<String, dynamic>.from(res) : {'status': 'none'};
    } catch (e) {
      debugPrint('[KycService] myStatus error: $e');
      return {'status': 'none'};
    }
  }

  /// Kirim permohonan KYC. Lempar PostgrestException bila gagal.
  Future<Map<String, dynamic>> submit({
    required String fullName,
    required String idType,
    required String idNumber,
    required String idPhoto,
    required String selfiePhoto,
    String? birthDate,
  }) async {
    final res = await _sb.rpc('submit_kyc', params: {
      'p_full_name': fullName,
      'p_id_type': idType,
      'p_id_number': idNumber,
      'p_id_photo': idPhoto,
      'p_selfie_photo': selfiePhoto,
      'p_birth_date': birthDate,
    });
    return res is Map ? Map<String, dynamic>.from(res) : {'ok': true};
  }

  /// Daftar permohonan (admin). Status: 'pending' | 'approved' | 'rejected' | 'all'.
  Future<List<Map<String, dynamic>>> adminList(String status) async {
    try {
      final res = await _sb.rpc('admin_kyc_list', params: {'p_status': status});
      if (res is List) return res.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[KycService] adminList error: $e');
    }
    return [];
  }

  /// Setujui/tolak permohonan (admin).
  Future<Map<String, dynamic>> adminReview({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    final res = await _sb.rpc('admin_kyc_review', params: {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_reason': reason,
    });
    return res is Map ? Map<String, dynamic>.from(res) : {'ok': true};
  }
}
