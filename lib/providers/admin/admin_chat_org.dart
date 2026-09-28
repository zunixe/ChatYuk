part of '../admin_provider.dart';

/// Organisasi monitor chat admin: PIN + KATEGORI (folder) per percakapan.
///
/// Murni sisi-KLIEN (SharedPreferences) — tidak menyentuh DB: ini alat kerja
/// admin untuk merapikan daftar monitor, bukan data produk. Persist antar
/// restart. Tidak ada fungsi FROZEN yang disentuh.
///
/// Pola sama dengan `admin_notif.dart` (state di mixin, persist di prefs).
mixin AdminChatOrgMx on AdminBase {
  // ── State ──
  final Set<String> _pinnedChatIds = {};
  /// chatId → nama kategori. ChatId tanpa entri = belum berkategori.
  final Map<String, String> _chatCategory = {};
  /// Daftar kategori (folder) yang dibuat admin, urut alfabetis saat tampil.
  final Set<String> _categories = {};
  /// Filter kategori aktif di UI (null = Semua).
  String? _activeCategory;
  bool _chatOrgLoaded = false;
  /// Future load TERAKHIR — operasi tulis menunggu ini supaya tidak
  /// balapan (load yang selesai setelah tulis akan menimpa state baru).
  Future<void>? _loadFuture;

  static const String _kPinnedKey = 'admin_chat_pinned_ids';
  static const String _kChatCatKey = 'admin_chat_categories_map';
  static const String _kCategoriesKey = 'admin_chat_category_list';

  // ── Getter (UI) ──
  bool get chatOrgLoaded => _chatOrgLoaded;
  bool isChatPinned(String chatId) => _pinnedChatIds.contains(chatId);
  String? chatCategoryOf(String chatId) => _chatCategory[chatId];
  List<String> get chatCategories {
    final list = _categories.toList()..sort();
    return list;
  }

  String? get activeChatCategory => _activeCategory;

  /// Muat dari PREF (lokal) lalu SERVER (sync antar- HP admin), bukan sekali.
  /// Layar monitor di dalam TabBarView dibuang & dibangun ulang saat pindah
  /// tab; kalau hanya muat sekali, pin/kategori bisa "hilang".
  ///
  /// Sumber kebenaran tunggal sekarang = SERVER (`admin_chat_org`): kategori
  /// dibuat di HP admin mana pun muncul di semua HP. Prefs lokal tetap dipakai
  /// sebagai cache instan + fallback offline.
  Future<void> loadChatOrg() {
    final f = _loadChatOrgInner();
    _loadFuture = f;
    return f;
  }

  Future<void> _loadChatOrgInner() async {
    // 1) Lokal dulu (instan, tahan offline).
    await _loadChatOrgLocal();
    // 2) Server menyusul — menimpa dengan versi tersinkron (bila ada).
    await _syncChatOrgFromServer();
    _chatOrgLoaded = true;
  }

  Future<void> _loadChatOrgLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinned = prefs.getStringList(_kPinnedKey) ?? const [];
      final cats = prefs.getStringList(_kCategoriesKey) ?? const [];
      final map = _decodeMap(prefs.getStringList(_kChatCatKey) ?? const []);
      _applyChatOrg(pinned, cats, map, notify: true);
    } catch (_) {}
  }

  /// Ambil dari server & jadikan sumber kebenaran (cache ke prefs). Diam
  /// bila gagal (offline) — lokal tetap dipakai.
  ///
  /// SEED (upgrade pertama): bila server MASIH KOSONG tapi HP ini sudah punya
  /// organisasi lokal (dibuat sebelum fitur sync ada) → dorong ke ATAS dulu,
  /// jangan dihapus. Setelah itu server jadi sumber kebenaran antar-HP.
  Future<void> _syncChatOrgFromServer() async {
    final remote = await _orgGet();
    if (remote == null) return;
    final pinned = _strList(remote['pinned_chat_ids']);
    final cats = _strList(remote['category_list']);
    final map = <String, String>{};
    final rawMap = remote['category_map'];
    if (rawMap is Map) {
      rawMap.forEach((k, v) {
        if (v != null) map['$k'] = '$v';
      });
    }
    final serverEmpty = pinned.isEmpty && cats.isEmpty && map.isEmpty;
    final localHasData = _pinnedChatIds.isNotEmpty ||
        _categories.isNotEmpty ||
        _chatCategory.isNotEmpty;
    if (serverEmpty && localHasData) {
      // Server kosong + lokal ada → seed server dari lokal (jangan timpa).
      await _pushChatOrgToServer();
      return;
    }
    _applyChatOrg(pinned, cats, map, notify: true);
    await _persistChatOrg(); // cache lokal = cermin server
  }

  static List<String> _strList(dynamic v) {
    if (v is List) return v.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    return const [];
  }

  void _applyChatOrg(
    List<String> pinned,
    List<String> cats,
    Map<String, String> map, {
    required bool notify,
  }) {
    final changed =
        !_setEquals(_pinnedChatIds, pinned) ||
        !_setEquals(_categories, cats) ||
        !_mapEquals(_chatCategory, map);
    _pinnedChatIds
      ..clear()
      ..addAll(pinned);
    _categories
      ..clear()
      ..addAll(cats);
    _chatCategory
      ..clear()
      ..addAll(map);
    // Jaga filter aktif tetap valid (kategori mungkin sudah dihapus).
    if (_activeCategory != null &&
        _activeCategory!.isNotEmpty &&
        !_categories.contains(_activeCategory)) {
      _activeCategory = null;
    }
    if (changed && notify && !_disposed) notifyListeners();
  }

  // ── Bridge ke service (di-override di AdminProvider; null = tanpa sync) ──
  /// Get org dari server. Null bila tidak tersedia / gagal.
  Future<Map<String, dynamic>?> Function()? orgGet;
  /// Simpan org ke server. Return true bila sukses.
  Future<bool> Function(List<String> pinned, List<String> categories,
      Map<String, String> map)? orgSet;

  Future<Map<String, dynamic>?> _orgGet() async {
    try {
      return await orgGet?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pushChatOrgToServer() async {
    try {
      await orgSet?.call(
        _pinnedChatIds.toList(),
        _categories.toList(),
        Map<String, String>.from(_chatCategory),
      );
    } catch (_) {}
  }

  static bool _setEquals(Set<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in b.entries) {
      if (a[e.key] != e.value) return false;
    }
    return true;
  }

  /// Map disimpan sebagai daftar "chatId\u0001kategori" (SharedPreferences
  /// tak punya setStringList untuk map).
  static Map<String, String> _decodeMap(List<String> raw) {
    final m = <String, String>{};
    for (final e in raw) {
      final i = e.indexOf('\u0001');
      if (i <= 0) continue;
      m[e.substring(0, i)] = e.substring(i + 1);
    }
    return m;
  }

  static List<String> _encodeMap(Map<String, String> m) =>
      m.entries.map((e) => '${e.key}\u0001${e.value}').toList();

  Future<void> _persistChatOrg() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPinnedKey, _pinnedChatIds.toList());
      await prefs.setStringList(_kCategoriesKey, _categories.toList());
      await prefs.setStringList(_kChatCatKey, _encodeMap(_chatCategory));
    } catch (_) {}
  }

  /// Toggle pin satu chat. Return state baru (true = sekarang terpin).
  Future<bool> toggleChatPin(String chatId) async {
    await _loadFuture;
    if (chatId.isEmpty) return false;
    final now = _pinnedChatIds.contains(chatId);
    if (now) {
      _pinnedChatIds.remove(chatId);
    } else {
      _pinnedChatIds.add(chatId);
    }
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
    await _pushChatOrgToServer();
    return !now;
  }

  /// Buat kategori baru (no-op bila kosong/sudah ada). Return nama tersimpan.
  Future<String> addChatCategory(String name) async {
    await _loadFuture;
    final n = name.trim();
    if (n.isEmpty) return '';
    _categories.add(n);
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
    await _pushChatOrgToServer();
    return n;
  }

  /// Pindahkan chat ke kategori (null = keluarkan dari kategori).
  Future<void> setChatCategory(String chatId, String? category) async {
    await _loadFuture;
    if (chatId.isEmpty) return;
    final cat = category?.trim();
    if (cat == null || cat.isEmpty) {
      _chatCategory.remove(chatId);
    } else {
      _categories.add(cat);
      _chatCategory[chatId] = cat;
    }
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
    await _pushChatOrgToServer();
  }

  /// Hapus kategori + lepaskan semua chat di dalamnya.
  Future<void> removeChatCategory(String name) async {
    await _loadFuture;
    _categories.remove(name);
    _chatCategory.removeWhere((_, v) => v == name);
    if (_activeCategory == name) _activeCategory = null;
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
    await _pushChatOrgToServer();
  }

  /// Ganti nama kategori (chats ikut pindah).
  Future<void> renameChatCategory(String from, String to) async {
    await _loadFuture;
    final n = to.trim();
    if (n.isEmpty || from == n) return;
    _categories.remove(from);
    _categories.add(n);
    _chatCategory.updateAll((_, v) => v == from ? n : v);
    if (_activeCategory == from) _activeCategory = n;
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
    await _pushChatOrgToServer();
  }

  /// Set filter kategori aktif (null = Semua). No-op bila nilainya SAMA —
  /// mencegah rebuild + muat-ulang halaman tiap kali chip yang sama diklik.
  void setActiveChatCategory(String? category) {
    if (_activeCategory == category) return;
    _activeCategory = category;
    if (!_disposed) notifyListeners();
  }

  /// ChatId yang terdaftar di kategori [cat] (sumber: category_map).
  Set<String> categoryChatIds(String cat) {
    final out = <String>{};
    for (final e in _chatCategory.entries) {
      if (e.value == cat) out.add(e.key);
    }
    return out;
  }
}
