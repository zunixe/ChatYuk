import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/privacy_settings.dart';
import '../../services/privacy_service.dart';

/// Snapshot state PrivacyProvider (immutable) — agar rebuild granular.
class PrivacyState {
  final PrivacySettings settings;
  final bool loading;
  final List<Map<String, dynamic>> excludable;
  final bool excludableLoading;
  final bool excludableLoaded;

  const PrivacyState({
    this.settings = const PrivacySettings(),
    this.loading = false,
    this.excludable = const [],
    this.excludableLoading = false,
    this.excludableLoaded = false,
  });

  PrivacyState copyWith({
    PrivacySettings? settings,
    bool? loading,
    List<Map<String, dynamic>>? excludable,
    bool? excludableLoading,
    bool? excludableLoaded,
  }) =>
      PrivacyState(
        settings: settings ?? this.settings,
        loading: loading ?? this.loading,
        excludable: excludable ?? this.excludable,
        excludableLoading: excludableLoading ?? this.excludableLoading,
        excludableLoaded: excludableLoaded ?? this.excludableLoaded,
      );
}

/// Provider privasi (Riverpod) — state reaktif (settings + excludable).
/// Migrasi dari ChangeNotifier → Notifier<PrivacyState>. Global (persist).
class PrivacyNotifier extends Notifier<PrivacyState> {
  final PrivacyService _service;

  PrivacyNotifier([PrivacyService? service])
      : _service = service ?? PrivacyService();

  @override
  PrivacyState build() => const PrivacyState();

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final s = await _service.fetch();
      state = state.copyWith(settings: s, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> ensureExcludable() async {
    if (state.excludableLoaded || state.excludableLoading) return;
    state = state.copyWith(excludableLoading: true);
    try {
      final list = await _service.excludableUsers();
      state = state.copyWith(excludable: list, excludableLoaded: true, excludableLoading: false);
    } catch (_) {
      state = state.copyWith(excludableLoaded: false, excludableLoading: false);
    }
  }

  Future<void> update({
    PrivacyVisibility? presence,
    PrivacyVisibility? lastSeen,
    PrivacyVisibility? profilePhoto,
    PrivacyVisibility? about,
    PrivacyVisibility? story,
    PrivacyVisibility? leaderboard,
    bool? readReceipts,
  }) async {
    state = state.copyWith(
      settings: state.settings.copyWith(
        presence: presence,
        lastSeen: lastSeen,
        profilePhoto: profilePhoto,
        about: about,
        story: story,
        leaderboard: leaderboard,
        readReceipts: readReceipts,
      ),
    );
    try {
      final s = await _service.update(
        presence: presence,
        lastSeen: lastSeen,
        profilePhoto: profilePhoto,
        about: about,
        story: story,
        leaderboard: leaderboard,
        readReceipts: readReceipts,
      );
      state = state.copyWith(settings: s);
    } catch (_) {
      await load();
    }
  }

  Future<void> updateExclusions(String field, Set<String> uids) async {
    state = state.copyWith(
      settings: state.settings.copyWith(
        exclusions: {...state.settings.exclusions, field: Set.of(uids)},
      ),
    );
    try {
      final s = await _service.replaceExclusions(field, uids);
      state = state.copyWith(settings: s);
    } catch (_) {
      await load();
    }
  }
}

final privacyProvider =
    NotifierProvider<PrivacyNotifier, PrivacyState>(PrivacyNotifier.new);
