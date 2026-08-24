import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/admin_call_watch_service.dart';
import 'profile_avatar.dart';

/// Overlay pantau panggilan video di monitor chat admin — pola sama dengan
/// ChatCallOverlay private chat: video utama setengah layar atas (bisa
/// di-resize drag), peserta kedua jadi bubble kecil yang bisa di-drag,
/// chat tetap tampil di bawahnya. Tanpa tombol end/mute — admin penonton.
class AdminCallWatchOverlay extends StatefulWidget {
  final WatchSession session;
  final VoidCallback onExpand;

  const AdminCallWatchOverlay({
    super.key,
    required this.session,
    required this.onExpand,
  });

  @override
  State<AdminCallWatchOverlay> createState() => _AdminCallWatchOverlayState();
}

class _AdminCallWatchOverlayState extends State<AdminCallWatchOverlay> {
  Offset? _bubblePos;
  double? _remoteH;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final sess = widget.session;
    final mq = MediaQuery.of(context);
    final appBarH =
        Scaffold.maybeOf(context)?.appBarMaxHeight ?? kToolbarHeight;
    final maxW = mq.size.width;
    final bodyHFull =
        mq.size.height - mq.padding.top - appBarH - mq.padding.bottom;
    final keyboardH = mq.viewInsets.bottom;
    final bodyH = (bodyHFull - keyboardH).clamp(200.0, double.infinity);
    final keyboardOpen = keyboardH > 40;
    const minChatVisible = 110.0;
    final maxRemoteWhenKeyboard = (bodyH - minChatVisible).clamp(
      bodyH * 0.18,
      bodyH * 0.45,
    );
    final halfH = bodyHFull * 0.5;
    _remoteH ??= halfH;
    final userRemoteH = _remoteH!.clamp(bodyHFull * 0.25, bodyHFull * 0.78);
    final remoteH = keyboardOpen
        ? userRemoteH.clamp(bodyH * 0.18, maxRemoteWhenKeyboard)
        : userRemoteH.clamp(bodyH * 0.25, bodyH * 0.78);

    final main = sess.participants[sess.mainIndex];
    final other = sess.participants[1 - sess.mainIndex];
    final bubbleW = maxW * 0.3;
    final bubbleH = bubbleW * 1.4;
    _bubblePos ??= Offset(maxW - bubbleW - 12, remoteH - bubbleH - 12);
    final pos = Offset(
      _bubblePos!.dx.clamp(8.0, maxW - bubbleW - 8),
      _bubblePos!.dy.clamp(8.0, bodyH - bubbleH - 8),
    );

    return SizedBox.expand(
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            top: 0,
            left: 0,
            right: 0,
            height: remoteH,
            child: _mainPanel(s, sess, main),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            top: remoteH - 14,
            left: 0,
            right: 0,
            height: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                setState(() {
                  _remoteH = (_remoteH! + d.delta.dy).clamp(
                    bodyHFull * 0.25,
                    bodyHFull * 0.78,
                  );
                });
              },
              onPanEnd: (_) {
                setState(() {
                  _bubblePos = Offset(
                    _bubblePos!.dx.clamp(8.0, maxW - bubbleW - 8),
                    _bubblePos!.dy.clamp(8.0, bodyH - bubbleH - 8),
                  );
                });
              },
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _bubble(other, pos, bubbleW, bubbleH, maxW, bodyH),
        ],
      ),
    );
  }

  Widget _mainPanel(S s, WatchSession sess, WatchParticipant p) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: const Color(0xFF10201A))),
        Positioned.fill(
          child: RTCVideoView(
            p.renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        if (!_showVideo(p))
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(
                    uid: p.uid,
                    name: p.name,
                    size: 80,
                    borderRadius: 40,
                  ),
                  SizedBox(height: 10),
                  Text(
                    _placeholderText(s, sess, p),
                    style: AppText.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: AppText.label.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _liveBadge(s),
              ],
            ),
          ),
        ),
        Positioned(bottom: 10, left: 0, right: 0, child: _controls(s)),
      ],
    );
  }

  bool _showVideo(WatchParticipant p) =>
      p.connected && p.hasVideoTrack && p.cameraOn;

  String _placeholderText(S s, WatchSession sess, WatchParticipant p) {
    if (sess.call.status == 'ringing') return s.adminCallRinging;
    if (!p.connected || p.connecting) return s.adminWatchConnecting;
    if (!p.hasVideoTrack && sess.isVideo) return s.adminWaitingVideo;
    if (!p.cameraOn) return s.adminCameraOff;
    return '';
  }

  Widget _liveBadge(S s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFFF4D4F),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          s.adminCallLive,
          style: AppText.micro.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        _WatchDurationText(session: widget.session),
      ],
    );
  }

  Widget _controls(S s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.cameraswitch,
          onTap: () => setState(
            () => widget.session.mainIndex = 1 - widget.session.mainIndex,
          ),
          label: s.adminSwapView,
        ),
        _ControlButton(icon: Icons.aspect_ratio, onTap: widget.onExpand),
      ],
    );
  }

  /// Video peserta kedua sebagai bubble kecil yang bisa di-drag.
  Widget _bubble(
    WatchParticipant p,
    Offset pos,
    double w,
    double h,
    double maxW,
    double maxH,
  ) {
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => setState(
          () => widget.session.mainIndex = 1 - widget.session.mainIndex,
        ),
        onPanUpdate: (d) {
          setState(() {
            _bubblePos = Offset(
              (_bubblePos!.dx + d.delta.dx).clamp(8.0, maxW - w - 8),
              (_bubblePos!.dy + d.delta.dy).clamp(8.0, maxH - h - 8),
            );
          });
        },
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 1),
            color: const Color(0xFF10201A),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                p.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              if (!_showVideo(p))
                ColoredBox(
                  color: const Color(0xFF10201A),
                  child: ProfileAvatar(
                    uid: p.uid,
                    name: p.name,
                    size: 44,
                    borderRadius: 22,
                  ),
                ),
              if (!p.micOn)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layar pantau fullscreen — expand dari overlay.
class AdminCallWatchFullScreen extends StatefulWidget {
  final WatchSession session;
  const AdminCallWatchFullScreen({super.key, required this.session});

  @override
  State<AdminCallWatchFullScreen> createState() =>
      _AdminCallWatchFullScreenState();
}

class _AdminCallWatchFullScreenState extends State<AdminCallWatchFullScreen> {
  Offset? _pipPos;
  double _pipScale = 1.0;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (_recording && widget.session.stopped) {
      _recording = false;
      widget.session.stopRecording();
    }
    setState(() {});
  }

  bool get _mediaConnected =>
      widget.session.participants.any((p) => p.connected || p.connecting);

  Future<void> _toggleRecord(S s) async {
    final sess = widget.session;
    if (_recording) {
      setState(() => _recording = false);
      await sess.stopRecording();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.recStop)));
      }
      return;
    }
    final path = await sess.startRecording();
    if (!mounted) return;
    if (path == 'STORAGE_DENIED') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.recStorageDenied)));
      return;
    }
    setState(() => _recording = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final sess = widget.session;
    final main = sess.participants[sess.mainIndex];
    final other = sess.participants[1 - sess.mainIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: RTCVideoView(
                main.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
            if (!_showVideo(main))
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileAvatar(
                        uid: main.uid,
                        name: main.name,
                        size: 96,
                        borderRadius: 48,
                      ),
                      SizedBox(height: 10),
                      Text(
                        _placeholderText(s, sess, main),
                        style: AppText.bodySmall.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // PiP peserta kedua — bisa di-drag, double-tap expand/kecilkan,
            // single-tap tukar dengan panel utama.
            Builder(
              builder: (ctx) {
                final mq = MediaQuery.of(ctx);
                const baseW = 104.0;
                const baseH = 146.0;
                final w = baseW * _pipScale;
                final h = baseH * _pipScale;
                _pipPos ??= Offset(
                  mq.size.width - w - 12,
                  mq.size.height * 0.55,
                );
                final pos = Offset(
                  _pipPos!.dx.clamp(8.0, mq.size.width - w - 8),
                  _pipPos!.dy.clamp(8.0, mq.size.height - h - 8),
                );
                return Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => sess.mainIndex = 1 - sess.mainIndex),
                    onDoubleTap: () => setState(
                      () => _pipScale = _pipScale == 1.0 ? 1.45 : 1.0,
                    ),
                    onPanUpdate: (d) => setState(() {
                      _pipPos = Offset(
                        pos.dx + d.delta.dx,
                        pos.dy + d.delta.dy,
                      );
                    }),
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.65),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        color: const Color(0xFF10201A),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RTCVideoView(
                            other.renderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                          if (!_showVideo(other))
                            ColoredBox(
                              color: const Color(0xFF10201A),
                              child: Center(
                                child: ProfileAvatar(
                                  uid: other.uid,
                                  name: other.name,
                                  size: (_pipScale > 1 ? 56 : 40),
                                  borderRadius: (_pipScale > 1 ? 28 : 20),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      '${main.name} & ${other.name}',
                      style: AppText.label.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_mediaConnected)
                        IconButton(
                          tooltip: _recording ? s.recStop : s.recStart,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _recording
                                ? Icons.stop_rounded
                                : Icons.fiber_manual_record,
                            color: _recording
                                ? const Color(0xFFFF4D4F)
                                : Colors.white70,
                            size: 26,
                          ),
                          onPressed: () => _toggleRecord(s),
                        ),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4D4F),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        s.adminCallLive,
                        style: AppText.micro.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      _WatchDurationText(session: sess),
                      SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _showVideo(WatchParticipant p) =>
      p.connected && p.hasVideoTrack && p.cameraOn;

  String _placeholderText(S s, WatchSession sess, WatchParticipant p) {
    if (sess.call.status == 'ringing') return s.adminCallRinging;
    if (!p.connected || p.connecting) return s.adminWatchConnecting;
    if (!p.hasVideoTrack && sess.isVideo) return s.adminWaitingVideo;
    if (!p.cameraOn) return s.adminCameraOff;
    return '';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
    if (label == null) return btn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn,
        const SizedBox(height: 2),
        Text(
          label!,
          style: AppText.micro.copyWith(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Timer durasi call yang dipantau — tick tiap detik.
class _WatchDurationText extends StatefulWidget {
  final WatchSession session;
  const _WatchDurationText({required this.session});

  @override
  State<_WatchDurationText> createState() => _WatchDurationTextState();
}

class _WatchDurationTextState extends State<_WatchDurationText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _text {
    final sec = widget.session.call.elapsedSeconds;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(_text, style: AppText.micro.copyWith(color: Colors.white70));
  }
}
