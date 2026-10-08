import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/riverpod/verified_provider.dart';

/// Badge terverifikasi berdasarkan UID — membaca cache `verifiedProvider`
/// dan memicu pemuatan bila belum diketahui.
///
/// Dipakai di kartu/list yang hanya punya uid (Online, Nearby, chat,
/// komentar). Mengembalikan SizedBox.shrink() bila uid kosong / belum verified.
class VerifiedBadgeForUid extends ConsumerStatefulWidget {
  final String uid;
  final double size;
  final String? tooltip;

  const VerifiedBadgeForUid({
    super.key,
    required this.uid,
    this.size = 15,
    this.tooltip,
  });

  @override
  ConsumerState<VerifiedBadgeForUid> createState() =>
      _VerifiedBadgeForUidState();
}

class _VerifiedBadgeForUidState extends ConsumerState<VerifiedBadgeForUid> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant VerifiedBadgeForUid old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _ensure();
  }

  void _ensure() {
    if (widget.uid.isEmpty) return;
    // Tunda ke frame berikut agar tidak memicu state-change saat build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(verifiedProvider.notifier).ensureLoaded([widget.uid]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) return const SizedBox.shrink();
    final ok = ref.watch(
      verifiedProvider.select((set) => set.contains(widget.uid)),
    );
    return VerifiedBadge(
      verified: ok,
      size: widget.size,
      tooltip: widget.tooltip,
    );
  }
}


/// Badge TERVERIFIKASI (nomor HP via Telegram) — centang dengan gradien emas.
///
/// Dipakai seragam di seluruh app (Online, Nearby, chat, komentar, profil).
/// Menggantikan centang biru `is_registered` lama (keputusan produk: badge
/// emas = nomor HP terverifikasi).
///
/// Ukuran mengikuti konteks daftar/kartu (default 14–15). Bila `showNull`
/// tidak diset dan [verified] false, widget mengembalikan SizedBox.shrink().
class VerifiedBadge extends StatelessWidget {
  final bool verified;
  final double size;

  /// Tooltip aksesibilitas (opsional).
  final String? tooltip;

  const VerifiedBadge({
    super.key,
    required this.verified,
    this.size = 15,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    if (!verified) return const SizedBox.shrink();
    final icon = Icon(
      Icons.verified_rounded,
      size: size,
      // Warna diambil dari gradien via ShaderMask; base putih agar aman bila
      // shader gagal render (fallback tetap terlihat).
      color: Colors.white,
    );
    final badge = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFE082), // emas terang
          Color(0xFFFFC107),
          Color(0xFFF59F00), // emas tua
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(bounds),
      child: icon,
    );
    if (tooltip == null) return badge;
    return Tooltip(message: tooltip!, child: badge);
  }
}
