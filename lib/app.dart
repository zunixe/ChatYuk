import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/theme.dart';
import 'models/auth_data.dart';
import 'providers/riverpod/auth_provider.dart';
import 'providers/riverpod/room_provider.dart';
import 'providers/riverpod/chat_provider.dart';
import 'services/device_info_service.dart';
import 'providers/riverpod/message_reaction_provider.dart';
import 'providers/riverpod/online_users_provider.dart';
import 'core/admin_gate.dart';
import 'providers/riverpod/locale_provider.dart';
import 'core/cache/message_cache.dart';
import 'core/nav_journal.dart';
import 'core/nav_visibility.dart';
import 'core/admin_trim_registry.dart';
import 'core/cache/photo_cache.dart';
import 'core/cache/post_photo_cache.dart';
import 'core/media/image_cache_hygiene.dart';
import 'core/media/native_image.dart';
import 'widgets/message/photo_prefetch.dart';
import 'providers/riverpod/connectivity_provider.dart';
import 'providers/riverpod/nav_provider.dart';
import 'providers/riverpod/theme_provider.dart';
import 'providers/riverpod/timeline_provider.dart';
import 'providers/riverpod/update_provider.dart';
import 'services/chat_service.dart';
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
import 'widgets/render_heartbeat.dart';
import 'widgets/call_banner.dart';
import 'widgets/skeleton_card.dart';
import 'screens/register_screen.dart';
import 'utils.dart';
import 'providers/riverpod/social_provider.dart';
import 'providers/riverpod/call_provider.dart';
import 'services/boot_overlay.dart';

part 'app_widgets.dart';
part 'app_gates.dart';

class ChatYukApp extends ConsumerStatefulWidget {
  const ChatYukApp({super.key});

  @override
  ConsumerState<ChatYukApp> createState() => _ChatYukAppState();
}

class _ChatYukAppState extends ConsumerState<ChatYukApp> {
  // Provider tab dibuat SEJAK APP START (saat skeleton auth masih tampil) —
  // disk cache (SQLite) menghangat paralel dengan auth init, sehingga begitu
  // skeleton hilang tab langsung menampilkan data, TANPA blink abu skeleton.

  @override
  void initState() {
    super.initState();
    // Muat preferensi tema/font tersimpan SEBELUM frame pertama (idempoten).
    ref.read(themeProvider.notifier).init();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Semua provider kini dikelola Riverpod (ProviderScope di main.dart).
    return AppFontGate(
        builder: (context) =>
            // Rebuild subtree saat ukuran font chat berubah (slider user) —
            // bubble chat langsung menyesuaikan tanpa restart navigasi.
            ValueListenableBuilder<double>(
              valueListenable: ChatTextScale.notifier,
              builder: (context, _, __) => AppLocaleGate(
                  builder: (context) => AppThemeModeGate(
                  builder: (context, themeMode) => MaterialApp(
                  title: 'ChatYuk',
                  debugShowCheckedModeBanner: false,
                  // Tidak pakai `key` agar navigasi tidak ter-reset saat font berubah;
                  // rebuild + getter AppTheme.*Theme (dibangun ulang tiap build)
                  // sudah cukup mengganti ThemeData ke font terbaru.
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeMode,
                  navigatorKey: navigatorKey,
                  navigatorObservers: [routeTracker],
                  // Batasi skala font sistem supaya label kecil & baris padat tidak pecah,
                  // tapi tetap menghormati preferensi aksesibilitas user.
                  // RenderHeartbeat: saat foreground, kirim repaint murah tiap
                  // ~32ms supaya panel MIUI tidak masuk DDIC idle (penyebab lag
                  // "buka chat setelah background" — lihat render_heartbeat.dart).
                  builder: (context, child) => RenderHeartbeat(
                    child: WithForegroundTask(
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

  // PERF (2026-10-08): trim arena native saat FOREGROUND-IDLE.
  //
  // Akar "makin lama makin lambat" (terukur Xiaomi 24129PN74G): arena
  // jemalloc membengkak saat aktivitas foreground (terutama pindah tab —
  // Free 5MB→477MB) dan HANYA dibersihkan saat app di-background. User yang
  // memakai NONSTOP tidak pernah men-trigger trim → RSS tinggi → swap/paging
  // (VmSwap ~107MB) → lag progresif. Trim dipanggil di sini HANYA setelah app
  // DIAM beberapa detik supaya tidak memicu re-decode massal (tidak ada yang
  // dilihat saat idle). Timer tiap [_idleTrimInterval]; hop hanya saat
  // interaksi terakhir >= [_idleTrimAfter].
  static const Duration _idleTrimInterval = Duration(seconds: 15);
  static const Duration _idleTrimAfter = Duration(seconds: 4);
  Timer? _idleTrimTimer;
  DateTime _lastInteractionAt = DateTime.now();


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
    // WARMUP FOTO (anti-kedip cold start, insiden 2026-10-11): 4 dtk setelah
    // frame pertama (timeline prewarm + tab prewarm jalan dulu), decode thumb
    // 3 chat terbaru di latar → bubble foto langsung gambar saat chat dibuka
    // dari MANA PUN (list/online/notif), tanpa berpacu dengan SQLCipher
    // dingin di timeout tap. Fire-and-forget, bounded, tak menahan apa pun.
    _schedulePhotoWarmup();
    // Gaya Telegram: halaman tab lain dibangun diam-diam SAAT IDLE (bukan
    // saat diklik) supaya tap pertama terasa instan. Bertahap 1 tab per
    // 800ms supaya tidak ada lonjakan frame — tab aktif sudah ter-render
    // penuh sebelum ini jalan.
    _scheduleTabPrewarm();
    // Trim arena native saat foreground-idle (lihat field _idleTrimTimer).
    _idleTrimTimer = Timer.periodic(_idleTrimInterval, (_) {
      if (!mounted || _pausedAt != null) return; // sedang background → skip
      if (DateTime.now().difference(_lastInteractionAt) < _idleTrimAfter) {
        return; // masih ada interaksi → jangan trim (hindari re-decode massal)
      }
      unawaited(NativeImage.trim());
    });
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
  bool _photoWarmScheduled = false;

  /// Warmup thumb foto 3 chat terbaru (lihat initState). Sekali per sesi.
  void _schedulePhotoWarmup() {
    if (_photoWarmScheduled) return;
    _photoWarmScheduled = true;
    Future<void>.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      try {
        final uid = ProviderScope.containerOf(context, listen: false)
            .read(authProvider.notifier)
            .uid;
        if (uid == null || !mounted) return;
        final snap = ProviderScope.containerOf(context, listen: false)
            .read(chatProvider.notifier)
            .lastPrivateChatsSnapshot(uid);
        final keys = (snap ?? const [])
            .take(3)
            .map((c) => 'private_${c.chatId}')
            .toList();
        if (keys.isEmpty || !mounted) return;
        await PhotoPrefetch.precacheRecentChats(keys)
            .timeout(const Duration(seconds: 25));
      } catch (_) {}
    });
  }

  void _scheduleTabPrewarm() {
    const order = [1, 2, 3]; // Pesan/Chat, Timeline, Profil
    var step = 0;
    void next() {
      if (!mounted || step >= order.length) {
        // Semua tab sudah dibangun → ini pemicu bloat arena terbesar (burst
        // decode/encode build halaman penuh). Trim SEGERA (delay pendek agar
        // tidak mengganggu frame prewarm terakhir): purge jemalloc paling
        // efektif saat halaman baru jadi sampah. Menyerang akar lebih cepat
        // daripada menunggu timer idle 15 dtk. Lihat docs/PERFORMANCE.md §42.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted && _pausedAt == null) unawaited(NativeImage.trim());
        });
        return;
      }
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
    _idleTrimTimer?.cancel();
    _idleTrimTimer = null;
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
      // PENTING: pelepasan cache bitmap + trim arena native DITUNDA ke resume
      // (lihat cabang resumed) supaya hanya dilakukan saat background LAMA.
      // Dulu dipanggil di sini (setiap pause) → HOME 3 dtk memaksa re-decode
      // SEMUA gambar saat resume = burst alokasi besar → jemalloc arena
      // membengkak (PSS 506MB dirty, RSS 823MB; FREE 481MB). Itu regresi
      // memori nyata (bukan sekadar reserved). Lihat docs/NATIVE_UI_ONLY.md.
    } else if (state == AppLifecycleState.detached) {
      // App di-kill/force-close → set idle (offline otomatis setelah threshold).
      auth.goIdle();
    } else if (state == AppLifecycleState.resumed) {
      // CATATAN (dicoba & TIDAK berhasil — jangan ulangi): stall 181ms pada
      // frame pertama setelah resume BUKAN kode kita, melainkan DDIC idle
      // mode MIUI. Bukti: framestats ui_work=0ms, Vsync melompat +181ms;
      // logcat "MI-SF: isTpIdleScene, mAverageFrameRate is 0" →
      // "isDdicIdleMode: 1". Percobaan (a) kunci preferredDisplayModeId=60Hz
      // dan (b) paksa frame bergerak 300ms saat resume — DUA-DUANYA GAGAL
      // (54 event DDIC idle tetap muncul). MIUI butuh arus frame terus-
      // menerus; begitu berhenti, panel langsung idle lagi. Ini kebijakan
      // sistem (hemat baterai), di luar kendali app. Yang bisa dikurangi
      // HANYA kerja app-nya (sudah: GC storm 158→17, PSS 385→220MB).
      // PERF: kalau app lama di-background (>60 dtk), buang cache pesan
      // in-memory (tiap chat menahan pesan + base64 foto) — cegah akumulasi
      // yang bikin "ngetik ngelag setelah dipakai lama". Background sebentar
      // TIDAK di-trim supaya chat tetap instan.
      final pausedFor = _pausedAt == null
          ? null
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      // PENTING (memori): saat resume, renderer Android (HWUI Skia-Vulkan) +
      // engine Flutter meng-commit buffer render ke arena allocator → "Native
      // Heap" PSS melonjak ~500MB. TERVERIFIKASI heapprofd: sumber =
      // vkCreateFramebuffer via android::uirenderer (HWUI) — BUKAN kode image
      // kita. Halaman itu di-purge oleh NativeImage.trim() (mallopt M_PURGE):
      // terukur settle ~500MB → ~37MB tiap siklus. Purge di beberapa titik
      // (puncak render bergeser) tanpa membebani — 5 channel call per resume.
      for (final ms in const [0, 2000, 4000, 7000, 10000]) {
        if (ms == 0) {
          unawaited(NativeImage.trim());
        } else {
          Future<void>.delayed(Duration(milliseconds: ms), () {
            unawaited(NativeImage.trim());
          });
        }
      }
      if (pausedFor != null && pausedFor.inSeconds >= 60) {
        // Background lama → buang cache RAM BESAR (pesan + foto full-res) +
        // bitmap, lalu minta arena native kembali ke OS.
        //
        // PENTING (terukur): JANGAN buang thumb foto di sini. Dulu memakai
        // trimMemCache() yang mengosongkan `_thumbMem` juga → saat user buka
        // chat, semua thumbnail harus dibaca + di-decode ULANG dari disk:
        // logcat menunjukkan "GC freed 1770KB, 372(17MB) LOS objects" +
        // "WaitForGcToComplete blocked Explicit on HeapTrim for 33.862ms" →
        // frame stall 200ms pada buka-pertama setelah resume (keluhan "masuk
        // private chat harus beberapa kali baru cepet").
        // Thumb = kecil (≤512px) & langsung dipakai bubble → dipertahankan.
        try {
          MessageCache.instance.trimMemCache();
        } catch (_) {}
        try {
          PhotoCache.instance.trimHeavyCache();
        } catch (_) {}
        // PostPhotoCache TIDAK di-trim: isinya thumb TIMELINE (bukan chat) dan
        // membuangnya memaksa decode ulang saat kartu timeline di-build →
        // jank di tab Timeline. Yang dibuang di atas (pesan + foto chat
        // full-res + imageCache) sudah cukup untuk tujuan hemat memori.
        try {
          // clearAll() sudah membuang Flutter imageCache + cache app terdaftar.
          ImageCacheHygiene.clearAll();
        } catch (_) {}
        // Force: commit buffer render ~500MB HARUS segera di-purge (throttle
        // 60 dtk dilewati — trim staggered di atas tak cukup untuk ini).
        unawaited(NativeImage.trim(force: true));
      } else if (pausedFor != null && pausedFor.inSeconds >= 15) {
        // Background sedang (15-60 dtk) → trim RAM foto full-res saja (paling
        // besar, paling murah dimuat ulang). Thumb + pesan tetap di RAM
        // supaya chat instan.
        try {
          PhotoCache.instance.trimHeavyCache();
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
    // Sinyal memori menipis dari OS → kembalikan juga arena native (jemalloc)
    // ke OS via JNI malloc_trim (docs/PERFORMANCE.md §39). No-op bila lib
    // native tak ada.
    unawaited(NativeImage.trim());
    // Cache RAM panel admin (post/room/chat) — hanya bila panel pernah
    // dibuka (registry kosong = no-op, TIDAK memaksa provider dibuat).
    AdminTrimRegistry.run();
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
    // Pindah tab = pemicu utama bloat arena native → tandai interaksi supaya
    // trim foreground-idle menunggu user benar-benar diam.
    _lastInteractionAt = DateTime.now();
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
    // P1c: kabarkan tab visible ke gate kerja latar (poll list chat/presence)
    // via ValueNotifier global — nol rebuild tambahan.
    if (visibleMainTab.value != tab) visibleMainTab.value = tab;
    // Rebuild seluruh tab saat mode terang/gelap berubah.
    final dark = ref.watch(themeProvider.select((t) => t.isDark));
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
    final s = ref.read(localeProvider).s;
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
    // Listener transparan: tandai SEMUA interaksi (tap/scroll/ketik) agar trim
    // foreground-idle (lihat _idleTrimTimer) menunggu app benar-benar diam.
    // Behavior.translucent = mengamati tanpa merebut gesture & tanpa mengubah
    // layout (meneruskan pointer ke child).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lastInteractionAt = DateTime.now(),
      child: PopScope(
        // Back di tab SELAIN Online → kembali ke tab Online (index 0).
        // Di Online sendiri → biarkan (keluar app seperti biasa).
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          NavJournal.log('back root tab=$tab -> goTo(0)');
          ref.read(navProvider.notifier).goTo(0);
        },
        child: Scaffold(
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
      bottomNavigationBar: AppBottomNav(currentIndex: tab, onTap: _onNavTap),
    ),
      ),
    );
  }
}

