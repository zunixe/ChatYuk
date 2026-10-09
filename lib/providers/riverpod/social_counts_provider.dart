import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/social_service.dart';

/// Cache jumlah TEMAN & FOLLOWER per-uid — dipakai badge kartu
/// ("1.2K Followers · 34 Friends") di list chat, social list, room member.
///
/// Pola sama dengan `verifiedProvider`: lazy `ensureLoaded(uids)` +
/// TTL pendek; hanya uid yang belum diketahui / cache basi yang di-fetch.
class SocialCountsNotifier extends Notifier<Map<String, ({int friends, int followers})>> {
  final SocialService _svc = SocialService();

  final Set<String> _pending = {};
  static const _ttl = Duration(minutes: 5);
  DateTime? _fetchedAt;

  @override
  Map<String, ({int friends, int followers})> build() => const {};

  /// Uid yang menunggu di-fetch dalam batch berikutnya.
  final Set<String> _batchQueue = {};
  Timer? _batchTimer;

  /// Kumpulkan permintaan sebentar lalu kirim SATU RPC untuk semua uid.
  ///
  /// PENTING (terukur): `SocialCountsLine` hidup PER KARTU — tiap kartu
  /// memanggil `ensureLoaded([uid])`. Tanpa batch, daftar 20 user = 20 RPC
  /// berbarengan (masing-masing ~1,2 dtk saat boot) → server antre, app
  /// terasa ngelag di awal. Batch 80ms menyatukan semuanya jadi 1 RPC.
  Future<void> ensureLoaded(Iterable<String> uids) async {
    final now = DateTime.now();
    final stale = _fetchedAt == null || now.difference(_fetchedAt!) > _ttl;
    for (final u in uids) {
      if (u.isEmpty) continue;
      if (stale || (!state.containsKey(u) && !_pending.contains(u))) {
        _batchQueue.add(u);
      }
    }
    if (_batchQueue.isEmpty) return;
    if (_batchTimer?.isActive ?? false) return;
    _batchTimer = Timer(const Duration(milliseconds: 80), () {
      final batch = _batchQueue.toList();
      _batchQueue.clear();
      unawaited(_flush(batch));
    });
  }

  Future<void> _flush(List<String> uids) async {
    if (uids.isEmpty) return;
    _pending.addAll(uids);
    final res = await _svc.countsForUids(uids);
    _pending.removeAll(uids);
    _fetchedAt = DateTime.now();
    if (res.isEmpty) return;
    final next = {...state, ...res};
    if (!mapEquals(next, state)) state = next;
  }

  /// Nilai tersimpan untuk uid (nullable bila belum dimuat).
  ({int friends, int followers})? forUid(String uid) => state[uid];
}

final socialCountsProvider =
    NotifierProvider<SocialCountsNotifier, Map<String, ({int friends, int followers})>>(
  SocialCountsNotifier.new,
);
