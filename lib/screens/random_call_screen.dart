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
import '../providers/riverpod/random_match_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../core/nav_guard.dart';
import '../utils.dart';
import '../widgets/chat_route.dart';
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

  @override
  void initState() {
    super.initState();
    // Durasi memakai jam dinding dari `connectedAt` — tidak perlu
    // mendengarkan tiap notifikasi sesi (hemat rebuild).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
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
    if (mounted) Navigator.of(context).maybePop();
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

    // Sesi berganti (Next) → reset penanda supaya overlay "mencari" tampil.
    if (session?.callId != _shownCallId) _shownCallId = session?.callId;

    final connecting =
        session == null || session.phase == CallPhase.connecting;
    final ended =
        session != null &&
        (session.phase == CallPhase.ended || session.phase == CallPhase.error);
    final searching = st.phase == RandomMatchPhase.searching || ended;

    final hasRemoteVideo =
        session != null && session.phase == CallPhase.inCall && session.hasRemoteVideo;
    final hasLocalVideo =
        session != null && session.cameraOn && session.localRenderer.srcObject != null;

    return Scaffold(
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
            _PartnerBackdrop(partner: partner, searching: searching || connecting),

          // Info atas.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
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
                            _subtitle(s, partner, searching, connecting),
                            style: AppText.caption.copyWith(
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
                    if (searching)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          s.randomCallSearchingAgain,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
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
    );
  }

  String _subtitle(
    S s,
    RandomPartner? p,
    bool searching,
    bool connecting,
  ) {
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

  const _PartnerBackdrop({this.partner, this.searching = false});

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
            if (searching) ...[
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
