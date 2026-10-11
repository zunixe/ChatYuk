import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav_journal.dart';

/// Kontrol tab navigasi utama (Riverpod) — dipakai screen lain untuk pindah
/// tab (mis. arahkan user anon ke tab Profil).
///
/// Migrasi dari ChangeNotifier (Provider) → Notifier (Riverpod). Global
/// (TANPA autoDispose) karena tab aktif harus persist sepanjang sesi.
class NavNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void goTo(int index) {
    if (index == state) return;
    NavJournal.log('tab $state -> $index');
    state = index;
  }
}

final navProvider = NotifierProvider<NavNotifier, int>(NavNotifier.new);
