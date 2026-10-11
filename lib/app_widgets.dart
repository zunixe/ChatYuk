part of 'app.dart';

class AppBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final uid = ref.watch(authProvider.select((a) => a.uid));
    final chat = ref.read(chatProvider.notifier);
    // Badge hijau = jumlah user online (bukan diri sendiri, bukan diblokir).
    // `select` mengembalikan ANGKA (bukan list) → AppBottomNav hanya rebuild
    // saat jumlahnya benar-benar berubah, bukan tiap kali list online
    // berubah referensi (yang dulu memicu rebuild seluruh bottom nav).
    final onlineCount = ref.watch(
      onlineUsersProvider.select((p) {
        var n = 0;
        for (final u in p.users) {
          if (u.uid != uid && !chat.isBlocked(u.uid) && u.status == 'online') {
            n++;
          }
        }
        return n;
      }),
    );

    return StreamBuilder<List<PrivateChatInfo>>(
      stream: uid != null ? chat.getMyPrivateChats(uid) : const Stream.empty(),
      builder: (_, snap) {
        // Ukur biaya agregasi badge per emission (kandidat optimasi QA).
        final totalUnread = PerfProbe.measure('Nav.unread', () {
          return (snap.data ?? []).fold<int>(0, (sum, c) {
            return sum + ((c.unreadCounts[uid] ?? 0));
          });
        });
        // Nav bar Android (system bar bawah) dibuat SAMA dengan footer
        // (bgCard) ala WhatsApp: edge-to-edge membuat app menggambar DI
        // BELAKANG system bar, jadi kita cat area inset bawah dengan warna
        // footer. Hanya kecerahan ikon nav yang disetel (tanpa warna nav
        // karena API warna system bar deprecated di Android 15+).
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            systemNavigationBarIconBrightness:
                AppTheme.isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: ColoredBox(
            color: AppTheme.bgCard,
            child: SafeArea(
              top: false,
              child: BottomAppBar(
                color: AppTheme.bgCard,
                shape: const CircularNotchedRectangle(),
                notchMargin: 6,
                padding: EdgeInsets.zero,
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _navItem(
                      context,
                      Icons.group_rounded,
                      s.navOnline,
                      0,
                      badge: onlineCount,
                      badgeColor: AppTheme.onlineDark,
                      badgePill: true,
                    ),
                    _navItem(
                      context,
                      Icons.chat_bubble,
                      s.navChats,
                      1,
                      badge: totalUnread,
                      badgePill: true,
                    ),
                    const SizedBox(width: 48),
                    _navItem(
                      context,
                      Icons.dynamic_feed_rounded,
                      s.navTimeline,
                      2,
                    ),
                    _navItem(context, Icons.person, s.navProfile, 3),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Pil indikator tab terpilih (gaya NavigationBar M3). Ukuran 68x30
  /// gepeng proporsional (radius = tinggi/2 = 15). Bulge sin() bikin
  /// pil sedikit mengembang di tengah animasi; ikon pop 0.85→1.
  /// Dua tahap: opacity full dalam 25% pertama (~125ms) supaya tap
  /// terasa respon instan; lebar easeOutExpo — ngacir di awal lalu
  /// melambat lembut di akhir (500ms). Collapse 250ms emphasized.
  /// Aksesibilitas: disableAnimations → pil langsung settle (tanpa
  /// tween, tanpa bulge, tanpa pop).
  Widget _navPill({
    required BuildContext context,
    required bool selected,
    required Widget child,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(
        width: 68,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected)
              Container(
                width: 68,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            child,
          ],
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: selected ? 0 : 1, end: selected ? 1 : 0),
      // 500ms → 260ms: tap tab terasa langsung "mendarat" (ala Telegram),
      // kurva easeOutExpo tetap membuat gerakannya lembut.
      duration: Duration(milliseconds: selected ? 260 : 180),
      curve: selected ? Curves.linear : const Cubic(0.2, 0.0, 0.0, 1.0),
      builder: (context, t, child) {
        final w = t >= 1 ? 1.0 : 1 - math.pow(2, -10 * t).toDouble();
        final o = (t / 0.25).clamp(0.0, 1.0);
        final bulge = 1 + 0.08 * math.sin(w * math.pi);
        return SizedBox(
          width: 68,
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: selected ? o : t,
                child: Container(
                  width: 68 * w * bulge,
                  height: 30 * (0.6 + 0.4 * w),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.85 + 0.15 * (t * 3).clamp(0.0, 1.0),
                child: child!,
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label,
    int index, {
    int badge = 0,
    Color badgeColor = AppTheme.danger,
    bool badgePill = false,
  }) {
    final selected = currentIndex == index;
    // Pil terpilih = soft transparan ala WhatsApp: tint primary tipis
    // di belakang ikon solid — kalem, tidak norak.
    final iconColor = selected ? AppTheme.primary : AppTheme.textSecondary;
    final labelColor = selected ? AppTheme.primary : AppTheme.textSecondary;
    // Tanpa InkWell — ripple kotak meliputi ikon+teks dihilangkan.
    // opaque → seluruh area item (termasuk padding transparan) ikut
    // menerima tap; tanpa ini tap di tepi sering "tidak kena".
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gaya NavigationBar M3 (seperti ScanOrder): pil muncul fade +
            // melebar dari tengah di belakang ikon. Aksesibilitas: user
            // menonaktifkan animasi sistem → pil langsung settle.
            _navPill(
              context: context,
              selected: selected,
              child: AppBadgedIcon(
                icon: icon,
                count: badge,
                color: iconColor,
                badgeColor: badgeColor,
                badgePill: badgePill,
              ),
            ),
            const SizedBox(height: 1),
            Text(label, style: AppText.micro.copyWith(color: labelColor)),
          ],
        ),
      ),
    );
  }
}

class AppBadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final Color badgeColor;
  final bool badgePill;
  const AppBadgedIcon({
    required this.icon,
    required this.count,
    this.color,
    this.badgeColor = AppTheme.danger,
    this.badgePill = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    if (count <= 0) return Icon(icon, color: c);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color),
        Positioned(
          right: -8,
          top: -4,
          // Pil (mis. badge online): kapsul hijau tua; default: bulet
          // 16px tanpa border, baru memanjang kalau 2 digit ke atas.
          child: Container(
            width: badgePill || count >= 10 ? null : 16,
            height: 16,
            padding: EdgeInsets.symmetric(
              horizontal: badgePill ? 6 : (count < 10 ? 0 : 4),
            ),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: AppText.micro.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// Skeleton loading saat auth check — IDENTIK dengan halaman Pengguna Online
/// (AppBar gradient + avatar + nama + filter + list kartu) supaya transisi
/// Splash replika di sisi Flutter — muncul pada fase `auth.loading`
/// (cold start warmup). Bg + logo IDENTIK dengan launch_background native
/// (drawable-v21) supaya system splash → Flutter splash menyatu mulus,
/// tidak ada lagi layar hitam polos di tengah cold start.
class AppSplashReplica extends StatelessWidget {
  const AppSplashReplica();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF121212), // = launch_bg colors.xml
      child: Center(
        child: Image.asset(
          'assets/launch_logo.png',
          width: 120,
          height: 120,
          // Logo sudah sama persis dengan splash native — tanpa animasi
          // agar transisi tidak terlihat sebagai "ganti layar".
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// skeleton → konten TIDAK terlihat sama sekali (layout sama persis).
/// JANGAN taruh logo app di sini: 62% piksel logo itu putih — di atas
/// background gelap jadi kilatan putih besar yang makin terlihat saat
/// cold start (jeda lama → loading lebih lama).
class AppAuthSkeletonScreen extends StatelessWidget {
  const AppAuthSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, {double r = 6}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(r),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.bgScreen,
        surfaceTintColor: AppTheme.bgScreen,
        toolbarHeight: 72,
        leading: Center(child: box(24, 24, r: 12)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [box(100, 18), const SizedBox(height: 2), box(60, 12)],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                box(24, 24, r: 12),
                const SizedBox(width: 6),
                box(24, 24, r: 12),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    box(56, 12),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, __) => Container(
                        width: 64,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: box(0, 52, r: 12)),
                  const SizedBox(width: 12),
                  Expanded(child: box(0, 52, r: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                itemCount: 8,
                itemBuilder: (_, _) => const SkeletonCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
