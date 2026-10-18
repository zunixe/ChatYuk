import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/profile_lite_service.dart';
export '../../services/profile_lite_service.dart' show ProfileLite, ProfileLiteService;

/// Nama+gender ringan per uid (kartu kontak) — pembungkus service.
class ProfileLiteNotifier {
  final ProfileLiteService service;
  ProfileLiteNotifier([ProfileLiteService? service])
      : service = service ?? ProfileLiteService();

  Future<ProfileLite?> forUid(String uid) => service.forUid(uid);
}

final profileLiteProvider =
    Provider<ProfileLiteNotifier>((_) => ProfileLiteNotifier());
