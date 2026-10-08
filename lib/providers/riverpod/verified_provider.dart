import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/phone_verify_service.dart';

/// Cache uid terverifikasi — dipakai badge emas di kartu/list.
///
/// Hanya menyimpan status "verified"; uid yang tidak terverifikasi tidak
/// masuk set. TTL pendek supaya perubahan (verifikasi baru) cepat terlihat
/// tanpa RPC berulang saat scroll.
class VerifiedNotifier extends Notifier<Set<String>> {
  final PhoneVerifyService _svc = PhoneVerifyService();

  final Set<String> _pending = {};
  static const _ttl = Duration(minutes: 5);
  DateTime? _fetchedAt;

  @override
  Set<String> build() => <String>{};

  /// Pastikan uid dalam [uids] sudah dicek. Ambil hanya yang belum diketahui
  /// & belum sedang di-fetch; kalau TTL habis → muat ulang.
  Future<void> ensureLoaded(Iterable<String> uids) async {
    final now = DateTime.now();
    final stale = _fetchedAt == null ||
        now.difference(_fetchedAt!) > _ttl;
    final want = <String>{};
    for (final u in uids) {
      if (u.isEmpty) continue;
      if (stale || (!state.contains(u) && !_pending.contains(u))) {
        want.add(u);
      }
    }
    if (want.isEmpty) return;
    _pending.addAll(want);
    final res = await _svc.verifiedUids(want.toList());
    _pending.removeAll(want);
    _fetchedAt = DateTime.now();
    if (res.isEmpty) return;
    // Hanya tambah; jangan hapus yang sudah diketahui di window ini
    // (menghindari badge kedip saat sebagian batch gagal).
    final next = {...state, ...res};
    if (!setEquals(next, state)) state = next;
  }

  /// Tandai satu uid verified (optimistik setelah verifikasi sukses).
  void markVerified(String uid) {
    if (uid.isEmpty || state.contains(uid)) return;
    state = {...state, uid};
  }
}

final verifiedProvider =
    NotifierProvider<VerifiedNotifier, Set<String>>(VerifiedNotifier.new);
