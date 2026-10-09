import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/social_counts_provider.dart';
import '../utils.dart';

/// Baris ringkas jumlah FOLLOWER & TEMAN (gaya IG), mis.
/// "1.2K Followers · 34 Friends".
///
/// Muncul HANYA bila ada nilainya (> 0) — kartu tetap ringkas untuk user baru.
/// Data diambil dari [socialCountsProvider] (bulk, di-cache per-uid);
/// widget memicu pemuatan sendiri bila uid belum diketahui.
///
/// Dipakai di list chat, social list, room member (kartu Online mengambil
/// count langsung dari RPC get_online_users — tak perlu widget ini).
class SocialCountsLine extends ConsumerStatefulWidget {
  final String uid;

  /// Nilai langsung (bila pemanggil sudah punya, mis. dari get_online_users).
  /// Bila diisi, widget tak perlu query provider.
  final int? friendsOverride;
  final int? followersOverride;

  const SocialCountsLine({
    super.key,
    required this.uid,
    this.friendsOverride,
    this.followersOverride,
  });

  @override
  ConsumerState<SocialCountsLine> createState() => _SocialCountsLineState();
}

class _SocialCountsLineState extends ConsumerState<SocialCountsLine> {
  bool get _hasOverride =>
      widget.friendsOverride != null || widget.followersOverride != null;

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant SocialCountsLine old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _ensure();
  }

  void _ensure() {
    if (_hasOverride || widget.uid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socialCountsProvider.notifier).ensureLoaded([widget.uid]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final int friends;
    final int followers;
    if (_hasOverride) {
      friends = widget.friendsOverride ?? 0;
      followers = widget.followersOverride ?? 0;
    } else {
      if (widget.uid.isEmpty) return const SizedBox.shrink();
      final v = ref.watch(
        socialCountsProvider.select((m) => m[widget.uid]),
      );
      if (v == null) return const SizedBox.shrink();
      friends = v.friends;
      followers = v.followers;
    }
    // Hanya tampil bila ada nilainya.
    if (friends == 0 && followers == 0) return const SizedBox.shrink();
    return Text(
      s.socialCountsShort(compactCount(followers), compactCount(friends)),
      style: AppText.caption.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
