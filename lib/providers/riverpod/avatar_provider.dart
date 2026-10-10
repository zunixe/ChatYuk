import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage_paths.dart';
import '../../services/avatar_service.dart';

/// Avatar (base64 by uid/path + cache) — action-only, wrapper service.
/// Migrasi dari ChangeNotifier (0 notifyListeners) → Provider.
class AvatarNotifier {
  final AvatarB64Service service;
  AvatarNotifier([AvatarB64Service? service])
      : service = service ?? AvatarB64Service.instance;

  Future<String> get(String uid) => service.get(uid);
  Future<String> getByPath(String path) => service.getByPath(path);
  bool isAvatarPath(String v) => isAvatarPathValue(v);
  String? cachedSync(String uid) => service.cachedSync(uid);
  String? cachedSyncIncludeDisk(String uid) => service.cachedSyncIncludeDisk(uid);
  String? cachedByPathSync(String path) => service.cachedByPathSync(path);
  Future<void> prefetch(List<String> uids) => service.prefetch(uids);
  void clearForUid(String uid) => service.clearForUid(uid);
  void clearForPath(String path) => service.clearForPath(path);
  void setForUid(String uid, String base64) => service.setForUid(uid, base64);
  void setForPath(String path, String base64) => service.setForPath(path, base64);
}

final avatarProvider = Provider<AvatarNotifier>((_) => AvatarNotifier());
