import 'package:flutter/foundation.dart';
import 'room_media_service.dart';

/// Stub SFU untuk Cloudflare Calls.
/// - Saat backend = 'sfu', RoomChatScreen akan pakai ini.
/// - Implementasi nyata: minta token dari Edge Function `cf-calls-token`,
///   join SFU via WebRTC (WHIP/WHEP), render remote tracks.
/// - Untuk Fase 1, ini hanya stub agar jalur SFU bisa di-feature-flag
///   tanpa mengubah UI. Belum diaktifkan (default 'mesh').
class SfuRoomService extends RoomMediaService {
  SfuRoomService({required this.roomId, required this.isBroadcaster, this.onEnded});

  @override
  final String roomId;
  @override
  final bool isBroadcaster;
  final VoidCallback? onEnded;

  @override
  int get viewerCount => 0;

  @override
  Future<void> start() async {
    debugPrint('[SFU] stub start room=$roomId isBroadcaster=$isBroadcaster — belum diimplementasi, fallback ke mesh');
    // TODO: implementasi Cloudflare Calls
    // 1. POST /functions/v1/cf-calls-token {roomId, isBroadcaster}
    // 2. dapat {url, token}
    // 3. createPeerConnection dengan token, addTrack, createOffer/Answer via SFU
    // Untuk sekarang lempar agar caller tahu stub.
    throw UnimplementedError('SFU backend belum aktif — pakai mesh');
  }

  @override
  Future<void> stop() async {
    debugPrint('[SFU] stub stop room=$roomId');
    onEnded?.call();
    notifyListeners();
  }
}
