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

  /// Pastikan uid dalam [uids] sudah dicek (muat yang belum diketahui).
  Future<void> ensureLoaded(Iterable<String> uids) async {
    final now = DateTime.now();
    final stale = _fetchedAt == null || now.difference(_fetchedAt!) > _ttl;
    final want = <String>{};
    for (final u in uids) {
      if (u.isEmpty) continue;
      if (stale || (!state.containsKey(u) && !_pending.contains(u))) {
        want.add(u);
      }
    }
    if (want.isEmpty) return;
    _pending.addAll(want);
    final res = await _svc.countsForUids(want.toList());
    _pending.removeAll(want);
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
