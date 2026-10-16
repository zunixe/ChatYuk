import 'package:flutter/material.dart';

/// Bagian (section) halaman Chat — menggantikan TabBar "Pesan / Grup /
/// Global Room". Dipakai [ChatYukChatHeader] & halaman pemanggil.
enum ChatSection { messages, groups, rooms }

/// Warna header disamakan dengan halaman Timeline (ChatYukHeader) supaya
/// konsisten antar halaman.
const Color kChatHeaderBg = Color(0xFF0F1115);
const Color kChatHeaderText = Color(0xFFF2F4F7);
const Color kChatHeaderLine = Color(0xFF1C2028);
const Color kChatAccentBlue = Color(0xFF4FB3F6);
const Color kChatMenuBg = Color(0xFF1A1E26);
const Color kChatMenuBorder = Color(0xFF2A2F3A);
const Color kChatMenuText = Color(0xFFD5D9E0);
const Color kChatUnreadDot = Color(0xFFFF5A5F);
const Color kChatBadgeBg = Color(0xFF2F95E8);
const Color kChatChipActiveBg = Color(0xFFF2F4F7);
const Color kChatChipActiveText = Color(0xFF0F1115);
const Color kChatChipBorder = Color(0xFF2E3440);
const Color kChatChipText = Color(0xFFC9CDD3);

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

  /// Aksi tombol compose (edit_square) — dipindah dari FAB supaya tidak
  /// menutupi daftar chat.
  final VoidCallback? onCompose;

  const ChatYukChatHeader({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.unreadCounts,
    required this.onSearch,
    required this.onMore,
    this.onCompose,
  });

  @override
  Size get preferredSize => const Size.fromHeight(53); // 52 konten + 1 garis

  String _label(ChatSection s) {
    switch (s) {
      case ChatSection.messages:
        return 'Pesan';
      case ChatSection.groups:
        return 'Grup';
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
    return Container(
      decoration: const BoxDecoration(
        color: kChatHeaderBg,
        border: Border(bottom: BorderSide(color: kChatHeaderLine)),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        centerTitle: false,
        titleSpacing: 16,
        automaticallyImplyLeading: false,
        title: _titleMenu(context),
        iconTheme: const IconThemeData(color: kChatHeaderText),
        actions: [
          _actionBtn(
            icon: Icons.edit_square,
            tooltip: 'Tulis',
            onPressed: onCompose,
          ),
          _actionBtn(
            icon: Icons.search_rounded,
            tooltip: 'Cari',
            onPressed: onSearch,
          ),
          _actionBtn(
            icon: Icons.more_vert_rounded,
            tooltip: 'Menu',
            onPressed: onMore,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 22,
        padding: EdgeInsets.zero,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }

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
        side: const BorderSide(color: kChatMenuBorder),
      ),
      itemBuilder: (_) => [
        _menuItem(ChatSection.messages),
        _menuItem(ChatSection.groups),
        _menuItem(ChatSection.rooms),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label(section),
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: kChatHeaderText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Icon(Icons.keyboard_arrow_down, color: kChatHeaderText),
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
                fontSize: 15,
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
                  fontSize: 11,
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
                  fontSize: 13.5,
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
