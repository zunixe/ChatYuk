import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/riverpod/chat_provider.dart';

/// Cache uid yang merupakan MODERATOR NEGARA (untuk badge perisai).
///
/// Pola sama dengan `verified_provider`: batch + TTL supaya scroll tidak
/// memicu RPC berulang. Sumber: RPC `moderator_uids` (hanya uid+country,
/// tanpa data pribadi lain).
class ModeratorNotifier extends Notifier<Set<String>> {
  static const _ttl = Duration(minutes: 5);
  DateTime? _fetchedAt;
  final Set<String> _pending = {};

  @override
  Set<String> build() => <String>{};

  Future<void> ensureLoaded(Iterable<String> uids) async {
    final now = DateTime.now();
    final stale = _fetchedAt == null || now.difference(_fetchedAt!) > _ttl;
    final want = <String>{};
    for (final u in uids) {
      if (u.isEmpty) continue;
      if (stale || (!state.contains(u) && !_pending.contains(u))) {
        want.add(u);
      }
    }
    if (want.isEmpty) return;

    _pending.addAll(want);
    final found =
        await ref.read(chatProvider.notifier).moderatorUids(want.toList());
    _pending.removeAll(want);
    _fetchedAt = DateTime.now();
    if (found.isEmpty) return;
    state = {...state, ...found};
  }

  /// Tandai langsung (mis. setelah user jadi moderator).
  void markModerator(String uid) {
    if (uid.isEmpty || state.contains(uid)) return;
    state = {...state, uid};
  }
}

final moderatorUidsProvider =
    NotifierProvider<ModeratorNotifier, Set<String>>(ModeratorNotifier.new);
