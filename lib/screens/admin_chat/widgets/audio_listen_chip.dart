import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';

/// Chip indikator mendengarkan panggilan audio di monitor chat admin.
class AudioListenChip extends StatefulWidget {
  final WatchSession session;
  const AudioListenChip({super.key, required this.session});

  @override
  State<AudioListenChip> createState() => _AudioListenChipState();
}

class _AudioListenChipState extends State<AudioListenChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.55,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _ctrl.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final sess = widget.session;
    final sec = sess.call.elapsedSeconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E5B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E9E5B), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FadeTransition(
                opacity: _ctrl,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E9E5B),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.graphic_eq, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.adminListening,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Status NYATA per peserta — admin bisa membedakan
                    // "belum tersambung" dari "tersambung tapi mic mati /
                    // memang diam". Dulu chip selalu bilang "Mendengarkan..."
                    // walau handshake belum selesai.
                    for (final p in sess.participants)
                      _participantStatus(s, sess, p),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call, size: 14, color: const Color(0xFF2E9E5B)),
                  const SizedBox(width: 4),
                  Text(
                    '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                    style: AppText.label.copyWith(
                      color: const Color(0xFF2E9E5B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Speaker gagal (audio nyangkut di earpiece/pelan) — satu-satunya
          // sinyal yang membedakannya dari "belum tersambung".
          if (sess.speakerFailed)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 4),
              child: Row(
                children: [
                  Icon(Icons.volume_off, size: 12, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s.adminSpeakerFallback,
                      style: AppText.micro.copyWith(color: Colors.orange),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Baris "Nama: status" per peserta.
  Widget _participantStatus(S s, WatchSession sess, WatchParticipant p) {
    final String status;
    final Color color;
    final IconData icon;
    if (sess.status == 'ringing') {
      status = s.adminCallRinging;
      color = AppTheme.textSecondary;
      icon = Icons.ring_volume;
    } else if (p.connecting || !p.connected) {
      status = s.adminWatchConnecting;
      color = Colors.orange;
      icon = Icons.sync;
    } else if (!p.micOn) {
      status = s.adminMicOff;
      color = AppTheme.danger;
      icon = Icons.mic_off;
    } else {
      status = s.adminListening;
      color = const Color(0xFF2E9E5B);
      icon = Icons.mic;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${p.name}: $status',
              style: AppText.micro.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
