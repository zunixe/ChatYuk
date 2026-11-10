import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../config/gifts.dart';
import '../config/theme.dart';

/// Overlay animasi gift BESAR di tengah layar chat: Lottie per-gift +
/// SFX per-gift, main sekali (~2,4 dtk) lalu hilang. IgnorePointer —
/// tidak menghalangi gesture chat. Pasang sebagai Stack child paling atas.
///
/// Sumber animasi: dibuat via LottieFiles Creator (assets/gifts/gift_*.json).
/// SFX: synth WAV per gift (assets/audio/gifts/gift_*.wav).
class GiftPlayOverlay extends StatefulWidget {
  const GiftPlayOverlay({super.key, required this.controller});

  final GiftPlayController controller;

  @override
  State<GiftPlayOverlay> createState() => _GiftPlayOverlayState();
}

/// Controller: screen memanggil [push] saat gift terkirim/diterima.
/// Gift terbaru menggantikan yang sedang tampil (momen besar, 1 per layar).
class GiftPlayController extends ChangeNotifier {
  GiftPlayItem? _current;
  int _seq = 0;

  GiftPlayItem? get current => _current;

  /// [label] sudah resolve lokal (mis. "agoy · Mawar") — dibangun caller.
  void push(GiftItem gift, String label) {
    _seq++;
    _current = GiftPlayItem(_seq, gift, label);
    notifyListeners();

    // Auto-hapus setelah durasi animasi + fade out.
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (_current?.id == _seq) {
        _current = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _current = null;
    super.dispose();
  }
}

class GiftPlayItem {
  final int id;
  final GiftItem gift;
  final String label;
  GiftPlayItem(this.id, this.gift, this.label);
}

class _GiftPlayOverlayState extends State<GiftPlayOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.controller.current;
    if (item == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dim lembut supaya animasi menonjol dari isi chat.
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: _GiftPlayCard(key: ValueKey(item.id), item: item),
          ),
        ],
      ),
    );
  }
}

class _GiftPlayCard extends StatefulWidget {
  const _GiftPlayCard({super.key, required this.item});

  final GiftPlayItem item;

  @override
  State<_GiftPlayCard> createState() => _GiftPlayCardState();
}

class _GiftPlayCardState extends State<_GiftPlayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 8),
      TweenSequenceItem(tween: ConstantTween(1), weight: 78),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 14),
    ]).animate(_ctrl);
    _ctrl.forward();
    // SFX per gift — player sekali pakai, di-dispose saat selesai.
    try {
      final p = AudioPlayer();
      _player = p;
      unawaited(
        p
            .play(AssetSource('audio/gifts/gift_${widget.item.gift.id}.wav'))
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    unawaited(_player?.dispose() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return FadeTransition(
      opacity: _fade,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset(
            'assets/gifts/gift_${widget.item.gift.id}.json',
            width: w * 0.62,
            height: w * 0.62,
            repeat: false,
            animate: true,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.item.label,
              style: AppText.label.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
