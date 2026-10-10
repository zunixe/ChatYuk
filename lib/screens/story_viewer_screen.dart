import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../models/story_model.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/chat_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/storage_provider.dart';
import '../../../providers/riverpod/story_provider.dart';
import '../../../core/cache/media_disk_cache.dart';
import '../../../utils.dart';
import '../../../widgets/story_text_overlay.dart';
import 'story_viewer/story_viewer_widgets.dart';
import '../../../widgets/story_viewer_avatar.dart';
import '../../../core/perf/perf_probe.dart';
import 'package:share_plus/share_plus.dart';

part 'story_viewer/story_viewer_init.dart';
part 'story_viewer/story_viewer_nav.dart';
part 'story_viewer/story_viewer_build.dart';

const Duration _slideDuration = Duration(seconds: 5);
const int _preloadAhead = 2;

/// Cache RAM bytes slide (path → image) — bertahan antar slide/penonton
/// selama sesi viewer supaya mundur/maju tidak download ulang.
///
/// PERF: dibatasi kecil (bukan 60) karena tiap byte slide bisa ~5MB
/// (960x1440). 8 entri cukup untuk window maju/mundur tanpa membanjiri
/// RAM (8 x ~5MB ≈ 40MB). Cap lama 60 ≈ 300MB → risiko OOM di HP low-end.
final Map<String, Uint8List> _slideBytesCache = {};
const int _kSlideBytesCacheMax = 8;

/// Index slide yang perlu dimuat untuk window preload: [start-1 .. start+ahead],
/// di-clamp ke [0, total-1]. Top-level & murni supaya bisa di-unit-test tanpa
/// membangun widget/halaman.
@visibleForTesting
List<int> storyPreloadWindow(int start, int total, int ahead) {
  if (total <= 0) return const [];
  final s = (start - 1).clamp(0, total - 1);
  final e = (start + ahead).clamp(0, total - 1);
  return [for (var i = s; i <= e; i++) i];
}

/// Apakah entri terlama harus dibuang setelah insert (size > max)? Murni &
/// top-level supaya kontrak cap cache bisa dikunci tanpa widget.
@visibleForTesting
bool slideCacheShouldEvict(int size, {int max = _kSlideBytesCacheMax}) =>
    size > max;

/// Viewer story fullscreen (gaya IG):
/// - Progress segmented atas (1 segmen per slide), auto-advance 5 detik.
/// - Hold = pause. Tap kanan/kiri = next/prev slide. Swipe vertikal = tutup.
/// - Horizontal PageView antar penonton (urutan tray).
/// - Slide milik sendiri: tombol hapus + tombol daftar penonton.
/// - Slide orang lain: foto SEUKURAN punya pembuat story (bisa digeser
///   ke atas/bawah) + kolom balas, like, dan share DI DALAM foto.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryTrayItem> items;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

/// State + field bersama StoryViewerScreen — dipakai mixin (file `part`).
abstract class _StoryBase extends ConsumerState<StoryViewerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late int _person;
  late AnimationController _progress;
  List<StorySlide> _slides = [];
  int _slide = 0;
  bool _loading = true;
  // Fetch gagal padahal tray bilang ada isi (jaringan flaky / timeout) —
  // tampilkan UI coba-lagi, bukan "belum ada story".
  bool _loadError = false;
  bool _paused = false;
  // True selagi user menggeser PageView antar-person (horizontal). Dipakai
  // untuk menahan auto-advance slide supaya tidak bertabrakan dengan swipe.
  bool _pageDragging = false;
  // Path gambar pembuka tiap person (index → path) — hasil preload tetangga.
  // Dipakai agar halaman tetangga tidak tampil hitam saat swipe: kalau path-nya
  // sudah punya byte di `_localImg`, render sebagai latar halaman tetangga.
  final Map<int, String> _neighborFirstPath = {};
  final Map<String, Uint8List?> _localImg = {};

  // Video pendek: satu controller aktif (slide aktif saja — hemat memori).
  // File mp4 di temp (bukan RAM cache gambar).
  VideoPlayerController? _videoCtrl;
  String _videoSlideId = '';

  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sendingReply = false;
  bool _sharingStory = false;
  // Tokoh yang sudah dikirimi notifikasi "balasan terkirim" (sekali).
  final Set<String> _replyNotified = {};

  // Slide yang benar-benar ditonton → dikirim SEKALI (bulk) saat keluar
  // viewer / ganti author. Dulu 1 RPC per slide.
  final List<String> _seenIds = [];
  final Set<String> _seenDedup = {};
  // Provider dicache saat init — JANGAN context.read di dispose/_flushSeen.
  // unmount() framework men-defunct-kan element DULU baru memanggil
  // dispose(), sehingga lookup ancestor dari context tidak bisa diandalkan
  // (flush saat keluar viewer diam-diam gagal → penonton story selalu 0).
  StoryNotifier? _storyProv;
  // Status admin dicache saat init — dipakai ghost-mode (admin tidak tercatat
  // sebagai penonton story orang). Jangan context.read di _flushSeen/dispose.
  bool _isAdminCached = false;
  // Sheet penonton sedang terbuka/loading — tap ikon mata berkali-kali
  // tidak boleh menumpuk sheet (laporan admin: "klik banyak, nampil banyak").
  bool _viewersOpen = false;
  // Sisa waktu slide saat app di-background — lanjut dari sisa,
  // bukan mulai ulang 5 detik penuh.
  Duration? _remainingOnResume;

  // Kontrak lintas-mixin.
  StoryTrayItem get _item;
  StorySlide? get _current;
  bool get _own;
  bool get _isAdmin;
  Future<Uint8List?> _bytes(String path);
  void _goToSlide(int i);
  Future<void> _loadPerson();
  void _markSeen();
  void _next();
  void _prev();
  void _pause();
  void _resume();
  Future<void> _preloadAdjacent();
  Future<void> _reloadCurrentIfMissing();
  void _startTimer({Duration? duration});
  void _startTimerIfImage();
  Future<void> _syncVideo();
  Future<void> _confirmDelete();
  Future<void> _showViewers();
}

class _StoryViewerScreenState extends _StoryBase
    with _StoryInitMx, _StoryNavMx, _StoryBuildMx {}
