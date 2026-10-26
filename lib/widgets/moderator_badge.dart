import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/riverpod/moderator_provider.dart';

/// Badge perisai untuk MODERATOR NEGARA.
///
/// Pola sama dengan [VerifiedBadgeForUid]: cek ter-batch lewat
/// `moderatorUidsProvider`, rebuild hanya saat status uid ini berubah.
class ModeratorBadgeForUid extends ConsumerStatefulWidget {
  const ModeratorBadgeForUid({
    super.key,
    required this.uid,
    this.size = 14,
    this.tooltip,
  });

  final String uid;
  final double size;
  final String? tooltip;

  @override
  ConsumerState<ModeratorBadgeForUid> createState() =>
      _ModeratorBadgeForUidState();
}

class _ModeratorBadgeForUidState extends ConsumerState<ModeratorBadgeForUid> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant ModeratorBadgeForUid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _ensure();
  }

  void _ensure() {
    if (widget.uid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(moderatorUidsProvider.notifier).ensureLoaded([widget.uid]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMod = ref.watch(
      moderatorUidsProvider.select((s) => s.contains(widget.uid)),
    );
    if (widget.uid.isEmpty || !isMod) return const SizedBox.shrink();
    return Tooltip(
      message: widget.tooltip ?? 'Moderator',
      child: Icon(
        Icons.shield_rounded,
        size: widget.size,
        color: AppTheme.primary,
      ),
    );
  }
}
