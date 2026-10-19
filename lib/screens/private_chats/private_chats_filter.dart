part of '../private_chats_screen.dart';

// ignore_for_file: unused_element

mixin _PcFilterMx on _PcBase {
  Widget _chatFilterBar(S s) {
    return ValueListenableBuilder<
      ({int all, int unread, int friends, int anon, int registered})
    >(
      valueListenable: _countsNotifier,
      builder: (_, counts, __) {
        return ChatFilterChipBar(
          items: [
            ChatFilterChipItem(
              label: s.filterAllCount(counts.all),
              active: _chatFilter == ChatFilter.all,
              onTap: () => _selectFilter(ChatFilter.all),
            ),
            ChatFilterChipItem(
              label: s.filterUnreadCount(counts.unread),
              active: _chatFilter == ChatFilter.unread,
              onTap: () => _selectFilter(ChatFilter.unread),
            ),
            // GRUP (tepat setelah Belum dibaca): item grup di daftar Pesan yang sama.
            ChatFilterChipItem(
              label: s.filterGroupsCount(
                ref.watch(
                  roomProvider.select((r) => r.myGroups.length),
                ),
              ),
              active: _chatFilter == ChatFilter.groups,
              onTap: () => _selectFilter(ChatFilter.groups),
            ),
            ChatFilterChipItem(
              label: s.filterFriendsCount(counts.friends),
              active: _chatFilter == ChatFilter.friends,
              onTap: () => _selectFilter(ChatFilter.friends),
            ),
            ChatFilterChipItem(
              label: s.filterAnonCount(counts.anon),
              active: _chatFilter == ChatFilter.anon,
              onTap: () => _selectFilter(ChatFilter.anon),
            ),
            ChatFilterChipItem(
              label: s.filterRegisteredCount(counts.registered),
              active: _chatFilter == ChatFilter.registered,
              onTap: () => _selectFilter(ChatFilter.registered),
            ),
          ],
        );
      },
    );
  }

  void _selectFilter(ChatFilter value) {
    if (_chatFilter == value) return;
    setState(() {
      _chatFilter = value;
      _page = 1;
      _selected.clear();
    });
    // Hitung ulang memakai data yang sudah ada (tanpa fetch).
    _recomputeDirty = true;
    _recomputeFiltered(
      myUid:
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(authProvider.notifier).uid ??
          '',
      query: widget.externalQuery ?? _query,
    );
  }

  Widget _archivedToggle(S s, int archivedCount) {
    // Jarak antar-kartu dipasang di LUAR InkWell. Dulu margin ada di dalam
    // InkWell → area tap/ripple meluber ~10px keluar kartu yang terlihat
    // (muncul "background" di luar form). Material memberi warna dasar
    // supaya ripple terlihat & terpotong borderRadius.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _showArchived = !_showArchived;
            _selected.clear();
            _page = 1;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Icon(
                  _showArchived ? Icons.unarchive : Icons.archive_outlined,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  s.labelArchived(archivedCount),
                  style: AppText.bodyStrong.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showArchived ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelected(String uid) async {
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      await _deleteChat(uid, id);
    }
    // Kalau hapus dari tampilan arsip sampai habis → kembali ke utama.
    if (_showArchived && mounted) setState(() => _showArchived = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(localeProvider).s.deleteSelectedSuccess(ids.length),
          ),
        ),
      );
    }
  }

  Future<void> _deleteChat(String uid, String chatId) async {
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier).hideChat(uid, chatId);
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // Sematan grup (lokal per perangkat) — baca sinkron dari RAM/disk.
    GroupPinStore.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // List chat hidup di IndexedStack → initState hanya sekali, padahal
    // swap akun (dummy ⇄ admin) mengganti auth.uid. Re-bind stream/snapshot
    // saat uid berubah supaya otherUid di-resolve ke akun yang benar.
    final uid = ref.watch(authProvider.select((a) => a.uid));
    if (uid == _boundUid) return;
    _boundUid = uid;
    if (uid != null) {
      _initial = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(chatProvider.notifier).lastPrivateChatsSnapshot(uid);
      _stream = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(chatProvider.notifier).getMyPrivateChats(uid);
    } else {
      _initial = null;
      _stream = null;
    }
  }

  @override
  void dispose() {
    _idleWarmTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _pageNotifier.dispose();
    _listNotifier.dispose();
    _archivedNotifier.dispose();
    _countsNotifier.dispose();
    super.dispose();
  }

  Timer? _idleWarmTimer;

  bool _pageDebounce = false;

  void _onScroll() {
    if (_pageDebounce) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 100) {
      _pageDebounce = true;
      _page++;
      // Scroll hanya menambah halaman — pakai notifier, bukan setState,
      // supaya seluruh halaman (AppBar + bar seleksi + bar arsip) tidak
      // ikut rebuild di tengah scroll.
      _pageNotifier.value = _page;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _pageDebounce = false;
      });
    }
  }

  bool _sameStatusMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// Hitung ulang list terlihat (filter + urut + arsip). Dahulu ini hidup
  /// di dalam build() → tiap rebuild (tema, presence, badge) mengurutkan
  /// ulang 50 chat. Sekarang hanya dijalankan saat DATA berubah.
  /// liveNameMap disuplai pemanggil (saat build) supaya nama live tetap
  /// dipakai; recompute internal (perubahan data) memakai nama tersimpan.
  /// Snapshot himpunan teman (uid) yang dipakai SATU recompute penuh.
  /// KENAPA: dulu `friendOf()` membaca `socialProvider` secara LIVE tiap
  /// pemanggilan — list (`matches`) dihitung sinkron, sedangkan angka chip
  /// (`countsWithFriends`) dihitung lagi di `apply()` post-frame. Bila
  /// `socialProvider._friends` berubah di antara dua momen itu (memang
  /// terjadi: `_loadDisk` lalu `_refreshSelfSetsNow` sama-sama `_emit()`),
  /// chip dapat angka baru tapi list masih snapshot lama → chip "Teman (1)"
  /// sementara list kosong (bug layar abu-abu). Sekarang keduanya WAJIB
  /// memakai set yang sama.
  Set<String> _friendSnapshot() => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(socialProvider.notifier).friends;

  void _recomputeFiltered({
    required String myUid,
    required String query,
    Map<String, String>? liveNameMap,
    Map<String, String>? pendingStatus,
    bool notify = true,
  }) {
    if (pendingStatus != null) _statusMap = pendingStatus;
    if (_lastChats.isEmpty) {
      _lastFiltered = const [];
      _archivedCount = 0;
      if (notify) {
        _listNotifier.value = const [];
        _countsNotifier.value = (
          all: 0,
          unread: 0,
          friends: 0,
          anon: 0,
          registered: 0,
        );
      }
      return;
    }
    final live = liveNameMap ?? _statusMap;
    final filtered = query.isEmpty
        ? List<PrivateChatInfo>.of(_lastChats)
        : _lastChats.where((c) {
            final otherUid = c.participants.firstWhere(
              (p) => p != myUid,
              orElse: () => '',
            );
            final otherName =
                live[otherUid] ?? c.participantNames[otherUid] ?? '';
            return otherName.toLowerCase().contains(query);
          }).toList();
    // Urutkan: pinned paling atas (terbaru pinned dulu), baru chat
    // TERBARU (lastMessageAt desc) — status online tidak menggeser
    // urutan, chat paling aktif selalu di paling atas.
    filtered.sort((a, b) {
      final aPinned = a.isPinnedFor(myUid);
      final bPinned = b.isPinnedFor(myUid);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      if (aPinned && bPinned) {
        final aT =
            a.pinnedAtFor(myUid) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT =
            b.pinnedAtFor(myUid) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = bT.compareTo(aT);
        if (c != 0) return c;
      }
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    _archivedCount = _lastChats.where((c) => c.isArchivedFor(myUid)).length;
    // Pengaman: arsip kosong tapi masih di tampilan arsip (mis. habis
    // unarchive) → paksa kembali ke list utama agar halaman tak kosong.
    if (_showArchived && _archivedCount == 0) _showArchived = false;
    // Tampilan arsip: hanya chat terarsip. Normal: arsip disembunyikan.
    final visible = _showArchived
        ? filtered.where((c) => c.isArchivedFor(myUid)).toList()
        : filtered.where((c) => !c.isArchivedFor(myUid)).toList();

    // Hitung jumlah per filter dari daftar yang SUDAH lolos arsip+query —
    // supaya angka chip konsisten dengan isi yang benar-benar tampil.
    int unreadOf(PrivateChatInfo c) => c.unreadCounts[myUid] ?? 0;

    // ── SUMBER TUNGGAL untuk status teman ────────────────────────────────
    // Snapshot SEKALI per recompute. Dipakai `friendOf()` di bawah untuk
    // list MAUPUN untuk angka chip — jadi chip & list tak mungkin beda.
    final friendSet = _friendSnapshot();
    String otherOf(PrivateChatInfo c) =>
        c.participants.firstWhere((p) => p != myUid, orElse: () => '');
    bool friendOf(PrivateChatInfo c) => friendSet.contains(otherOf(c));

    bool registeredOf(PrivateChatInfo c) {
      final other = otherOf(c);
      return c.participantRegistered[other] == true;
    }

    // ── Precompute (unread, registered, friend) SATU KALI per item ───────
    // Dipakai untuk `matches()` DAN `countsWithFriends()`. Dengan begitu
    // predikat yang memutuskan tampilnya item identik dengan yang
    // menambah angka chip.
    final meta = <PrivateChatInfo, ({int unread, bool registered, bool friend})>{
      for (final c in visible)
        c: (
          unread: unreadOf(c),
          registered: registeredOf(c),
          friend: friendOf(c),
        ),
    };

    _lastFiltered = visible
        .where((c) {
          final m = meta[c]!;
          return ChatFilterLogic.matches(
            _chatFilter,
            unread: m.unread,
            otherRegistered: m.registered,
            otherFriend: m.friend,
          );
        })
        .toList();
    if (notify) {
      // TULIS SINKRON (bukan post-frame). Dulu `apply()` di-defer saat
      // dipanggil dari build → `_countsNotifier` bisa dihitung ulang di
      // frame berikut dengan `friends` yang sudah berbeda dari yang dipakai
      // `_lastFiltered`. Sekarang keduanya memakai `meta` (snapshot yang
      // sama) dan ditulis di giliran yang sama → chip & list konsisten.
      _listNotifier.value = _lastFiltered;
      _archivedNotifier.value = _archivedCount;
      _countsNotifier.value = ChatFilterLogic.countsWithFriends(
        visible.map(
          (c) => (
            unread: meta[c]!.unread,
            registered: meta[c]!.registered,
            friend: meta[c]!.friend,
          ),
        ),
      );
    }
  }
}
