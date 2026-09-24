import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
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
    final names = sess.participants.map((p) => p.name).join(' & ');
    final sec = sess.call.elapsedSeconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E5B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E9E5B), width: 1),
      ),
      child: Row(
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
                  names,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  s.adminListening,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
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
                style: AppText.label.copyWith(color: const Color(0xFF2E9E5B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
