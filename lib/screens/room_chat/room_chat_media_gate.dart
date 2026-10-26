part of '../room_chat_screen.dart';

// GERBANG KLIEN media room publik (dipisah dari room_chat_live.dart;
// REVIEW_2026-10-24 ARCH-01 + fitur moderasi 2026-10-26).
//
// Server adalah penjaga terakhir (`enforce_room_media_gate_trg`); bagian ini
// hanya menahan tombol foto/video + menampilkan ALASAN yang tepat:
//   * account_too_new / not_enough_messages → aktivitas belum cukup
//   * needs_permit  → beda negara, tawarkan "Ajukan izin"
//   * permit_pending→ sudah menunggu tinjauan moderator
// Room privat (grup) TIDAK dibatasi.

mixin _RcMediaGateMx on _RoomChatBase {
  Map<String, dynamic>? _mediaGate;

  bool get _mediaAllowed => _mediaGate?['allowed'] != false;

  @override
  Future<void> _refreshMediaGate() async {
    if (isPrivateRoom) return;
    try {
      final res = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(chat_riverpod.chatProvider.notifier)
          .roomMediaGateState(widget.room.id);
      if (!mounted) return;
      if (res != null) setState(() => _mediaGate = res);
    } catch (_) {}
  }

  @override
  bool _mediaGateAllows() {
    if (isPrivateRoom) return true;
    if (_mediaAllowed) return true; // belum diketahui / gagal → server menolak

    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final reason = '${_mediaGate?['reason'] ?? ''}';

    switch (reason) {
      case 'needs_permit':
      case 'permit_pending':
        final country = '${_mediaGate?['room_country'] ?? ''}';
        if (reason == 'permit_pending') {
          showChatSnack(context, s.roomMediaPermitPending);
        } else {
          _askPermit(country);
        }
        break;
      case 'account_too_new':
        showChatSnack(context, s.roomMediaBlocked);
        break;
      case 'not_enough_messages':
        showChatSnack(
          context,
          s.roomMediaNotEnough(
            (_mediaGate?['min_msgs'] as num?)?.toInt() ?? 20,
            (_mediaGate?['have_msgs'] as num?)?.toInt() ?? 0,
          ),
        );
        break;
      default:
        showChatSnack(context, s.roomMediaBlocked);
    }
    _refreshMediaGate();
    return false;
  }

  @override
  Future<bool> contentSafetyAllowsMedia(String storagePath) async {
    // Hanya room PUBLIK (grup/privat tidak dibatasi, sesuai keputusan produk).
    if (isPrivateRoom) return true;
    final verdict = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chat_riverpod.chatProvider.notifier)
        .checkContentSafety(storagePath);
    if (verdict == 'reject') {
      if (mounted) {
        final s = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s;
        showChatSnack(context, s.roomMediaNsfwRejected);
      }
      return false;
    }
    // 'review' → tetap dikirim, namun ditandai agar moderator meninjau
    // (dibuat sebagai laporan otomatis di server saat moderasi).
    return true;
  }

  /// Dialog "Ajukan izin" untuk kirim media di room negara lain.
  Future<void> _askPermit(String country) async {
    if (country.isEmpty) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.roomMediaPermitRequest),
        content: Text(s.roomMediaNeedsPermit(country)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.roomMediaPermitRequest),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chat_riverpod.chatProvider.notifier)
        .requestCountryPermit(country);
    if (!mounted) return;
    showChatSnack(
      context,
      res['requested'] == true || res['already_pending'] == true
          ? s.roomMediaPermitRequested
          : s.roomMediaPermitPending,
    );
    await _refreshMediaGate();
  }
}
