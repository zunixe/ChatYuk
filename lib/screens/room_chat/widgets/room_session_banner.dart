import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/app_foreground.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/room_session_provider.dart';
import '../../../utils.dart';

/// Banner sesi Room v2 di dalam room (di bawah AppBar):
/// - scheduled: judul + jam mulai + host (+ tombol "Mulai Sesi" untuk host)
/// - live: LIVE + judul + host + jumlah penonton (+ "Akhiri Sesi" untuk host)
/// Widget ini juga memuat sesi room ini & men-tick peak_viewers tiap 60 dtk
/// (tanpa dummy di server) selama sesi live.
class RoomSessionBanner extends ConsumerStatefulWidget {
  final String roomId;
  const RoomSessionBanner({super.key, required this.roomId});

  @override
  ConsumerState<RoomSessionBanner> createState() => _RoomSessionBannerState();
}

class _RoomSessionBannerState extends ConsumerState<RoomSessionBanner> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(roomSessionProvider.notifier).loadFor([widget.roomId]);
    });
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || !AppForeground.now) return;
      ref.read(roomSessionProvider.notifier).tick(widget.roomId);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = ref.read(localeProvider).s;
    try {
      await ref.read(roomSessionProvider.notifier).startSession(widget.roomId);
      _toast(s.sessionStartedToast);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = ref.read(localeProvider).s;
    try {
      await ref.read(roomSessionProvider.notifier).endSession(widget.roomId);
      _toast(s.sessionEndedToast);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final session = ref.watch(
      roomSessionProvider.select((st) => st.byRoom[widget.roomId]),
    );
    if (session == null) return const SizedBox.shrink();
    final myUid = ref.watch(authProvider.select((a) => a.uid));
    final isHost = myUid != null && myUid == session.hostUid;
    final live = session.isLive;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: live
            ? AppTheme.danger.withValues(alpha: 0.10)
            : AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: live
              ? AppTheme.danger.withValues(alpha: 0.45)
              : AppTheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            live ? Icons.podcasts_rounded : Icons.schedule_rounded,
            size: 18,
            color: live ? AppTheme.danger : AppTheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  live
                      ? '${s.exploreLive} · ${session.title}'
                      : '${formatSessionStart(session.startsAt, isId: s.isId)} — ${session.title}',
                  style: AppText.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: live ? AppTheme.danger : AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  live
                      ? '${s.sessionHostBy(session.hostName)} · '
                          '${s.sessionViewers(formatCompactCount(session.peakViewers, isId: s.isId))}'
                      : s.sessionHostBy(session.hostName),
                  style: AppText.caption
                      .copyWith(color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isHost) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: _busy ? null : (live ? _end : _start),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor:
                      live ? AppTheme.danger : AppTheme.primary,
                ),
                child: Text(
                  live ? s.sessionEnd : s.sessionStart,
                  style: AppText.label.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
