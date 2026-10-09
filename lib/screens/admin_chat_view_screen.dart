import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../core/media/native_image.dart';
import '../core/nav_guard.dart';
import '../models/active_call_model.dart';
import '../models/message_model.dart';
import '../providers/admin_provider.dart';
import '../widgets/gender_avatar.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/cache/photo_cache.dart';
import '../core/cache/message_cache.dart';
import '../utils.dart';
import '../widgets/admin_call_watch_overlay.dart';
import '../widgets/date_chip.dart';
import '../widgets/private_chat_message.dart';
import 'admin_chat/widgets/audio_listen_chip.dart';
import '../providers/riverpod/theme_provider.dart';
import '../config/strings_admin.dart';
import 'user_info_screen.dart';
import '../providers/riverpod/admin_provider.dart';

/// Sisi kiri (lawan bicara) monitor chat — fungsi MURNI agar prioritas
/// terkunci test (`test/admin_chat_leftuid_test.dart`). Harus STABIL
/// (tidak ikut urutan kedatangan) supaya bubble tidak berpindah sisi.
///
/// Urutan sumber (PENTING — jangan dibalik):
/// 1) chatId split 'uid1_uid2' (format 1:1, uid SORTED → abadi, tidak
///    berubah saat nama di-rename / cache vs server beda urutan map).
/// 2) participantOrder (dari list screen) — hanya cadangan.
/// 3) senders terurut — supaya tidak semua kanan (null) bila dua sumber
///    di atas gagal.
///
/// Dulu participantOrder menang; itu yang membuat `order.first`
/// bergantung urutan key `participant_names` (JSONB) — ikut berubah saat
/// nickname berubah / beda antara snapshot cache & fetch baru → SEMUA
/// bubble lawan pindah ke kanan. chatId deterministik, jadi sekarang jadi
/// jangkar utama.
String? computeMonitorLeftUid({
  required List<String> participantOrder,
  required String chatId,
  required List<String> senders,
}) {
  final parts = chatId.split('_').where((e) => e.isNotEmpty).toList();
  if (parts.length == 2) return parts.first;
  final order = participantOrder.where((e) => e.isNotEmpty).toList();
  if (order.length >= 2) return order.first;
  if (senders.isNotEmpty) {
    final sorted = senders.where((e) => e.isNotEmpty).toList()..sort();
    if (sorted.isNotEmpty) return sorted.first;
  }
  return null;
}

/// Urutan uid peserta yang DETERMINISTIK dari chatId (uid SORTED, sama
/// dengan `privateChatId`). Dipakai agar label judul + avatar header +
/// sisi bubble admin selalu konsisten & tidak pernah bergeser. Bila
/// chatId tidak berformat 1:1 → urutkan uid unik agar tetap stabil.
List<String> stableChatParticipantOrder({
  required String chatId,
  required List<String> participants,
}) {
  final parts = chatId.split('_').where((e) => e.isNotEmpty).toList();
  if (parts.length == 2) return parts;
  final uniq = <String>{};
  for (final p in participants) {
    if (p.isNotEmpty) uniq.add(p);
  }
  return uniq.toList()..sort();
}

/// Guard anti double-push kartu monitor chat (diuji
/// `test/admin_chat_back_button_test.dart`).
///
/// Tap 2× cepat saat transisi push belum selesai menumpuk 2 route chat
/// identik — 1× back lalu terlihat "tidak ada reaksi" (kasus nyata chat
/// "Anggi & Jaky"). Klaim dilepas saat route di-pop ([releaseChatPush]).
///
/// Implementasi DIPINDAH ke `lib/core/nav_guard.dart` supaya jalur user &
/// admin memakai satu sumber yang sama. Nama lama dipertahankan sebagai
/// pembungkus agar pemanggil + test lama tidak berubah.
bool tryClaimChatPush(String chatId, {DateTime? now}) =>
    tryClaimNav(navKeyChat(chatId), now: now);

/// Lepas klaim [tryClaimChatPush] — dipanggil saat route chat di-pop.
void releaseChatPush(String chatId) => releaseNav(navKeyChat(chatId));

class AdminChatViewScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatLabel;

  /// Urutan peserta sesuai judul (nama pertama = bubble kiri, kedua = kanan).
  final List<String> participantOrder;

  /// uid → nama peserta (untuk avatar 2 sisi di header monitor).
  final Map<String, String> participantNames;

  /// uid → gender peserta (untuk ring warna avatar tanpa foto di header,
  /// sama seperti daftar "Pengguna Online" & kartu monitor).
  final Map<String, String> participantGenders;
  const AdminChatViewScreen({
    super.key,
    required this.chatId,
    required this.chatLabel,
    this.participantOrder = const [],
    this.participantNames = const {},
    this.participantGenders = const {},
  });

  @override
  ConsumerState<AdminChatViewScreen> createState() => _AdminChatViewScreenState();
}

class _AdminChatViewScreenState extends ConsumerState<AdminChatViewScreen> {
  List<MessageModel> _msgs = [];
  // True setelah SQLite/server pertama selesai — supaya empty-state TIDAK
  // berkedip muncul sesaat sebelum pesan terisi.
  bool _firstResolved = false;
  // Masih ada pesan lama untuk dimuat (pagination) — state lokal supaya
  // build tak perlu watch AdminProvider.
  bool _hasMore = false;
  // True HANYA saat load-more benar-benar berjalan. Footer spinner dulu
  // muncul selama `_hasMore` true (bahkan saat idle) → terlihat "muter" terus
  // tiap buka chat. Sekarang spinner hanya saat fetch halaman lama jalan.
  bool _loadingMore = false;
  /// True bila pemuatan pesan gagal. UI memakai teks ramah `s.adminChatError`
  /// — detail exception hanya ke dlog, tidak pernah ke layar.
  bool _error = false;
  String? _leftUid;
  String get _chatKey => cacheKeyFor(widget.chatId);
  // last_read_at kedua peserta (uid → waktu) — dasar hitung centang-2
  // sama seperti chat asli (bukan isMe).
  Map<String, DateTime> _lastRead = {};
  late Timer _pollTimer;
  RealtimeChannel? _channel;
  /// Client pemilik [\_channel] — untuk `removeChannel` saat dispose (buang
  /// channel sepenuhnya, cegah bocor saat buka-tutup chat berulang).
  SupabaseClient? _channelClient;
  final _photoLoading = <String>{};
  // Antrean foto: maks 3 unduhan bersamaan + cooldown 10 dtk per id
  // (pola sama seperti private chat). Tanpa ini tiap foto menembak RPC +
  // download + isolate thumbnail SEKALIGUS → berebut bandwidth/CPU dan
  // semua spinner foto muter lama.
  final List<String> _photoQueue = [];
  final Set<String> _photoQueued = {};
  final Map<String, DateTime> _photoLastAttempt = {};
  int _photoActive = 0;
  static const int _maxPhotoLoads = 3;
  /// Batas jumlah foto yang dipra-muat otomatis (dari pesan TERBARU). Sisa
  /// foto dimuat saat discroll/bubble-nya muncul — buka chat dengan ratusan
  /// pesan berisi foto tidak lagi menembak puluhan unduhan sekaligus.
  static const int _photoAutoLoadMax = 12;
  /// Peta id → indeks pada `_msgs` (dibangun ulang saat `_msgs` berubah) —
  /// menggantikan `indexWhere` O(n) yang membuat path foto O(n²).
  Map<String, int> _msgIndexById = const {};
  void _rebuildMsgIndex() {
    final m = <String, int>{};
    for (var i = 0; i < _msgs.length; i++) {
      m[_msgs[i].id] = i;
    }
    _msgIndexById = m;
  }
  final _scrollCtrl = ScrollController();
  final Map<String, LayerLink> _msgLinks = {};
  LayerLink _linkFor(String id) => _msgLinks.putIfAbsent(id, () => LayerLink());

  // ── Pantau call aktif di chat ini ──
  // WatchSession hidup hanya selama layar ini terbuka; dispose → stop()
  // memutus semua koneksi (admin berhenti mendengar/melihat).
  Timer? _callTimer;
  WatchSession? _watch;
  bool _startingWatch = false;
  // Poll 5 dtk bisa tumpang tindih saat RPC lambat.
  bool _polling = false;
  int _pollCount = 0;

  void _onWatchChanged() {
    if (!mounted) return;
    if (_watch?.stopped ?? false) setState(() {});
  }

  /// Samakan sesi pantau dengan call aktif dari provider.
  Future<void> _syncCallWatch() async {
    if (!mounted || _startingWatch) return;
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
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
    final ws = ProviderScope.containerOf(context, listen: false).read(adminProvider).createWatchSession(call);
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
  List<ChatItem>? _itemsCache;
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
            dateChipLabel(m.timestamp, ProviderScope.containerOf(context, listen: false).read(localeProvider).s),
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
    // Sisi kiri langsung dari judul/chatId — jangan tunggu pesan.
    // Kalau nunggu _applyMessages + kena early-return (cache == server),
    // _leftUid tetap null → semua bubble kanan.
    _leftUid = _computeLeftUid(const []);
    _fetch();
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _scrollCtrl.addListener(_onScroll);
    // Call aktif: fetch pertama + polling 5 detik selama layar terbuka.
    // Call aktif: mulai pantau SEGERA bila daftar sudah memuat call ini
    // (jangan tunggu RPC fetchActiveCalls — menghapus jeda s.d. ±5 dtk).
    // Fetch tetap jalan paralel sebagai penyegar + penanganan call baru.
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    unawaited(_syncCallWatch());
    Future.microtask(() async {
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
    _callTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
  }

  @override
  void dispose() {
    _pollTimer.cancel();
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
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
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
    final s = senders ??
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
  bool _applyMessages() {
    if (!mounted) return false;
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    return _applyRawMessages(admin.chatMessagesFor(widget.chatId));
  }

  /// Pasang daftar pesan mentah (dari cache prefetch monitor / provider) ke
  /// layar. Dipakai jalur SINKRON supaya frame pertama langsung terisi.
  ///
  /// MERGE by id — bukan replace. Alasannya:
  ///  - poll/realtime hanya membawa puluhan pesan terbaru (limit 15/40);
  ///    replace akan MEMANGKAS riwayat yang sudah dimuat via scroll.
  ///  - dua sumber (provider map vs SQLite view) bisa punya window beda.
  /// Hasil selalu: union(incoming, existing) urut terbaru dulu.
  ///
  /// Return true bila _msgs berubah (pemanggil menyimpan ke cache).
  /// Perbandingan mencakup isDeleted/edited/type — teks TAK BERUBAH saat
  /// soft-delete (hanya flag), jadi banding id+teks saja membuat penanda
  /// hapus tak pernah muncul.
  bool _applyRawMessages(List<Map<String, dynamic>> raw) {
    if (!mounted || raw.isEmpty) return false;
    final incoming = _mapMessages(raw);
    if (incoming.isEmpty) {
      _ensureLeftUid();
      return false;
    }
    // Union by id: incoming menang untuk id yang sama (data lebih segar).
    final byId = <String, MessageModel>{};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    for (final m in _msgs) {
      byId.putIfAbsent(m.id, () => m);
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // Pertahankan imageData yang sudah di-load (jangan hilang setelah merge).
    final oldImg = <String, String>{};
    for (final m in _msgs) {
      if (m.imageData.isNotEmpty) oldImg[m.id] = m.imageData;
    }
    for (var i = 0; i < list.length; i++) {
      final kept = oldImg[list[i].id];
      if (kept != null && kept.isNotEmpty && list[i].imageData.isEmpty) {
        list[i] = list[i].copyWith(imageData: kept);
      }
    }
    // Anti-rebuild: isi identik → tak perlu setState. Bandingkan juga
    // isDeleted/edited/type (bukan cuma id+teks) supaya penanda hapus/edit
    // yang masuk tetap memicu rebuild. imageData SENGAJA dikecualikan:
    // foto yang sudah di-load (thumb) vs datang '' dari server — ikut
    // dibandingkan malah menghapus foto yang tampil tiap poll.
    if (list.length == _msgs.length) {
      var same = true;
      for (var i = 0; i < list.length; i++) {
        final a = list[i];
        final b = _msgs[i];
        if (a.id != b.id ||
            a.text != b.text ||
            a.isDeleted != b.isDeleted ||
            a.edited != b.edited ||
            a.type != b.type) {
          same = false;
          break;
        }
      }
      if (same) {
        _ensureLeftUid();
        return false;
      }
    }
    final senderSet = <String>{};
    for (final m in list) {
      if (m.senderId.isNotEmpty) senderSet.add(m.senderId);
    }
    final senders = senderSet.toList();
    setState(() {
      _msgs = list;
      _invalidateItems();
      // Sisi kiri STABIL: hanya diisi bila masih kosong. Menimpa tiap poll
      // dengan hasil hitung-ulang (yang bisa null/kosong saat data sesaat
      // kosong) membuat SEMUA bubble pindah ke kanan.
      if (_leftUid == null || _leftUid!.isEmpty) {
        final computed = _computeLeftUid(senders);
        if (computed != null && computed.isNotEmpty) _leftUid = computed;
      }
      _error = false;
    });
    _loadPhotos();
    return true;
  }

  // ── Voice: VoiceBubble cache disk sendiri (play pertama download
  // sekali, sesi berikutnya dari lokal). imageData = voice_path.

  /// Sisi kiri = peserta pertama sesuai urutan judul (mis. judul
  /// "A & B" → bubble A di kiri, B di kanan). Konsisten, tidak tergantung
  /// siapa yang terakhir kirim pesan.
  ///
  /// FIX (gejala "lawan kadang muncul kadang ilang"): fallback WAJIB
  /// deterministik. Dulu cadangan terakhir `senders.first` = pengirim pesan
  /// Delegasi tipis ke [computeMonitorLeftUid] (fungsi murni, terkunci test).
  /// JANGAN menaruh logika di sini — dulu tiap lawan mengirim pesan,
  /// `_leftUid` berubah → SEMUA bubble berpindah sisi.
  String? _computeLeftUid(List<String> senders) =>
      computeMonitorLeftUid(
        participantOrder: widget.participantOrder,
        chatId: widget.chatId,
        senders: senders,
      );

  /// Samakan last-read dari server (dasar centang-2 per pesan).
  /// Dipanggil tiap fetch + poll 5 detik supaya live mengikuti.
  Future<void> _refreshRead() async {
    try {
      final raw = await ProviderScope.containerOf(context, listen: false)
          .read(adminProvider)
          .fetchChatLastRead(widget.chatId);
      if (!mounted) return;
      final map = <String, DateTime>{};
      raw.forEach((k, v) {
        final t = DateTime.tryParse(v);
        if (t != null) map[k] = t;
      });
      setState(() => _lastRead = map);
    } catch (_) {}
  }

  /// Lawan bicara pengirim di chat 1:1 (uid satunya). Null bila tak jelas
  /// (bukan format uid1_uid2) → pesan fallback centang-1.
  String? _recipientOf(String senderId) {
    final parts = widget.chatId.split('_');
    if (parts.length != 2) return null;
    if (senderId == parts[0]) return parts[1];
    if (senderId == parts[1]) return parts[0];
    return null;
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// [force] = true memaksa load ulang dari server (pull-to-refresh).
  /// Tanpa [force], kalau pesan sudah ada di cache lokal (memori/SQLite),
  /// layar TIDAK menembak server — pesan lama dari lokal, yang baru lewat
  /// poll/realtime. Inilah yang bikin buka ulang chat terasa instan.
  Future<void> _fetch({bool force = false}) async {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    // 0) SINKRON dari cache pesan monitor (hasil prefetch tap) — paling
    //    cepat, tanpa await: frame pertama langsung terisi seperti private
    //    chat. Dulu jalur ini tak ada (hanya cache stream `private_<id>`
    //    yang beda dari yang dipakai monitor) → selalu spinner → RPC.
    final adminMem = admin.peekChatMessages(widget.chatId);
    if (adminMem.isNotEmpty && _msgs.isEmpty) {
      _applyRawMessages(adminMem);
    }
    // 1) SINKRON dari memori stream (bila chat pernah dibuka sebagai user).
    final mem = MessageCache.instance.peekMessages(_chatKey);
    if (mem != null && mem.isNotEmpty && _msgs.isEmpty) {
      final senders = <String>{};
      for (final m in mem) {
        if (m.senderId.isNotEmpty) senders.add(m.senderId);
      }
      setState(() {
        _msgs = mem;
        _invalidateItems();
        _leftUid ??= _computeLeftUid(senders.toList());
      });
      _loadPhotos();
    }
    // 2) SQLite (cache lokal) — cepat, tetap tanpa skeleton. Tampilkan begitu
    //    ada, server menyusul & menggantikan.
    try {
      final cached = await MessageCache.instance.loadMessages(_chatKey);
      if (mounted && cached.isNotEmpty && _msgs.isEmpty) {
        final senders = <String>{};
        for (final m in cached) {
          if (m.senderId.isNotEmpty) senders.add(m.senderId);
        }
        setState(() {
          _msgs = cached;
          _invalidateItems();
          _leftUid ??= _computeLeftUid(senders.toList());
        });
        _loadPhotos();
      }
    } catch (_) {}
    // SQLite sudah dicek → boleh tentukan kosong/isi (hindari empty-state blink).
    if (mounted && !_firstResolved) setState(() => _firstResolved = true);
    // PERSISTEN: sudah ada pesan lokal & tidak dipaksa → cukup. Pesan BARU
    // ditangani poll 5 dtk + realtime (tidak menembak server di sini).
    if (!force && _msgs.isNotEmpty) {
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      unawaited(_refreshRead());
      return;
    }
    try {
      final ok = await admin.fetchChatMessages(widget.chatId, force: force);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = true;
        });
        return;
      }
      _applyMessages();
      unawaited(_refreshRead());
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      // Simpan ke cache untuk buka berikutnya (instant).
      if (_msgs.isNotEmpty) {
        unawaited(MessageCache.instance.saveMessages(_chatKey, _msgs));
      }
      dlog('[ADMIN-TIME] _fetch selesai msgs=${_msgs.length} hasMore=$_hasMore force=$force');
    } catch (e) {
      if (!mounted) return;
      dlog('[ADMIN] chat view load error: $e');
      setState(() {
        _error = true;
      });
    }
  }

  Future<void> _poll() async {
    // Tumpukan poll saat jaringan lambat = RPC bertubi + rebuild
    // beruntun. Satu poll jalan dalam satu waktu.
    if (_polling) return;
    _polling = true;
    try {
      final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
      // Poll hanya butuh pesan BARU (15 cukup) — bukan 1 halaman penuh.
      await admin.refreshChatMessages(widget.chatId, limit: 15);
      if (!mounted) return;
      // Berubah (baru/dihapus/diedit) → simpan ke cache lokal supaya
      // buka-ulang langsung benar tanpa menunggu poll berikutnya.
      if (_applyMessages()) {
        if (_msgs.isNotEmpty) {
          unawaited(MessageCache.instance.saveMessages(_chatKey, _msgs));
        }
      }
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      // last-read jarang berubah — cek tiap ~15 dtk, bukan tiap 5 dtk.
      if (++_pollCount % 3 == 0) unawaited(_refreshRead());
    } finally {
      _polling = false;
    }
  }

  List<MessageModel> _mapMessages(List<Map<String, dynamic>> raw) {
    return raw.map(_toMessageModel).where((m) => m.id.isNotEmpty).toList();
  }

  // ── Photo Loading (lazy, background) ─────────────────────────────────────

  bool _thumbBatchRunning = false;

  /// Dua lapis supaya tidak spinner lama:
  /// 1) Thumbnail lokal (file chat di HP ini) dibaca SEKALIGUS via
  ///    `loadMany` (1 isolate) — bukan satu-satu seperti dulu.
  /// 2) Sisanya (belum pernah dibuka di HP ini) baru unduh per foto.
  Future<void> _loadPhotos() async {
    bool isPhoto(MessageModel m) =>
        m.type == 'image' ||
        m.type == 'view_once' ||
        m.type == 'view_once_expired';
    // CATATAN: video TIDAK lewat jalur thumbnail ini. Path video diisi dari
    // RPC (image_path) → ChatVideoBubble mengunduh & memutar sendiri.
    if (!_thumbBatchRunning) {
      _thumbBatchRunning = true;
      try {
        final ids = <String>[];
        for (final m in _msgs) {
          if (isPhoto(m) &&
              m.imageData.isEmpty &&
              !_photoLoading.contains(m.id)) {
            ids.add(m.id);
          }
        }
        if (ids.isNotEmpty && mounted) {
          final thumbs = await PhotoCache.instance.loadMany(_chatKey, ids);
          if (mounted) {
            var changed = false;
            for (final id in ids) {
              final t = thumbs[id];
              if (t == null || t.isEmpty) continue;
              final idx = _msgIndexById[id] ?? -1;
              if (idx >= 0 && _msgs[idx].imageData.isEmpty) {
                _msgs[idx] = _msgs[idx].copyWith(imageData: t);
                changed = true;
              }
            }
            if (changed) setState(() {});
          }
        }
      } catch (_) {
      } finally {
        _thumbBatchRunning = false;
      }
    }
    if (!mounted) return;
    // _msgs datang DESC (terbaru dulu) → pra-muat HANYA [_photoAutoLoadMax]
    // foto terbaru. Sisa foto dimuat saat bubble-nya tampil (via _retryImage
    // saat deferred) — buka chat banyak foto jadi mulus.
    var scheduled = 0;
    final now = DateTime.now();
    for (final m in _msgs) {
      if (scheduled >= _photoAutoLoadMax) break;
      if (!isPhoto(m) || m.imageData.isNotEmpty || m.isDeleted) continue;
      if (_photoLoading.contains(m.id) || _photoQueued.contains(m.id)) {
        continue;
      }
      final last = _photoLastAttempt[m.id];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _photoLastAttempt[m.id] = now;
      _photoQueue.add(m.id);
      _photoQueued.add(m.id);
      scheduled++;
    }
    _drainPhotoQueue();
  }

  /// Jalankan antrean foto maksimal [_maxPhotoLoads] bersamaan.
  /// Selesai satu (sukses/gagal) → lanjutkan berikutnya.
  void _drainPhotoQueue() {
    if (!mounted) return;
    while (_photoActive < _maxPhotoLoads && _photoQueue.isNotEmpty) {
      final id = _photoQueue.removeAt(0);
      _photoQueued.remove(id);
      final idx = _msgIndexById[id] ?? -1;
      if (idx < 0) continue;
      final m = _msgs[idx];
      if (m.imageData.isNotEmpty || m.isDeleted) continue;
      final target = m;
      _photoActive++;
      _loadOnePhoto(target).whenComplete(() {
        _photoActive--;
        _drainPhotoQueue();
      });
    }
  }

  /// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap) —
  /// kalau tidak, RPC foto melempar 'Unauthorized' dan foto tak pernah
  /// tampil. Cek di client supaya pesannya jelas.
  bool _isAdminSession() =>
      AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

  /// Return true bila foto berhasil tampil. Gagal (mis. sesi dummy,
  /// offline) → false supaya pemanggil bisa memberi tahu user, bukan diam.
  Future<bool> _loadOnePhoto(MessageModel msg) async {
    if (!mounted) return false;
    _photoLoading.add(msg.id);
    var loaded = false;
    try {
      var data = '';
      // Coba PhotoCache dulu (thumbnail yang sudah ada di device ini)
      try {
        data = await PhotoCache.instance.load(_chatKey, msg.id) ?? '';
      } catch (_) {}
      // Kalau belum ada di cache, fetch dari server via admin RPC
      if (data.isEmpty) {
        final msgId = int.tryParse(msg.id);
        if (msgId != null && mounted) {
          final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
          var raw = await admin
              .fetchMessageImage(msgId)
              .timeout(const Duration(seconds: 15));
          // image_data berupa PATH storage (foto baru) → download dari bucket.
          if (raw.isNotEmpty &&
              mounted &&
              ProviderScope.containerOf(context, listen: false).read(storageProvider).isPath(raw)) {
            raw =
                await ProviderScope.containerOf(context, listen: false)
          .read(storageProvider)
                    .download(raw)
                    .timeout(const Duration(seconds: 15)) ??
                '';
          }
          data = raw;
          if (data.isNotEmpty) {
            try {
              await PhotoCache.instance.save(_chatKey, msg.id, data);
            } catch (_) {}
          }
        }
      }
      // Decode + buat thumbnail dari full-res
      if (data.isNotEmpty) {
        var thumb = '';
        try {
          thumb = await PhotoCache.instance.loadThumb(_chatKey, msg.id) ?? '';
        } catch (_) {}
        if (thumb.isEmpty) {
          try {
            thumb = await NativeImage.processAdminThumb(data) ?? '';
          } catch (_) {}
        }
        if (thumb.isEmpty) thumb = '';
        if (!mounted) return false;
        final idx = _msgIndexById[msg.id] ?? -1;
        if (idx >= 0) {
          // Gunakan thumbnail kalau ada, fallback ke full-res
          final imgData = thumb.isNotEmpty ? thumb : data;
          if (_msgs[idx].imageData.isEmpty ||
              _msgs[idx].imageData != imgData) {
            _msgs[idx] = _msgs[idx].copyWith(imageData: imgData);
            // Batch: TIDAK setState per foto (dulu tiap foto = rebuild seluruh
            // list → blink/jank). Jadwalkan satu rebuild per frame.
            _schedulePhotoSetState();
          }
          loaded = _msgs[idx].imageData.isNotEmpty;
        }
      }
    } catch (_) {
      // Gagal (timeout/network/RPC) → biarkan placeholder; tap/auto-load
      // berikutnya bisa coba lagi (id SELALU dibuang di finally).
    } finally {
      _photoLoading.remove(msg.id);
    }
    return loaded;
  }

  Timer? _photoSetStateTimer;
  void _schedulePhotoSetState() {
    if (!mounted) return;
    // Coalesce 400ms: foto selesai berselang detik (network), bukan dalam
    // frame yang sama — post-frame saja berarti 1 rebuild PER FOTO (12 foto
    // = 12x rebuild 40 bubble). Timer ini menggabungkannya jadi sedikit.
    if (_photoSetStateTimer?.isActive ?? false) return;
    _photoSetStateTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _retryImage(String msgId) async {
    final msg = _msgs.where((m) => m.id == msgId).firstOrNull;
    if (msg == null || !mounted) return;
    final ok = await _loadOnePhoto(msg);
    // Gagal tampil JANGAN diam: beri tahu sebabnya. Sesi dummy = RPC
    // ditolak server; kalau tidak, berarti koneksi/kuota.
    if (!ok && mounted) {
      final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _isAdminSession() ? s.adminPhotoLoadFail : s.dummyNeedAdmin,
            ),
          ),
        );
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    // Lewat provider (bukan Supabase.instance langsung) supaya test bisa
    // menyuntik client mock — perilaku produksi identik.
    final sb = ProviderScope.containerOf(context, listen: false).read(adminProvider).realtimeClient;
    _channelClient = sb;
    _channel = sb.channel('admin-${widget.chatId.hashCode}');
    // FILTER chat_id — tanpa ini SETIAP pesan di seluruh app memicu _poll
    // (fetch+setState) → blink/berat. Hanya perubahan chat INI yang reaksi.
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'chat_id',
      value: widget.chatId,
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.subscribe((status, err) {
      // Realtime error (mis. offline) → catat; timer _pollTimer 5 dtk tetap
      // jadi fallback sehingga monitor tidak mati diam-diam.
      if (err != null) debugPrint('[ADMIN] chat-monitor realtime error: $err');
    });
  }

  // ── Mapping ───────────────────────────────────────────────────────────────

  MessageModel _toMessageModel(Map<String, dynamic> m) {
    return MessageModel(
      id: '${m['id']}',
      senderId: '${m['sender_id'] ?? ''}',
      senderName: '${m['sender_name'] ?? 'Anon'}',
      senderGender: '${m['sender_gender'] ?? 'other'}',
      isRegistered: false,
      text: '${m['text'] ?? ''}',
      type: '${m['type'] ?? 'text'}',
      // Voice: RPC kirim voice_path → disimpan di imageData (dipakai
      // VoiceBubble dengan disk cache-nya sendiri).
      // Foto/video: pakai `image_data` bila ada (view-once), kalau kosong
      // fallback ke `image_path` (path storage) — supaya admin BISA melihat
      // foto biasa & video di monitor (dulu kosong → tak tampil).
      imageData: m['type'] == 'voice'
          ? '${m['voice_path'] ?? ''}'
          : (('${m['image_data'] ?? ''}').isNotEmpty
                ? '${m['image_data']}'
                : '${m['image_path'] ?? ''}'),
      isDeleted: m['is_deleted'] == true,
      edited: m['edited'] == true,
      durationMs: m['duration_ms'] is int
          ? m['duration_ms'] as int
          : int.tryParse('${m['duration_ms'] ?? ''}'),
      timestamp: parseDate(m['created_at']),
      repliedToId: m['replied_to_id'] is String ? m['replied_to_id'] : null,
      repliedToText: m['replied_to_text'],
      repliedToSenderName: m['replied_to_sender_name'],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Dua avatar peserta DITUMPANG-TINDIH (bukan satu di kiri & satu di kanan)
  /// — gaya sama dengan kartu di daftar monitor agar header rapi. Tap salah
  /// satu avatar → buka PROFIL-nya (UserInfoScreen, sama seperti tap avatar
  /// di private chat) — bukan zoom foto.
  Widget _headerAvatarPair() {
    final uids = widget.participantOrder
        .where((u) => u.isNotEmpty)
        .take(2)
        .toList();
    if (uids.isEmpty) return const SizedBox.shrink();
    const size = 34.0;
    const overlap = 12.0;

    Widget avatarOf(String uid, int i, {required bool withRing}) {
      final name = widget.participantNames[uid] ?? '';
      return Container(
        // Ring pemisah HANYA saat avatar tumpang-tindih (2 peserta) supaya
        // batas antar-avatar terlihat rapi. Avatar TUNGGAL tampil polos
        // (tanpa border) — persis gaya daftar "Pengguna Online".
        decoration: withRing
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.headerGradient.colors.first,
                  width: 2,
                ),
              )
            : null,
        child: GestureDetector(
          onTap: () => _openProfile(uid, name),
          // Gaya SAMA PERSIS dengan daftar "Pengguna Online": lingkaran latar
          // + ring warna gender untuk yang tanpa foto.
          child: GenderAvatar(
            uid: uid,
            name: name,
            gender: widget.participantGenders[uid] ?? '',
            size: size,
          ),
        ),
      );
    }

    if (uids.length == 1) return avatarOf(uids[0], 0, withRing: false);
    return SizedBox(
      width: size * 2 - overlap,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 2; i++)
            Positioned(
              left: i * (size - overlap),
              child: avatarOf(uids[i], i, withRing: true),
            ),
        ],
      ),
    );
  }

  /// Tap avatar header → profil peserta (sama seperti private chat).
  void _openProfile(String uid, String name) {
    if (uid.isEmpty || !mounted) return;
    final navKey = navKeyUser(uid);
    if (!tryClaimNav(navKey)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: uid, fallbackName: name),
      ),
    ).then((_) => releaseNav(navKey));
  }

  /// Tahan bubble pesan → salin teks (sama seperti "salin" di private chat).
  /// Monitor read-only: langsung salin + toast, tanpa mode seleksi.
  Future<void> _copyMessage(MessageModel msg) async {
    if (msg.text.isEmpty || !mounted) return;
    await Clipboard.setData(ClipboardData(text: msg.text));
    if (!mounted) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.msgMessageCopied)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // JANGAN watch AdminProvider — notifyListeners (poll/tab lain) bikin
    // seluruh layar rebuild = kedip. Data pesan diambil via _applyMessages
    // (read), hasMore disimpan di state lokal.
    final watchingVideo = _watch != null && _watch!.isVideo;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        // titleSpacing 0: area judul mulai tepat di kanan tombol back →
        // grup (avatar-nama-avatar) benar-benar di tengah antara tombol back
        // dan tepi kanan layar (default 16dp menggeser ke kanan).
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        title: Center(
          child: Row(
            // Grup (avatar tumpang-tindih + nama) di tengah — gaya sama
            // dengan kartu di daftar monitor.
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerAvatarPair(),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.chatLabel,
                  textAlign: TextAlign.center,
                  style: AppText.titleEmphasis.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Tanpa bar loading — data dari SQLite instan (WhatsApp-style).
          if (_error)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 6),
              color: AppTheme.danger.withValues(alpha: 0.1),
              child: Text(
                s.adminChatError,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: AppTheme.danger),
              ),
            ),
          // Chip "mendengarkan" untuk call audio — masuk chat = mulai dengar,
          // keluar dari layar ini = berhenti.
          if (_watch != null && !_watch!.isVideo)
            AudioListenChip(session: _watch!),
          Expanded(
            child: Stack(
              children: [
                _msgs.isEmpty && _firstResolved
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              s.adminChatNoChats,
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetch(force: true),
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          // Bangun sedikit item di luar viewport — kartu jauh
                          // tidak ikut decode foto (buka chat banyak pesan
                          // tidak memuat puluhan gambar sekaligus).
                          scrollCacheExtent: ScrollCacheExtent.pixels(200),
                          padding: EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            MediaQuery.of(context).padding.bottom + 16,
                          ),
                          itemCount:
                              _items.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            // Spinner footer HANYA saat load-more benar-benar
                            // berjalan (dulu selalu tampil selama _hasMore →
                            // terlihat "muter" terus tiap buka chat).
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            }
                            final item = _items[_items.length - 1 - i];
                            if (item.dateLabel != null)
                              return DateChip(label: item.dateLabel!);
                            final msg = item.msg!;
                            final isMe = msg.senderId != _leftUid;
                            // Samakan chat asli: centang-2 hanya bila
                            // PENERIMA sudah baca (timestamp < last-read
                            // penerima). Tak diketahui → centang-1.
                            final recipient = _recipientOf(msg.senderId);
                            final readAt = recipient != null
                                ? _lastRead[recipient]
                                : null;
                            final isRead =
                                readAt != null &&
                                msg.timestamp.isBefore(readAt);
                            final isImageDeferred =
                                msg.type == 'image' && msg.imageData.isEmpty;
                            // RepaintBoundary per bubble: scroll tidak
                            // merender ulang bubble lain (isolasi repaint) —
                            // kunci utama anti-jank saat pesan banyak.
                            // Video di luar 50 terbaru → poster tidak
                            // auto-load (hemat kuota); tap memuat.
                            return RepaintBoundary(
                              child: MessageBubble(
                                key: ValueKey(msg.id),
                                link: _linkFor(msg.id),
                                msg: msg,
                                chatKey: _chatKey,
                                autoVideoPoster: i < 50,
                                isMe: isMe,
                                isRead: isRead,
                                isAdminView: true,
                                // Admin melihat percakapan 2 orang → centang
                                // muncul di KEDUA sisi (kiri & kanan), bukan
                                // hanya milik pengirim.
                                showChecksBothSides: true,
                                isImageDeferred: isImageDeferred,
                                onRetryImage: isImageDeferred
                                    ? _retryImage
                                    : null,
                                onLongPressMenu: (d, m, _) => _copyMessage(m),
                              ),
                            );
                          },
                        ),
                      ),
                // Call video aktif → overlay setengah layar seperti private
                // chat; bisa di-expand ke fullscreen.
                if (watchingVideo)
                  Positioned.fill(
                    child: AdminCallWatchOverlay(
                      session: _watch!,
                      onExpand: _expandWatch,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// Thumbnail admin kini diproses di NATIVE via `NativeImage.processAdminThumb`
// (fallback ke `dartAdminThumbB64` Dart di lib/core/media/chat_photo_helper.dart).
