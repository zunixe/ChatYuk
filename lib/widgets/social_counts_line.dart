import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/social_counts_provider.dart';
import '../utils.dart';

/// Baris ringkas jumlah FOLLOWER & TEMAN (gaya IG), mis.
/// "1.2K Followers · 34 Friends" — selalu tampil, termasuk "0" bila belum
/// ada (agar konsisten antar layar; info tidak hilang diam-diam).
///
/// Data diambil dari [socialCountsProvider] (bulk, di-cache per-uid);
/// widget memicu pemuatan sendiri bila uid belum diketahui. Selama data
/// belum dimuat, widget tidak menampilkan apa pun (hindari angka 0 palsu
/// sebelum hasil RPC tiba).
///
/// Dipakai di list chat, social list, room member, sheet avatar room.
class SocialCountsLine extends ConsumerStatefulWidget {
  final String uid;

  const SocialCountsLine({
    super.key,
    required this.uid,
  });

  @override
  ConsumerState<SocialCountsLine> createState() => _SocialCountsLineState();
}

class _SocialCountsLineState extends ConsumerState<SocialCountsLine> {
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
    if (widget.uid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socialCountsProvider.notifier).ensureLoaded([widget.uid]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(localeProvider).s;
    final v = ref.watch(
      socialCountsProvider.select((m) => m[widget.uid]),
    );
    // Belum dimuat → sembunyi dulu (jangan tampilkan 0 palsu).
    if (v == null) return const SizedBox.shrink();
    return Text(
      s.socialCountsShort(compactCount(v.followers), compactCount(v.friends)),
      style: AppText.caption.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
