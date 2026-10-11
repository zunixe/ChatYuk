part of 'app.dart';

class AppFontGate extends ConsumerWidget {
  final Widget Function(BuildContext context) builder;
  const AppFontGate({required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider.select((a) => a.appFontFamily));
    return builder(context);
  }
}

/// Gerbang bahasa (Riverpod) — subtree root rebuild saat bahasa berganti.
class AppLocaleGate extends ConsumerWidget {
  final Widget Function(BuildContext context) builder;
  const AppLocaleGate({required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    return builder(context);
  }
}

/// Gerbang ThemeMode (Riverpod) — MaterialApp hanya rebuild saat mode
/// gelap/terang berubah (bukan saat notify AuthNotifier lain).
class AppThemeModeGate extends ConsumerWidget {
  final Widget Function(BuildContext context, ThemeMode mode) builder;
  const AppThemeModeGate({required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider.select((t) => t.themeMode));
    return builder(context, mode);
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
    final s = ref.watch(localeProvider).s;
    // Watch ThemeProvider supaya seluruh tree rebuild saat mode gelap/terang
    // berubah — warna AppTheme diambil ulang di build().
    ref.watch(themeProvider);

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
      // snapshot HyperOS dan diangkat saat konten siap (AppSwapMask).
      return const AppSplashReplica();
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
    // → `AppProfileGate(child: _MainNav())` ter-render sekejap (flash halaman
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
    // melempar sesi kosong ke AppProfileGate(_MainNav): klik logout malah
    // mendarat di menu utama terkunci popup profil (laporan Xiaomi).
    if (gate == GateScreen.profileGate) {
      return AppProfileGate(child: _MainNav());
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
      // Preload cache PROFIL lawan-chat teratas → info teman/pengikut tampil
      // INSTAN (peekProfileCache sinkron) saat buka profil, tanpa "keload dulu".
      if (warmUid != null) MessageCache.instance.preloadObjPrefix('profile:'),
      // Preload semua cache bintang ke memori → bias tampil instan di cold
      // start tanpa menunggu disk per-chat (anti-glich).
      ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).preloadAllStarred(),
    ]).timeout(_warmTimeout, onTimeout: () async => const <void>[]);
    return FutureBuilder<void>(
      future: _warmFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const AppAuthSkeletonScreen();
        // Raster MainNav di belakang skeleton 1 frame — swap buffer GPU
        // (Skia half-present #b6b6b6) tidak pernah sampai ke layar.
        return AppSwapMask(child: _MainNav());
      },
    );
  }
}

/// Poin transisi skeleton → konten. Frame PERTAMA _MainNav (raster paling
/// berat: IndexedStack + list) ditutup salinan tampilan skeleton; frame
/// kedua sudah smooth → angkat penutup. Tanpa ini Android menampilkan
/// buffer clear abu 2-4 frame saat GPU belum siap.
class AppSwapMask extends StatefulWidget {
  final Widget child;
  const AppSwapMask({required this.child});
  @override
  State<AppSwapMask> createState() => AppSwapMaskState();
}

/// Gerbang profil wajib isi: aplikasi tampil di belakang (pengguna online)
/// tapi TERTUTUP barrier — user tidak bisa interaksi apa pun sampai form
/// profil (nickname/gender/umur/negara/kota) disubmit. Setelah submit,
/// registerProfile → reloadProfile → isRegistered true → gate rebuild dan
/// popup hilang sendiri. Back button juga diblok (canPop: false).
class AppProfileGate extends StatelessWidget {
  final Widget child;
  const AppProfileGate({required this.child});
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

class AppSwapMaskState extends State<AppSwapMask> {
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
        if (_covered) const Positioned.fill(child: AppAuthSkeletonScreen()),
      ],
    );
  }
}

