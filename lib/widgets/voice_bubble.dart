import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/theme.dart';
import '../services/media_disk_cache.dart';
import '../services/storage_photo_service.dart';

/// Manager player GLOBAL — hanya SATU voice yang playing di seluruh app.
/// Dulu: tiap bubble punya player sendiri → dua voice bisa play paralel
/// (audio bercampur). Play bubble baru → bubble lama otomatis pause.
class _VoicePlayerManager {
  _VoicePlayerManager._();
  static final instance = _VoicePlayerManager._();

  AudioPlayer? _current;
  final _controller = StreamController<AudioPlayer>.broadcast();

  /// Stream: player yang BARU saja mulai play (listener lama pause diri).
  Stream<AudioPlayer> get started => _controller.stream;

  void started_(AudioPlayer p) {
    final old = _current;
    _current = p;
    if (old != null && old != p) old.pause();
    _controller.add(p);
  }
}

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
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _otherSub;

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: widget.durationMs);
    _posSub = _player.onPositionChanged.listen((p) => setState(() => _pos = p));
    _durSub = _player.onDurationChanged.listen((d) => setState(() => _dur = d));
    _completeSub = _player.onPlayerComplete.listen((_) => setState(() { _playing = false; _pos = Duration.zero; }));
    // Bubble lain mulai play → pause diri (satu suara saja di app).
    _otherSub = _VoicePlayerManager.instance.started.listen((p) {
      if (p != _player && _playing) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _otherSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      try {
        // DISK FIRST: voice di-cache lokal (per path) — play pertama
        // download sekali, play berikutnya & sesi berikutnya dari lokal.
        final disk = await MediaDiskCache.instance.read(widget.path);
        if (disk != null && disk.isNotEmpty) {
          final f = await MediaDiskCache.instance.fileFor(widget.path);
          if (f != null) {
            _VoicePlayerManager.instance.started_(_player);
            await _player.play(DeviceFileSource(f.path));
            setState(() => _playing = true);
            return;
          }
        }
        // Belum ada di disk → download sekali, tulis disk, play file.
        final bytes = await StoragePhotoService.instance
            .downloadBytes(widget.path);
        if (bytes == null || bytes.isEmpty) return;
        await MediaDiskCache.instance.write(widget.path, bytes);
        final f = await MediaDiskCache.instance.fileFor(widget.path);
        if (f == null) return;
        _VoicePlayerManager.instance.started_(_player);
        await _player.play(DeviceFileSource(f.path));
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      // Transparan — biar menyatu dengan bubble chat, hanya tombol bulat yang terlihat
      color: Colors.transparent,
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
                  alignment: Alignment.center,
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
