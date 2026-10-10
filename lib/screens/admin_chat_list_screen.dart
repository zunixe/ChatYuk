import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../widgets/admin_error_view.dart';
import '../models/active_call_model.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/locale_provider.dart';
import '../main.dart' show resumeWarmup;
import '../providers/riverpod/theme_provider.dart';
import '../core/ui/scroll_pagination.dart';
import '../providers/riverpod/admin_provider.dart';
import 'admin_chat_list/admin_chat_list_widgets.dart';

/// Admin: daftar semua percakapan user (monitoring).
class AdminChatListScreen extends ConsumerStatefulWidget {
  const AdminChatListScreen({super.key});

  @override
  ConsumerState<AdminChatListScreen> createState() =>
      _AdminChatListScreenState();
}

class _AdminChatListScreenState extends ConsumerState<AdminChatListScreen>
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
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
        unawaited(
          resumeWarmup().then((_) {
            if (mounted)
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(adminProvider).fetchActiveCalls();
          }),
        );
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
    final sig =
        '${identityHashCode(chats)}|${activeByChat.length}|'
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
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
    final wants = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider).categoryChatIds(activeCategory);
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
      final admin = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(adminProvider);
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
      if (!_categoryFullyLoaded(cat) &&
          admin.chatsHasMore &&
          !admin.chatsLoading) {
        // Masih belum lengkap padahal halaman belum habis → anggap gagal
        // jaringan (jangan spinner tanpa akhir; tampilkan tombol retry).
        _categoryLoadFailed = true;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('AdminChatList');
    ref.watch(themeProvider);
    // GRANULAR: layar ini menampilkan dua domain sekaligus — daftar chat
    // (revChats) DAN badge call aktif (revCalls) — jadi harus bergantung ke
    // keduanya. Tanpa ini, setiap notify dari domain lain (stats/devices/
    // deleted) ikut me-rebuild layar monitor yang berat.
    ref.watch(adminProvider.select((p) => p.revChats));
    ref.watch(adminProvider.select((p) => p.revCalls));
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    final s = ref.watch(localeProvider).s;
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
                avatar: Icon(Icons.add, size: 16, color: AppTheme.primary),
                label: Text(s.adminChatNewCategory),
                onPressed: () async {
                  final name = await _promptCategoryName(context, s);
                  if (name.isEmpty) return;
                  await admin.addChatCategory(name);
                  if (context.mounted) {
                    admin.setActiveChatCategory(name);
                  }
                },
                labelStyle: AppText.bodySmall.copyWith(color: AppTheme.primary),
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
                              (admin.chatsFetchingMore &&
                                      visibleChats.isNotEmpty
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
                            // Panaskan cache monitor SEJAK KARTU DI-RENDER (bukan
                            // hanya saat tap): baca disk `admin_chatmsg_<id>` ke
                            // memori provider sementara user masih menelusuri daftar.
                            // Tanpa ini, buka-pertama menunggu RPC (~1 dtk) dan baru
                            // cepat pada buka berikutnya (keluhan "harus beberapa
                            // kali baru cepet"). Debounce internal di provider →
                            // hanya 1 baca per chat, tak mengulang tiap rebuild.
                            admin.prefetchChatMessages(chatId);
                            // RepaintBoundary: kartu lain tidak ikut repaint saat
                            // satu kartu berubah (badge call/unread) — list monitor
                            // panjang jadi lebih hemat (konsisten dgn menu Online).
                            return RepaintBoundary(
                              child: AdminChatCard(
                                chat: chat,
                                s: s,
                                adminUids: admin.adminUids,
                                activeCall:
                                    admin.activeCallsByChat[chat['chat_id']],
                                pinned: admin.isChatPinned(chatId),
                                category: admin.chatCategoryOf(chatId),
                                onLongPressMenu: () => _chatActions(
                                  context,
                                  chat,
                                  label: _chatLabel(chat, s),
                                ),
                              ),
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
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
                leading: Icon(
                  Icons.folder_off_outlined,
                  color: AppTheme.textSecondary,
                ),
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
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
                  const Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: Color(0xFF7E57C2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.adminChatMoveToCategory,
                      style: AppText.bodyStrong,
                    ),
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
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
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
                    title: Text(
                      s.adminChatRenameCategory,
                      style: AppText.title,
                    ),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: AppText.body.copyWith(color: AppTheme.textPrimary),
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
                        onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
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
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
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
