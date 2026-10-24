import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Bagian (section) halaman Chat — menggantikan TabBar "Pesan / Grup /
/// Global Room". Dipakai [ChatYukChatHeader] & halaman pemanggil.
enum ChatSection { messages, rooms }

/// PERMINTAAN pindah SECTION dari luar halaman Chat (Pesan ⇄ Global Room).
///
/// Kenapa perlu: pintasan "Global Room" di halaman Online dulu membuka
/// `LobbyScreen` STANDALONE — itu jadi halaman Global Room KEDUA (header
/// sendiri), berbeda dari tab Rooms di halaman Chat (yang punya lonceng +
/// cari). Sekarang pintasan cukup mengalihkan ke tab Chat + section Rooms
/// lewat sinyal ini, sehingga hanya ADA SATU halaman Global Room.
///
/// Sekali-pakai: pembaca (ChatsScreen) meng-apply lalu mengosongkannya.
final ValueNotifier<ChatSection?> requestedChatSection = ValueNotifier(null);

/// Warna header disamakan dengan halaman Timeline (ChatYukHeader) supaya
/// konsisten antar halaman. DINAMIS mengikuti tema (mode terang ≠ hitam).
// SAMA dengan header halaman Profil (bgScreen / textPrimary / divider),
// mode terang & gelap konsisten antar halaman.
Color get kChatHeaderBg => AppTheme.bgScreen;
Color get kChatHeaderText => AppTheme.textPrimary;
Color get kChatMenuBg =>
    AppTheme.isDark ? const Color(0xFF1A1E26) : Colors.white;
Color get kChatMenuBorder =>
    AppTheme.isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD5D9E0);
Color get kChatMenuText =>
    AppTheme.isDark ? const Color(0xFFD5D9E0) : const Color(0xFF3A3F47);
Color get kChatChipText =>
    AppTheme.isDark ? const Color(0xFFC9CDD3) : const Color(0xFF3A3F47);
const Color kChatAccentBlue = Color(0xFF4FB3F6);
const Color kChatUnreadDot = Color(0xFFFF5A5F);
const Color kChatBadgeBg = Color(0xFF2F95E8);
Color get kChatChipActiveBg =>
    AppTheme.isDark ? const Color(0xFFF2F4F7) : const Color(0xFF14171C);
Color get kChatChipActiveText =>
    AppTheme.isDark ? const Color(0xFF0F1115) : Colors.white;
Color get kChatChipBorder =>
    AppTheme.isDark ? const Color(0xFF2E3440) : const Color(0xFFD5D9E0);

/// Header ringkas halaman Chat — konsisten dengan [TimelineScreen].
///
/// Layout: 52px konten + 1px garis bawah (= preferredSize 53).
///  - Kiri  : judul section aktif + panah; tap → menu pindah section.
///  - Kanan : edit/compose, search_rounded, more_vert_rounded (44x44).
///
/// Titik merah kecil di samping panah bila ADA section lain yang punya
/// pesan belum dibaca.
class ChatYukChatHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final ChatSection section;
  final ValueChanged<ChatSection> onSectionChanged;

  /// Jumlah pesan belum dibaca per section (badge angka di item menu).
  final Map<ChatSection, int> unreadCounts;
  final VoidCallback onSearch;
  final VoidCallback onMore;
  /// Buka sidebar notifikasi room/grup (badge bila [notificationCount] > 0).
  final VoidCallback? onNotifications;
  final int notificationCount;

  /// Mode cari: field muncul sebagai TITLE header (ala halaman Timeline),
  /// tombol aksi kanan disembunyikan & diganti tombol back (leading).
  final bool isSearching;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onCloseSearch;
  final String searchHint;

  const ChatYukChatHeader({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.unreadCounts,
    required this.onSearch,
    required this.onMore,
    this.onNotifications,
    this.notificationCount = 0,
    this.isSearching = false,
    this.searchController,
    this.onSearchChanged,
    this.onCloseSearch,
    this.searchHint = 'Cari',
  });

  @override
  Size get preferredSize => const Size.fromHeight(53); // 52 konten + 1 garis

  String _label(ChatSection s) {
    switch (s) {
      case ChatSection.messages:
        return 'Pesan';
      case ChatSection.rooms:
        return 'Global Room';
    }
  }

  /// Ada section LAIN (bukan aktif) yang punya unread → titik merah.
  bool get _othersHaveUnread {
    for (final e in unreadCounts.entries) {
      if (e.key != section && e.value > 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final searching = isSearching;
    return Container(
      decoration: BoxDecoration(color: kChatHeaderBg),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        centerTitle: false,
        titleSpacing: searching ? 0 : 16,
        automaticallyImplyLeading: false,
        leading: searching
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: kChatHeaderText),
                onPressed: onCloseSearch,
              )
            : null,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axis: Axis.horizontal,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
          child: searching
              ? KeyedSubtree(key: const ValueKey('search'), child: _searchField())
              : KeyedSubtree(key: const ValueKey('title'), child: _titleMenu(context)),
        ),        iconTheme: IconThemeData(color: kChatHeaderText),
        actions: searching
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onNotifications != null)
                        Tooltip(
                          message: 'Notifikasi',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onNotifications,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: _BellWithBadge(
                                count: notificationCount,
                                color: kChatHeaderText,
                              ),
                            ),
                          ),
                        ),
                      Tooltip(
                        message: 'Cari',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onSearch,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Menu',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onMore,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(Icons.more_vert_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
      ),
    );
  }

  /// Field cari jadi title header — ukuran & bentuk SAMA dengan menu Online
  /// (tinggi 40, radius 12, prefix ikon), plus border biru aksen + animasi
  /// AnimatedSwitcher (lihat build()).
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: TextField(
          controller: searchController,
          autofocus: true,
          onChanged: onSearchChanged,
          style: AppText.body.copyWith(color: kChatHeaderText),
          decoration: InputDecoration(
            isDense: true,
            hintText: searchHint,
            hintStyle: AppText.body.copyWith(color: Colors.white54),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.white70,
              size: 20,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 0,
            ),
            suffixIcon: (searchController?.text.isNotEmpty ?? false)
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      size: 18,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      searchController?.clear();
                      onSearchChanged?.call('');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.10),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            border: _searchBorder(kChatAccentBlue),
            enabledBorder: _searchBorder(Colors.white24),
            focusedBorder: _searchBorder(kChatAccentBlue, width: 1.5),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _searchBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _titleMenu(BuildContext context) {
    return PopupMenuButton<ChatSection>(
      tooltip: '',
      onSelected: onSectionChanged,
      color: kChatMenuBg,
      elevation: 8,
      offset: const Offset(0, 48),
      constraints: const BoxConstraints(minWidth: 230),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kChatMenuBorder),
      ),
      itemBuilder: (_) => [
        _menuItem(ChatSection.messages),
        _menuItem(ChatSection.rooms),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label(section),
            style: TextStyle(
              fontSize: AppTextSize.s23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: kChatHeaderText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Icon(Icons.keyboard_arrow_down, color: kChatHeaderText),
          // Titik merah: section LAIN punya unread.
          if (_othersHaveUnread)
            Container(
              margin: const EdgeInsets.only(left: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: kChatUnreadDot,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<ChatSection> _menuItem(ChatSection value) {
    final active = section == value;
    final unread = unreadCounts[value] ?? 0;
    return PopupMenuItem<ChatSection>(
      value: value,
      height: 46,
      child: Row(
        children: [
          if (active)
            const Icon(Icons.check, color: kChatAccentBlue, size: 20)
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _label(value),
              style: TextStyle(
                fontSize: AppTextSize.s15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? kChatHeaderText : kChatMenuText,
              ),
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: kChatBadgeBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppTextSize.s11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

}

/// Baris filter chip (Semua, Belum dibaca, Teman, Anon, Terdaftar).
/// Hanya ditampilkan di section Pesan. Tinggi baris 44px.
class ChatFilterChipBar extends StatelessWidget {
  final List<ChatFilterChipItem> items;
  const ChatFilterChipBar({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final it = items[i];
          return GestureDetector(
            onTap: it.onTap,
            child: Container(
              height: 32,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: it.active ? kChatChipActiveBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: it.active
                    ? null
                    : Border.all(color: kChatChipBorder),
              ),
              child: Text(
                it.label,
                style: TextStyle(
                  fontSize: AppTextSize.s135,
                  fontWeight: FontWeight.w700,
                  color: it.active ? kChatChipActiveText : kChatChipText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Satu chip pada [ChatFilterChipBar].
class ChatFilterChipItem {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const ChatFilterChipItem({
    required this.label,
    required this.active,
    required this.onTap,
  });
}

/// Ikon lonceng + badge angka (biru) bila ada notifikasi belum dibaca.
class _BellWithBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _BellWithBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Icon(Icons.notifications_outlined, size: 24, color: color),
          ),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15),
                decoration: BoxDecoration(
                  color: kChatBadgeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kChatHeaderBg, width: 1.2),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTextSize.s95,
                    fontWeight: FontWeight.w800,
                    height: AppTextSize.lh12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
