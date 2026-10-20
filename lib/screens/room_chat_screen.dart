import '../core/app_foreground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../providers/riverpod/message_reaction_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/notification_prefs_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../models/chat_contact.dart';
import '../models/chat_poll.dart';
import '../models/message_model.dart';
import '../widgets/contact_picker_sheet.dart';
import '../widgets/poll/poll_composer_sheet.dart';
import '../models/user_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/chat_provider.dart' as chatRiverpod;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/connectivity_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/location_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/poll_provider.dart';
import '../core/cache/message_cache.dart';
import '../core/nav_journal.dart';
import '../core/cache/offline_outbox.dart';
import '../core/admin_gate.dart';
import '../utils.dart';
import '../main.dart';
import 'room_members_sheet.dart';
import 'group_info_screen.dart';
import 'group_media_screen.dart';
import '../widgets/app_gesture.dart';
import '../widgets/date_chip.dart';
import 'room_chat/widgets/room_widgets.dart';
import 'room_chat/widgets/room_message_bubble.dart';
import 'room_chat/widgets/voice_stage_strip.dart';
import 'room_chat/widgets/broadcast_stage.dart';
import '../widgets/photo_album_bubble.dart';
import '../widgets/reply_composer_preview.dart';
import '../widgets/message/swipe_to_reply.dart';
import 'room_chat/widgets/voice_diagnostics_sheet.dart';
import 'room_chat/widgets/room_search_sheet.dart';
import 'room_chat/widgets/room_user_action_sheet.dart';
import '../providers/riverpod/room_voice_provider.dart';
import 'private_chat/widgets/coin_gift_dialogs.dart';
import '../widgets/chat_composer_input.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/location_picker_sheet.dart';
import '../core/chat/chat_location.dart';
import '../core/chat/pending_confirm.dart';
import '../core/call/call_permissions.dart';
import '../widgets/call_permission_dialog.dart';
import '../utils/mention.dart';
import '../widgets/gift_fly_overlay.dart';
import '../widgets/room_gift_panel.dart';
import '../config/gifts.dart';
import '../providers/riverpod/theme_provider.dart';
import 'package:flutter/services.dart';
import '../widgets/message_reaction_bar.dart';
import '../mixins/chat_selection_mixin.dart';
import '../mixins/chat_outbox_mixin.dart';
import '../mixins/chat_photo_send_mixin.dart';
import '../mixins/chat_send_mixin.dart';
import '../mixins/chat_file_send_mixin.dart';
import '../mixins/chat_gallery_send_mixin.dart';
import '../mixins/chat_sticker_send_mixin.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/call_provider.dart';
import '../core/media/chat_background.dart';

part 'room_chat/room_chat_core.dart';
part 'room_chat/room_chat_room.dart';
part 'room_chat/room_chat_live.dart';
part 'room_chat/room_chat_build.dart';


// Isolate helpers untuk proses foto (sama seperti private chat).
class RoomChatScreen extends ConsumerStatefulWidget {
  final RoomModel room;
  const RoomChatScreen({super.key, required this.room});

  @override
  ConsumerState<RoomChatScreen> createState() => _RoomChatScreenState();
}

/// State + field bersama RoomChatScreen — dipakai mixin (file `part`).
abstract class _RoomChatBase extends ConsumerState<RoomChatScreen>
    with
        WidgetsBindingObserver,
        ChatOutboxMixin<RoomChatScreen>,
        ChatSelectionMixin<RoomChatScreen>,
        ChatPhotoSendMixin<RoomChatScreen>,
        ChatSendMixin<RoomChatScreen>,
        ChatFileSendMixin<RoomChatScreen>,
        ChatGallerySendMixin<RoomChatScreen>,
        ChatStickerSendMixin<RoomChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _showUsers = false;
  bool _sheetOpen = false;
  late AuthNotifier _auth;
  late chatRiverpod.ChatNotifier _chat;
  int _lastMsgCount = 0;
  PointsNotifier? _pointsProv;
  Timer? _presenceTimer;
  String? _pendingPhotoBase64;
  // ── Video (room: grup & global) — paritas private chat ──
  String? _pendingVideoPath;
  String? _pendingVideoPoster;
  int _pendingVideoMs = 0;
  bool _pendingVideoOnce = false;
  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<UserModel>> _usersStream;
  // ── Optimistic + antrean offline (centang-1 → centang-2 saat online) ──
  final List<MessageModel> _pending = [];
  final Set<String> _queuedIds = {};
  final Set<String> _confirmedPhotoIds = {};
  final Set<String> _confirmedVoiceIds = {};
  // Video (biasa & sekali-lihat) — dedupe pending vs baris server.
  final Set<String> _confirmedVideoIds = {};
  // Gema teks yang sudah memakai satu pending (lihat consumeConfirmedText).
  final Set<String> _confirmedTextIds = {};
  late final DateTime _openedAt;
  bool _connOnline = true;
  bool _flushingOutbox = false;
  // Katup pengaman back SEKALI-PAKAI (lihat PopScope di room_chat_live):
  // escape bila veto desync / handler melempar, supaya back tak pernah
  // mati permanen sampai restart.
  bool _backEscape = false;
  final _backGuard = BackVetoGuard();
  // ── Room gift (live) ──
  final _giftFly = GiftFlyController();
  // Insertion-order terjaga — cap FIFO (skip terlama) tanpa clear().
  Set<String> _seenGiftMsgIds = {};
  // ── Private room v2 ──
  String? _myRole;
  bool _muted = false;
  String? _highlightId;
  final Map<String, GlobalKey> _msgKeys = {};
  chatRiverpod.ChatMessageStream? _msgsHandle;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  List<MessageModel> _lastMsgs = const [];
  StreamSubscription<List<UserModel>>? _usersSub;
  // Strip user online persisten: tahan list terakhir saat stream blip
  // kosong; teks "tidak ada yang online" hanya setelah kosong terkonfirmasi.
  List<UserModel> _lastRoomUsers = const [];
  Timer? _roomUsersEmptyTimer;
  bool _roomUsersEmpty = false;
  String? _liveUid;
  int _pendingCount = 0;
  RoomBroadcastSession? _broadcastSession;
  Timer? _livePoll;
  bool _isGrantedBroadcast = false;
  StreamSubscription<Map<String, Map<String, int>>>? _reactionsSub;
  // ── Memo derivasi list (anti-lag slide/interaksi di room ramai) ───────────
  // `StreamBuilder.builder` ikut rebuild saat PARENT setState (pilih teks,
  // buka menu, reaksi/starred berubah, dsb), bukan cuma saat stream emit.
  // Dulu tiap rebuild itu menghitung ulang: salin list gabungan + set
  // `deletedIds` + bangun `items` (satu ChatItem per pesan) → O(N) tiap
  // interaksi → "slide berat" saat room panjang & ramai (General).
  // Sekarang derivasi (items + deletedIds) di-CACHE: dihitung ulang HANYA
  // saat (a) referensi list pesan berubah, (b) jumlah `_pending` berubah,
  // atau (c) label tanggal berubah (locale/hari). Rebuild parent lain =
  // cache hit → O(1). Pola sama seperti `private_chat_screen._deriveItems`.
  List<ChatItem> _cachedItems = const [];
  Set<String> _cachedDeletedIds = const {};
  List<MessageModel>? _cacheItemsMsgsSrc;
  int _cacheItemsPendingLen = -1;
  String _cacheItemsLocale = '';
  DateTime? _cacheItemsDay;
  // PERF (pola private chat): stream reaksi/starred bisa emit sering (tiap
  // orang reaksi di room). setState LANGSUNG = rebuild SELURUH RoomChatScreen
  // (appbar + voice strip + semua bubble) tiap emission → jank saat room
  // ramai. `_scheduleRebuild` mengoalesensi semua setState pasca-emit jadi
  // SATU per frame (scheduleFrameCallback).
  bool _rebuildScheduled = false;
  // ── Voice stage global room (audio-only, max 6 mic) ──
  RoomVoiceSession? _voiceSession;
  bool _voiceJoining = false;
  // ── Mention @ ──
  // Grup/private room → anggota (termasuk offline). Global room → user online.
  List<Map<String, dynamic>> _roomMembers = const [];
  // ── Private room v2 ──
  bool _roleChecked = false;
  /// State broadcast (live_uid + grant) sudah diketahui? Dipakai AppBar agar
  /// ikon "angkat tangan" TIDAK tampil sekilas lalu langsung berganti ke
  /// "Mulai Broadcast" (kedip) saat baru masuk grup/private room.
  bool _broadcastReady = false;
  /// Controller poll ROOM (grup & global room) — ditangkap saat init karena
  /// `ref` tak boleh dipakai di dispose.
  PollController? _roomPollCtl;
  bool _broadcastStarting = false;
  bool _stageMinimized = false;
  Offset? _pipPos;
  bool _pipResizing = false;
  Size _pipResizeStartSize = Size.zero;
  Offset _pipResizeStartLocal = Offset.zero;
  RealtimeChannel? _roomLiveChannel;
  bool _isSending = false;
  ChatLocation? _pendingLocation;
  Timer? _liveTimer;
  bool _showAttachRow = false;

  StreamSubscription<Set<String>>? _starredSub;
  Size _pipSize = const Size(140, 190);

  // Kontrak lintas-mixin.
  bool get isPrivateRoom;
  bool get canModerate;
  bool get canModerateVoice;
  bool get iAmBroadcasting;
  bool get isGrantedBroadcast;
  bool get _isNearBottom;
  Set<String> get _stripUids;
  bool get _voiceStripCoversUsers;
  List<Mention> get _mentionCandidates;
  PreferredSizeWidget _buildRoomAppBar(BuildContext context, S s);
  Widget _buildMessageList(S s, AuthNotifier auth);
  (List<ChatItem>, Set<String>) _deriveItems(
    S s,
    List<MessageModel> msgsSrc,
    List<MessageModel> all, {
    required DateTime day,
  });
  void _scrollToBottom();
  Future<void> _ensureViewerSession();
  Future<void> _refreshGrant();
  Future<void> _refreshLiveUid();
  void _syncBroadcastSession();
  Future<void> _startBroadcastSession();
  Future<void> _showVoiceDiagnostics();
  Future<void> _onSpeakerTap(String uid);
  List<Mention> _mentionAllExpansion();
  void _startPresenceHeartbeat();
  Future<void> _joinRoom();
  void _onFontScaleChanged();
  void _onVoiceChanged();
  void _onMessagesForGift(List<MessageModel> msgs);
  Future<void> _onMicTap();
  Future<void> _onMicLongPress();
  Future<void> _raiseHand();
  void _onGroupMenu(String v);
  Future<void> _openMembersSheet();
  Future<void> _onStartBroadcastTap();
  Future<void> _openRoomGiftPanel();
}

class _RoomChatScreenState extends _RoomChatBase
    with _RcCoreMx, _RcRoomMx, _RcLiveMx, _RcBuildMx {
  @override
  void dispose() {
    // Reaction-bar seleksi adalah OverlayEntry full-screen di Overlay root
    // (TIDAK ikut terbuang saat rute di-pop). Kalau user keluar saat bar
    // masih tampil tanpa lewat clearSelection, overlay YATIM menutupi layar
    // di bawahnya → tap tertelan. Cabut di sini (private chat sudah).
    hideActionBar();
    // Realtime suara poll room hanya hidup selama layar ini terbuka.
    _roomPollCtl?.detachChat();
    super.dispose();
  }
}
