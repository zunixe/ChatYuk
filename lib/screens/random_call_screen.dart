import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/random_match.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/call_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/random_match_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../core/nav_guard.dart';
import '../core/call/call_permissions.dart';
import '../utils.dart';
import '../widgets/chat_route.dart';
import '../widgets/call_no_coin_dialog.dart';
import '../widgets/gender_avatar.dart';

/// Layar video call RANDOM (hasil Match). Video lawan penuh layar, kamera
/// sendiri di pojok, tombol Next besar untuk ganti orang.
///
/// Sesi media tetap milik [callProvider] — layar ini hanya menampilkan.
class RandomCallScreen extends ConsumerStatefulWidget {
  const RandomCallScreen({super.key});

  @override
  ConsumerState<RandomCallScreen> createState() => _RandomCallScreenState();
}

class _RandomCallScreenState extends ConsumerState<RandomCallScreen> {
  Timer? _tick;
  bool _busy = false;
  String? _shownCallId;
  bool _endNotified = false;

  /// Sedang pop setelah user mengakhiri call — bypass veto PopScope
  /// (pola yang sama dengan `_minimizing` di CallScreen).
  bool _popping = false;

  /// Dialog konfirmasi keluar sedang tampil — back beruntun tidak membuka
  /// dua dialog.
  bool _exitDialogShown = false;

  /// Error media LOKAL saat sesi berakhir (kamera/mic gagal) — disimpan saat
  /// fase error terdeteksi supaya pesan yang tampil "izin/kamera bermasalah",
  /// bukan "lawan keluar" (keduanya berbeda penyebab & aksi perbaikannya).
  CallMediaError? _endMediaError;

  /// Sesi yang sedang didengarkan (CallSession adalah ChangeNotifier yang
  /// notify saat onTrack / fase berubah). Tanpa listener ini layar hanya
  /// tahu video sudah siap pada tick 1 detik berikutnya → video lawan yang
  /// sebenarnya sudah live tetap tertutup backdrop sampai 1 detik penuh.
  CallSession? _listenedSession;

  @override
  void initState() {
    super.initState();
    // Durasi memakai jam dinding dari `connectedAt` — tidak perlu
    // mendengarkan tiap notifikasi sesi (hemat rebuild).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _checkNoCoin();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _listenedSession?.removeListener(_onSessionChanged);
    _listenedSession = null;
    super.dispose();
  }

  /// Sesi berubah (track masuk, fase berubah) → langsung render ulang,
  /// supaya frame pertama video tampil seketika, bukan menunggu tick.
  /// Notifikasi bisa datang saat frame sedang dibangun → tunda ke frame
  /// berikutnya agar tidak memicu setState-di-tengah-build.
  void _onSessionChanged() {
    if (!mounted || _sessionUpdateScheduled) return;
    _sessionUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionUpdateScheduled = false;
      if (mounted) setState(() {});
    });
    // Jaga-jaga bila frame berikutnya tidak datang (mis. app di background
    // saat track terakhir masuk): jadwalkan juga lewat microtask.
    scheduleMicrotask(() {
      if (!mounted || !_sessionUpdateScheduled) return;
      _sessionUpdateScheduled = false;
      setState(() {});
    });
  }

  bool _sessionUpdateScheduled = false;

  /// Pasang/ganti listener bila sesi aktif berganti (Match → Next).
  void _bindSession(CallSession? session) {
    if (identical(session, _listenedSession)) return;
    _listenedSession?.removeListener(_onSessionChanged);
    _listenedSession = session;
    _listenedSession?.addListener(_onSessionChanged);
  }

  bool _noCoinDialogShown = false;

  /// Cek apakah sesi sedang menunggu user memutuskan (koin habis).
  void _checkNoCoin() {
    final session = ref.read(callProvider).activeSession;
    if (session == null) return;
    if (!session.awaitingContinue || _noCoinDialogShown) return;
    _noCoinDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = ref.read(localeProvider).s;
      // Batas gratis female habis → top-up tak bisa melanjutkan: Akhiri saja.
      if (session.billingPauseReason == 'free_limit') {
        await showCallFreeLimitDialog(
          context,
          limitMin: session.billingFreeLimitMin,
          onEnd: () {
            _noCoinDialogShown = false;
            session.endCallNoCoin();
          },
        );
        return;
      }
      final perMin = session.billingPerMinute > 0
          ? session.billingPerMinute
          : 20;
      await showCallNoCoinDialog(
        context,
        perMinute: perMin,
        onEnd: () {
          _noCoinDialogShown = false;
          session.endCallNoCoin();
        },
        onContinue: () async {
          _noCoinDialogShown = false;
          final ok = await session.resumeBillingAfterTopup();
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.callNoCoinStillEmpty)),
            );
          }
        },
      );
    });
  }

  String _duration() {
    final start = ref.read(callProvider).activeSession?.connectedAt;
    if (start == null) return '00:00';
    return formatMmSs(DateTime.now().difference(start).inSeconds);
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(randomMatchProvider.notifier).next();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _end() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(randomMatchProvider.notifier).hangup();
    if (!mounted) return;
    // Rebuild dulu (PopScope canPop=true karena call sudah ended) baru
    // pop — maybePop sebelum rebuild akan kena veto & membuka dialog lagi.
    setState(() => _popping = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  /// Back / keluar dari layar call saat panggilan MASIH HIDUP → konfirmasi
  /// dulu. Keluar berarti mengakhiri panggilan (dulu back diam-diam
  /// membiarkan call jalan di background + banner hijau muncul di radar —
  /// user mengira keluar sudah memutus, padahal tidak).
  Future<void> _confirmExit() async {
    if (_busy || _exitDialogShown || !mounted) return;
    _exitDialogShown = true;
    final s = ref.read(localeProvider).s;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          s.randomCallExitTitle,
          style: AppText.title.copyWith(color: AppTheme.textPrimary),
        ),
        content: Text(
          s.randomCallExitBody,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.yukcoinCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(s.randomCallExitYes),
          ),
        ],
      ),
    );
    _exitDialogShown = false;
    if (exit == true && mounted) await _end();
  }

  Future<void> _reportBlock(RandomPartner p) async {
    final s = ref.read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.randomCallReportTitle),
        content: Text(s.randomCallReportBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnRandomCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.randomCallReport),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final me = ref.read(authProvider.notifier).uid;
    if (me != null) {
      try {
        await ref
            .read(chatProvider.notifier)
            .reportUser(reporterId: me, reportedId: p.uid, reason: 'random_call');
      } catch (e) {
        dlog('[RandomCall] report error: $e');
      }
      try {
        await ref.read(chatProvider.notifier).blockUser(me, p.uid);
      } catch (e) {
        dlog('[RandomCall] block error: $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.randomCallReportDone)));
    await _next();
  }

  Future<void> _openChat(RandomPartner p) async {
    final s = ref.read(localeProvider).s;
    final auth = ref.read(authProvider.notifier);
    final me = auth.uid;
    if (me == null) return;
    final navKey = navKeyChat(
      ref.read(chatProvider.notifier).privateChatId(me, p.uid),
    );
    if (!tryClaimNav(navKey)) return;
    try {
      final chatId = await ref
          .read(chatProvider.notifier)
          .startPrivateChat(
            myUid: me,
            otherUid: p.uid,
            myName: auth.profile?.nickname ?? '',
            otherName: p.nickname,
            myGender: auth.profile?.gender ?? '',
          );
      await ref.read(randomMatchProvider.notifier).hangup();
      if (!mounted) return;
      // Layar call diganti layar chat (bukan ditumpuk di atasnya).
      await Navigator.pushReplacement(
        context,
        chatRoute(
          chatId: chatId,
          otherName: p.nickname,
          otherUid: p.uid,
          routeName: privateChatRoute(chatId),
        ),
      );
    } catch (e) {
      dlog('[RandomCall] open chat error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    } finally {
      releaseNav(navKey);
    }
  }

  Future<void> _toggleFollow(RandomPartner p) async {
    final social = ref.read(socialProvider.notifier);
    if (social.isFollowing(p.uid)) {
      await social.unfollow(p.uid);
    } else {
      await social.follow(p.uid);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final st = ref.watch(randomMatchProvider);
    final callState = ref.watch(callProvider);
    final session = callState.activeSession;
    final partner = st.partner;
    // Counter YukCoin: saldo live (realtime) — caller male melihat koin
    // turun tiap tick billing, callee female melihat income masuk.
    final coinSnap = ref.watch(
      pointsProvider.select((p) => (coins: p.points, on: p.enabled)),
    );
    final charged = session?.billingChargedTotal ?? 0;

    // Listener event-driven: hilangkan jeda hingga 1 detik sebelum video
    // lawan terlihat setelah track pertama datang.
    _bindSession(session);

    // Sesi berganti (Next) → reset penanda supaya overlay "mencari" tampil.
    if (session?.callId != _shownCallId) {
      _shownCallId = session?.callId;
      _endNotified = false;
      _endMediaError = null;
    }

    // Teks "Menyambungkan…" hanya selama benar-benar belum ada media.
    // Bila track sudah masuk tapi fase tertinggal, jangan tampilkan teks itu
    // (user melihat video tetapi membaca "menyambungkan" = membingungkan).
    final connecting =
        session == null ||
        (session.phase == CallPhase.connecting && !session.hasRemoteVideo);

    // Lawan menutup call (atau media error): kabari provider SEKALI supaya
    // layar menampilkan "X keluar" + Next — jangan auto-cari diam-diam.
    final sessionEnded =
        session != null &&
        (session.phase == CallPhase.ended || session.phase == CallPhase.error);
    if (sessionEnded && !_endNotified) {
      _endNotified = true;
      _endMediaError = session.mediaError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(randomMatchProvider.notifier).onRemoteEnded();
        }
      });
    }
    // Sesi HILANG padahal fase sudah inCall (startSession pernah sukses):
    // call sudah berakhir di mana-mana (mis. lawan end saat app di
    // background → clearSession jalan tanpa layar tahu) → settle state,
    // JANGAN biarkan backdrop "Menyambungkan…" tampil selamanya.
    if (session == null &&
        st.phase == RandomMatchPhase.inCall &&
        !_endNotified) {
      _endNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(randomMatchProvider.notifier).onRemoteEnded();
        }
      });
    }
    final partnerEnded = st.partnerEnded;
    // Pesan akhir: error media lokal (izin/kamera) ≠ lawan menutup call.
    final endText = partnerEnded
        ? (_endMediaError != null
            ? callMediaErrorMessage(s, _endMediaError)
            : s.randomCallPartnerLeft(partner?.nickname ?? ''))
        : null;
    final searching = st.phase == RandomMatchPhase.searching;

    // JANGAN syaratkan `phase == inCall`: di sebagian device fase bisa
    // tertinggal beberapa ratus ms (atau callback ICE tak pernah datang)
    // padahal track video sudah mengalir. Track yang ada = tampilkan.
    final hasRemoteVideo = session != null && session.hasRemoteVideo;
    final hasLocalVideo =
        session != null && session.cameraOn && session.localRenderer.srcObject != null;

    // Panggilan masih hidup → back TIDAK boleh langsung pop: tampilkan
    // konfirmasi (keluar = mengakhiri call). Setelah call berakhir
    // (ended/error) back bebas.
    final liveCall = session != null &&
        session.phase != CallPhase.ended &&
        session.phase != CallPhase.error;

    return PopScope(
      canPop: !liveCall || _popping,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        dlog('[NAV] back veto random-call → konfirmasi keluar');
        _confirmExit();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video lawan — SELALU di-mount supaya audio remote tetap berbunyi
          // walau video belum/tidak ada (pola CallScreen).
          if (session != null)
            RepaintBoundary(
              child: RTCVideoView(
                session.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          if (!hasRemoteVideo)
            _PartnerBackdrop(
              partner: partner,
              searching: (searching || connecting) && !partnerEnded,
              endedText: endText,
            ),

          // Info atas.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    if (partner != null)
                      GenderAvatar(
                        uid: partner.uid,
                        name: partner.nickname,
                        gender: partner.gender,
                        size: 38,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner?.nickname ?? s.randomSearching,
                            style: AppText.bodyStrong.copyWith(
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _subtitle(
                              s,
                              partner,
                              searching,
                              connecting,
                              partnerEnded,
                              endText,
                            ),
                            style: AppText.caption.copyWith(
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Counter koin: angka = sisa saldo, "−N" = terpakai
                    // call ini. Sembunyi bila sistem koin dimatikan admin.
                    if (coinSnap.on) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.monetization_on_outlined,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        charged > 0
                            ? '${coinSnap.coins} (−$charged)'
                            : '${coinSnap.coins}',
                        style: AppText.label.copyWith(color: Colors.white),
                      ),
                    ],
                    if (partner != null)
                      IconButton(
                        tooltip: s.randomCallReport,
                        onPressed: () => _reportBlock(partner),
                        icon: const Icon(
                          Icons.flag_outlined,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Kamera sendiri (PiP).
          if (hasLocalVideo)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 70,
              right: 12,
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 96,
                    height: 132,
                    child: RTCVideoView(
                      session.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          // Aksi cepat (follow / chat) — hanya saat tersambung.
          if (partner != null && session?.phase == CallPhase.inCall)
            Positioned(
              right: 12,
              bottom: 168,
              child: Column(
                children: [
                  _QuickAction(
                    icon: ref.watch(socialProvider).isFollowing(partner.uid)
                        ? Icons.person_remove_alt_1_outlined
                        : Icons.person_add_alt_1_outlined,
                    label: s.btnFollow,
                    onTap: () => _toggleFollow(partner),
                  ),
                  const SizedBox(height: 12),
                  _QuickAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: s.randomCallChat,
                    onTap: () => _openChat(partner),
                  ),
                ],
              ),
            ),

          // Kontrol bawah.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE6000000), Color(0x00000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (searching || partnerEnded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          partnerEnded
                              ? (endText ?? '')
                              : s.randomCallSearchingAgain,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    // Kontrol call (mic/kamera/end) disembunyikan saat lawan
                    // sudah keluar — tidak ada lagi yang dikontrol.
                    if (!partnerEnded)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _RoundBtn(
                            icon: session?.micOn == true
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            onTap: () async {
                              await session?.toggleMic();
                              if (mounted) setState(() {});
                            },
                          ),
                          const SizedBox(width: 14),
                          _RoundBtn(
                            icon: Icons.cameraswitch_rounded,
                            onTap: () async {
                              await session?.switchCamera();
                            },
                          ),
                          const SizedBox(width: 14),
                          _RoundBtn(
                            icon: Icons.call_end_rounded,
                            color: AppTheme.danger,
                            onTap: _end,
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.quickTimeline,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text(s.randomCallNext),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _subtitle(
    S s,
    RandomPartner? p,
    bool searching,
    bool connecting,
    bool partnerEnded,
    String? endText,
  ) {
    if (partnerEnded) {
      return endText ?? s.randomCallPartnerLeft(p?.nickname ?? '');
    }
    if (searching) return s.randomCallSearchingAgain;
    if (connecting) return s.randomConnecting;
    final parts = <String>[_duration()];
    if (p != null) {
      if (p.age != null && p.age! > 0) parts.add('${p.age}');
      if (p.city.isNotEmpty) parts.add(p.city);
      final d = p.distanceKm;
      if (d != null) {
        parts.add(d < 1 ? '<1km' : '${d.toStringAsFixed(1)}km');
      }
    }
    return parts.join(' · ');
  }
}

class _PartnerBackdrop extends StatelessWidget {
  final RandomPartner? partner;
  final bool searching;

  /// Teks "X keluar" saat lawan menutup call — menggantikan spinner agar
  /// user paham panggilan sudah berakhir (bukan masih mencari).
  final String? endedText;

  const _PartnerBackdrop({
    this.partner,
    this.searching = false,
    this.endedText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1116),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (partner != null)
              GenderAvatar(
                uid: partner!.uid,
                name: partner!.nickname,
                gender: partner!.gender,
                size: 96,
              ),
            if (endedText != null) ...[
              const SizedBox(height: 18),
              Text(
                endedText!,
                style: AppText.bodyStrong.copyWith(color: Colors.white),
              ),
            ] else if (searching) ...[
              const SizedBox(height: 18),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppText.caption.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _RoundBtn({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}
