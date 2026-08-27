import 'package:flutter/foundation.dart';
import 'room_broadcast_service.dart';

/// Abstraction untuk media room — mesh (P2P) vs SFU (Cloudflare Calls).
/// UI (RoomChatScreen) hanya bicara ke interface ini.
abstract class RoomMediaService extends ChangeNotifier {
  Future<void> start();
  Future<void> stop();
  bool get isBroadcaster;
  String get roomId;
  int get viewerCount;
}

/// Factory — pilih backend berdasarkan app_settings / flag.
/// Default 'mesh'. SFU disiapkan (lib/services/sfu_service.dart) dan
/// akan dipakai saat flag = 'sfu' (Cloudflare Calls).
class RoomMediaFactory {
  static RoomMediaService create({
    required String roomId,
    required bool isBroadcaster,
    VoidCallback? onEnded,
    String backend = 'mesh',
  }) {
    // SFU stub ada di sfu_service.dart — aktifkan saat backend == 'sfu'
    // ignore: dead_code
    if (backend == 'sfu') {
      // return SfuRoomService(roomId: roomId, isBroadcaster: isBroadcaster, onEnded: onEnded);
    }
    return MeshRoomMediaService(roomId: roomId, isBroadcaster: isBroadcaster, onEnded: onEnded);
  }
}

/// Adapter mesh — delegasi ke RoomBroadcastSession yang sudah ada.
class MeshRoomMediaService extends RoomMediaService {
  final RoomBroadcastSession _inner;
  MeshRoomMediaService({required String roomId, required bool isBroadcaster, VoidCallback? onEnded})
      : _inner = RoomBroadcastSession(roomId: roomId, isBroadcaster: isBroadcaster, onEnded: onEnded) {
    _inner.addListener(notifyListeners);
  }

  @override
  String get roomId => _inner.roomId;
  @override
  bool get isBroadcaster => _inner.isBroadcaster;
  @override
  int get viewerCount => _inner.viewerCount;
  RoomBroadcastSession get session => _inner;

  @override
  Future<void> start() => _inner.start();
  @override
  Future<void> stop() => _inner.stop();

  @override
  void dispose() {
    _inner.removeListener(notifyListeners);
    _inner.dispose();
    super.dispose();
  }
}
