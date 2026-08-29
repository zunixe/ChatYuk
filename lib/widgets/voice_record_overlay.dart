import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class VoiceRecordOverlay extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSend;
  const VoiceRecordOverlay({super.key, required this.onCancel, required this.onSend});

  @override
  State<VoiceRecordOverlay> createState() => VoiceRecordOverlayState();
}

class VoiceRecordOverlayState extends State<VoiceRecordOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      if (_seconds >= 60) widget.onSend();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _fmt => '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)]),
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.3).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Text(_fmt, style: AppText.bodyStrong.copyWith(color: Colors.red)),
          const SizedBox(width: 12),
          Expanded(child: Row(children: List.generate(20, (i) => Expanded(child: Container(margin: EdgeInsets.symmetric(horizontal: 1), height: 6 + (i % 4) * 4.0, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))))))),
          const SizedBox(width: 12),
          GestureDetector(onTap: widget.onCancel, child: Icon(Icons.close, color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          GestureDetector(onTap: widget.onSend, child: Container(padding: EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle), child: Icon(Icons.send, color: Colors.white, size: 18))),
        ],
      ),
    );
  }
}
