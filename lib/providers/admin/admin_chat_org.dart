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

  /// Muat dari prefs. SELALU memuat ulang (bukan sekali) — layar monitor di
  /// dalam TabBarView dibuang & dibangun ulang saat pindah tab, dan provider
  /// bisa di-remount; kalau hanya muat sekali, pin/kategori bisa "hilang"
  /// (state in-memory kosong tapi load di-skip). Murah (baca prefs lokal).
  Future<void> loadChatOrg() {
    final f = _loadChatOrgInner();
    _loadFuture = f;
    return f;
  }

  Future<void> _loadChatOrgInner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinned = prefs.getStringList(_kPinnedKey) ?? const [];
      final cats = prefs.getStringList(_kCategoriesKey) ?? const [];
      final map = _decodeMap(prefs.getStringList(_kChatCatKey) ?? const []);
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
      _chatOrgLoaded = true;
      if (changed && !_disposed) notifyListeners();
    } catch (_) {
      _chatOrgLoaded = true;
    }
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
  }

  /// Hapus kategori + lepaskan semua chat di dalamnya.
  Future<void> removeChatCategory(String name) async {
    await _loadFuture;
    _categories.remove(name);
    _chatCategory.removeWhere((_, v) => v == name);
    if (_activeCategory == name) _activeCategory = null;
    if (!_disposed) notifyListeners();
    await _persistChatOrg();
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
  }

  /// Set filter kategori aktif (null = Semua).
  void setActiveChatCategory(String? category) {
    _activeCategory = category;
    if (!_disposed) notifyListeners();
  }
}
