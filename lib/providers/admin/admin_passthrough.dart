part of '../admin_provider.dart';

/// Passthrough (Fase 9b) — screen admin tidak import AdminService.
/// Delegasi satu baris + wrapper tipis ke `_service`.
mixin AdminPassthroughMx on AdminBase {
  Future<void> setDummyAi(
    String uid,
    bool enabled,
    Map<String, dynamic> persona, {
    bool? scheduleAuto,
    bool? guardEnabled,
    bool? noRateLimit,
    int? maxReplies,
    int? minInterval,
    List<int>? activeHours,
    String? model,
    bool? photosEnabled,
  }) =>
      _service.setDummyAi(
        uid, enabled, persona,
        scheduleAuto: scheduleAuto,
        guardEnabled: guardEnabled,
        noRateLimit: noRateLimit,
        maxReplies: maxReplies,
        minInterval: minInterval,
        activeHours: activeHours,
        model: model,
        photosEnabled: photosEnabled,
      );
  Future<List<int>> autoScheduleAi(String uid) => _service.autoScheduleAi(uid);
  /// Buat sesi pantau panggilan (admin) — di-dispose oleh screen.
  WatchSession createWatchSession(ActiveCallInfo call) => WatchSession(call);

  /// Popup update aplikasi (app_settings) — dibaca/disimpan dari tab
  /// Global Setting. Screen admin tidak import AdminService.
  Future<Map<String, dynamic>?> getUpdateConfig() =>
      _service.getUpdateConfig();
  Future<void> saveUpdateConfig({
    required bool enabled,
    required String latestVersion,
    required String minVersion,
    required String notes,
  }) =>
      _service.saveUpdateConfig(
        enabled: enabled,
        latestVersion: latestVersion,
        minVersion: minVersion,
        notes: notes,
      );

  Future<Map<String, dynamic>> getPointSettings() => _service.getPointSettings();
  Future<Map<String, dynamic>> updatePointSettings(Map<String, dynamic> p) =>
      _service.updatePointSettings(p);
  Future<Map<String, dynamic>> getAiSettings() => _service.getAiSettings();
  Future<Map<String, dynamic>> setAiSettings({
    bool? globalEnabled,
    int? maxReplies,
    int? minInterval,
    bool? guardEnabled,
    bool? aiAiEnabled,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
  }) =>
      _service.setAiSettings(
        globalEnabled: globalEnabled,
        maxReplies: maxReplies,
        minInterval: minInterval,
        guardEnabled: guardEnabled,
        aiAiEnabled: aiAiEnabled,
        apiBase: apiBase,
        apiKey: apiKey,
        defaultModel: defaultModel,
      );
  Future<List<Map<String, dynamic>>> getAiProviders() =>
      _service.getAiProviders();
  Future<Map<String, dynamic>> saveAiProvider({
    String? id,
    String? label,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
    String? storyModel,
    String? fallbackModel,
  }) =>
      _service.saveAiProvider(
        id: id,
        label: label,
        apiBase: apiBase,
        apiKey: apiKey,
        defaultModel: defaultModel,
        storyModel: storyModel,
        fallbackModel: fallbackModel,
      );
  Future<void> deleteAiProvider(String id) => _service.deleteAiProvider(id);
  Future<void> activateAiProvider(String id) => _service.activateAiProvider(id);
  Future<Map<String, dynamic>> registerDummy({
    required String nickname,
    String gender = 'male',
    int age = 25,
    String country = 'Indonesia',
    String city = 'Jakarta',
  }) =>
      _service.registerDummy(
        nickname: nickname,
        gender: gender,
        age: age,
        country: country,
        city: city,
      );
  Future<Map<String, dynamic>> listDummiesPage({int limit = 50, int offset = 0}) =>
      _service.listDummiesPage(limit: limit, offset: offset);
  Future<Map<String, dynamic>> getDummyStories(String uid, {int days = 14}) =>
      _service.getDummyStories(uid, days: days);
  Future<Map<String, dynamic>> generateDummyStory(
    String uid, {
    required String storyDate,
  }) =>
      _service.generateDummyStory(uid, storyDate: storyDate);
  Future<Map<String, dynamic>> deleteDummy(String uid) => _service.deleteDummy(uid);
  Future<void> updateDummyProfile({
    required String uid,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) =>
      _service.updateDummyProfile(
        uid: uid, nickname: nickname, gender: gender, age: age,
        country: country, city: city,
      );
  Future<bool> isNicknameAvailable(String nickname, {String? excludeUid}) =>
      _service.isNicknameAvailable(nickname, excludeUid: excludeUid);
  Future<void> setDummyStatus(String uid, String status) =>
      _service.setDummyStatus(uid, status);
  Future<void> wakeDummy(String uid, {int minutes = 30}) =>
      _service.wakeDummy(uid, minutes: minutes);
}
