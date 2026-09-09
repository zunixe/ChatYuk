import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/online_users_provider.dart';
import 'providers/points_provider.dart';
import 'providers/social_provider.dart';
import 'core/admin_gate.dart';
import 'providers/locale_provider.dart';
import 'providers/call_provider.dart';
import 'providers/nav_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/timeline_provider.dart';
import 'providers/story_provider.dart';
import 'services/chat_service.dart';
import 'services/boot_overlay.dart';
import 'main.dart';
import 'screens/entry_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/online_users_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/post_composer_screen.dart';
import 'widgets/anon_prompt_dialog.dart';
import 'widgets/call_banner.dart';
import 'widgets/skeleton_card.dart';
import 'screens/register_screen.dart';

class ChatYukApp extends StatefulWidget {
  const ChatYukApp({super.key});

  @override
  State<ChatYukApp> createState() => _ChatYukAppState();
}

class _ChatYukAppState extends State<ChatYukApp> {
  // Provider tab dibuat SEJAK APP START (saat skeleton auth masih tampil) —
  // disk cache (SQLite) menghangat paralel dengan auth init, sehingga begitu
  // skeleton hilang tab langsung menampilkan data, TANPA blink abu skeleton.
  final _roomProvider = RoomProvider();
  final _onlineUsersProvider = OnlineUsersProvider();

  @override
  void dispose() {
    _roomProvider.dispose();
    _onlineUsersProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
          create: (_) => PointsProvider()
            ..checkOnboarding()
            ..refreshEnabled()
            ..subscribeEnabled(),
        ),
        ChangeNotifierProvider(create: (_) => SocialProvider()),
        ChangeNotifierProvider(create: (_) => TimelineProvider()),
        // Refresh perdana story DITUNDA ke post-frame (di
        // OnlineUsersScreen.initState) — RPC story_tray + subscribe
        // realtime jangan berebut CPU/network dengan frame pertama.
        ChangeNotifierProvider(create: (_) => StoryProvider()),
        ...AdminGate.extraProviders,
        ChangeNotifierProvider.value(value: _roomProvider),
        ChangeNotifierProvider.value(value: _onlineUsersProvider),
        ChangeNotifierProvider(create: (_) => NavProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => localeProvider),
        ChangeNotifierProvider.value(value: CallProvider.instance),
      ],
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, _, theme, _) => MaterialApp(
          title: 'ChatYuk',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: theme.themeMode,
          navigatorKey: navigatorKey,
          navigatorObservers: [routeTracker],
          // Batasi skala font sistem supaya label kecil & baris padat tidak pecah,
          // tapi tetap menghormati preferensi aksesibilitas user.
          builder: (context, child) => WithForegroundTask(
            // Pelapor aktivitas GLOBAL: setiap sentuhan di layar APAPUN
            // (chat/room/profil/dialog/bottom-sheet) me-reset timer idle
            // dan mengembalikan idle→online. Dulu hanya body _MainNav yang
            // melapor, sehingga user yang lama di layar chat tercatat
            // 'idle' di server walau sedang aktif mengetik.
            // Listener hanya mengamati (tidak rebut gesture), murah:
            // tanpa idle→online cuma cancel+restart satu Timer.
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                try {
                  context.read<AuthProvider>().notifyActivity();
                } catch (_) {}
              },
              child: Stack(
                children: [
                  MediaQuery.withClampedTextScaling(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.3,
                    child: child ?? const SizedBox.shrink(),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: CallBanner(),
                  ),
                ],
              ),
            ),
          ),
          home: _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  DateTime? _lastRecoveryNav;
  Timer? _autoRetryTimer;
  int _autoRetryCount = 0;
  // Warm-up disk cache (SQLite) — ditunggu MAKSIMAL ini setelah auth siap.
  // Selama menunggu: layar polos bgScreen TANPA elemen abu (nol blink abu).
  Future<void>? _warmFuture;
  // Warm-gate: disk HANYA cache — tidak layak menahan skeleton lama.
  // Cap 2 detik (dulu 8s): kalau Keystore/SQLite lambat, konten tetap
  // tampil; disk load jalan di belakang dan merge saat selesai.
  static const _warmTimeout = Duration(seconds: 2);

  // Kalau DNS/network down lama, coba login ulang otomatis tiap 8 detik
  // (maks 3×) — begitu koneksi pulih, app masuk sendiri tanpa sentuhan user.
  void _maybeScheduleAutoRetry(AuthProvider auth) {
    if (auth.error == null) {
      _autoRetryCount = 0;
      _autoRetryTimer?.cancel();
      return;
    }
    if (_autoRetryCount >= 3 || (_autoRetryTimer?.isActive ?? false)) return;
    _autoRetryTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _autoRetryCount++;
      debugPrint('[AUTHGATE] auto retry #$_autoRetryCount');
      context.read<AuthProvider>().retry();
    });
  }

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        // Guard: cegah push ganda jika event ter-trigger berulang
        // (misal setSession dari deep link + event SDK).
        final now = DateTime.now();
        if (_lastRecoveryNav != null &&
            now.difference(_lastRecoveryNav!) < const Duration(seconds: 2)) {
          return;
        }
        _lastRecoveryNav = now;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Guard: pastikan Navigator masih valid sebelum push.
          final nav = navigatorKey.currentState;
          if (nav == null || !mounted) return;
          // Pakai push (bukan pushReplacement) — pushReplacement men-dispose
          // route aktif (misal LoginScreen dengan TextEditingController aktif)
          // saat transition → error "TextEditingController used after being disposed".
          nav.push(
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    // Watch ThemeProvider supaya seluruh tree rebuild saat mode gelap/terang
    // berubah — warna AppTheme diambil ulang di build().
    context.watch<ThemeProvider>();

    // Jadwalkan auto-retry saat layar error tampil.
    _maybeScheduleAutoRetry(auth);

    if (auth.loading) {
      // SPLASH REPLIKA: bg gelap + logo di tengah — identik dengan
      // launch_background native, jadi transisi system splash → Flutter
      // mulus TANPA layar hitam polos selama warmup (init engine,
      // Supabase, provider). Overlay native tetap bertugas anti-blink
      // snapshot HyperOS dan diangkat saat konten siap (_SwapMask).
      return const _SplashReplica();
    }

    if (auth.error != null) {
      // Jalur error jaringan: layar error first-frame → angkat overlay.
      WidgetsBinding.instance.addPostFrameCallback((_) => BootOverlay.hide());
      return Scaffold(
        backgroundColor: AppTheme.bgScreen,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: AppTheme.textSecondary, size: 48),
                SizedBox(height: 16),
                Text(s.msgServerError, style: AppText.title),
                SizedBox(height: 8),
                Text(
                  s.msgServerErrorHint,
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.read<AuthProvider>().retry(),
                  icon: const Icon(Icons.refresh),
                  label: Text(s.btnRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Non-anon (Google/email) yang login ulang tanpa melengkapi profil →
    // masuk ke app TAPI terkunci popup isian profil (bukan halaman
    // terpisah). Tetap muncul walau logout-login email sama sampai profil
    // diisi. Anon bebas (pakai AnonPromptDialog per fitur).
    final needsProfile = !auth.isAnonymous &&
        (auth.profile == null ||
            (auth.profile?.nickname.trim().isEmpty ?? true) ||
            !(auth.profile?.isRegistered ?? false));

    if (auth.profile == null && auth.isAnonymous) {
      // Jalur anon belum isi form: EntryScreen first-frame → angkat overlay.
      WidgetsBinding.instance.addPostFrameCallback((_) => BootOverlay.hide());
      return EntryScreen();
    }

    if (needsProfile) {
      return _ProfileGate(child: _MainNav());
    }

    // Warm-gate: tunggu disk cache tab pertama siap (maks 800ms) dengan
    // tampilan polos bgScreen — NOL warna abu — lalu konten langsung utuh.
    _warmFuture ??= Future.wait([
      context.read<RoomProvider>().warmFuture,
      context.read<OnlineUsersProvider>().warmup(),
    ]).timeout(_warmTimeout, onTimeout: () async => const <void>[]);
    return FutureBuilder<void>(
      future: _warmFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const _AuthSkeletonScreen();
        // Raster MainNav di belakang skeleton 1 frame — swap buffer GPU
        // (Skia half-present #b6b6b6) tidak pernah sampai ke layar.
        return _SwapMask(child: _MainNav());
      },
    );
  }
}

/// Poin transisi skeleton → konten. Frame PERTAMA _MainNav (raster paling
/// berat: IndexedStack + list) ditutup salinan tampilan skeleton; frame
/// kedua sudah smooth → angkat penutup. Tanpa ini Android menampilkan
/// buffer clear abu 2-4 frame saat GPU belum siap.
class _SwapMask extends StatefulWidget {
  final Widget child;
  const _SwapMask({required this.child});
  @override
  State<_SwapMask> createState() => _SwapMaskState();
}

/// Gerbang profil wajib isi: aplikasi tampil di belakang (pengguna online)
/// tapi TERTUTUP barrier — user tidak bisa interaksi apa pun sampai form
/// profil (nickname/gender/umur/negara/kota) disubmit. Setelah submit,
/// registerProfile → reloadProfile → isRegistered true → gate rebuild dan
/// popup hilang sendiri. Back button juga diblok (canPop: false).
class _ProfileGate extends StatelessWidget {
  final Widget child;
  const _ProfileGate({required this.child});
  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          child,
          const ModalBarrier(dismissible: false, color: Colors.black87),
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: screenH * 0.85,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RegisterScreen(mode: RegisterMode.profileOnly),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapMaskState extends State<_SwapMask> {
  bool _covered = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tahan ~200ms SETELAH frame pertama — Skia masih present 2-5 frame
      // buffer abu (#b6b6b6) saat raster MainNav berat; mask gelap
      // menutup semuanya, konten muncul saat benar-benar smooth.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _covered = false);
        // Konten asli sudah terlihat → angkat overlay splash logo native
        // (fade 250ms). Ini satu-satunya titik hide untuk jalur login.
        BootOverlay.hide();
      });
    });
  }
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Penutup sementara — samakan tampilan dengan warm-gate di atasnya.
        if (_covered)
          const Positioned.fill(child: _AuthSkeletonScreen()),
      ],
    );
  }
}

class _MainNav extends StatefulWidget {
  const _MainNav();

  @override
  State<_MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<_MainNav> with WidgetsBindingObserver {
  // Provider tab sudah dibuat di root (_ChatYukAppState) sejak app start —
  // di sini cukup consume. Dulu: dibuat DI SINI (setelah skeleton auth
  // hilang) → disk cache baru menghangat saat halaman sudah tampil →
  // blink abu skeleton beberapa ratus ms.

  // Instance halaman dibuat ulang HANYA saat mode terang/gelap berubah —
  // bukan tiap tab switch (menghindari rebuild berlebihan).
  List<Widget>? _pages;
  bool? _pagesDark; // tema saat _pages terakhir dibuat

  // Tab yang pernah dikunjungi — halaman hanya dibangun saat pertama kali
  // dikunjungi (lazy IndexedStack). Tanpa ini, 4 halaman dibangun sekaligus
  // di frame pertama setelah skeleton → blink abu terang 1-2 frame.
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = context.read<AuthProvider>();
    auth.goOnline();
    auth.resetIdleTimer();
    // Hanya user terdaftar yang menerima panggilan masuk (anon: tidak).
    CallProvider.instance.ensureListening(
      registered: auth.profile?.isRegistered ?? false,
    );
    final uid = auth.uid;
    if (uid != null) {
      context.read<ChatProvider>().loadBlockedUids(uid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused) {
      // App di-background/ditutup → set idle, bukan offline.
      // User tetap tampil di menu online sebagai idle, baru hilang saat logout.
      auth.goIdle();
    } else if (state == AppLifecycleState.resumed) {
      // Re-sync invisible dulu (multi-device) supaya device kedua tidak
      // menimpa balik status admin yang sudah di-toggle invisible.
      auth.resyncInvisible();
      auth.goOnline();
      // Sinkron profil lintas-device: selama sleep, event realtime profil
      // (ganti avatar dsb.) bisa terlewat → refresh dari server.
      auth.refreshProfile();
    }
  }

  /// Pindah tab utama (juga dipanggil NavProvider dari screen lain).
  /// Anon diblokir dari tab timeline — popup saja, tab tidak pindah.
  void _onNavTap(int i) {
    if (i == 2) {
      final auth = context.read<AuthProvider>();
      if (!(auth.profile?.isRegistered ?? false)) {
        showAnonPromptDialog(context);
        return;
      }
    }
    context.read<NavProvider>().goTo(i);
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<NavProvider>().tab;
    // Rebuild seluruh tab saat mode terang/gelap berubah.
    final dark = context.watch<ThemeProvider>().isDark;
    if (_pages == null || _pagesDark != dark) {
      _pages = [
        OnlineUsersScreen(),
        ChatsScreen(),
        TimelineScreen(),
        ProfileScreen(),
      ];
      _pagesDark = dark;
    }
    if (!_visitedTabs.contains(tab)) _visitedTabs.add(tab);
    final auth = context.watch<AuthProvider>();
    final s = context.read<LocaleProvider>().s;
    // Soft gate anon: banner tipis di atas konten saat fitur anon OFF.
    // Read tetap jalan (anon masih browsing), tulis dicegat di composer.
    final anonBanner = auth.anonBlocked;
    return Scaffold(
        body: Column(
          children: [
            if (anonBanner)
              Material(
                color: AppTheme.primary.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () => showAnonPromptDialog(context),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.anonGateBanner,
                              style: AppText.caption
                                  .copyWith(color: AppTheme.textPrimary),
                            ),
                          ),
                          Text(
                            s.anonGateBannerCta,
                            style: AppText.caption.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => context.read<AuthProvider>().notifyActivity(),
                onPanDown: (_) =>
                    context.read<AuthProvider>().notifyActivity(),
                child: IndexedStack(
                  index: tab,
                  children: [
                    for (var i = 0; i < _pages!.length; i++)
                      _visitedTabs.contains(i)
                          ? _pages![i]
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: SizedBox(
          width: 52,
          height: 52,
          child: FloatingActionButton(
            onPressed: () {
              final auth = context.read<AuthProvider>();
              // Anon (belum isi email) — samakan dengan timeline: arahkan
              // ke profil, jangan buka composer.
              if (!(auth.profile?.isRegistered ?? false)) {
                showAnonPromptDialog(context);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PostComposerScreen()),
              );
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryDark,
                    AppTheme.primary,
                    AppTheme.accent,
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _BottomNav(currentIndex: tab, onTap: _onNavTap),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final uid = context.select<AuthProvider, String?>((a) => a.uid);
    final chat = context.read<ChatProvider>();
    // Badge hijau = jumlah user berstatus online (di luar diri sendiri
    // & yang diblokir) — cermin filter list tab Online tanpa filter
    // negara/gender/search.
    final onlineCount = context
        .select<OnlineUsersProvider, int>(
          (p) => p.users
              .where((u) =>
                  u.uid != uid &&
                  !chat.isBlocked(u.uid) &&
                  u.status == 'online')
              .length,
        );

    return StreamBuilder<List<PrivateChatInfo>>(
      stream: uid != null ? chat.getMyPrivateChats(uid) : const Stream.empty(),
      builder: (_, snap) {
        final totalUnread = (snap.data ?? []).fold<int>(0, (sum, c) {
          return sum + ((c.unreadCounts[uid] ?? 0));
        });
        return BottomAppBar(
          color: AppTheme.bgCard,
          shape: const CircularNotchedRectangle(),
          notchMargin: 6,
          padding: EdgeInsets.zero,
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.group_rounded, s.navOnline, 0,
                  badge: onlineCount,
                  badgeColor: AppTheme.onlineDark,
                  badgePill: true),
              _navItem(Icons.chat_bubble, s.navChats, 1,
                  badge: totalUnread, badgePill: true),
              const SizedBox(width: 48),
              _navItem(Icons.dynamic_feed_rounded, s.navTimeline, 2),
              _navItem(Icons.person, s.navProfile, 3),
            ],
          ),
        );
      },
    );
  }

  Widget _navItem(IconData icon, String label, int index,
      {int badge = 0,
      Color badgeColor = AppTheme.danger,
      bool badgePill = false}) {
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
            // melebar dari tengah di belakang ikon, kurva emphasized M3
            // Cubic(0.2, 0, 0, 1) — bukan crossfade warna. Ukuran 68x30
            // gepeng proporsional (radius = tinggi/2 = 15).
            // Bulge sin() bikin pil sedikit mengembang di tengah animasi
            // (efek melebar smooth), ikon ikut pop 0.85→1.
            // Dua tahap: opacity full dalam 25% pertama (~125ms) supaya
            // tap terasa respon instan; lebar pakai easeOutExpo — ngacir
            // di awal lalu melambat lembut di akhir (500ms). Collapse
            // tetap 250ms emphasized biar responsif.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: selected ? 0 : 1, end: selected ? 1 : 0),
              duration: Duration(milliseconds: selected ? 500 : 250),
              curve: selected
                  ? Curves.linear
                  : const Cubic(0.2, 0.0, 0.0, 1.0),
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
                          color:
                              AppTheme.primary.withValues(alpha: 0.12),
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
              child: _BadgedIcon(
                  icon: icon,
                  count: badge,
                  color: iconColor,
                  badgeColor: badgeColor,
                  badgePill: badgePill),
            ),
            const SizedBox(height: 1),
            Text(label, style: AppText.micro.copyWith(color: labelColor)),
          ],
        ),
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final Color badgeColor;
  final bool badgePill;
  const _BadgedIcon(
      {required this.icon,
      required this.count,
      this.color,
      this.badgeColor = AppTheme.danger,
      this.badgePill = false});

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
                horizontal: badgePill ? 6 : (count < 10 ? 0 : 4)),
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
class _SplashReplica extends StatelessWidget {
  const _SplashReplica();

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
class _AuthSkeletonScreen extends StatelessWidget {
  const _AuthSkeletonScreen();

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
          children: [
            box(100, 18),
            const SizedBox(height: 2),
            box(60, 12),
          ],
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
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 10),
                      itemBuilder: (_, __) => Container(
                        width: 64,
                        height: 96,
                        decoration: BoxDecoration(
                          color:
                              AppTheme.primary.withValues(alpha: 0.10),
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
