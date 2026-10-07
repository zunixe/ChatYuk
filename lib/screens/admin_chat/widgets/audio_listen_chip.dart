import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter/material.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../config/theme.dart';

/// Chip indikator mendengarkan panggilan audio di monitor chat admin.
class AudioListenChip extends ConsumerStatefulWidget {
  final WatchSession session;
  const AudioListenChip({super.key, required this.session});

  @override
  ConsumerState<AudioListenChip> createState() => _AudioListenChipState();
}

class _AudioListenChipState extends ConsumerState<AudioListenChip>
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
    final s = ref.watch(localeProvider).s;
    final sess = widget.session;
    final sec = sess.call.elapsedSeconds;
    // Status call NYATA: header tidak boleh selalu "Mendengarkan…" saat call
    // masih ringing / handshake belum selesai. Dulu header selalu "Mendengarkan…"
    // walau belum ada audio → admin bingung ("mendengarkan" tapi suara belum ada).
    final bool ringing = sess.status == 'ringing';
    final bool anyConnected = sess.participants.any((p) => p.connected);
    final String headerText = ringing
        ? s.adminCallRinging
        : (anyConnected ? s.adminListening : s.adminWatchConnecting);
    final Color headerColor = ringing
        ? AppTheme.textSecondary
        : (anyConnected ? const Color(0xFF2E9E5B) : Colors.orange);
    final IconData headerIcon = ringing
        ? Icons.ring_volume
        : (anyConnected ? Icons.graphic_eq : Icons.sync);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: headerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerColor, width: 1),
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
                  decoration: BoxDecoration(
                    color: headerColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(headerIcon, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerText,
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
                  Icon(Icons.call, size: 14, color: headerColor),
                  const SizedBox(width: 4),
                  Text(
                    '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                    style: AppText.label.copyWith(
                      color: headerColor,
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
      // Saat call masih ringing, bedakan ARAH: pemanggil "Menelepon",
      // penerima "Berdering". Dulu keduanya "Memanggil…" → admin tak tahu
      // siapa yang menunggu dijawab.
      final bool isCaller = p.uid == sess.call.callerId;
      status = isCaller ? s.adminCallerCalling : s.adminCalleeRinging;
      color = AppTheme.textSecondary;
      icon = isCaller ? Icons.call_made : Icons.ring_volume;
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
