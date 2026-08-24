import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../providers/locale_provider.dart';
import '../services/call_service.dart';
import '../services/call_notification.dart';
import '../widgets/profile_avatar.dart';

/// Layar panggilan 1:1 — dipakai caller (menelpon) dan callee (menerima).
/// Audio: avatar + timer. Video: remote fullscreen + preview lokal kecil.
class CallScreen extends StatefulWidget {
  final String callId;
  final String remoteUid;
  final String remoteName;
  final String callType;
  final bool isCaller;
  final List<Map<String, dynamic>> pendingSignals;
  final CallSession? session;
  final String chatId;

  /// Dipanggil saat user minimize video ke dalam chat (tombol / back).
  /// Null atau panggilan audio → layar tidak bisa diminimize.
  final VoidCallback? onMinimize;

  const CallScreen({
    super.key,
    required this.callId,
    required this.remoteUid,
    required this.remoteName,
    required this.callType,
    required this.isCaller,
    this.pendingSignals = const [],
    this.session,
    this.chatId = '',
    this.onMinimize,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallSession _session;
  bool _ownsSession = true;
  Timer? _autoClose;
  String _elapsed = '00:00';
  Offset? _localPreviewPos;
  Size _localPreviewSize = const Size(100, 150);

  /// True → kamera saya fullscreen, video remote jadi bubble kecil.
  bool _swapped = false;

  /// Mode gesture aktif di bubble: geser posisi atau resize dari pojok.
  bool _resizingBubble = false;
  Size _resizeStartSize = Size.zero;
  Offset _resizeStartLocal = Offset.zero;
  bool _minimizing = false;

  /// Video + ada callback minimize → bisa kecilkan ke overlay chat.
  bool get _minimizable =>
      widget.onMinimize != null && widget.callType == 'video';

  /// Back sistem jadi minimize (bukan tutup) selama call belum berakhir.
  bool get _backMinimizes => _minimizable && _session.phase != CallPhase.ended;

  @override
  void initState() {
    super.initState();
    CallProvider.instance.registerCall(widget.callId);
    final profile = context.read<AuthProvider>().profile;
    final s = context.read<LocaleProvider>().s;
    if (widget.session != null) {
      // Session sudah dibuat & di-init oleh CallProvider (mode chat / expand).
      _session = widget.session!;
      _ownsSession = false;
    } else {
      _session = CallSession(
        callId: widget.callId,
        remoteUid: widget.remoteUid,
        remoteName: widget.remoteName,
        callType: widget.callType,
        isCaller: widget.isCaller,
        myName: profile?.nickname ?? '',
        myGender: profile?.gender ?? 'other',
        pendingSignals: widget.pendingSignals,
      );
      _ownsSession = true;
    }
    _session.addListener(_onSession);
    if (_ownsSession) {
      unawaited(
        CallNotification.showActive(
          body: widget.callType == 'video'
              ? s.callNotifActiveVideo
              : s.callNotifActiveAudio,
          channelName: s.callNotifActiveAudio,
          channelDesc: s.callNotifActiveAudio,
          chatId: widget.chatId,
          otherUid: widget.remoteUid,
          otherName: widget.remoteName,
        ),
      );
      unawaited(_session.init());
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _autoClose?.cancel();
    if (_ownsSession) {
      unawaited(_session.close());
      unawaited(CallNotification.cancel());
      CallProvider.instance.unregisterCall(widget.callId);
    }
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    if (_session.phase == CallPhase.ended) {
      unawaited(CallNotification.cancel());
    }
    if (_session.phase == CallPhase.ended && _autoClose == null) {
      _autoClose = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  String _phaseText(S s) {
    switch (_session.phase) {
      case CallPhase.ringing:
        return s.callRinging;
      case CallPhase.connecting:
        return s.callConnecting;
      case CallPhase.error:
        return s.msgCallError;
      case CallPhase.ended:
        switch (_session.endReason) {
          case CallEndReason.declined:
            return s.msgCallDeclined;
          case CallEndReason.busy:
            return s.msgCallBusy;
          case CallEndReason.missed:
            return s.msgCallMissed;
          case CallEndReason.error:
            return s.msgCallError;
          default:
            return s.msgCallEnded;
        }
      case CallPhase.inCall:
        return _elapsed;
    }
  }

  void _tick() {
    final start = _session.connectedAt;
    if (start == null) return;
    final d = DateTime.now().difference(start);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted && _elapsed != '$m:$sec') {
      setState(() => _elapsed = '$m:$sec');
    }
  }

  /// Kecilkan video ke overlay dalam chat: pindahkan mode ke chat lalu
  /// tutup layar ini — session tetap hidup di CallProvider.
  void _minimize() {
    if (!_minimizable || _minimizing) return;
    setState(() => _minimizing = true);
    CallProvider.instance.setMode(CallMode.chat);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Tukar video besar ↔ kecil (double tap).
  void _toggleSwap() {
    if (!mounted) return;
    setState(() => _swapped = !_swapped);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final isVideo = widget.callType == 'video';
    final inCall = _session.phase == CallPhase.inCall;
    final showRemoteVideo = inCall && isVideo && _session.hasRemoteVideo;
    final showLocalPreview =
        inCall &&
        isVideo &&
        _session.cameraOn &&
        _session.localRenderer.srcObject != null;

    return PopScope(
      canPop: !_backMinimizes || _minimizing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10201A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Remote stream — SELALU di-mount supaya Android memutar audio
            // remote meski tak ada video track (panggilan audio, atau video
            // masih negosiasi). Tanpa view terpasang, audio remote diam.
            // Double tap di fullscreen → tukar dengan bubble kecil.
            RTCVideoView(
              _swapped && showRemoteVideo
                  ? _session.localRenderer
                  : _session.remoteRenderer,
              mirror: _swapped && showRemoteVideo,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: showLocalPreview && showRemoteVideo
                  ? _toggleSwap
                  : null,
            ),
            // Overlay avatar untuk panggilan audio / sebelum video tiba.
            if (!showRemoteVideo)
              Container(
                color: const Color(0xFF10201A),
                child: _RemoteFallback(
                  uid: widget.remoteUid,
                  name: widget.remoteName,
                  muted: inCall && !_session.micOn,
                ),
              ),

            // Bubble kecil — BISA digeser, di-resize dari pojok kanan bawah,
            // dan double tap untuk tukar dengan video besar.
            // Muncul pertama di KIRI ATAS supaya tidak menutupi tombol.
            if (showLocalPreview)
              Builder(
                builder: (ctx) {
                  final mq = MediaQuery.of(ctx);
                  const minW = 70.0;
                  const minH = 100.0;
                  const handle = 44.0;
                  final maxW = mq.size.width * 0.6;
                  final maxH = mq.size.height * 0.6;
                  final w = _localPreviewSize.width.clamp(minW, maxW);
                  final h = _localPreviewSize.height.clamp(minH, maxH);
                  // Default: KANAN ATAS layar, di bawah status bar.
                  _localPreviewPos ??= Offset(mq.size.width - w - 12, 24);
                  final pos = Offset(
                    _localPreviewPos!.dx.clamp(8.0, mq.size.width - w - 8),
                    _localPreviewPos!.dy.clamp(8.0, mq.size.height - h - 8),
                  );
                  return Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: showRemoteVideo ? _toggleSwap : null,
                      onPanStart: (d) {
                        _resizingBubble =
                            d.localPosition.dx > w - handle &&
                            d.localPosition.dy > h - handle;
                        _resizeStartSize = Size(w, h);
                        _resizeStartLocal = d.localPosition;
                      },
                      onPanUpdate: (d) {
                        setState(() {
                          if (_resizingBubble) {
                            _localPreviewSize = Size(
                              (_resizeStartSize.width +
                                      d.localPosition.dx -
                                      _resizeStartLocal.dx)
                                  .clamp(minW, maxW),
                              (_resizeStartSize.height +
                                      d.localPosition.dy -
                                      _resizeStartLocal.dy)
                                  .clamp(minH, maxH),
                            );
                          } else {
                            _localPreviewPos = Offset(
                              (_localPreviewPos!.dx + d.delta.dx).clamp(
                                8.0,
                                mq.size.width - w - 8,
                              ),
                              (_localPreviewPos!.dy + d.delta.dy).clamp(
                                8.0,
                                mq.size.height - h - 8,
                              ),
                            );
                          }
                        });
                      },
                      onPanEnd: (_) => _resizingBubble = false,
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
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: RTCVideoView(
                                _swapped && showRemoteVideo
                                    ? _session.remoteRenderer
                                    : _session.localRenderer,
                                mirror: !(_swapped && showRemoteVideo),
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            ),
                            // Handle resize di pojok kanan bawah.
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Icon(
                                Icons.open_in_full_rounded,
                                size: 22,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // Info atas
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    widget.remoteName,
                    style: AppText.headline.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _phaseText(s),
                    style: AppText.body.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Kontrol bawah
            if (inCall)
              Positioned(
                bottom: 48,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ControlButton(
                      icon: _session.micOn ? Icons.mic : Icons.mic_off,
                      color: _session.micOn ? null : Colors.redAccent,
                      tooltip: _session.micOn ? s.btnMute : s.btnUnmute,
                      onTap: _session.toggleMic,
                    ),
                    if (isVideo) ...[
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: _session.cameraOn
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: _session.cameraOn ? null : Colors.redAccent,
                        tooltip: s.btnSwitchCamera,
                        onTap: _session.toggleCamera,
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: Icons.cameraswitch,
                        tooltip: s.btnSwitchCamera,
                        onTap: _session.switchCamera,
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: _session.speakerOn
                            ? Icons.volume_up
                            : Icons.volume_off,
                        color: _session.speakerOn ? null : Colors.redAccent,
                        tooltip: s.btnSpeaker,
                        onTap: _session.toggleSpeaker,
                      ),
                      if (_minimizable) ...[
                        const SizedBox(width: 16),
                        _ControlButton(
                          icon: Icons.picture_in_picture_alt,
                          tooltip: s.callMinimize,
                          onTap: _minimize,
                        ),
                      ],
                    ],
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.call_end,
                      color: Colors.redAccent,
                      tooltip: s.btnEndCall,
                      onTap: _session.end,
                    ),
                  ],
                ),
              )
            else if (_session.phase == CallPhase.ringing ||
                _session.phase == CallPhase.connecting)
              Positioned(
                bottom: 48,
                left: 0,
                right: 0,
                child: Center(
                  child: _ControlButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    tooltip: s.btnEndCall,
                    onTap: _session.end,
                  ),
                ),
              ),

            // Timer saat in-call (di atas kontrol)
            if (inCall)
              Positioned(
                bottom: 130,
                left: 0,
                right: 0,
                child: _ElapsedTimer(onTick: _tick),
              ),
          ],
        ),
      ),
    );
  }
}

/// Timer durasi call — hanya jalan saat connectedAt sudah terisi.
class _ElapsedTimer extends StatefulWidget {
  final VoidCallback onTick;
  const _ElapsedTimer({required this.onTick});

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => widget.onTick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _RemoteFallback extends StatelessWidget {
  final String uid;
  final String name;
  final bool muted;

  const _RemoteFallback({
    required this.uid,
    required this.name,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ProfileAvatar(uid: uid, name: name, size: 120, borderRadius: 60),
          const SizedBox(height: 24),
          if (muted) Icon(Icons.mic_off, color: Colors.white70, size: 28),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color ?? Colors.white24,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
