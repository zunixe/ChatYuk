import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    state = index;
  }
}

final navProvider = NotifierProvider<NavNotifier, int>(NavNotifier.new);
