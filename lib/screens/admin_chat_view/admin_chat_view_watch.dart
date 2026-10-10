part of '../admin_chat_view_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _AcWatchMx on _AdminBase {
  void _onWatchChanged() {
    if (!mounted) return;
    if (_watch?.stopped ?? false) setState(() {});
  }

  /// Samakan sesi pantau dengan call aktif dari provider.
  Future<void> _syncCallWatch() async {
    if (!mounted || _startingWatch) return;
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    if (_watch != null && _watch!.stopped) {
      final done = _watch!;
      _watch = null;
      done.removeListener(_onWatchChanged);
      await done.stop();
      if (mounted) setState(() {});
    }
    ActiveCallInfo? call;
    for (final c in admin.activeCalls) {
      if (c.chatId == widget.chatId) call = c;
    }
    if (call == null) return;
    if (_watch != null && _watch!.call.id == call.id) return;
    _startingWatch = true;
    final old = _watch;
    _watch = null;
    old?.removeListener(_onWatchChanged);
    await old?.stop();
    final ws = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider).createWatchSession(call);
    ws.addListener(_onWatchChanged);
    try {
      await ws.start();
    } catch (_) {}
    if (!mounted) {
      await ws.stop();
      _startingWatch = false;
      return;
    }
    setState(() => _watch = ws);
    _startingWatch = false;
  }

  Future<void> _stopWatch() async {
    final ws = _watch;
    _watch = null;
    ws?.removeListener(_onWatchChanged);
    await ws?.stop();
  }

  void _expandWatch() {
    final ws = _watch;
    if (ws == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdminCallWatchFullScreen(session: ws),
      ),
    );
  }

  // Selipkan chip tanggal (Hari ini/Kemarin/tanggal) di antara grup hari,
  // pola WhatsApp — sama seperti room chat. _msgs datang DESC (terbaru dulu),
  // jadi iterasi dibalik supaya terbaru tampil di bawah.
  // ── Items cache: dihitung SEKALI per perubahan _msgs (bukan tiap build) ──
  // Dulu getter dihitung ulang tiap frame → list panjang O(n²) + scroll
  // jump/kedip. Sekarang cache.
  List<ChatItem> get _items {
    final cached = _itemsCache;
    if (cached != null) return cached;
    final items = <ChatItem>[];
    String? prevDateKey;
    for (final m in _msgs.reversed) {
      final local = m.timestamp.toLocal();
      final dateKey = '${local.year}-${local.month}-${local.day}';
      if (prevDateKey != dateKey) {
        items.add(
          ChatItem.date(
            dateChipLabel(
              m.timestamp,
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(localeProvider).s,
            ),
          ),
        );
      }
      prevDateKey = dateKey;
      items.add(ChatItem.message(m));
    }
    _itemsCache = items;
    return items;
  }

  void _invalidateItems() {
    _itemsCache = null;
    _rebuildMsgIndex();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sisi kiri langsung dari judul/chatId — jangan tunggu pesan.
    // Kalau nunggu _applyMessages + kena early-return (cache == server),
    // _leftUid tetap null → semua bubble kanan.
    _leftUid = _computeLeftUid(const []);
    _fetch();
    _subscribeRealtime();
    // Poll 15 dtk (dulu 5 dtk) — pesan BARU sudah instan via realtime
    // (INSERT/UPDATE/DELETE terfilter chat_id). Poll hanya jaring fallback
    // saat realtime mati. Interval 5 dtk membuat parse JSON + _applyMessages
    // (map/union/sort map) tiap 5 dtk → GC Explicit tiap 5 dtk → frame stall
    // 181ms (terukur via gfxinfo + logcat GC).
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
    _scrollCtrl.addListener(_onScroll);
    // Call aktif: realtime UPDATE sudah instan; polling 15 dtk cukup sebagai
    // fallback (dulu 5 dtk, tumpang-tindih dgn _pollTimer → dua RPC + dua
    // rebuild tiap 5 dtk).
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    unawaited(_syncCallWatch());
    Future.microtask(() async {
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
    _callTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      final admin = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(adminProvider);
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
  }

  // ── Lifecycle: STOP polling saat app di-background ─────────────────────
  //
  // AKAR KELUHAN "admin lebih ngelag dari app user saat habis background":
  // layar ini dulu TIDAK punya handler lifecycle, jadi `_pollTimer` +
  // `_callTimer` (15 dtk) TETAP menembak RPC selama app di background — dan
  // realtime channel juga tetap terbuka. Saat resume, RPC-RPC itu bertumpuk
  // dengan rangkaian resume (warm-up koneksi + auth refresh + stats poll +
  // Heartbeat presence) → server antre → buka chat pertama terasa ~1 dtk.
  //
  // App USER tidak punya masalah ini: `_MainNav`/`AdminPanelScreen` (induk)
  // membatalkan semua timer saat pause. Layar ini sebelumnya luput.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _callTimer?.cancel();
      _callTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      // Segarkan sekali (ambil pesan yang masuk selama background), lalu
      // hidupkan kembali timer. Satu fetch — bukan tumpukan.
      unawaited(_poll());
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
      if (_callTimer == null) {
        _callTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
          if (!mounted) return;
          final admin = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(adminProvider);
          await admin.fetchActiveCalls();
          if (mounted) await _syncCallWatch();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _callTimer?.cancel();
    _photoSetStateTimer?.cancel();
    // Buang channel SEPENUHNYA (bukan hanya unsubscribe). `unsubscribe()`
    // saja meninggalkan channel di client Supabase → menumpuk tiap
    // buka-tutup chat → makin lambat saat bolak-balik (bocor socket).
    // Pola benar (sama seperti chat_service_private): removeChannel.
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      final sb = _channelClient;
      if (sb != null) {
        unawaited(sb.removeChannel(ch));
      } else {
        unawaited(ch.unsubscribe());
      }
    }
    _channelClient = null;
    _scrollCtrl.dispose();
    unawaited(_stopWatch());
    super.dispose();
  }

  void _onScroll() {
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    if (!_scrollCtrl.hasClients) return;
    // ListView( reverse:true → "atas" (pesan lebih lama) = maxScrollExtent.
    if (_scrollCtrl.position.pixels <
        _scrollCtrl.position.maxScrollExtent - 300) {
      return;
    }
    // GUARD: tanpa ini scroll memicu RPC bertubi-tubi (tiap pixel) →
    // "muter lama". Satu load-more dalam satu waktu.
    if (_loadingMore) return;
    if (!_hasMore) return;
    _loadingMore = true;
    if (mounted) setState(() {});
    admin.fetchMoreChatMessages(widget.chatId).then((_) {
      if (!mounted) return;
      _applyMessages();
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      _loadingMore = false;
      setState(() {});
    });
  }

  /// Pastikan _leftUid tidak null — dipanggil dari jalur cache maupun
  /// early-return supaya tidak semua bubble kanan.
  void _ensureLeftUid([List<String>? senders]) {
    if (_leftUid != null) return;
    final s =
        senders ??
        (() {
          final set = <String>{};
          for (final m in _msgs) {
            if (m.senderId.isNotEmpty) set.add(m.senderId);
          }
          return set.toList();
        })();
    final computed = _computeLeftUid(s);
    if (computed != null) {
      setState(() => _leftUid = computed);
    }
  }

  /// Re-map dari provider ke _msgs (dipakai setelah load-more / fetch).
  /// WAJIB memakai pesan chat INI (`chatMessagesFor`) — dulu `admin.chatMessages`
  /// (buffer bersama) sehingga saat dua layar monitor hidup pesan chat lain
  /// ikut tampil di layar ini ("pesan kecampur", semua bubble ke kanan).
}
