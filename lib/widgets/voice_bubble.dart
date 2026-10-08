import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/theme.dart';
import '../core/cache/media_disk_cache.dart';
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
  final bool isQueued;
  final bool isRead;
  const VoiceBubble({super.key, required this.path, required this.durationMs, this.isMe = false, this.timeStr = '', this.isPending = false, this.isQueued = false, this.isRead = false});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
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
    // onError di semua stream player: stream plugin (just_audio) bisa error
    // (mis. file rusak/offline) — tanpa ini error tak tertangkap merusak
    // frame/dispatcher (back mati). Cukup log; UI dibiarkan apa adanya.
    _posSub = _player.onPositionChanged.listen(
      (p) => setState(() => _pos = p),
      onError: (e) => debugPrint('[VOICE] position stream error: $e'),
    );
    _durSub = _player.onDurationChanged.listen(
      (d) => setState(() => _dur = d),
      onError: (e) => debugPrint('[VOICE] duration stream error: $e'),
    );
    _completeSub = _player.onPlayerComplete.listen(
      (_) => setState(() {
        _playing = false;
        _pos = Duration.zero;
      }),
      onError: (e) => debugPrint('[VOICE] complete stream error: $e'),
    );
    // Bubble lain mulai play → pause diri (satu suara saja di app).
    _otherSub = _VoicePlayerManager.instance.started.listen(
      (p) {
        if (p != _player && _playing) setState(() => _playing = false);
      },
      onError: (e) => debugPrint('[VOICE] manager stream error: $e'),
    );
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
      // Tap ganda saat unduh + path kosong — abaikan (anti double-download).
      if (_loading || widget.path.isEmpty) return;
      try {
        // DISK FIRST (instan): kalau voice SUDAH ada di disk, play LANGSUNG
        // tanpa spinner — biar terasa seperti GAMBAR (buka chat, tap, langsung
        // bunyi), bukan "load ulang". Spinner hanya saat benar-benar perlu
        // DOWNLOAD (cache miss).
        final f = await MediaDiskCache.instance.fileFor(widget.path);
        if (f != null) {
          _VoicePlayerManager.instance.started_(_player);
          await _player.play(DeviceFileSource(f.path));
          if (mounted) setState(() => _playing = true);
          return;
        }
        // Cache miss → tampilkan spinner selama unduh.
        setState(() => _loading = true);
        final bytes = await StoragePhotoService.instance
            .downloadBytes(widget.path);
        if (bytes == null || bytes.isEmpty) return;
        await MediaDiskCache.instance.write(widget.path, bytes);
        final f2 = await MediaDiskCache.instance.fileFor(widget.path);
        if (f2 == null || !mounted) return;
        _VoicePlayerManager.instance.started_(_player);
        await _player.play(DeviceFileSource(f2.path));
        if (mounted) setState(() => _playing = true);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  String _fmt(Duration d) {
    // remainder(60): menit wrap di 60 (perilaku lama dipertahankan).
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
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
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
                    Text(_fmt(displayDur), style: AppText.chatTime.copyWith(color: AppTheme.textSecondary)),
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
                Text(widget.timeStr, style: AppText.chatTime.copyWith(color: AppTheme.textSecondary.withValues(alpha: 0.7))),
              if (widget.isMe && widget.timeStr.isNotEmpty) ...[
                const SizedBox(width: 3),
                Icon(
                  (widget.isPending || widget.isQueued)
                      ? Icons.done
                      : Icons.done_all,
                  size: 12,
                  color: (widget.isRead &&
                          !widget.isPending &&
                          !widget.isQueued)
                      ? const Color(0xFF7EC8FF)
                      : Colors.white38,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
