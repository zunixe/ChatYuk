import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../core/media/native_image.dart';
import '../core/nav_guard.dart';
import '../models/active_call_model.dart';
import '../models/message_model.dart';
import '../providers/admin_provider.dart';
import '../widgets/gender_avatar.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/cache/photo_cache.dart';
import '../core/cache/message_cache.dart';
import '../utils.dart';
import '../widgets/admin_call_watch_overlay.dart';
import '../widgets/date_chip.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/voice_bubble.dart';
import 'admin_chat/widgets/audio_listen_chip.dart';
import '../providers/riverpod/theme_provider.dart';
import '../config/strings_admin.dart';
import 'user_info_screen.dart';
import '../providers/riverpod/admin_provider.dart';
export 'admin_chat_view_helpers.dart';
import 'admin_chat_view_helpers.dart';

part 'admin_chat_view/admin_chat_view_watch.dart';
part 'admin_chat_view/admin_chat_view_data.dart';
part 'admin_chat_view/admin_chat_view_build.dart';

const int _maxPhotoLoads = 3;
const int _photoAutoLoadMax = 12;

/// Sisi kiri (lawan bicara) monitor chat — fungsi MURNI agar prioritas
/// terkunci test (`test/admin_chat_leftuid_test.dart`). Harus STABIL
/// (tidak ikut urutan kedatangan) supaya bubble tidak berpindah sisi.
///
/// Urutan sumber (PENTING — jangan dibalik):
/// 1) chatId split 'uid1_uid2' (format 1:1, uid SORTED → abadi, tidak
///    berubah saat nama di-rename / cache vs server beda urutan map).
/// 2) participantOrder (dari list screen) — hanya cadangan.
class AdminChatViewScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatLabel;

  /// Urutan peserta sesuai judul (nama pertama = bubble kiri, kedua = kanan).
  final List<String> participantOrder;

  /// uid → nama peserta (untuk avatar 2 sisi di header monitor).
  final Map<String, String> participantNames;

  /// uid → gender peserta (untuk ring warna avatar tanpa foto di header,
  /// sama seperti daftar "Pengguna Online" & kartu monitor).
  final Map<String, String> participantGenders;
  const AdminChatViewScreen({
    super.key,
    required this.chatId,
    required this.chatLabel,
    this.participantOrder = const [],
    this.participantNames = const {},
    this.participantGenders = const {},
  });

  @override
  ConsumerState<AdminChatViewScreen> createState() =>
      _AdminChatViewScreenState();
}

/// State + field bersama AdminChatViewScreen — dipakai mixin (file `part`).
abstract class _AdminBase extends ConsumerState<AdminChatViewScreen>
    with WidgetsBindingObserver {
  List<MessageModel> _msgs = [];
  // True setelah SQLite/server pertama selesai — supaya empty-state TIDAK
  // berkedip muncul sesaat sebelum pesan terisi.
  bool _firstResolved = false;
  // Masih ada pesan lama untuk dimuat (pagination) — state lokal supaya
  // build tak perlu watch AdminProvider.
  bool _hasMore = false;
  // True HANYA saat load-more benar-benar berjalan. Footer spinner dulu
  // muncul selama `_hasMore` true (bahkan saat idle) → terlihat "muter" terus
  // tiap buka chat. Sekarang spinner hanya saat fetch halaman lama jalan.
  bool _loadingMore = false;

  /// True bila pemuatan pesan gagal. UI memakai teks ramah `s.adminChatError`
  /// — detail exception hanya ke dlog, tidak pernah ke layar.
  bool _error = false;
  String? _leftUid;
  String get _chatKey => cacheKeyFor(widget.chatId);
  // last_read_at kedua peserta (uid → waktu) — dasar hitung centang-2
  // sama seperti chat asli (bukan isMe).
  Map<String, DateTime> _lastRead = {};
  Timer? _pollTimer;
  RealtimeChannel? _channel;

  /// Client pemilik [\_channel] — untuk `removeChannel` saat dispose (buang
  /// channel sepenuhnya, cegah bocor saat buka-tutup chat berulang).
  SupabaseClient? _channelClient;
  final _photoLoading = <String>{};
  // Antrean foto: maks 3 unduhan bersamaan + cooldown 10 dtk per id
  // (pola sama seperti private chat). Tanpa ini tiap foto menembak RPC +
  // download + isolate thumbnail SEKALIGUS → berebut bandwidth/CPU dan
  // semua spinner foto muter lama.
  final List<String> _photoQueue = [];
  final Set<String> _photoQueued = {};
  final Map<String, DateTime> _photoLastAttempt = {};
  int _photoActive = 0;

  /// Batas jumlah foto yang dipra-muat otomatis (dari pesan TERBARU). Sisa
  /// foto dimuat saat discroll/bubble-nya muncul — buka chat dengan ratusan
  /// pesan berisi foto tidak lagi menembak puluhan unduhan sekaligus.
  /// Peta id → indeks pada `_msgs` (dibangun ulang saat `_msgs` berubah) —
  /// menggantikan `indexWhere` O(n) yang membuat path foto O(n²).
  Map<String, int> _msgIndexById = const {};
  void _rebuildMsgIndex() {
    final m = <String, int>{};
    for (var i = 0; i < _msgs.length; i++) {
      m[_msgs[i].id] = i;
    }
    _msgIndexById = m;
  }

  final _scrollCtrl = ScrollController();
  final Map<String, LayerLink> _msgLinks = {};
  LayerLink _linkFor(String id) => _msgLinks.putIfAbsent(id, () => LayerLink());

  // ── Pantau call aktif di chat ini ──
  // WatchSession hidup hanya selama layar ini terbuka; dispose → stop()
  // memutus semua koneksi (admin berhenti mendengar/melihat).
  Timer? _callTimer;
  WatchSession? _watch;
  bool _startingWatch = false;
  // Poll 5 dtk bisa tumpang tindih saat RPC lambat.
  bool _polling = false;
  int _pollCount = 0;
  List<ChatItem>? _itemsCache;
  bool _thumbBatchRunning = false;
  Timer? _photoSetStateTimer;
  // Kontrak lintas-mixin.
  List<ChatItem> get _items;
  Future<void> _fetch({bool force = false});
  Future<void> _poll();
  bool _applyMessages();
  void _invalidateItems();
  // ignore: unused_element_parameter
  void _ensureLeftUid([List<String>? senders]);
  String? _computeLeftUid(List<String> senders);
  String? _recipientOf(String senderId);
  void _subscribeRealtime();
  Widget _headerAvatarPair();
  void _expandWatch();
  Future<void> _retryImage(String msgId);
  Future<void> _copyMessage(MessageModel msg);
}

class _AdminChatViewScreenState extends _AdminBase
    with _AcWatchMx, _AcDataMx, _AcBuildMx {}
