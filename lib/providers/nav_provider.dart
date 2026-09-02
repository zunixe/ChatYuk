import 'package:flutter/foundation.dart';

/// Kontrol tab navigasi utama — dipakai screen lain untuk pindah tab
/// (mis. arahkan user anon ke tab Profil).
class NavProvider extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  int _tab = 0;
  int get tab => _tab;

  void goTo(int index) {
    if (index == _tab) return;
    _tab = index;
    if (!_disposed) notifyListeners();
  }
}
