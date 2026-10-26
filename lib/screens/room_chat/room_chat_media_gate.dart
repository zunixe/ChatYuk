part of '../room_chat_screen.dart';

// GERBANG KLIEN media room publik (dipisah dari room_chat_live.dart;
// REVIEW_2026-10-24 ARCH-01 + fitur moderasi 2026-10-26).
//
// Server adalah penjaga terakhir (`enforce_room_media_gate_trg`); bagian ini
// hanya menonaktifkan tombol foto/video agar user tidak menunggu upload
// yang pasti ditolak. Room privat (grup) TIDAK dibatasi.

mixin _RcMediaGateMx on _RoomChatBase {
  /// Hasil cek server: boleh kirim MEDIA di room ini?
  /// null = belum diketahui / RPC gagal → UI tidak memblokir (server menolak).
  bool? _mediaAllowed;

  @override
  Future<void> _refreshMediaGate() async {
    // Room privat & grup privat: perilaku lama, tanpa RPC.
    if (isPrivateRoom) return;
    try {
      final res = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(chat_riverpod.chatProvider.notifier).canSendRoomMedia(widget.room.id);
      if (!mounted) return;
      if (res != _mediaAllowed) setState(() => _mediaAllowed = res);
    } catch (_) {}
  }

  /// Gerbang klien untuk tombol media di ROOM PUBLIK. Server tetap penjaga
  /// terakhir (trigger `enforce_room_media_gate`).
  @override
  bool _mediaGateAllows() {
    if (isPrivateRoom) return true;
    if (_mediaAllowed != false) return true; // belum diketahui/gagal → biarkan
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    showChatSnack(context, s.roomMediaBlocked);
    _refreshMediaGate();
    return false;
  }
}
