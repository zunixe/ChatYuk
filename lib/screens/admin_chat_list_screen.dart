import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../widgets/admin_error_view.dart';
import '../models/active_call_model.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../core/admin_err.dart';
import '../utils.dart';
import 'admin_chat_view_screen.dart';
import '../providers/theme_provider.dart';
import '../core/ui/scroll_pagination.dart';
import '../core/nav_guard.dart';
import '../widgets/gender_avatar.dart';
import 'user_info_screen.dart';

/// Admin: daftar semua percakapan user (monitoring).
class AdminChatListScreen extends StatefulWidget {
  const AdminChatListScreen({super.key});

  @override
  State<AdminChatListScreen> createState() => _AdminChatListScreenState();
}

class _AdminChatListScreenState extends State<AdminChatListScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  Timer? _callTimer;
  Timer? _searchDebounce;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  ScrollPagination? _pagination;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final admin = context.read<AdminProvider>();
    Future.microtask(() {
      admin.loadChatOrg();
      admin.fetchChats();
      admin.fetchActiveCalls();
    });
    _startTimers();
    _pagination = ScrollPagination(
      controller: _scrollCtrl,
      onLoadMore: () {
        if (!mounted) return;
        admin.fetchMoreChats();
      },
    );
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _callTimer?.cancel();
    final admin = context.read<AdminProvider>();
    // 30 dtk (dulu 15) — cukup fresh tanpa rebuild berlebihan.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      admin.refreshChats();
    });
    // Polling call aktif lebih cepat — badge video/audio call harus live.
    _callTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      admin.fetchActiveCalls();
    });
  }

  /// App di-background → stop polling (hemat baterai & beban DB).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _callTimer?.cancel();
      _callTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_refreshTimer == null) {
        context.read<AdminProvider>().fetchActiveCalls();
        _startTimers();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _callTimer?.cancel();
    _searchDebounce?.cancel();
    _pagination?.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Ketik search = debounce 250ms: filter+sort O(n log n) hanya jalan
  /// setelah user berhenti mengetik, bukan tiap huruf.
  void _onQueryChanged(String v) {
    _query = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }


  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> chats) {
    // Sembunyikan chat kosong (belum ada percakapan) dari monitor.
    final nonEmpty = chats
        .where((chat) => ((chat['message_count'] ?? 0) as num) > 0)
        .toList();
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return nonEmpty;
    return nonEmpty.where((chat) {
      final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
      final label = names.values
          .where((e) => e != null && '$e'.isNotEmpty)
          .join(' ')
          .toLowerCase();
      final lastMsg = (chat['last_message'] as String? ?? '').toLowerCase();
      return label.contains(q) || lastMsg.contains(q);
    }).toList();
  }

  // ── Memoize hasil filter+sort ──────────────────────────────────────────
  // List screen di-rebuild tiap AdminProvider.notifyListeners (poll chat 30s,
  // call 10s, presence, dsb). Tanpa memoize, `_sortedFiltered` (duplikasi
  // list + sort) jalan tiap rebuild → makin berat saat chat banyak / bolak-
  // balik buka-tutup. Cache di-invalidate via signature input yang murah.
  List<Map<String, dynamic>>? _sortedCache;
  String? _sortedCacheSig;

  List<Map<String, dynamic>> _sortedFiltered(
    List<Map<String, dynamic>> chats,
    Map<String, ActiveCallInfo> activeByChat, {
    required bool Function(String) isPinned,
    required String? Function(String) categoryOf,
    required String? activeCategory,
  }) {
    // Signature: identitas list chats + ukuran pin/kategori/call + query +
    // filter kategori. Perubahan pin/kategori mengganti ukuran set-nya, jadi
    // signature ikut berubah → cache invalid. Perubahan ISI satu chat (mis.
    // last_message baru) datang dengan list `chats` BARU (identitas beda).
    final sig = '${identityHashCode(chats)}|${activeByChat.length}|'
        '$_pinnedCount|$_catMapCount|${activeCategory ?? "\u0000"}|$_query';
    if (_sortedCache != null && _sortedCacheSig == sig) return _sortedCache!;
    final out = _sortedFilteredCompute(
      chats,
      activeByChat,
      isPinned: isPinned,
      categoryOf: categoryOf,
      activeCategory: activeCategory,
    );
    _sortedCache = out;
    _sortedCacheSig = sig;
    return out;
  }

  /// Jumlah pin/kategori — dipakai sebagai bagian signature memoize.
  /// Di-set dari build (dari provider) supaya cache tahu kapan invalid.
  int _pinnedCount = 0;
  int _catMapCount = 0;

  List<Map<String, dynamic>> _sortedFilteredCompute(
    List<Map<String, dynamic>> chats,
    Map<String, ActiveCallInfo> activeByChat, {
    required bool Function(String) isPinned,
    required String? Function(String) categoryOf,
    required String? activeCategory,
  }) {
    var filtered = _filtered(chats);
    // Filter kategori (folder): 'all' = semua; '' = tanpa kategori;
    // selain itu = nama kategori.
    if (activeCategory != null) {
      filtered = filtered.where((c) {
        final cat = categoryOf('${c['chat_id'] ?? ''}');
        if (activeCategory.isEmpty) return cat == null || cat.isEmpty;
        return cat == activeCategory;
      }).toList();
    }
    if (filtered.isEmpty) return filtered;
    // Urutan: (1) pin admin paling atas, (2) call aktif, (3) sisanya.
    final pinned = <Map<String, dynamic>>[];
    final calling = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final c in filtered) {
      final chatId = '${c['chat_id'] ?? ''}';
      if (isPinned(chatId)) {
        pinned.add(c);
      } else if (activeByChat.containsKey(chatId)) {
        calling.add(c);
      } else {
        rest.add(c);
      }
    }
    calling.sort((a, b) {
      final ca = activeByChat['${a['chat_id']}']!;
      final cb = activeByChat['${b['chat_id']}']!;
      return cb.createdAt.compareTo(ca.createdAt);
    });
    return [...pinned, ...calling, ...rest];
  }

  // Guard agar auto-load kategori tidak menembak berulang tiap build.
  bool _autoLoadingCategory = false;
  // True HANYA saat benar-benar sedang memuat halaman untuk kategori aktif.
  // Dipakai menggantikan cek `chatsHasMore` (global) yang bikin spinner
  // selamanya pada kategori KOSONG (mis. folder tanpa chat) — dulu dianggap
  // "masih memuat" padahal tak ada yang sedang dimuat.
  bool _categorySearching = false;
  // Setelah auto-load GAGAL (jaringan) → berhenti mencoba; tampilkan
  // empty-state + tombol coba lagi, bukan spinner tanpa akhir.
  bool _categoryLoadFailed = false;
  // Kategori terakhir yang dipantau — reset flag gagal saat kategori GANTI.
  String? _lastCategory;

  /// True bila SEMUA chat kategori [cat] sudah ada di daftar yang termuat →
  /// chip bisa tampil instan tanpa fetch/pindai lagi.
  bool _categoryFullyLoaded(String cat) {
    final admin = context.read<AdminProvider>();
    final want = admin.categoryChatIds(cat);
    if (want.isEmpty) return true;
    final have = admin.chats.map((c) => '${c['chat_id']}').toSet();
    for (final id in want) {
      if (!have.contains(id)) return false;
    }
    return true;
  }

  /// Muat halaman sampai SEMUA chat kategori aktif termuat — SATU operasi
  /// (loop internal di provider), bukan satu-halaman-per-frame.
  ///
  /// LAZY: berhenti begitu kategori sudah lengkap; klik ulang chip yang sama
  /// tidak memicu apa pun (tak "muter" berulang).
  void _maybeAutoLoadForCategory({
    required String? activeCategory,
    required bool loading,
    required bool hasMore,
  }) {
    if (activeCategory != _lastCategory) {
      _lastCategory = activeCategory;
      _categoryLoadFailed = false; // kategori ganti → reset status gagal
    }
    if (activeCategory == null || activeCategory.isEmpty) {
      _categorySearching = false;
      return; // 'Semua' / tanpa kategori → tidak perlu auto-load.
    }
    // Kategori KOSONG (belum ada chat dipetakan) → tak ada yang dicari.
    // Tampilkan empty-state, JANGAN spinner.
    final wants = context.read<AdminProvider>().categoryChatIds(activeCategory);
    if (wants.isEmpty) {
      _categorySearching = false;
      return;
    }
    // Sudah lengkap → tampil langsung, JANGAN muat/pindai lagi.
    if (_categoryFullyLoaded(activeCategory)) {
      _categorySearching = false;
      return;
    }
    if (loading || !hasMore || _autoLoadingCategory) return;
    if (_categoryLoadFailed) return; // sudah gagal → jangan ulang terus.
    _autoLoadingCategory = true;
    _categorySearching = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _autoLoadingCategory = false;
        _categorySearching = false;
        return;
      }
      final admin = context.read<AdminProvider>();
      final cat = admin.activeChatCategory;
      if (cat == null || cat.isEmpty) {
        _autoLoadingCategory = false;
        _categorySearching = false;
        return;
      }
      // SATU operasi: provider memuat halaman berulang sampai semua chat
      // kategori ini ketemu / halaman habis / batas halaman.
      await admin.ensureChatsContain(admin.categoryChatIds(cat));
      _autoLoadingCategory = false;
      _categorySearching = false;
      if (!_categoryFullyLoaded(cat) && admin.chatsHasMore && !admin.chatsLoading) {
        // Masih belum lengkap padahal halaman belum habis → anggap gagal
        // jaringan (jangan spinner tanpa akhir; tampilkan tombol retry).
        _categoryLoadFailed = true;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    // Hitung SEKALI per build: dulu `_sortedFiltered()` (filter+sort)
    // dipanggil di empty-check + itemCount + di dalam itemBuilder per baris
    // (O(n²) saat scroll). Hasilnya dipakai ulang di bawah.
    // Set jumlah pin/kategori untuk signature memoize (invalid saat organisasi
    // berubah walau identitas `chats` tetap).
    _pinnedCount = admin.chatPinnedCount;
    _catMapCount = admin.chatCategoryMapCount;
    final visibleChats = _sortedFiltered(
      admin.chats,
      admin.activeCallsByChat,
      isPinned: admin.isChatPinned,
      categoryOf: admin.chatCategoryOf,
      activeCategory: admin.activeChatCategory,
    );

    // Filter kategori aktif + belum ada yang cocok di halaman yang termuat,
    // TAPI masih ada halaman lain → muat terus otomatis sampai ketemu atau
    // habis. Tanpa ini, memilih kategori yang chat-nya ada di halaman >1
    // membuat daftar kosong + "muter-muter" tanpa akhir.
    _maybeAutoLoadForCategory(
      activeCategory: admin.activeChatCategory,
      loading: admin.chatsLoading,
      hasMore: admin.chatsHasMore,
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminChatMonitor, style: AppText.titleEmphasis),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppTheme.primary),
                onPressed: () => admin.fetchChats(),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onQueryChanged,
            style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: s.adminSearchChat,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Baris chip kategori (folder). SELALU tampil — termasuk saat daftar
        // kosong — supaya dari kategori kosong tetap bisa tap "Semua" untuk
        // balik (dulu chip ikut hilang bersama daftar → susah balik).
        // Tap chip = filter; tahan chip = kelola (rename/hapus).
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _catChip(
                label: s.adminChatCatAll,
                selected: admin.activeChatCategory == null,
                onTap: () => admin.setActiveChatCategory(null),
              ),
              if (admin.chatCategories.isNotEmpty)
                _catChip(
                  label: s.adminChatCatNone,
                  selected: admin.activeChatCategory == '',
                  onTap: () => admin.setActiveChatCategory(''),
                ),
              for (final cat in admin.chatCategories)
                _catChip(
                  label: cat,
                  selected: admin.activeChatCategory == cat,
                  onTap: () => admin.setActiveChatCategory(cat),
                  onLongPress: () => _manageCategory(context, cat),
                ),
              // Tombol buat kategori baru (tanpa perlu pin chat dulu).
              ActionChip(
                avatar: Icon(
                  Icons.add,
                  size: 16,
                  color: AppTheme.primary,
                ),
                label: Text(s.adminChatNewCategory),
                onPressed: () async {
                  final name = await _promptCategoryName(context, s);
                  if (name.isEmpty) return;
                  await admin.addChatCategory(name);
                  if (context.mounted) {
                    admin.setActiveChatCategory(name);
                  }
                },
                labelStyle: AppText.bodySmall.copyWith(
                  color: AppTheme.primary,
                ),
                backgroundColor: AppTheme.bgInput,
                side: BorderSide(color: AppTheme.primary),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        Expanded(
          child: admin.chatsLoading && admin.chats.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              // Layar error penuh HANYA bila belum ada data sama sekali.
              : admin.chatsError != null && admin.chats.isEmpty
              ? AdminErrorView(
                  s: s,
                  error: admin.chatsError!,
                  onRetry: () => admin.fetchChats(),
                )
              // Spinner HANYA saat benar-benar sedang mencari chat kategori
              // (bukan sekadar `chatsHasMore` global — kategori kosong dulu
              // jadi spinner selamanya). Gagal → empty-state + tombol retry.
              : (visibleChats.isEmpty &&
                    _categorySearching &&
                    !_categoryLoadFailed)
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : visibleChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(height: 12),
                      Text(
                        _query.isEmpty ? s.adminChatNoChats : s.searchNoResult,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      // Auto-load kategori gagal (jaringan) → tombol coba lagi.
                      if (_categoryLoadFailed) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _categoryLoadFailed = false);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(s.btnRetry),
                        ),
                      ],
                      // Filter kategori bernama sedang aktif (isi boleh kosong)
                      // → tombol hapus kategori langsung di sini, supaya tak
                      // perlu tahu gesture tahan-chip.
                      if (_query.isEmpty &&
                          admin.activeChatCategory != null &&
                          admin.activeChatCategory!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => admin.removeChatCategory(
                            admin.activeChatCategory!,
                          ),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppTheme.danger,
                          ),
                          label: Text(
                            s.adminChatDeleteCategory,
                            style: AppText.body.copyWith(
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Data ada tapi refresh gagal → banner, bukan layar error.
                    if (admin.chatsError != null)
                      Container(
                        width: double.infinity,
                        color: AppTheme.danger.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              size: 16,
                              color: AppTheme.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.adminErrStaleBanner,
                                style: AppText.bodySmall.copyWith(
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                  onRefresh: () => admin.fetchChats(),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      MediaQuery.of(context).padding.bottom + 12,
                    ),
                    // Spinner "muat lebih" HANYA saat halaman berikutnya
                    // BENAR-BENAR sedang dimuat (`chatsFetchingMore`) — dulu
                    // pakai `chatsHasMore` (masih ada halaman) sehingga footer
                    // spinner MUTER TERUS saat idle. Plus hanya bila ada baris
                    // tampil (daftar kosong → empty-state, bukan spinner).
                    itemCount:
                        visibleChats.length +
                        (admin.chatsFetchingMore && visibleChats.isNotEmpty
                            ? 1
                            : 0),
                    itemBuilder: (_, i) {
                      if (i >= visibleChats.length) {
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
                      final chat = visibleChats[i];
                      final chatId = '${chat['chat_id'] ?? ''}';
                      return _AdminChatCard(
                        chat: chat,
                        s: s,
                        adminUids: admin.adminUids,
                        activeCall: admin.activeCallsByChat[chat['chat_id']],
                        pinned: admin.isChatPinned(chatId),
                        category: admin.chatCategoryOf(chatId),
                        onLongPressMenu: () =>
                            _chatActions(context, chat, label: _chatLabel(chat, s)),
                      );
                    },
                  ),
                ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Label chat (nama peserta / jumlah user) — dipakai sheet & header.
  String _chatLabel(Map<String, dynamic> chat, S s) {
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final nameList = names.values
        .where((e) => e != null && '$e'.isNotEmpty)
        .toList();
    if (nameList.isNotEmpty) return nameList.join(' & ');
    return participants.length == 1
        ? '${participants.length} ${s.adminUserSingular}'
        : '${participants.length} ${s.adminUsersPlural}';
  }

  Widget _catChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          labelStyle: AppText.bodySmall.copyWith(
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.bgInput,
          side: BorderSide(color: AppTheme.divider),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// Sheet aksi gaya WhatsApp (muncul dari bawah saat kartu ditahan):
  /// Pin/Unpin, pindah/hapus kategori, dan hapus percakapan.
  Future<void> _chatActions(
    BuildContext context,
    Map<String, dynamic> chat, {
    required String label,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final admin = context.read<AdminProvider>();
    final chatId = '${chat['chat_id'] ?? ''}';
    if (chatId.isEmpty) return;
    final pinned = admin.isChatPinned(chatId);
    final currentCat = admin.chatCategoryOf(chatId);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.forum_outlined,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: AppTheme.primary,
              ),
              title: Text(pinned ? s.adminChatUnpin : s.adminChatPin),
              onTap: () async {
                final nowPinned = await admin.toggleChatPin(chatId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        nowPinned ? s.adminChatPinned : s.adminChatUnpinned,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.folder_outlined,
                color: Color(0xFF7E57C2),
              ),
              title: Text(
                currentCat == null
                    ? s.adminChatMoveToCategory
                    : s.adminChatChangeCategory,
              ),
              onTap: () => _pickCategory(ctx, chatId, currentCat),
            ),
            if (currentCat != null)
              ListTile(
                leading: Icon(Icons.folder_off_outlined,
                    color: AppTheme.textSecondary),
                title: Text(s.adminChatRemoveFromCategory),
                onTap: () async {
                  await admin.setChatCategory(chatId, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// Pilih kategori (atau buat baru) untuk sebuah chat.
  Future<void> _pickCategory(
    BuildContext sheetCtx,
    String chatId,
    String? current,
  ) async {
    final s = context.read<LocaleProvider>().s;
    final admin = context.read<AdminProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      size: 18, color: Color(0xFF7E57C2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.adminChatMoveToCategory,
                        style: AppText.bodyStrong),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final name = await _promptCategoryName(context, s);
                      if (name.isEmpty || !ctx.mounted) return;
                      await admin.setChatCategory(chatId, name);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.adminChatNewCategory),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final cat in admin.chatCategories)
                    ListTile(
                      leading: Icon(
                        Icons.folder,
                        color: cat == current
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                      title: Text(cat, style: AppText.body),
                      trailing: cat == current
                          ? Icon(Icons.check, color: AppTheme.primary, size: 20)
                          : null,
                      onTap: () async {
                        await admin.setChatCategory(chatId, cat);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// Dialog input nama kategori.
  Future<String> _promptCategoryName(BuildContext context, S s) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.adminChatNewCategory, style: AppText.title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppText.body.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: s.adminChatCategoryNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(s.btnSave),
          ),
        ],
      ),
    );
    return (name ?? '').trim();
  }

  /// Kelola kategori (rename / hapus) — dari long-press chip kategori.
  Future<void> _manageCategory(BuildContext context, String cat) async {
    final s = context.read<LocaleProvider>().s;
    final admin = context.read<AdminProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 18, color: Color(0xFF7E57C2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(cat, style: AppText.bodyStrong)),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
              title: Text(s.adminChatRenameCategory),
              onTap: () async {
                final ctrl = TextEditingController(text: cat);
                final newName = await showDialog<String>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    backgroundColor: AppTheme.bgCard,
                    title: Text(s.adminChatRenameCategory,
                        style: AppText.title),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style:
                          AppText.body.copyWith(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: s.adminChatCategoryNameHint,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx),
                        child: Text(s.btnCancel),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dctx, ctrl.text.trim()),
                        child: Text(s.btnSave),
                      ),
                    ],
                  ),
                );
                if ((newName ?? '').isNotEmpty) {
                  await admin.renameChatCategory(cat, newName!);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: Text(
                s.adminChatDeleteCategory,
                style: AppText.body.copyWith(color: AppTheme.danger),
              ),
              onTap: () async {
                await admin.removeChatCategory(cat);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _AdminChatCard extends StatelessWidget {
  final Map<String, dynamic> chat;
  final S s;
  final List<String> adminUids;

  /// Call aktif di chat ini (null = tidak sedang call).
  final ActiveCallInfo? activeCall;
  /// Disematkan admin (ikon pin + border).
  final bool pinned;
  /// Kategori (folder) chat ini (null = tanpa kategori).
  final String? category;
  /// Tahan kartu → buka sheet aksi (pin/kategori).
  final VoidCallback? onLongPressMenu;
  const _AdminChatCard({
    required this.chat,
    required this.s,
    required this.adminUids,
    this.activeCall,
    this.pinned = false,
    this.category,
    this.onLongPressMenu,
  });

  /// Buka profil user (sama seperti dari private chat: tap avatar header).
  /// Dipakai avatar peserta di kartu monitor.
  void _openUserProfile(BuildContext context, String uid, String name) {
    if (uid.isEmpty) return;
    final navKey = navKeyUser(uid);
    if (!tryClaimNav(navKey)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: uid, fallbackName: name),
      ),
    ).then((_) => releaseNav(navKey));
  }

  /// Dua avatar peserta (kiri = nama pertama di judul) berdampingan sedikit
  /// tumpang-tindih. Tiap avatar BISA DIKETUK → buka profil user tsb.
  /// Bila tak ada uid (data aneh) → fallback ikon forum seperti dulu.
  ///
  /// [genders] = peta uid→gender (dari `participant_genders`). Untuk peserta
  /// TANPA foto, avatar diberi ring warna gender (male=biru / female=pink /
  /// lain=accent) — sama seperti daftar "Pengguna Online". Foto tetap tanpa
  /// ring (lihat ProfileAvatar: ring hanya muncul di placeholder inisial).
  Widget _avatarPair(
    BuildContext context,
    List<String> uids,
    Map<dynamic, dynamic> names, {
    Map<dynamic, dynamic> genders = const {},
  }) {
    final shown = uids.take(2).toList();
    if (shown.isEmpty) {
      return SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.forum_outlined,
            color: AppTheme.primary,
            size: 22,
          ),
        ),
      );
    }
    const size = 40.0;
    const overlap = 10.0;
    final width = shown.length == 1 ? size : size * 2 - overlap;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              // Avatar kanan digambar di atas → sisi tumpang terlihat rapi.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openUserProfile(
                  context,
                  shown[i],
                  '${names[shown[i]] ?? ''}',
                ),
                child: Container(
                  // Ring pemisah HANYA saat avatar tumpang-tindih (≥2 peserta)
                  // supaya batas antar-avatar rapi. Avatar TUNGGAL tampil polos
                  // (tanpa border) — persis gaya daftar "Pengguna Online".
                  decoration: shown.length > 1
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.bgCard,
                            width: 2,
                          ),
                        )
                      : null,
                  child: GenderAvatar(
                    uid: shown[i],
                    name: '${names[shown[i]] ?? ''}',
                    gender: '${genders[shown[i]] ?? ''}',
                    size: size,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final genders =
        (chat['participant_genders'] as Map<dynamic, dynamic>?) ?? const {};
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final chatId = '${chat['chat_id'] ?? ''}';
    // Urutan uid DETERMINISTIK dari chatId (uid sorted, abadi) — bukan
    // urutan key `participant_names` (JSONB) yang ikut berubah saat nama
    // di-rename / beda antara snapshot cache & fetch baru. Inilah yang dulu
    // membuat judul "A & B" menukar urutan DAN semua bubble lawan pindah
    // ke kanan saat urutan flip.
    final orderUids = stableChatParticipantOrder(
      chatId: chatId,
      participants: participants.map((p) => '$p').toList(),
    );
    final nameList = [
      for (final u in orderUids)
        if (names[u] != null && '${names[u]}'.isNotEmpty) '${names[u]}',
    ];
    final label = nameList.isNotEmpty
        ? nameList.join(' & ')
        : participants.length == 1
        ? '${participants.length} ${s.adminUserSingular}'
        : '${participants.length} ${s.adminUsersPlural}';
    final lastMsg = (chat['last_message'] as String? ?? '').trim();
    final count = chat['message_count'] ?? 0;
    final tsRaw = chat['last_message_at'];
    final ts = tsRaw != null ? DateTime.tryParse('$tsRaw') : null;

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: activeCall != null
            ? Border.all(color: const Color(0xFF2E9E5B), width: 1.2)
            : pinned
            ? Border.all(color: AppTheme.primary, width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onLongPress: onLongPressMenu,
          onTap: () {
            final id = chat['chat_id'] as String? ?? '';
            // Tap 2× cepat menumpuk 2 route identik → 1× back terlihat mati.
            if (!tryClaimChatPush(id)) return;
            // Panaskan cache pesan MONITOR (provider `_chatMsgMem` + disk
            // `admin_chatmsg_<id>`) selagi animasi transisi jalan — layar
            // membaca ini lebih dulu → frame pertama langsung terisi.
            // (Dulu `preloadMessages` = cache stream user, bukan yang dipakai
            // monitor → tetap RPC server saat buka.)
            context.read<AdminProvider>().prefetchChatMessages(id);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminChatViewScreen(
                  chatId: id,
                  chatLabel: label,
                  participantOrder: orderUids,
                  participantNames: {
                    for (final e in names.entries)
                      '${e.key}': '${e.value ?? ''}',
                  },
                  participantGenders: {
                    for (final e in genders.entries)
                      '${e.key}': '${e.value ?? ''}',
                  },
                ),
              ),
            ).then((_) => releaseChatPush(id));
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Avatar peserta (menggantikan ikon forum) — tiap avatar
                    // bisa diketuk untuk melihat profil user, sama seperti
                    // dari private chat.
                    _avatarPair(context, orderUids, names, genders: genders),
                    if (activeCall != null)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: _CallActiveBadge(callType: activeCall!.callType),
                      ),
                  ],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (pinned || (category != null && category!.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              if (pinned) ...[
                                Icon(
                                  Icons.push_pin,
                                  size: 12,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  s.adminChatPin,
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (pinned &&
                                  category != null &&
                                  category!.isNotEmpty)
                                const SizedBox(width: 8),
                              if (category != null && category!.isNotEmpty) ...[
                                Icon(
                                  Icons.folder,
                                  size: 12,
                                  color: const Color(0xFF7E57C2),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    category!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.micro.copyWith(
                                      color: const Color(0xFF7E57C2),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      SizedBox(height: 3),
                      Text(
                        lastMsg.isEmpty
                            ? (count > 0 ? '$count ${s.adminChatMsgs}' : '')
                            : lastMsg,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (activeCall != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            activeCall!.callType == 'video'
                                ? Icons.videocam
                                : Icons.call,
                            size: 14,
                            color: const Color(0xFF2E9E5B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.adminCallLive,
                            style: AppText.micro.copyWith(
                              color: const Color(0xFF2E9E5B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                    ],
                    if (count > 0)
                      Text(
                        '$count',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (ts != null) ...[
                      SizedBox(height: 2),
                      Text(
                        formatRelativeTime(ts, isId: s.isId),
                        style: AppText.micro.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showDeleteDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final myUids = participants.map((e) => '$e').toList();
    if (myUids.length < 2) return;
    // Aksi tulis: tidak boleh jalan saat offline.
    if (guardOfflineCtx(
      context,
      s.adminNeedsConnection,
      (m) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m))),
    )) {
      return;
    }

    final selected = <String>{};
    // Secara default centang SEMUA user yang bukan admin.
    for (final uid in myUids) {
      if (!adminUids.contains(uid)) selected.add(uid);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Icon(Icons.delete_forever, color: AppTheme.danger, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.adminDeleteChatTitle,
                    style: AppText.titleEmphasis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.adminDeleteChatBody,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tampilkan SEMUA peserta — sebelumnya hanya 2 pertama yang
                  // muncul di dialog, padahal `selected` berisi semua non-admin
                  // → peserta ke-3+ terhapus diam-diam tanpa persetujuan.
                  for (final uid in myUids)
                    CheckboxListTile(
                      value: selected.contains(uid),
                      onChanged: adminUids.contains(uid)
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? selected.add(uid)
                                  : selected.remove(uid);
                            }),
                      title: Text(
                        '${s.adminDeleteUser}: ${names[uid] ?? 'User'}${adminUids.contains(uid) ? ' ${s.adminCannotDeleteAdmin}' : ''}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      activeColor: AppTheme.danger,
                    ),
                  SizedBox(height: 4),
                  Text(
                    s.adminDeleteChatOnly,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  s.btnCancel,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                child: Text(
                  s.adminDeleteChat,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final admin = context.read<AdminProvider>();
    final ok = await admin.deleteChat(
      chat['chat_id'] as String? ?? '',
      selected.toList(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.adminChatDeleted : s.adminDeleteFail)),
    );
    admin.fetchChats();
  }
}

/// Badge call aktif — lingkaran hijau berdenyut dengan icon video/audio.
class _CallActiveBadge extends StatefulWidget {
  final String callType;
  const _CallActiveBadge({required this.callType});

  @override
  State<_CallActiveBadge> createState() => _CallActiveBadgeState();
}

class _CallActiveBadgeState extends State<_CallActiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.55,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF2E9E5B),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.bgCard, width: 2),
        ),
        child: Icon(
          widget.callType == 'video' ? Icons.videocam : Icons.call,
          size: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}
