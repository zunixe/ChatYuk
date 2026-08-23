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

  const CallScreen({
    super.key,
    required this.callId,
    required this.remoteUid,
    required this.remoteName,
    required this.callType,
    required this.isCaller,
    this.pendingSignals = const [],
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallSession _session;
  Timer? _autoClose;
  String _elapsed = '00:00';

  @override
  void initState() {
    super.initState();
    CallProvider.instance.registerCall(widget.callId);
    final profile = context.read<AuthProvider>().profile;
    final s = context.read<LocaleProvider>().s;
    unawaited(CallNotification.showActive(
      body: widget.callType == 'video'
          ? s.callNotifActiveVideo
          : s.callNotifActiveAudio,
      channelName: s.callNotifActiveAudio,
      channelDesc: s.callNotifActiveAudio,
    ));
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
    _session.addListener(_onSession);
    unawaited(_session.init());
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _autoClose?.cancel();
    unawaited(_session.close());
    unawaited(CallNotification.cancel());
    CallProvider.instance.unregisterCall(widget.callId);
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final isVideo = widget.callType == 'video';
    final inCall = _session.phase == CallPhase.inCall;
    final showRemoteVideo =
        inCall && isVideo && _session.hasRemoteVideo;
    final showLocalPreview =
        inCall && isVideo && _session.cameraOn && _session.localRenderer.srcObject != null;

    return Scaffold(
      backgroundColor: const Color(0xFF10201A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Remote stream — SELALU di-mount supaya Android memutar audio
          // remote meski tak ada video track (panggilan audio, atau video
          // masih negosiasi). Tanpa view terpasang, audio remote diam.
          RTCVideoView(
            _session.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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

          // Preview lokal (video, overlay kecil di pojok)
          if (showLocalPreview)
            Positioned(
              top: 40,
              right: 16,
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: RTCVideoView(
                  _session.localRenderer,
                  mirror: true,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
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
                      color:
                          _session.speakerOn ? null : Colors.redAccent,
                      tooltip: s.btnSpeaker,
                      onTap: _session.toggleSpeaker,
                    ),
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
          if (muted)
            Icon(Icons.mic_off, color: Colors.white70, size: 28),
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