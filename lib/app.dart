import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/theme.dart';
import 'providers/riverpod/auth_provider.dart';
import 'providers/riverpod/room_provider.dart';
import 'providers/riverpod/chat_provider.dart';
import 'services/device_info_service.dart';
import 'providers/riverpod/message_reaction_provider.dart';
import 'providers/riverpod/online_users_provider.dart';
import 'providers/riverpod/points_provider.dart';
import 'providers/riverpod/social_provider.dart';
import 'core/admin_gate.dart';
import 'providers/locale_provider.dart';
import 'core/cache/message_cache.dart';
import 'core/cache/photo_cache.dart';
import 'core/cache/post_photo_cache.dart';
import 'core/media/image_cache_hygiene.dart';
import 'models/user_model.dart';
import 'providers/riverpod/connectivity_provider.dart';
import 'providers/riverpod/call_provider.dart';
import 'providers/riverpod/nav_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/riverpod/timeline_provider.dart';
import 'providers/riverpod/story_provider.dart';
import 'providers/riverpod/update_provider.dart';
import 'services/chat_service.dart';
import 'services/boot_overlay.dart';
import 'core/perf/perf_probe.dart';
import 'main.dart';
import 'screens/entry_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/online_users_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/post_composer_screen.dart';
import 'widgets/anon_prompt_dialog.dart';
import 'widgets/offline_banner.dart';
import 'widgets/call_banner.dart';
import 'widgets/skeleton_card.dart';
import 'screens/register_screen.dart';
import 'utils.dart';

class ChatYukApp extends StatefulWidget {
  const ChatYukApp({super.key});

  @override
  State<ChatYukApp> createState() => _ChatYukAppState();
}

class _ChatYukAppState extends State<ChatYukApp> {
  // Provider tab dibuat SEJAK APP START (saat skeleton auth masih tampil) —
  // disk cache (SQLite) menghangat paralel dengan auth init, sehingga begitu
  // skeleton hilang tab langsung menampilkan data, TANPA blink abu skeleton.

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Refresh perdana story DITUNDA ke post-frame (di
        // OnlineUsersScreen.initState) — RPC story_tray + subscribe
        // realtime jangan berebut CPU/network dengan frame pertama.
        ...AdminGate.extraProviders,
        // NavProvider: MIGRASI ke Riverpod (navProvider) — dihapus dari sini.
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => localeProvider),
        // ConnectivityProvider: MIGRASI ke Riverpod (connectivityProvider).
      ],
      // Selector hanya pada appFontFamily → MaterialApp hanya rebuild saat
      // font global berubah (bukan tiap notifikasi AuthNotifier).
      child: _FontGate(
        builder: (context) =>
            // Rebuild subtree saat ukuran font chat berubah (slider user) —
            // bubble chat langsung menyesuaikan tanpa restart navigasi.
            ValueListenableBuilder<double>(
              valueListenable: ChatTextScale.notifier,
              builder: (context, _, __) => Consumer2<LocaleProvider, ThemeProvider>(
                builder: (context, _, theme, _) => MaterialApp(
                  title: 'ChatYuk',
                  debugShowCheckedModeBanner: false,
                  // Tidak pakai `key` agar navigasi tidak ter-reset saat font berubah;
                  // rebuild + getter AppTheme.*Theme (dibangun ulang tiap build)
                  // sudah cukup mengganti ThemeData ke font terbaru.
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
                          ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).notifyActivity();
                        } catch (_) {}
                      },
                      child: OfflineBanner(
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
                  ),
                  home: _AuthGate(),
                ),
              ),
            ),
      ),
    );
  }
}

/// Keputusan layar root gate (murni, teruji).
/// URUTAN PENTING: `signingOut` di ATAS `loading` — signOut() men-set
/// keduanya, dan tanpa urutan ini gate menampilkan splash sekejap lalu
/// EntryScreen (satu halaman berkedip saat logout).
enum GateScreen { splash, error, entry, profileGate, banned, main }

GateScreen decideGateScreen({
  required bool loading,
  required bool hasError,
  required bool signingOut,
  required bool isAnonymous,
  required bool dummySessionActive,
  required bool isSignedIn,
  required bool hasProfile,
  required bool needsProfile,
  required bool banned,
  bool needsOnboarding = false,
}) {
  if (signingOut) return GateScreen.entry;
  if (loading) return GateScreen.splash;
  if (hasError) return GateScreen.error;
  if (needsProfile) {
    return isSignedIn ? GateScreen.profileGate : GateScreen.entry;
  }
  // Profil dibuat otomatis oleh trigger (nickname placeholder 'AnonXXXX',
  // `needs_onboarding=true`) dan user BELUM memilih nama → EntryScreen.
  // BERLAKU untuk anon MAUPUN yang sudah registered (email/OTP): kalau user
  // menutup app sebelum menyelesaikan langkah isi-nama, flag ini mencegah
  // mereka berkeliaran dengan nickname "AnonXXXX" selamanya.
  // Sesi dummy (admin menyamar) dikecualikan — bukan user sungguhan.
  if (!dummySessionActive && (!hasProfile || needsOnboarding)) {
    return GateScreen.entry;
  }
  if (isAnonymous && !dummySessionActive && !hasProfile) {
    return GateScreen.entry;
  }
  if (banned) return GateScreen.banned;
  return GateScreen.main;
}

class _FontGate extends ConsumerWidget {
  final Widget Function(BuildContext context) builder;
  const _FontGate({required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider.select((a) => a.appFontFamily));
    return builder(context);
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  ProviderSubscription<AuthData>? _authListenSub;
  DateTime? _lastRecoveryNav;
  Timer? _autoRetryTimer;
  int _autoRetryCount = 0;
  // Warm-up disk cache (SQLite) — ditunggu MAKSIMAL ini setelah auth siap.
  // Selama menunggu: layar polos bgScreen TANPA elemen abu (nol blink abu).
  Future<void>? _warmFuture;
  // Warm-gate: disk HANYA cache — tidak layak menahan skeleton lama.
  // Turun ke 400ms (dulu 2s): konten tampil cepat; disk/server menyusul di
  // belakang & merge (list chat pakai peekRawList sinkron setelah siap).
  static const _warmTimeout = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    // Auto-retry error jaringan lewat LISTENER (bukan build): begitu auth
    // masuk state error, jadwalkan login ulang tiap 8 dtk (maks 3×). Tidak
    // ada side-effect (Timer/retry) di build → build murni render.
    _authListenSub = ProviderScope.containerOf(context, listen: false).listen<AuthData>(
      authProvider,
      (prev, next) {
        if (prev?.error != next.error) _onAuthChanged();
      },
    );
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
    }, onError: (e) => dlog('[GATE] auth stream error: $e'));
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (auth.error == null) {
      _autoRetryCount = 0;
      _autoRetryTimer?.cancel();
      return;
    }
    if (_autoRetryCount >= 3 || (_autoRetryTimer?.isActive ?? false)) return;
    _autoRetryTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _autoRetryCount++;
      dlog('[AUTHGATE] auto retry #$_autoRetryCount');
      ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).retry();
    });
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _authSub?.cancel();
    _authListenSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // select field spesifik — hindari watch penuh AuthNotifier yang
    // me-rebuild seluruh gate pada tiap notifyListeners (presence, poin).
    final loading = ref.watch(authProvider.select((a) => a.loading));
    final error = ref.watch(authProvider.select((a) => a.error));
    final isAnonymous = ref.watch(
      authProvider.select((a) => a.isAnonymous),
    );
    final dummySessionActive = ref.watch(
      authProvider.select((a) => a.dummySessionActive),
    );
    final profile = ref.watch(authProvider.select((a) => a.profile));
    final signingOut = ref.watch(
      authProvider.select((a) => a.signingOut),
    );
    final isSignedIn = ref.watch(
      authProvider.select((a) => a.isSignedIn),
    );
    final s = context.watch<LocaleProvider>().s;
    // Watch ThemeProvider supaya seluruh tree rebuild saat mode gelap/terang
    // berubah — warna AppTheme diambil ulang di build().
    context.watch<ThemeProvider>();

    final p0 = profile;
    final isAdminGate0 = ref.watch(
      authProvider.select((a) => a.isRealAdmin),
    );
    final gate = decideGateScreen(
      loading: loading,
      hasError: error != null,
      signingOut: signingOut,
      isAnonymous: isAnonymous,
      dummySessionActive: dummySessionActive,
      isSignedIn: isSignedIn,
      hasProfile: p0 != null,
      needsOnboarding: p0?.needsOnboarding ?? false,
      needsProfile: !isAnonymous &&
          !dummySessionActive &&
          (p0 == null ||
              p0.nickname.trim().isEmpty ||
              !p0.isRegistered ||
              // Profil dibuat trigger tapi user belum selesaikan isi nickname.
              p0.needsOnboarding),
      banned: p0 != null &&
          !isAdminGate0 &&
          isBannedNickname(p0.nickname),
    );
    if (gate == GateScreen.entry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => BootOverlay.hide());
      return const EntryScreen();
    }

    if (loading) {
      // SPLASH REPLIKA: bg gelap + logo di tengah — identik dengan
      // launch_background native, jadi transisi system splash → Flutter
      // mulus TANPA layar hitam polos selama warmup (init engine,
      // Supabase, provider). Overlay native tetap bertugas anti-blink
      // snapshot HyperOS dan diangkat saat konten siap (_SwapMask).
      return const _SplashReplica();
    }

    if (error != null) {
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
                  onPressed: () => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).retry(),
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
    // diisi. Anon bebas (pakai AnonPromptDialog per fitur). Sesi dummy
    // admin juga bebas — bukan user sungguhan.
    //
    // LOGOUT CLEAN (jangan dihapus): saat proses keluar, LANGSUNG render
    // EntryScreen. Tanpa cabang ini, `signOut()` membuat `profile=null`
    // sementara `dummySessionActive` sudah false → `needsProfile` jadi true
    // → `_ProfileGate(child: _MainNav())` ter-render sekejap (flash halaman
    // utama + popup form) sebelum EntryScreen. Khusus sesi dummy, karena
    // dummy punya email (isAnonymous=false) sehingga tidak tertangkap
    // cabang `profile == null && isAnonymous` di bawah.
    if (gate == GateScreen.banned && profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => BootOverlay.hide());
      return Scaffold(
        backgroundColor: AppTheme.bgScreen,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, color: AppTheme.textSecondary, size: 48),
                SizedBox(height: 16),
                Text(s.errNicknameBanned, style: AppText.title),
                SizedBox(height: 8),
                Text(
                  profile.nickname,
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).signOut(),
                  icon: const Icon(Icons.logout),
                  label: Text(s.btnLogout),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Sesi KOSONG (sudah keluar / belum masuk) WAJIB EntryScreen — jangan
    // menu utama. Tanpa cabang ini, needsProfile=true untuk profil null
    // melempar sesi kosong ke _ProfileGate(_MainNav): klik logout malah
    // mendarat di menu utama terkunci popup profil (laporan Xiaomi).
    if (gate == GateScreen.profileGate) {
      return _ProfileGate(child: _MainNav());
    }

    // Warm-gate: tunggu SEKADARNYA saja (cap 400ms) lalu tampil konten.
    // Disk/server menyusul & merge di belakang — jangan tahan splash demi
    // cache. Preload list chat ke MEMORI tetap diikutkan supaya centang-2
    // terisi sejak frame pertama (SQLite lokal = cepat); kalau lambat,
    // timeout → konten tetap tampil (skeleton tidak menahan lama).
    final warmUid = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid;
    _warmFuture ??= Future.wait([
      ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).warmFuture,
      ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).warmup(),
      if (warmUid != null) MessageCache.instance.preloadRawList(warmUid),
      // Preload semua cache bintang ke memori → bias tampil instan di cold
      // start tanpa menunggu disk per-chat (anti-glich).
      ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).preloadAllStarred(),
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
          // Blur latar belakang (list tetap terlihat samar, kartu tetap tajam).
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ModalBarrier(
                dismissible: false,
                color: Colors.black.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                // Angkat popup saat keyboard naik (pengganti resize Scaffold).
                // Horizontal 24 = sama dengan entry screen supaya lebar kartu
                // identik (layar − 48).
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: screenH * 0.85),
                  // Bayangan luar supaya kartu terlihat mengambang.
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: RegisterScreen(mode: RegisterMode.profileOnly),
                    ),
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
        if (_covered) const Positioned.fill(child: _AuthSkeletonScreen()),
      ],
    );
  }
}

class _MainNav extends ConsumerStatefulWidget {
  const _MainNav();

  @override
  ConsumerState<_MainNav> createState() => _MainNavState();
}

/// Menahan (freeze) subtree tab yang TIDAK aktif agar tidak ikut rebuild
/// saat parent (_MainNav / IndexedStack) rebuild.
///
/// Masalah: IndexedStack membangun SEMUA tab yang pernah dikunjungi. Setiap
/// `_MainNav` rebuild (badge/anonymous/select berubah) → seluruh tab ikut
/// di-build ulang, termasuk tab Online yang berisi puluhan `UserAvatar` —
/// inilah yang membuat buka-tutup private chat makin lama makin berat
/// ([AVATAR] 100+ resolve/detik saat storm transisi).
///
/// Solusi: simpan instance `child` TERAKHIR saat tab ini tidak aktif; bila
/// parent memberi `child` baru sementara `active == false`, kita abaikan
/// child baru itu (pakai yang lama) sehingga subtree tidak di-build ulang.
/// Saat tab kembali aktif, child terbaru langsung dipakai.
class _TabFreeze extends StatefulWidget {
  final bool active;
  final Widget child;
  const _TabFreeze({required this.active, required this.child});

  @override
  State<_TabFreeze> createState() => _TabFreezeState();
}

class _TabFreezeState extends State<_TabFreeze> {
  late Widget _frozenChild = widget.child;

  @override
  void didUpdateWidget(covariant _TabFreeze old) {
    super.didUpdateWidget(old);
    // Update child (build ulang) HANYA saat tab aktif, atau tepat saat baru
    // berubah aktif→non-aktif (tangkap keadaan terakhir). Saat non-aktif
    // stabil, pertahankan instance lama → subtree berat tak di-build ulang.
    if (widget.active || old.active) {
      _frozenChild = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: widget.active, child: _frozenChild);
}

class _MainNavState extends ConsumerState<_MainNav>
    with WidgetsBindingObserver {
  // Kapan app terakhir di-background — untuk memutuskan trim cache memori
  // saat resume (hanya kalau background CUKUP LAMA, biar chat tetap instan
  // saat app sekadar sebentar pindah app).
  DateTime? _pausedAt;
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
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    auth.goOnline();
    auth.resetIdleTimer();
    // Follow/unfollow → invalidate cache followee di TimelineProvider
    // (R4: TTL cache supaya switch tab tidak mem-fetch follows berulang,
    // tapi tetap akurat saat graf follow berubah).
    ref.read(socialProvider.notifier).onFollowGraphChanged = () {
      ref.read(timelineProvider.notifier).invalidateFollowedIds();
    };
    // Hanya user terdaftar yang menerima panggilan masuk (anon: tidak).
    ref.read(callProvider.notifier).ensureListening(
      registered: auth.profile?.isRegistered ?? false,
    );
    final uid = auth.uid;
    if (uid != null) {
      ref.read(chatProvider.notifier).loadBlockedUids(uid);
    }
    // Logout paksa (sesi kedaluwarsa) tidak lewat tombol logout → pasang
    // hook: tutup stream chat & channel milik user lama.
    auth.onSignedOut = () {
      try {
        ref.read(chatProvider.notifier).reset();
      } catch (_) {}
    };
    // Prewarm timeline di background (3s setelah frame pertama — lewat
    // warm-up utama auth/rooms/online): saat user tap tab Timeline feed
    // sudah terisi, tidak ada spinner RPC list_posts pertama.
    Timer(const Duration(seconds: 3), () {
      // Gerbang Timeline absolut: anon tidak bisa lihat feed → jangan prewarm
      // (RPC list_posts pasti raise ANON_DISABLED, buang kuota + isi error).
      final anonBlocked =
          mounted && ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).anonTimelineBlocked;
      if (mounted && !anonBlocked) ref.read(timelineProvider.notifier).prewarm();
      // Prewarm juga daftar grup (tab Grup) — klik tab instant.
      if (mounted) ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).loadMyGroups(refresh: true);
    });
    // Gaya Telegram: halaman tab lain dibangun diam-diam SAAT IDLE (bukan
    // saat diklik) supaya tap pertama terasa instan. Bertahap 1 tab per
    // 800ms supaya tidak ada lonjakan frame — tab aktif sudah ter-render
    // penuh sebelum ini jalan.
    _scheduleTabPrewarm();
  }

  /// Bangun halaman tab lain di belakang layar, satu per satu saat idle.
  ///
  /// TIMING (diukur 2026-09-30, Xiaomi 24129PN74G): tiap `setState` di sini
  /// membangun SATU halaman tab penuh secara sinkron dalam frame itu (build
  /// berat = 1 jank frame). Dulu mulai 1200ms + interval 800ms → tab3 baru
  /// hangat di 2800ms, padahal UI sudah interaktif ~1300ms. Jendela 1300-2800ms
  /// itulah sumber jank terukur saat tap: tab belum dibangun → build halaman
  /// jatuh di frame tap (tap@1.5-1.8s = 14-22ms/jank; tap tab hangat = 0 jank).
  ///
  /// UPDATE 2026-10-06 (keluhan "menu bawah lag diklik di awal, setelah
  /// dipencet-pencet baru cepat"): prewarm bertahap 250ms MASIH menyisakan
  /// jendela di mana tab belum siap saat user tap cepat (mis. tap Chat <300ms
  /// atau Profil <800ms setelah app tampil). Tiap tab = 1 jank frame build.
  /// Dipercepat: mulai 0ms (langsung setelah frame pertama) + interval 1 frame
  /// (~16ms) → ketiga tab hangat ~50ms, SEBELUM jari user sempat tap. Biaya: 3
  /// jank frame kecil di awal idle (tak terasa, layar baru tampil) — jauh lebih
  /// baik daripada jank di frame tap. Jangan perlambat tanpa ukur ulang
  /// (metrik `tab{N} tap→frame` + `janky(build)`).
  void _scheduleTabPrewarm() {
    const order = [1, 2, 3]; // Pesan/Chat, Timeline, Profil
    var step = 0;
    void next() {
      if (!mounted || step >= order.length) return;
      final i = order[step++];
      if (_visitedTabs.contains(i)) {
        next();
        return;
      }
      if (mounted) setState(() => _visitedTabs.add(i));
      Future<void>.delayed(const Duration(milliseconds: 16), next);
    }

    Future<void>.delayed(const Duration(milliseconds: 32), next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      // Ringkasan probe (p50/p90/max) dicetak saat app di-background — satu
      // blok per sesi, tanpa perlu memanggil manual. No-op saat probe off.
      PerfProbe.report('sesi berakhir (app di-background)');
      // App di-background → set idle, bukan offline.
      // User tetap tampil di menu online sebagai idle.
      auth.goIdle();
      // Lepaskan cache bitmap (native heap) saat background: OS gencar
      // menuntut RAM dari app background, dan bitmap besar di-hold percuma
      // (layar tidak terlihat). Saat resume, gambar yang tampil di-decode
      // ulang dari disk cache (murah). Ini yang membuat RSS turun drastis
      // & mencegah app dibunuh OS saat user buka app lain.
      try {
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
      } catch (_) {}
    } else if (state == AppLifecycleState.detached) {
      // App di-kill/force-close → set idle (offline otomatis setelah threshold).
      auth.goIdle();
    } else if (state == AppLifecycleState.resumed) {
      // PERF: kalau app lama di-background (>60 dtk), buang cache pesan
      // in-memory (tiap chat menahan pesan + base64 foto) — cegah akumulasi
      // yang bikin "ngetik ngelag setelah dipakai lama". Background sebentar
      // TIDAK di-trim supaya chat tetap instan.
      final pausedFor = _pausedAt == null
          ? null
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (pausedFor != null && pausedFor.inSeconds >= 60) {
        // Background lama → buang SEMUA cache RAM (pesan + foto) + bitmap.
        try {
          MessageCache.instance.trimMemCache();
        } catch (_) {}
        try {
          PhotoCache.instance.trimMemCache();
        } catch (_) {}
        try {
          PostPhotoCache.instance.trimMemCache();
        } catch (_) {}
        try {
          ImageCacheHygiene.clearAll();
        } catch (_) {}
      } else if (pausedFor != null && pausedFor.inSeconds >= 15) {
        // Background sedang (15-60 dtk) → trim RAM foto saja (paling besar,
        // paling murah dimuat ulang). Pesan tetap di RAM supaya chat instan.
        try {
          PhotoCache.instance.trimMemCache();
        } catch (_) {}
        try {
          PostPhotoCache.instance.trimMemCache();
        } catch (_) {}
      }
      // PERF: hangatkan koneksi HTTP Supabase DULUAN (fire-and-forget).
      // Setelah idle, koneksi keep-alive basi → request pertama user
      // menggantung ~13 detik (terukur). Warm-up ini membuang koneksi basi
      // lebih awal supaya aksi user terasa ringan begitu kembali.
      unawaited(warmupRpcConnection());
      // Re-sync invisible dulu (multi-device) supaya device kedua tidak
      // menimpa balik status admin yang sudah di-toggle invisible.
      auth.resyncInvisible();
      auth.goOnline();
      // Revalidasi koneksi tiap resume — cek awal connectivity_plus bisa
      // menangkap `none` sesaat lalu tak ada event lagi → banner offline
      // nyangkut + kirim selalu masuk antrean padahal internet ada.
      try {
        ref.read(connectivityProvider.notifier).revalidate();
      } catch (_) {}
      // Catat ulang Device ID tiap resume — TIDAK tergantung guard goOnline
      // (invisible/banned) supaya device selalu tercatat di admin. Fire-and-
      // forget; idempoten (upsert).
      if (auth.uid != null) {
        safeUnawaited(DeviceInfoService.instance.syncToServer());
      }
      // Sinkron profil lintas-device: selama sleep, event realtime profil
      // (ganti avatar dsb.) bisa terlewat → refresh dari server.
      auth.refreshProfile();
      // Tap notifikasi "panggilan aktif" (foreground service) membuka app
      // kembali tanpa payload — kalau ada call berjalan & layar call belum
      // tampil, buka langsung (post-frame agar navigator siap).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ensureCallScreenRoute(navigatorKey.currentState);
      });
      // Pasang ULANG notif "panggilan aktif" bila sesi masih hidup tapi
      // notifnya hilang (app di-swipe/OS restart service saat keluar) —
      // tanpa ini tap-untuk-kembali-ke-panggilan lenyap padahal call jalan.
      unawaited(ref.read(callProvider.notifier).ensureActiveNotif());
      // Update: cek ulang saat kembali foreground — popup hanya muncul
      // bila ada versi baru yang belum ditangani; download yang sudah
      // dimulai user lanjut diam-diam di background (tidak di-nag ulang).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(updateProvider.notifier).presentIfNeeded(navigatorKey);
        ref.read(updateProvider.notifier).check(navigatorKey: navigatorKey);
      });
    }
  }

  /// PERF (memory pressure): OS memberi tahu memori menipis. Ini satu-satunya
  /// sinyal LANGSUNG dari sistem (beda dari lifecycle paused/resumed) �?"
  /// tanpa handler ini cache hanya dibersihkan saat app di-background >=60 dtk,
  /// jadi user yang memakai HP nonstop tidak pernah di-trim  memori naik
  /// terus  GC storm  "ngetik ngelag setelah dipakai lama".
  ///
  /// Yang dibuang: SEMUA cache RAM (disk tetap)  pesan/foto dibaca ulang dari
  /// SQLite/AES saat dibuka lagi (murah). TIDAK menyentuh data yang benar-benar
  /// dibutuhkan sekarang (list pesan aktif tetap dirender dari stream).
  @override
  void didHaveMemoryPressure() {
    try {
      MessageCache.instance.trimMemCache();
    } catch (_) {}
    try {
      PhotoCache.instance.trimMemCache();
    } catch (_) {}
    try {
      PostPhotoCache.instance.trimMemCache();
    } catch (_) {}
    try {
      ImageCacheHygiene.clearAll();
    } catch (_) {}
  }

  /// Pindah tab utama (juga dipanggil NavProvider dari screen lain).
  /// Anon diblokir dari tab timeline — popup saja, tab tidak pindah.
  void _onNavTap(int i) {
    if (i == 2) {
      final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
      if (!(auth.profile?.isRegistered ?? false)) {
        showAnonPromptDialog(context);
        return;
      }
    }
    PerfProbe.tabStart(i);
    ref.read(navProvider.notifier).goTo(i);
    if (PerfProbe.measuring) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PerfProbe.tabTrace(i);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(navProvider);
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
    PerfProbe.buildCount('MainNav');
    // Ukur "tap → frame pertama tab ini ter-render" (probe off = no-op).
    // measuring (bukan enabled) supaya ikut terukur di build RILIS+PERF_PROBE.
    if (PerfProbe.measuring) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PerfProbe.tabEnd(tab);
      });
    }
    // Rebuild _MainNav HANYA saat nilai yang benar-benar dipakai berubah —
    // BUKAN setiap AuthNotifier.notifyListeners (presence/idle/ping tiap
    // beberapa detik). Sebelumnya `watch<AuthNotifier>()` membuat seluruh
    // IndexedStack (termasuk feed Timeline) di-layout ulang terus-menerus →
    // pindah tab terasa berat. `select` granular = nol rebuild saat notify
    // yang tidak relevan.
    final anonBanner = ref.watch(
      authProvider.select((a) => a.anonBlocked),
    );
    final isRealAdmin = ref.watch(
      authProvider.select((a) => a.isRealAdmin),
    );
    final dummySession = ref.watch(
      authProvider.select((a) => a.dummySessionActive),
    );
    final s = context.read<LocaleProvider>().s;
    // Tombol Admin Panel melayang (admin sungguhan saja) — HANYA di tab
    // Online (index 0), supaya tidak menutupi konten di tab lain.
    final showAdminFab = AdminGate.panelBuilder != null &&
        isRealAdmin &&
        !dummySession &&
        tab == 0;
    // Di tab Online saat kotak Disembunyikan ada isi: FAB mepet di atas
    // header kotak yang ketutup (~51px + spasi dikit) supaya tidak
    // bertumpuk dengan card-nya tapi juga tidak mengambang kejauhan.
    // `select` int → rebuild _MainNav hanya saat jumlahnya berubah, bukan
    // tiap heartbeat presence.
    final hiddenCount = ref.watch(
      onlineUsersProvider.select((p) => p.hiddenCount),
    );
    final adminFabBottom = (tab == 0 && hiddenCount > 0) ? 64.0 : 14.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
          // Banner anon: cegah tertutup status bar pada edge-to-edge
          // Android 15. Banner jadi elemen teratas → ambil inset atas
          // sendiri; AppBar tab di bawahnya di-nol-kan inset atasnya
          // (removeTop) supaya tidak dobel.
          if (anonBanner)
            SafeArea(
              bottom: false,
              child: Material(
                color: AppTheme.primary.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () => showAnonPromptDialog(context),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.anonGateBanner,
                              style: AppText.caption.copyWith(
                                color: AppTheme.textPrimary,
                              ),
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
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).notifyActivity(),
              onPanDown: (_) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).notifyActivity(),
              // Saat banner menempel di atas, ia sudah mengambil inset atas
              // → nol-kan inset atas AppBar tab supaya tidak dobel.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: anonBanner,
                child: IndexedStack(
                  index: tab,
                  children: [
                    for (var i = 0; i < _pages!.length; i++)
                      _visitedTabs.contains(i)
                          // _TabFreeze: tab non-aktif TIDAK ikut rebuild saat
                          // _MainNav rebuild (cegah storm avatar/list di
                          // belakang → buka-tutup chat tak makin berat).
                          ? _TabFreeze(active: tab == i, child: _pages![i])
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
          // Tombol melayang Admin Panel — KIRI BAWAH, di atas menu nav.
          // Admin sungguhan saja (bukan sesi dummy). Ikon saja, tanpa bulatan.
          if (showAdminFab)
            Positioned(
              left: 14,
              bottom: adminFabBottom,
              child: SafeArea(
                child: Tooltip(
                  message: 'Admin Panel',
                  // Transparan — hanya ikon, tanpa bulatan/background.
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final b = AdminGate.panelBuilder;
                        if (b == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: b),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: AppTheme.textPrimary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
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
            final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
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

class _BottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.watch<LocaleProvider>().s;
    final uid = ref.watch(authProvider.select((a) => a.uid));
    final chat = ref.read(chatProvider.notifier);
    // Badge hijau = jumlah user online (bukan diri sendiri, bukan diblokir).
    // `select` mengembalikan ANGKA (bukan list) → _BottomNav hanya rebuild
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
              child: _BadgedIcon(
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

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final Color badgeColor;
  final bool badgePill;
  const _BadgedIcon({
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
