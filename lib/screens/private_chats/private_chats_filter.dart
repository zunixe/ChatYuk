part of '../private_chats_screen.dart';

// ignore_for_file: unused_element

mixin _PcFilterMx on _PcBase {
  Widget _chatFilterBar(S s) {
    return ValueListenableBuilder<
      ({int all, int unread, int friends, int anon, int registered})
    >(
      valueListenable: _countsNotifier,
      builder: (_, counts, __) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: Row(
            children: [
              _filterChip(s.filterAllCount(counts.all), ChatFilter.all),
              const SizedBox(width: 6),
              _filterChip(
                s.filterUnreadCount(counts.unread),
                ChatFilter.unread,
              ),
              const SizedBox(width: 6),
              _filterChip(
                s.filterFriendsCount(counts.friends),
                ChatFilter.friends,
              ),
              const SizedBox(width: 6),
              _filterChip(s.filterAnonCount(counts.anon), ChatFilter.anon),
              const SizedBox(width: 6),
              _filterChip(
                s.filterRegisteredCount(counts.registered),
                ChatFilter.registered,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, ChatFilter value) {
    return FilterChipPill(
      label: label,
      active: _chatFilter == value,
      onTap: () {
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
      },
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
    bool friendOf(PrivateChatInfo c) {
      final other = c.participants.firstWhere(
        (p) => p != myUid,
        orElse: () => '',
      );
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(socialProvider.notifier).isFriend(other);
    }

    bool registeredOf(PrivateChatInfo c) {
      final other = c.participants.firstWhere(
        (p) => p != myUid,
        orElse: () => '',
      );
      return c.participantRegistered[other] == true;
    }

    _lastFiltered = visible
        .where(
          (c) => ChatFilterLogic.matches(
            _chatFilter,
            unread: unreadOf(c),
            otherRegistered: registeredOf(c),
            otherFriend: friendOf(c),
          ),
        )
        .toList();
    if (notify) {
      // set ValueNotifier saat fase BUILD → "setState called during build".
      // Defer ke post-frame bila sedang build (dipanggil dari build()).
      final inBuild =
          SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;
      void apply() {
        _listNotifier.value = _lastFiltered;
        _archivedNotifier.value = _archivedCount;
        _countsNotifier.value = ChatFilterLogic.countsWithFriends(
          visible.map(
            (c) => (
              unread: unreadOf(c),
              registered: registeredOf(c),
              friend: friendOf(c),
            ),
          ),
        );
      }

      if (inBuild) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) apply();
        });
      } else {
        apply();
      }
    }
  }
}
