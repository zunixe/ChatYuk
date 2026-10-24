import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/chat_service.dart';

/// Cache uid yang akunnya SUDAH DIHAPUS (profil tidak ada lagi) — dipakai
/// penanda "Akun dihapus" di bubble room (pesan lama tetap tampil karena nama
/// pengirim tersimpan di tiap pesan).
///
/// Permintaan dari banyak bubble di-batch jadi SATU query per frame. Akun
/// terhapus bersifat permanen → tiap uid cukup dicek sekali per sesi; query
/// gagal → uid boleh dicek ulang (tidak pernah ditandai terhapus karena error).
class DeletedUsersNotifier extends Notifier<Set<String>> {
  DeletedUsersNotifier({ChatService? service}) : _injected = service;

  final ChatService? _injected;
  late final ChatService _svc = _injected ?? ChatService();

  final Set<String> _checked = {};
  final Set<String> _queue = {};
  Timer? _flush;

  static const int _batchMax = 100;

  @override
  Set<String> build() {
    ref.onDispose(() => _flush?.cancel());
    return <String>{};
  }

  void ensureChecked(String uid) {
    if (uid.isEmpty || _checked.contains(uid)) return;
    _checked.add(uid);
    _queue.add(uid);
    _flush ??= Timer(const Duration(milliseconds: 60), _run);
  }

  Future<void> _run() async {
    _flush = null;
    while (_queue.isNotEmpty) {
      final batch = _queue.take(_batchMax).toList();
      _queue.removeAll(batch);
      final missing = await _svc.missingProfileUids(batch);
      if (missing == null) {
        _checked.removeAll(batch);
        continue;
      }
      if (missing.isNotEmpty) state = {...state, ...missing};
    }
  }

  /// Cek & tunggu hasil untuk SATU uid — dipakai guard tap (mis.
  /// `_onTapUser`) supaya kasus tap-cepat (bubble lama belum pernah dibangun
  /// oleh DeletedUserBuilder) tidak lolos guard lalu dapat snack generik
  /// "User tidak ditemukan". Kosong bila uid sudah pasti aktif.
  Future<bool> checkedDeletedNow(String uid) async {
    if (uid.isEmpty) return false;
    if (state.contains(uid)) return true;
    final wasChecked = _checked.contains(uid);
    ensureChecked(uid);
    if (!wasChecked) {
      // Tunggu batch selesai (guard timeout ringan 1 detik).
      for (var i = 0; i < 20 && _queue.contains(uid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    return state.contains(uid);
  }

  /// Tandai langsung (mis. hasil `isUserActive` = false).
  void markDeleted(String uid) {
    if (uid.isEmpty || state.contains(uid)) return;
    _checked.add(uid);
    state = {...state, uid};
  }
}

final deletedUsersProvider =
    NotifierProvider<DeletedUsersNotifier, Set<String>>(
      DeletedUsersNotifier.new,
    );
