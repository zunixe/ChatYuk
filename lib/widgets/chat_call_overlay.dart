import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/call_service.dart';
import 'profile_avatar.dart';

/// Overlay panggilan video dalam chat (gaya OmeTV, split setengah):
/// - Video lawan mengisi setengah layar ATAS — tidak bisa di-drag.
/// - Video sendiri jadi bubble kecil yang BISA di-drag ke mana saja.
/// - Chat tetap tampil & aktif di setengah bawah di belakang overlay.
///
/// Dipasang sebagai anak [Stack] body chat via Positioned.fill.
class ChatCallOverlay extends StatefulWidget {
  final CallSession session;
  final VoidCallback onExpand;
  final VoidCallback onEnd;

  const ChatCallOverlay({
    super.key,
    required this.session,
    required this.onExpand,
    required this.onEnd,
  });

  @override
  State<ChatCallOverlay> createState() => _ChatCallOverlayState();
}

class _ChatCallOverlayState extends State<ChatCallOverlay> {
  Offset? _bubblePos;

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

  String _statusText(S s, CallSession sess) {
    switch (sess.phase) {
      case CallPhase.ringing:
        return s.callRinging;
      case CallPhase.connecting:
        return s.callConnecting;
      case CallPhase.ended:
        return s.msgCallEnded;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final sess = widget.session;
    final isVideo = sess.callType == 'video';
    final inCall = sess.phase == CallPhase.inCall;
    final showLocal =
        inCall && isVideo && sess.cameraOn && sess.localRenderer.srcObject != null;

    // Hitung dimensi dari MediaQuery — aman di build(), tidak memicu
    // !_debugDoingThisLayout yang terjadi saat MediaQuery dipanggil di LayoutBuilder.
    final mq = MediaQuery.of(context);
    final appBarH = Scaffold.maybeOf(context)?.appBarMaxHeight ?? kToolbarHeight;
    final maxW = mq.size.width;
    final bodyH = mq.size.height - mq.padding.top - appBarH - mq.padding.bottom;
    final halfH = bodyH * 0.5;
    final bubbleW = maxW * 0.3;
    final bubbleH = bubbleW * 1.4;
    _bubblePos ??= Offset(maxW - bubbleW - 12, halfH - bubbleH - 12);
    final pos = Offset(
      _bubblePos!.dx.clamp(8.0, maxW - bubbleW - 8),
      // Clamp Y ke tinggi penuh body — bubble boleh didrag ke area chat juga.
      _bubblePos!.dy.clamp(8.0, bodyH - bubbleH - 8),
    );

    debugPrint(
      '[OVERLAY] w=$maxW bodyH=$bodyH half=$halfH bubble=${bubbleW}x$bubbleH '
      'phase=${sess.phase} call=${sess.callType} cam=${sess.cameraOn} '
      'showLocal=$showLocal showRemote=$inCall&&$isVideo&&${sess.hasRemoteVideo} '
      'localSrc=${sess.localRenderer.srcObject != null} '
      'remoteSrc=${sess.remoteRenderer.srcObject != null}',
    );

    // SizedBox.expand memastikan Stack mendapat tight constraints dari parent
    // (Positioned top/left/right/bottom=0), mencegah RenderStack NEEDS-PAINT.
    return SizedBox.expand(
      child: Stack(
        children: [
          _remotePanel(s, sess, isVideo, inCall, halfH),
          if (showLocal)
            _localBubble(sess, pos, bubbleW, bubbleH, maxW, bodyH),
        ],
      ),
    );
  }

  /// Setengah layar atas: video lawan + bar info + bar kontrol.
  Widget _remotePanel(
    S s,
    CallSession sess,
    bool isVideo,
    bool inCall,
    double height,
  ) {
    final showRemote = inCall && isVideo && sess.hasRemoteVideo;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: Stack(
        children: [
          // Selalu di-mount supaya audio remote jalan & video langsung tampil.
          // Positioned.fill wajib — di dalam Stack tanpa ini RTCVideoView dapat
          // ukuran 0 dan video tidak tampil.
          Positioned.fill(
            child: RTCVideoView(
              sess.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          if (!showRemote)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF10201A),
                child: Center(
                  child: ProfileAvatar(
                    uid: sess.remoteUid,
                    name: sess.remoteName,
                    size: 80,
                    borderRadius: 40,
                  ),
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
                      sess.remoteName,
                      style: AppText.caption.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _statusText(s, sess),
                    style: AppText.micro.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Positioned(bottom: 10, left: 0, right: 0, child: _controls(s, sess, isVideo)),
        ],
      ),
    );
  }

  Widget _controls(S s, CallSession sess, bool isVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallControlButton(
          icon: sess.micOn ? Icons.mic : Icons.mic_off,
          color: sess.micOn ? null : Colors.redAccent,
          onTap: sess.toggleMic,
        ),
        if (isVideo)
          _CallControlButton(
            icon: Icons.cameraswitch,
            onTap: sess.switchCamera,
          ),
        _CallControlButton(
          icon: sess.speakerOn ? Icons.volume_up : Icons.volume_off,
          color: sess.speakerOn ? null : Colors.redAccent,
          onTap: sess.toggleSpeaker,
        ),
        _CallControlButton(
          icon: Icons.aspect_ratio,
          onTap: widget.onExpand,
        ),
        _CallControlButton(
          icon: Icons.call_end,
          color: Colors.redAccent,
          label: s.btnEndCall,
          onTap: widget.onEnd,
        ),
      ],
    );
  }

  /// Bubble video sendiri — kecil dan bisa di-drag ke seluruh area layar.
  Widget _localBubble(
    CallSession sess,
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
          ),
          clipBehavior: Clip.antiAlias,
          child: RTCVideoView(
            sess.localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }
}

/// Tombol bulat transparan untuk kontrol call overlay.
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String? label;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    this.color,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: color ?? Colors.black54,
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
