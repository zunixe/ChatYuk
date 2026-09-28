import 'package:flutter/foundation.dart';

import '../services/avatar_service.dart';

/// Provider avatar (base64 by uid/path + cache) — screen tidak import
/// `services/`. Widget boleh tetap pakai service langsung.
class AvatarProvider extends ChangeNotifier {
  final AvatarB64Service service;
  AvatarProvider({AvatarB64Service? service})
      : service = service ?? AvatarB64Service.instance;

  Future<String> get(String uid) => service.get(uid);
  Future<String> getByPath(String path) => service.getByPath(path);
  /// Peek sinkron dari RAM (tanpa network) — foto tampil instan anti-kedip.
  String? cachedSync(String uid) => service.cachedSync(uid);
  /// RAM lalu disk (baca file) — untuk halaman profil tunggal.
  String? cachedSyncIncludeDisk(String uid) =>
      service.cachedSyncIncludeDisk(uid);
  String? cachedByPathSync(String path) => service.cachedByPathSync(path);
  Future<void> prefetch(List<String> uids) => service.prefetch(uids);
  void clearForUid(String uid) => service.clearForUid(uid);
  void clearForPath(String path) => service.clearForPath(path);
  void setForUid(String uid, String base64) => service.setForUid(uid, base64);
  void setForPath(String path, String base64) =>
      service.setForPath(path, base64);
}
