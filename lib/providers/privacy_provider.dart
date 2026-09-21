import 'package:flutter/foundation.dart';
import '../models/privacy_settings.dart';
import '../services/privacy_service.dart';

class PrivacyProvider extends ChangeNotifier {
  final PrivacyService _service;
  PrivacySettings _settings = const PrivacySettings();
  bool _loading = false;
  List<Map<String, dynamic>> _excludable = const [];
  bool _excludableLoading = false;
  bool _excludableLoaded = false;

  PrivacyProvider({PrivacyService? service})
    : _service = service ?? PrivacyService();

  PrivacySettings get settings => _settings;
  bool get loading => _loading;

  /// Teman + anon yang bisa dikecualikan (untuk kedua opsi "kecuali...").
  List<Map<String, dynamic>> get excludable => _excludable;
  bool get excludableLoading => _excludableLoading;
  bool get excludableLoaded => _excludableLoaded;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _service.fetch();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Muat daftar excludable sekali, lazy saat picker dibuka.
  Future<void> ensureExcludable() async {
    if (_excludableLoaded || _excludableLoading) return;
    _excludableLoading = true;
    notifyListeners();
    try {
      _excludable = await _service.excludableUsers();
      _excludableLoaded = true;
    } catch (_) {
      // Gagal jaringan → biarkan kosong; picker menampilkan empty state.
      _excludableLoaded = false;
    } finally {
      _excludableLoading = false;
      notifyListeners();
    }
  }

  Future<void> update({
    PrivacyVisibility? presence,
    PrivacyVisibility? lastSeen,
    PrivacyVisibility? profilePhoto,
    PrivacyVisibility? about,
    PrivacyVisibility? story,
    bool? readReceipts,
  }) async {
    _settings = _settings.copyWith(
      presence: presence,
      lastSeen: lastSeen,
      profilePhoto: profilePhoto,
      about: about,
      story: story,
      readReceipts: readReceipts,
    );
    notifyListeners();
    try {
      _settings = await _service.update(
        presence: presence,
        lastSeen: lastSeen,
        profilePhoto: profilePhoto,
        about: about,
        story: story,
        readReceipts: readReceipts,
      );
      notifyListeners();
    } catch (_) {
      await load();
    }
  }

  Future<void> updateExclusions(String field, Set<String> uids) async {
    _settings = _settings.copyWith(
      exclusions: {..._settings.exclusions, field: Set.of(uids)},
    );
    notifyListeners();
    try {
      _settings = await _service.replaceExclusions(field, uids);
      notifyListeners();
    } catch (_) {
      await load();
    }
  }
}
