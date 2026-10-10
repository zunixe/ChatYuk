import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../core/perf/perf_probe.dart';
import '../../../providers/riverpod/chat_provider.dart';
import '../../../providers/riverpod/online_users_provider.dart';
import '../../../widgets/leaderboard_sheet.dart';
import 'online_channel.dart';

/// AppBar halaman "Pengguna Online": tombol search (leading), judul + badge
/// channel + baris statistik (title), tray story (bottom), dan tombol
/// tambah-story + dropdown channel (actions).
///
/// Seluruh state & aksi dimiliki layar induk; widget ini murni tampilan +
/// callback sehingga perilaku (search toggle, ganti channel) tetap sama.
class OnlineAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final S s;
  final String? authUid;
  final Set<String> friendSet;
  final OnlineChannel channel;
  final bool isSearching;
  final String search;
  final TextEditingController searchCtrl;
  final Widget storyTray;

  final VoidCallback onToggleSearch;
  final VoidCallback onClearSearch;
  final void Function(String) onSearchChanged;
  final VoidCallback onOpenStoryComposer;
  final void Function(OnlineChannel) onChannelSelected;

  const OnlineAppBar({
    super.key,
    required this.s,
    required this.authUid,
    required this.friendSet,
    required this.channel,
    required this.isSearching,
    required this.search,
    required this.searchCtrl,
    required this.storyTray,
    required this.onToggleSearch,
    required this.onClearSearch,
    required this.onSearchChanged,
    required this.onOpenStoryComposer,
    required this.onChannelSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(62 + 146);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: AppTheme.bgScreen,
      surfaceTintColor: AppTheme.bgScreen,
      // 62 (isi judul + badge channel + baris stat) — cukup untuk 3 baris
      // tipis tanpa overflow; ruang ekstra tetap minimal.
      toolbarHeight: 62,
      // titleSpacing 0 saat searching: field cari menempel ke tombol
      // search (leading) & mengisi lebar sampai tempat ikon Top Aktif.
      // Saat tidak searching, biarkan default agar judul tidak mepet.
      titleSpacing: isSearching ? 0 : null,
      // Tombol search di KIRI ATAS (leading). Ikon Admin Panel pindah
      // ke actions kanan (hanya tampil untuk admin sungguhan).
      // Di samping search: ikon "Top Aktif" — pola Tooltip + GestureDetector
      // + Padding(horizontal: 3) + Icon (tanpa IconButton yang memaksa
      // 48px). Saat MODE SEARCH aktif, ikon Top Aktif disembunyikan — kalau
      // tidak, field search (title) menutupi/menumpuk ikon tsb.
      leadingWidth: isSearching ? 56 : 76,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: s.searchHint,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(
                  isSearching ? Icons.close : Icons.search_rounded,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          if (!isSearching)
            Tooltip(
              message: s.topActiveTooltip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tampil LANGSUNG di halaman ini sebagai bottom sheet
                // (bukan push halaman baru) — sama seperti aksi titik-3.
                onTap: () => LeaderboardSheet.show(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(Icons.emoji_events_rounded),
                ),
              ),
            ),
        ],
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SizeTransition(
            sizeFactor: anim,
            axis: Axis.horizontal,
            axisAlignment: -1,
            child: child,
          ),
        ),
        child: isSearching
            ? Padding(
                key: const ValueKey('search'),
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                height: 40,
                width: double.infinity,
                child: TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  onChanged: onSearchChanged,
                  style: AppText.body.copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: s.searchHint,
                    hintStyle: AppText.body.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 0,
                    ),
                    suffixIcon: search.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 18,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: onClearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.bgCard,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                ),
              )
            : rv.Consumer(
                key: const ValueKey('title'),
                builder: (ctx, ref, __) {
                  final prov = ref.watch(onlineUsersProvider);
                  PerfProbe.buildCount('Online.title');
                  // Hitung sama seperti list: exclude self + blocked +
                  // hidden + dedupe by uid/nickname, supaya angka = kartu.
                  // Saat channel "Teman", angka juga ikut channel (hanya
                  // teman) supaya konsisten dengan daftar di bawahnya.
                  final chat = ProviderScope.containerOf(context, listen: false)
                      .read(chatProvider.notifier);
                  final onlyFriends = channel == OnlineChannel.friends;
                  final seenU = <String>{};
                  final seenN = <String>{};
                  final n = prov.users
                      .where(
                        (u) =>
                            u.uid != authUid &&
                            u.uid.isNotEmpty &&
                            !chat.isBlocked(u.uid) &&
                            !prov.isHidden(u.uid) &&
                            (!onlyFriends || friendSet.contains(u.uid)) &&
                            seenU.add(u.uid) &&
                            seenN.add(u.nickname.toLowerCase()),
                      )
                      .length;
                  // Baris stat COMPACT (satu baris, pemisah '·'):
                  //   ● 10 online · 355 terdaftar · 136 anon
                  // Angka online diberi warna online (hijau) + dot supaya
                  // jadi fokus; total registered/anon abu-abu (sekunder).
                  // Total disembunyikan hingga termuat (null) → tetap rapi.
                  final reg = prov.totalRegistered;
                  final anon = prov.totalAnon;
                  final base = AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  );
                  final sep = TextSpan(
                    text: '  ·  ',
                    style: base.copyWith(
                      color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.titleOnline,
                        style: AppText.title.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Label channel aktif (Semua / Teman) — warna mencolok
                      // (primary) supaya user sadar daftar sedang terfilter.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              channel.icon,
                              size: 12,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              channel.label(s),
                              style: AppText.caption.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      // Baris stat bisa di-SLIDE horizontal: bila konten
                      // > lebar tersedia (mis. "13 pengguna aktif · 356
                      // terdaftar · 136 anon" di HP sempit) user bisa geser
                      // untuk lihat bagian kanan yang tadinya terpotong.
                      // Muat pas → tetap ter-center & tidak bisa digeser.
                      LayoutBuilder(
                        builder: (ctx, cons) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: ConstrainedBox(
                            // minWidth = lebar tersedia → saat konten lebih
                            // pendek, Center menaruhnya di tengah; saat lebih
                            // panjang, konten melebihi & bisa di-slide.
                            constraints: BoxConstraints(
                              minWidth: cons.maxWidth,
                            ),
                            child: Center(
                              child: Text.rich(
                              TextSpan(
                                children: [
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: const BoxDecoration(
                                        color: AppTheme.online,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: '$n',
                                    style: base.copyWith(
                                      color: AppTheme.online,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${s.onlineActiveUsers}',
                                    style: base,
                                  ),
                                  if (reg != null) ...[
                                    sep,
                                    TextSpan(
                                      text: '$reg ',
                                      style: base.copyWith(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: s.onlineTotalRegistered,
                                      style: base,
                                    ),
                                  ],
                                  if (anon != null) ...[
                                    sep,
                                    TextSpan(
                                      text: '$anon ',
                                      style: base.copyWith(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: s.onlineTotalAnon,
                                      style: base,
                                    ),
                                  ],
                                ],
                              ),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
      // Avatar + nama user + TRAY STORY (preferredSize) — tidak ikut
      // hilang saat mode search aktif.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(146),
        child: Padding(
          // Atas 2 (rapat ke field cari di toolbar) — total
          // 2 + 132 + 4 = 138 ≤ 146, tidak overflow.
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: storyTray,
        ),
      ),
      iconTheme: IconThemeData(color: AppTheme.textPrimary),
      // Tombol + story (SEMUA user — anon juga bisa, dipaksa public
      // oleh server). "Orang Sekitar" kini jadi salah satu item di dropdown
      // channel (Semua / Teman / Orang Sekitar) supaya AppBar lebih rapi.
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tombol Admin Panel dipindah ke tombol melayang kiri-bawah
              // (lihat _MainNav di app.dart) — tidak lagi di AppBar.
              Tooltip(
                message: s.storyAddTooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpenStoryComposer,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.add_circle_outline),
                  ),
                ),
              ),
              // Dropdown channel (Semua / Teman / Orang Sekitar) — menu kecil
              // muncul di SAMPING tombol (PopupMenuButton). Ikon berubah
              // sesuai channel aktif. Gaya selaras tombol admin panel:
              // transparan, tanpa bulatan. Tinggal tambah nilai enum untuk
              // ekspansi (mis. Bisnis).
              PopupMenuButton<OnlineChannel>(
                tooltip: channel.label(s),
                initialValue: channel,
                padding: EdgeInsets.zero,
                // Tanpa bulatan/ripple di belakang ikon (gaya admin panel).
                splashRadius: 0,
                color: AppTheme.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: onChannelSelected,
                itemBuilder: (_) => [
                  for (final c in OnlineChannel.values)
                    PopupMenuItem<OnlineChannel>(
                      value: c,
                      height: 44,
                      child: Row(
                        children: [
                          Icon(
                            c.icon,
                            size: 18,
                            color: c == channel
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            c.label(s),
                            style: AppText.body.copyWith(
                              color: c == channel
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary,
                              fontWeight: c == channel
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (c == channel) ...[
                            const Spacer(),
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(channel.icon, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
