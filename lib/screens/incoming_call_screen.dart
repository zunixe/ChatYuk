import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/call_provider.dart';
import '../providers/locale_provider.dart';
import '../services/call_service.dart';
import '../widgets/profile_avatar.dart';
import 'call_screen.dart';

/// Layar panggilan masuk — muncul saat ada call realtime atau push FCM.
/// Accept → ganti ke CallScreen (role callee). Decline → status declined.
/// Kalau caller membatalkan (status canceled) → otomatis tutup.
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerUid;
  final String callType; // 'audio' | 'video'

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerUid,
    required this.callType,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final CallService _service = CallService.instance;
  StreamSubscription<String>? _statusSub;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  String _callerName = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CallProvider.instance.registerCall(widget.callId);
    _loadCaller();
    _startRingtone();
    _statusSub = _service.onCallStatus(widget.callId).listen((status) {
      if (status == 'canceled' || status == 'ended') _close();
    });
  }

  Future<void> _startRingtone() async {
    await _ringtonePlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        audioFocus: AndroidAudioFocus.gainTransientExclusive,
        usageType: AndroidUsageType.notificationRingtone,
        contentType: AndroidContentType.music,
        isSpeakerphoneOn: true,
      ),
    ));
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringtonePlayer.play(AssetSource('audio/ringtone.mp3'));
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }

  Future<void> _loadCaller() async {
    final name = await _service.getNickname(widget.callerUid);
    if (!mounted || name == null) return;
    setState(() => _callerName = name);
  }

  @override
  void dispose() {
    CallProvider.instance.unregisterCall(widget.callId);
    _statusSub?.cancel();
    _ringtonePlayer.stop();
    _ringtonePlayer.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    _busy = true;
    await _stopRingtone();
    try {
      await _service.updateStatus(widget.callId, 'answered');
    } catch (_) {
      _busy = false;
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: widget.callId,
          remoteUid: widget.callerUid,
          remoteName: _callerName.isEmpty ? 'User' : _callerName,
          callType: widget.callType,
          isCaller: false,
          pendingSignals: const [],
        ),
      ),
    );
  }

  Future<void> _decline() async {
    if (_busy) return;
    _busy = true;
    await _stopRingtone();
    try {
      await _service.updateStatus(widget.callId, 'declined');
      await _service.sendSignal(widget.callId, 'bye');
    } catch (_) {}
    _close();
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final isVideo = widget.callType == 'video';
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Avatar caller
            ProfileAvatar(
              uid: widget.callerUid,
              name: _callerName.isEmpty ? '?' : _callerName,
              size: 96,
              borderRadius: 48,
            ),
            const SizedBox(height: 20),
            Text(
              _callerName.isEmpty ? '...' : _callerName,
              style: AppText.headline,
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? s.callIncomingVideo : s.callIncomingAudio,
              style: AppText.body.copyWith(color: AppTheme.textSecondary),
            ),
            const Spacer(),
            // Tombol terima / tolak
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallAction(
                  icon: Icons.call_end,
                  color: AppTheme.danger,
                  onTap: _decline,
                ),
                SizedBox(width: 60),
                _CallAction(
                  icon: isVideo ? Icons.videocam : Icons.call,
                  color: const Color(0xFF2E9E5B),
                  onTap: _accept,
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CallAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}