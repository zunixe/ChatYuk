import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils.dart';

/// Status KYC user — cermin `get_my_kyc` di server.
/// `status`: 'none' (belum pernah) | 'pending' | 'approved' | 'rejected'.
class KycState {
  final bool loading;
  final bool submitting;
  final String status;
  final String? rejectReason;
  final DateTime? reviewedAt;
  /// Error transien (gagal muat) — layar tetap menampilkan data terakhir.
  final String? error;

  const KycState({
    this.loading = true,
    this.submitting = false,
    this.status = 'none',
    this.rejectReason,
    this.reviewedAt,
    this.error,
  });

  KycState copyWith({
    bool? loading,
    bool? submitting,
    String? status,
    String? rejectReason,
    DateTime? reviewedAt,
    String? error,
  }) =>
      KycState(
        loading: loading ?? this.loading,
        submitting: submitting ?? this.submitting,
        status: status ?? this.status,
        rejectReason: rejectReason ?? this.rejectReason,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        error: error,
      );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get canSubmit => status == 'none' || status == 'rejected';
}

/// Notifier KYC — satu-satunya pintu RPC `submit_kyc`/`get_my_kyc`
/// dari klien (boundary: screen tak boleh import services).
class KycNotifier extends Notifier<KycState> {
  SupabaseClient get _sb => Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  @override
  KycState build() {
    _authSub?.cancel();
    _authSub = _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        state = const KycState(loading: false);
        return;
      }
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession ||
          s.event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      }
    }, onError: (e) => dlog('[KYC] auth stream error: $e'));

    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    if (_sb.auth.currentUser == null) {
      return const KycState(loading: false);
    }
    refresh();
    return const KycState();
  }

  Future<void> refresh() async {
    if (_sb.auth.currentUser == null) {
      state = const KycState(loading: false);
      return;
    }
    try {
      final res = await _sb.rpc('get_my_kyc');
      final j = (res as Map?)?.cast<String, dynamic>() ?? const {};
      state = KycState(
        loading: false,
        status: (j['status'] as String?) ?? 'none',
        rejectReason: j['reject_reason'] as String?,
        reviewedAt: j['reviewed_at'] != null
            ? DateTime.tryParse(j['reviewed_at'].toString())
            : null,
      );
    } catch (e) {
      dlog('[KYC] get_my_kyc error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Kirim pengajuan KYC. [idPhoto]/[selfiePhoto] = data URL base64
  /// (`data:image/jpeg;base64,…`) — kontrak `submit_kyc` (min length 100).
  /// Return null = sukses (status → pending); String = pesan error klien.
  /// Error server (duplicate/invalid) dipetakan ke kode yang dikenali layar.
  Future<String?> submit({
    required String fullName,
    required String idType,
    required String idNumber,
    required String idPhoto,
    required String selfiePhoto,
    DateTime? birthDate,
  }) async {
    if (state.submitting) return 'busy';
    state = state.copyWith(submitting: true);
    try {
      await _sb.rpc(
        'submit_kyc',
        params: {
          'p_full_name': fullName,
          'p_id_type': idType,
          'p_id_number': idNumber,
          'p_id_photo': idPhoto,
          'p_selfie_photo': selfiePhoto,
          if (birthDate != null)
            'p_birth_date': birthDate.toIso8601String().substring(0, 10),
        },
      );
      state = state.copyWith(submitting: false, status: 'pending');
      return null;
    } on PostgrestException catch (e) {
      dlog('[KYC] submit_kyc error: ${e.message}');
      state = state.copyWith(submitting: false, error: e.message);
      // Pesan dari `raise exception` RPC tiba mentah — layar memetakan
      // yang dikenal ('KYC already submitted' → kycErrDuplicate).
      return e.message.contains('already submitted')
          ? 'duplicate'
          : 'server:${e.message}';
    } catch (e) {
      dlog('[KYC] submit_kyc error: $e');
      state = state.copyWith(submitting: false, error: e.toString());
      return 'generic';
    }
  }
}

final kycProvider =
    NotifierProvider<KycNotifier, KycState>(KycNotifier.new);
