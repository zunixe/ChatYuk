import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/room_voice_service.dart';
export '../../services/room_voice_service.dart' show RoomVoiceSession;

/// Voice stage room (Riverpod) — pabrik sesi + re-ekspor tipe.
/// Fase B boundary: screen/widget room dilarang import services/ langsung.
/// Lifecycle sesi (attach listener, stop) tetap di screen (perilaku sama).
class RoomVoiceNotifier {
  RoomVoiceSession create({
    required String roomId,
    required String myUid,
    void Function()? onEnded,
    void Function()? onStageFull,
    void Function()? onMutedByAdmin,
  }) =>
      RoomVoiceSession(
        roomId: roomId,
        myUid: myUid,
        onEnded: onEnded,
        onStageFull: onStageFull,
        onMutedByAdmin: onMutedByAdmin,
      );
}

final roomVoiceProvider = Provider<RoomVoiceNotifier>((_) => RoomVoiceNotifier());
