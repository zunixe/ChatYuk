import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/call_provider.dart';
import '../providers/riverpod/chat_provider.dart' as chatRiverpod;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/connectivity_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/location_provider.dart';
import '../providers/riverpod/points_provider.dart';
import 'story_camera_capture_screen.dart';
import '../providers/riverpod/social_provider.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import '../core/cache/post_photo_cache.dart';
import '../core/cache/offline_outbox.dart';
import '../core/chat/read_receipt.dart';
import '../core/chat/pending_confirm.dart';
import '../core/nav_guard.dart';
import '../core/nav_journal.dart';
import '../core/chat/chat_location.dart';
import '../core/media/chat_background.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/message/image_decode_core.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/video_prefetch.dart';
import '../widgets/date_chip.dart';
import '../utils/mention.dart';
import '../widgets/person_avatar.dart';
import '../widgets/verified_badge.dart';
import '../widgets/chat_call_overlay.dart';
import '../widgets/chat_ui_shared.dart';
import '../main.dart';
import 'call_screen.dart';
import 'user_info_screen.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/call_permission_dialog.dart';
import '../core/call/call_permissions.dart';
import '../utils.dart';
import '../mixins/chat_selection_mixin.dart';
import 'private_chat/widgets/coin_gift_dialogs.dart';
import '../mixins/chat_photo_send_mixin.dart';
import '../mixins/chat_send_mixin.dart';
import '../widgets/chat_composer_input.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/location_picker_sheet.dart';
import '../mixins/chat_outbox_mixin.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/message_reaction_provider.dart';
import '../providers/riverpod/privacy_provider.dart';

part 'private_chat/private_chat_open_timing.dart';
part 'private_chat/private_chat_core.dart';
part 'private_chat/private_chat_chat.dart';
part 'private_chat/private_chat_chat2.dart';
part 'private_chat/private_chat_media.dart';
part 'private_chat/private_chat_build.dart';
part 'private_chat/private_chat_layout_widgets.dart';

const int _maxImageFetches = 3;
const _confirmedCap = 200;

/// Warna latar Scaffold private chat — WAJIB opaque (bukan transparent).
///
/// Route transparan bocor ke halaman DI BAWAH private chat selama transisi
/// push/pop (mis. buka profil dari avatar) → sekejap terlihat daftar
/// chat/online + avatar inisial. bgScreen identik visual dengan Container bg
/// di body, jadi tampilan tak berubah; hanya menutup kebocoran transisi.
/// Dikunci sebagai konstanta supaya invarian ini bisa di-unit-test.
@visibleForTesting
final Color privateChatScaffoldBg = AppTheme.bgScreen;

class PrivateChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  final String otherGender;
  final String otherCountry;
  final String otherCity;
  final int otherAge;
  final bool otherRegistered;
  final bool initialOtherDeleted;

  /// Seed avatar header (base64 dari list) — anti-kedip inisial→foto.
  final String initialAvatarB64;
  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherName,
    required this.otherUid,
    this.otherGender = '',
    this.otherCountry = '',
    this.otherCity = '',
    this.otherAge = 0,
    this.otherRegistered = false,
    this.initialOtherDeleted = false,
    this.initialAvatarB64 = '',
  });

  @override
  ConsumerState<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

/// Id pesan yang teksnya mengandung [query] (case-insensitive),
/// urut TERBARU dulu — untuk navigasi search chat ala WhatsApp.
/// Murni (tanpa context) supaya bisa di-unit-test.
List<String> searchChatMatches(List<MessageModel> msgs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <String>[];
  for (var i = msgs.length - 1; i >= 0 && out.length < 300; i--) {
    final m = msgs[i];
    if (m.isDeleted) continue;
    if (m.text.isNotEmpty && m.text.toLowerCase().contains(q)) {
      out.add(m.id);
    }
  }
  return out;
}

/// State + field bersama PrivateChatScreen — dipakai mixin (file `part`).
abstract class _PrivateChatBase extends ConsumerState<PrivateChatScreen>
    with
        ChatOutboxMixin<PrivateChatScreen>,
        ChatSelectionMixin<PrivateChatScreen>,
        ChatPhotoSendMixin<PrivateChatScreen>,
        ChatSendMixin<PrivateChatScreen>,
        _PcOpenTimingMx {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  bool _showAttachRow = false;
  // ── Search dalam percakapan (ala WhatsApp) ──
  bool _searching = false;
  // Katup pengaman back SEKALI-PAKAI (lihat PopScope di private_chat_core):
  // bila veto terpicu padahal tak ada yang menahan (state desync) atau
  // handler melempar, flag ini dibuka lalu pop() dipanggil — tanpa flag,
  // PopScope juga mem-veto pop programatik → back mati permanen.
  bool _backEscape = false;
  final _backGuard = BackVetoGuard();

  /// Nilai `otherLastRead` untuk subtree list (centang-2) — di-drive
  /// `ref.listen(chatHeaderProvider)` supaya HANYA list yang rebuild.
  final ValueNotifier<DateTime?> _lastReadNotifier = ValueNotifier(null);
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';
  List<String> _matchIds = const [];
  Set<String> _matchSet = const {};
  int _matchIndex = 0;
  // GlobalKey per pesan cocok — untuk lompat scroll ke hasil.
  // Hanya pesan cocok yang pakai ini (bukan ValueKey), sisanya tidak
  // tersentuh supaya state bubble lain (mis. voice) tidak ikut reset.
  final Map<String, GlobalKey> _searchKeys = {};
  int _searchJumpTries = 0;

  /// Id pesan yang baru dihapus secara lokal — jaring supaya UI langsung
  /// menyembunyikannya walau stream realtime belum sempat memperbarui.
  final Set<String> _localDeletedIds = {};
  ChatLocation? _pendingLocation;
  Timer? _liveTimer;
  int? _viewTimerSecs;
  // T1c/T3a: stream+timing pindah ke private_chat_open_timing.dart (part).
  late Stream<List<chatRiverpod.PrivateChatInfo>> _chatInfoStream;
  bool _loadingOlder = false;
  // ── AUTO-LOAD image deferred ──
  // "harusnya muncul semua image yang dikirim user" — image pesan lama
  // (di luar window 50) di-fetch OTOMATIS saat emit masuk, tanpa tap.
  // Guard: in-flight (jangan dobel) + cooldown 10s per id (emit berikut
  // tidak spam retry kalau fetch gagal; tap manual tetap bisa kapan pun).
  final Set<String> _imgInFlight = {};
  final List<String> _imgQueue = [];
  final Set<String> _imgQueued = {};
  final Map<String, DateTime> _imgLastAttempt = {};
  // Penanda id pesan yang SUDAH pernah dipindai auto-load — supaya pemindaian
  // tak mengulang SELURUH list tiap emit (dulu O(N) per emit → berat saat
  // chat panjang / scroll). Hanya pesan BARU yang dicek.
  final Set<String> _imgScannedIds = {};
  // ── HEADER (Prioritas 4) ─────────────────────────────────────────────
  // Dulu 9 field ini di State → tiap update = setState() ROOT layar (rebuild
  // AppBar+Scaffold+PopScope+list). Sekarang di provider per-chat
  // (`chatHeaderProvider`) → hanya subtree yang watch yang rebuild.
  // `_hdr` = baca sekali per build; `_patchHdr` = tulis (skip bila identik).
  chatRiverpod.ChatHeader get _hdr =>
      ref.read(chatRiverpod.chatHeaderProvider(widget.chatId));
  void _patchHdr(chatRiverpod.ChatHeader Function(chatRiverpod.ChatHeader) f) =>
      ref
          .read(chatRiverpod.chatHeaderProvider(widget.chatId).notifier)
          .patch(f);
  DateTime? _lastIncomingSeen;
  StreamSubscription<List<chatRiverpod.PrivateChatInfo>>? _chatInfoSub;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  StreamSubscription<String>? _statusSub;
  bool _wasBlocked = false;
  final List<MessageModel> _pending = [];
  // Antrean offline: id pending yang belum terkirim ke server (centang-1).
  // Terkirim saat koneksi pulih → centang-2 (biru bila dibaca).
  final Set<String> _queuedIds = {};
  bool _connOnline = true;
  bool _flushingOutbox = false;
  // LayerLink per pesan — dipakai anchor bar reaksi ala WA tepat di atas
  // bubble. CompositedTransformFollower ikut mengikuti bubble saat list
  // di-scroll, jadi bar reaksi tidak "menempel" di layar.
  // Mode seleksi ala WA: tahan pesan → header jadi toolbar
  // (balas/bintang/hapus/teruskan), bar emoji mengambang di atas bubble.
  StreamSubscription<Map<String, Map<String, int>>>? _reactionsSub;
  StreamSubscription<Set<String>>? _starredSub;
  // Call video dalam chat: overlay panel draggable di atas layar chat.
  bool _callExpanded = false;
  // Foto yang sudah dikonfirmasi server (id pesan server) — dipakai dedupe
  // FIFO karena imageData di stream berupa thumbnail, bukan base64 penuh.
  // Hanya foto dengan timestamp setelah screen dibuka yang diproses, supaya
  // history lama tidak ikut menghapus pending.
  final Set<String> _confirmedPhotoIds = {};
  final Set<String> _confirmedVoiceIds = {};
  final Set<String> _confirmedVideoIds = {};
  // Gema teks yang sudah memakai satu pending (lihat consumeConfirmedText).
  final Set<String> _confirmedTextIds = {};
  late final DateTime _openedAt;
  // Batas id konfirmasi yang disimpan. Set ini HANYA dipakai untuk dedupe
  // FIFO jangka-pendek; menahannya tanpa batas sepanjang sesi = memori naik
  // terus (GC pressure = lag). LinkedHashSet menjaga urutan insert, jadi kita
  // buang yang paling lama saat lewat cap.
  // ── Memo derivasi list (anti-lag ngetik/scroll/buka) ──────────────────────
  // `StreamBuilder.builder` ikut rebuild saat PARENT setState (ngetik, pilih
  // teks, buka menu, dsb), bukan cuma saat stream emit. Dulu tiap rebuild itu
  // menghitung ulang: salin list, set `deletedIds`, `searchChatMatches`, dan
  // bangun `items` (satu ChatItem per pesan) → O(N) tiap ketikan → "ngetik
  // ngelag" + scroll berat saat chat panjang.
  //
  // Sekarang derivasi (deletedIds + items) di-CACHE: dihitung ulang HANYA
  // saat (a) referensi list pesan berubah, (b) jumlah `_pending` berubah,
  // atau (c) label tanggal berubah (locale/hari). Rebuild parent lain = cache
  // hit → O(1).
  List<ChatItem> _cachedItems = const [];
  Set<String> _cachedDeletedIds = const {};
  int _cacheItemsPendingLen = -1;
  // A1: revisi isi pesan (dari ChatStreamSession) — kunci cache stabil,
  // ganti `identical(msgsSrc)` yang selalu miss (stream emit list baru).
  int _cacheItemsRevision = -2;
  String _cacheItemsLocale = '';
  DateTime? _cacheItemsDay;
  CallPhase? _prevCallPhase;
  // ── Koalesensi rebuild pekerjaan pasca-buka (FIX jank "buka chat") ──
  // Saat buka chat, beberapa timer (220ms reaksi/starred, 280ms channel +
  // profil lawan) masing-masing memicu setState → layar penuh di-build
  // 2-3× dalam ~300ms (terukur di logcat: dua [CHAT-BUILD] hanya 17ms
  // terpisah). Helper ini menggabungkan rebuild yang jatuh di frame yang
  // sama jadi SATU setState — mengurangi jumlah build penuh tanpa mengubah
  // kapan data muncul (tetap menyusul setelah transisi).
  bool _rebuildScheduled = false;

  /// Signature state call terakhir yang memicu rebuild — dipakai untuk
  /// memfilter rebuild `_onCallChanged` (lihat penjelasan di sana).
  String _prevCallSig = '_none';
  bool _expandingCall = false;
  DateTime? _lastSeenFetchedAt;
  bool _isSending = false;
  Timer? _pendingConfirmTimer;
  StreamSubscription<(String, int)>? _typingSub;
  Timer? _typingClearTimer;
  // Timer penunda kerja non-kritis saat buka chat (reaksi/starred/status/
  // typing/profil) — supaya tidak jatuh bersamaan animasi transisi. Di-cancel
  // di dispose agar kotak buka-tutup cepat tak menyisakan subscribe nyangkut.
  Timer? _openWorkTimer;
  // Tahap kedua: channel realtime (status/typing) + RPC profil — dipisah dari
  // _openWorkTimer supaya handshake channel tak "ketahan" di frame transisi.
  Timer? _channelWorkTimer;
  DateTime _lastTypingSent = DateTime(2000);

  /// Status bubble typing/recording lawan — 0=off, 1=typing, 2=recording.
  /// ValueNotifier (bukan setState) supaya perubahan typing TIDAK me-rebuild
  /// SELURUH layar CHAT maupun seluruh ListView pesan — dulu ValueListenableBuilder
  /// membungkus SELURUH daftar (items O(n) + semua MessageBubble + avatar)
  /// sehingga tiap pulse typing = list ke-load semua ulang = "ngetik jeda".
  /// Sekarang HANYA bubble typing (item index 0) yang di-drive notifier ini;
  /// list & bubble lain tidak tersentuh.
  final ValueNotifier<int> _typingState = ValueNotifier<int>(0);
  // Id + waktu pesan terakhir dari lawan bicara — dipakai mematikan
  // bubble typing begitu balasan masuk (otoritatif, anti stuck) dan
  // mengabaikan pulse basi dari invokasi lama.
  String? _lastPartnerMsgId;
  DateTime? _lastPartnerMsgTime;
  String? _pendingPhotoBase64;
  // ── Preview VIDEO (private chat) ──
  String? _pendingVideoPath;
  String? _pendingVideoPoster;
  int _pendingVideoMs = 0;
  // Sekali lihat (bukan timer detik — video durasinya = panjang video).
  bool _pendingVideoOnce = false;
  bool _newChatBonusClaimed = false;
  bool _bonusToastScheduled = false;

  // Kontrak lintas-mixin.
  Widget _buildBottomBar(BuildContext context, S s, bool pointsEnabled);
  AppBar _buildSearchAppBar();
  void _drainImageQueue();
  Future<void> _fetchImageQueued(String id);
  void _hideTyping();
  void _onCallChanged();
  void _scrollToMatch(int dir);
  Future<void> _sendCoins(int amount);
  Future<void> _sendGift(String giftId, String name, int coins);
  void _startLiveLocationUpdates(String messageId, ChatLocation initial);
  void _trimConfirmed(Set<String> ids);
  Future<void> voiceFinishRecording(String path, int recordedMs);
  bool get _showCallOverlay;
  void _expandCall();
  void _sendRecordingSignal();
  void _sendTypingSignal();

  void _closeSearch();
  void _openSearch();
  void _onSearchChanged(String v);
  void _gotoMatch(int dir);
  (List<ChatItem>, Set<String>) _deriveItems(
    S s,
    List<MessageModel> msgsSrc,
    List<MessageModel> all, {
    required DateTime day,
  });
  void _autoLoadMissingImages(List<MessageModel> msgs);
  void _primeReadFromCache();
  void _primeStarredFromCache();
  void _loadCachedRead();
  void _persistRead(DateTime t);
  void _scheduleRebuild();
  void _scrollToBottom();
  void _maybeNewChatBonus();
  void _schedulePendingConfirmFallback();
  void _subscribeStatus();
  void _subscribeTyping();
  Future<void> _startCall(BuildContext ctx, String callType, CallMode mode);
  void _showReportDialog();
  Future<void> _sendLocation();
  void _onFontScaleChanged();
  void _onScrollToLoadOlder();
  List<Mention> get _mentionCandidates;
}

class _PrivateChatScreenState extends _PrivateChatBase
    with _PcCoreMx, _PcChatMx, _PcChat2Mx, _PcMediaMx, _PcBuildMx {}
