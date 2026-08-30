import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/theme.dart';
import '../services/storage_photo_service.dart';

class VoiceBubble extends StatefulWidget {
  final String path; // storage path voice/...
  final int durationMs;
  final bool isMe;
  final String timeStr;
  final bool isPending;
  final bool isRead;
  const VoiceBubble({super.key, required this.path, required this.durationMs, this.isMe = false, this.timeStr = '', this.isPending = false, this.isRead = false});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  String? _url;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: widget.durationMs);
    _posSub = _player.onPositionChanged.listen((p) => setState(() => _pos = p));
    _durSub = _player.onDurationChanged.listen((d) => setState(() => _dur = d));
    _completeSub = _player.onPlayerComplete.listen((_) => setState(() { _playing = false; _pos = Duration.zero; }));
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      try {
        String? url = _url;
        if (url == null) {
          // Download bytes then play via temp file or via storage public URL
          // For now, get public URL from Supabase storage
          // Use StoragePhotoService to get download URL via public URL
          // Simplify: download to bytes and play via file
          final bytes = await StoragePhotoService.instance.downloadBytes(widget.path);
          if (bytes == null) return;
          // audioplayers can play from bytes via file - write to temp
          // For simplicity, use base64 data uri
          // Instead, use public URL if bucket is public
          // chat-photos is public, so construct URL
          url = 'https://fohcucyyejdryryoxitm.supabase.co/storage/v1/object/public/chat-photos/${widget.path}';
          _url = url;
        }
        await _player.play(UrlSource(url));
        setState(() => _playing = true);
      } catch (_) {}
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _dur.inMilliseconds;
    final displayDur = _playing ? _dur - _pos : Duration(milliseconds: widget.durationMs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: RoundSliderThumbShape(enabledThumbRadius: 10)),
                      child: Slider(value: progress.clamp(0, 1), min: 0, max: 1, onChanged: (v) async {
                        final seek = Duration(milliseconds: (_dur.inMilliseconds * v).toInt());
                        await _player.seek(seek);
                      }, activeColor: AppTheme.primary, inactiveColor: AppTheme.divider),
                    ),
                    Text(_fmt(displayDur), style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.timeStr.isNotEmpty)
                Text(widget.timeStr, style: AppText.micro.copyWith(color: AppTheme.textSecondary.withValues(alpha: 0.7))),
              if (widget.isMe && widget.timeStr.isNotEmpty) ...[
                const SizedBox(width: 3),
                Icon(
                  widget.isPending ? Icons.done : (widget.isRead ? Icons.done_all : Icons.done),
                  size: 12,
                  color: widget.isPending ? Colors.white38 : (widget.isRead ? const Color(0xFF7EC8FF) : Colors.white38),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
