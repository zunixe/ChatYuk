part of '../private_chats_screen.dart';

// ignore_for_file: unused_element

mixin _PcSelectMx on _PcBase {
  void _toggleSelect(String chatId) {
    setState(() {
      if (_selected.contains(chatId))
        _selected.remove(chatId);
      else
        _selected.add(chatId);
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  /// Buka private chat dari kartu list. Dipanggil AppGestureDetector (lapis
  /// luar) supaya tak bergantung InkWell di dalam Dismissible (tap lambat).
  Future<void> _openChat(PrivateChatInfo chat) async {
    final myUid = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier).uid;
    final otherUid = chat.participants.firstWhere(
      (p) => p != myUid,
      orElse: () => '',
    );
    final otherName = chat.participantNames[otherUid] ?? '';
    // Guard double-push (§18): tap 2× cepat menumpuk 2 route identik.
    final navKey = navKeyChat(chat.chatId);
    if (!tryClaimNav(navKey)) return;
    // PUSH INSTAN (2026-10-11): prefetch dipindah ke PARALEL (fire-and-forget)
    // — TIDAK lagi di-await sebelum push. Dulu di-await agar `peekMessages`
    // pasti HIT saat mount, tapi efeknya transisi BARU MULAI setelah query
    // SQLite selesai → tap terasa telat & tak konsisten (DB besar = makin
    // lambat). Sekarang transisi langsung jalan; layar chat mengisi dari
    // `peekMessages`/initialData (fallback sudah ada) atau skeleton sekilas.
    unawaited(ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier).prefetchPrivateChat(chat.chatId));
    Navigator.push(
      context,
      chatRoute(
        chatId: chat.chatId,
        otherName: otherName,
        otherUid: otherUid,
        otherGender: chat.participantGenders[otherUid] ?? '',
        otherCountry: chat.participantLocations[otherUid] ?? '',
        otherAge: chat.participantAges[otherUid] ?? 0,
        otherRegistered: chat.participantRegistered[otherUid] == true,
        initialOtherDeleted: chat.otherDeleted,
      ),
    ).then((_) => releaseNav(navKey));
  }

  /// Aksi massal gaya WhatsApp — pin, mute, arsip untuk semua terpilih.
  /// Tombol menampilkan AKSI (misal semua sudah pin → tawarkan unpin).
  Future<void> _pinSelected(String uid, bool pin) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier);
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.pinChat(id, pin, myUid: uid);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pin ? s.msgPinned : s.msgUnpinned)),
      );
    }
  }

  Future<void> _muteSelected(String uid, bool mute) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier);
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.muteChat(id, mute, myUid: uid);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mute ? s.msgMuted : s.msgUnmuted)));
    }
  }

  Future<void> _archiveSelected(String uid, bool archive) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier);
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.archiveChat(id, archive, myUid: uid);
      } catch (_) {}
    }
    // Habis unarchive → kembali ke list utama (tampilan arsip kini kosong).
    if (!archive && mounted) setState(() => _showArchived = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archive ? s.msgArchived : s.msgUnarchived)),
      );
    }
  }

  Future<void> _confirmDeleteSelected(String uid) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          s.btnDeleteSelected,
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          s.deleteSelectedConfirm(_selected.length),
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDeleteSelected,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _deleteSelected(uid);
  }

  /// Ikon aksi bar seleksi gaya WhatsApp: pin, hapus, mute, arsip.
  /// Ikon = AKSI yang akan dijalankan (semua sudah pin → tawarkan unpin).
  List<Widget> _selectionActions(String uid, S s) {
    final byId = <String, PrivateChatInfo>{
      for (final c in _lastChats) c.chatId: c,
    };
    var allPinned = _selected.isNotEmpty;
    var allMuted = _selected.isNotEmpty;
    for (final id in _selected) {
      final c = byId[id];
      if (c == null || !c.isPinnedFor(uid)) allPinned = false;
      if (c == null || !c.isMutedFor(uid)) allMuted = false;
    }
    return [
      IconButton(
        tooltip: allPinned ? s.btnUnpin : s.btnPin,
        icon: Icon(allPinned ? Icons.push_pin_outlined : Icons.push_pin),
        onPressed: () => _pinSelected(uid, !allPinned),
      ),
      IconButton(
        tooltip: s.btnDeleteChat,
        icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
        onPressed: () => _confirmDeleteSelected(uid),
      ),
      IconButton(
        tooltip: allMuted ? s.btnUnmute : s.btnMute,
        icon: Icon(
          allMuted
              ? Icons.notifications_active
              : Icons.notifications_off_outlined,
        ),
        onPressed: () => _muteSelected(uid, !allMuted),
      ),
      if (!_showArchived)
        IconButton(
          tooltip: s.btnArchive,
          icon: const Icon(Icons.archive_outlined),
          onPressed: () => _archiveSelected(uid, true),
        )
      else
        IconButton(
          tooltip: s.btnUnarchive,
          icon: const Icon(Icons.unarchive),
          onPressed: () => _archiveSelected(uid, false),
        ),
    ];
  }

  /// Bar seleksi dalam body (mode embedded — tab Chat tidak punya AppBar sendiri).
  /// [overlay] = dipakai sbg overlay di atas filter bar: margin atas 0 supaya
  /// mulai lebih ke atas & MENUTUPI penuh baris filter di belakangnya
  /// (Semua/Belum dibaca/Teman/...) — tidak ada yang nyembul.
  Widget _selectionBar(String uid, S s, {bool overlay = false}) {
    return Container(
      margin: EdgeInsets.fromLTRB(10, overlay ? 0 : 10, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.btnCancel,
            icon: const Icon(Icons.arrow_back),
            onPressed: _clearSelection,
          ),
          Text(s.selectedCount(_selected.length), style: AppText.bodyStrong),
          const Spacer(),
          ..._selectionActions(uid, s),
        ],
      ),
    );
  }

  /// Baris "Diarsipkan (n)" — ketuk untuk buka/tutup tampilan arsip.
  /// Baris chip filter daftar chat. Hanya baris ini yang rebuild saat
  /// jumlah berubah (ValueListenable) — bukan seluruh halaman.
}
