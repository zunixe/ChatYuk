import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../models/active_call_model.dart';
import '../models/message_model.dart';
import '../providers/admin_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/admin_call_watch_service.dart';
import '../services/photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import '../widgets/admin_call_watch_overlay.dart';
import '../widgets/date_chip.dart';
import '../widgets/private_chat_message.dart';
import '../providers/theme_provider.dart';
import '../config/strings_admin.dart';

class AdminChatViewScreen extends StatefulWidget {
  final String chatId;
  final String chatLabel;

  /// Urutan peserta sesuai judul (nama pertama = bubble kiri, kedua = kanan).
  final List<String> participantOrder;
  const AdminChatViewScreen({
    super.key,
    required this.chatId,
    required this.chatLabel,
    this.participantOrder = const [],
  });

  @override
  State<AdminChatViewScreen> createState() => _AdminChatViewScreenState();
}

class _AdminChatViewScreenState extends State<AdminChatViewScreen> {
  List<MessageModel> _msgs = [];
  bool _loading = true;
  String? _error;
  String? _leftUid;
  String get _chatKey => cacheKeyFor(widget.chatId);
  bool _markedRead = false;
  late Timer _pollTimer;
  RealtimeChannel? _channel;
  final _photoLoading = <String>{};
  final _scrollCtrl = ScrollController();
  final Map<String, LayerLink> _msgLinks = {};
  LayerLink _linkFor(String id) => _msgLinks.putIfAbsent(id, () => LayerLink());

  // ── Pantau call aktif di chat ini ──
  // WatchSession hidup hanya selama layar ini terbuka; dispose → stop()
  // memutus semua koneksi (admin berhenti mendengar/melihat).
  Timer? _callTimer;
  WatchSession? _watch;
  bool _startingWatch = false;

  void _onWatchChanged() {
    if (!mounted) return;
    if (_watch?.stopped ?? false) setState(() {});
  }

  /// Samakan sesi pantau dengan call aktif dari provider.
  Future<void> _syncCallWatch() async {
    if (!mounted || _startingWatch) return;
    final admin = context.read<AdminProvider>();
    if (_watch != null && _watch!.stopped) {
      final done = _watch!;
      _watch = null;
      done.removeListener(_onWatchChanged);
      await done.stop();
      if (mounted) setState(() {});
    }
    ActiveCallInfo? call;
    for (final c in admin.activeCalls) {
      if (c.chatId == widget.chatId) call = c;
    }
    if (call == null) return;
    if (_watch != null && _watch!.call.id == call.id) return;
    _startingWatch = true;
    final old = _watch;
    _watch = null;
    old?.removeListener(_onWatchChanged);
    await old?.stop();
    final ws = WatchSession(call);
    ws.addListener(_onWatchChanged);
    try {
      await ws.start();
    } catch (_) {}
    if (!mounted) {
      await ws.stop();
      _startingWatch = false;
      return;
    }
    setState(() => _watch = ws);
    _startingWatch = false;
  }

  Future<void> _stopWatch() async {
    final ws = _watch;
    _watch = null;
    ws?.removeListener(_onWatchChanged);
    await ws?.stop();
  }

  void _expandWatch() {
    final ws = _watch;
    if (ws == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdminCallWatchFullScreen(session: ws),
      ),
    );
  }

  // Selipkan chip tanggal (Hari ini/Kemarin/tanggal) di antara grup hari,
  // pola WhatsApp — sama seperti room chat. _msgs datang DESC (terbaru dulu),
  // jadi iterasi dibalik supaya terbaru tampil di bawah.
  List<ChatItem> get _items {
    final items = <ChatItem>[];
    String? prevDateKey;
    for (final m in _msgs.reversed) {
      final local = m.timestamp.toLocal();
      final dateKey = '${local.year}-${local.month}-${local.day}';
      if (prevDateKey != dateKey) {
        items.add(
          ChatItem.date(
            dateChipLabel(m.timestamp, context.read<LocaleProvider>().s),
          ),
        );
      }
      prevDateKey = dateKey;
      items.add(ChatItem.message(m));
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _fetch();
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _scrollCtrl.addListener(_onScroll);
    // Call aktif: fetch pertama + polling 5 detik selama layar terbuka.
    final admin = context.read<AdminProvider>();
    Future.microtask(() async {
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
    _callTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final admin = context.read<AdminProvider>();
      await admin.fetchActiveCalls();
      if (mounted) await _syncCallWatch();
    });
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    _callTimer?.cancel();
    _channel?.unsubscribe();
    _scrollCtrl.dispose();
    unawaited(_stopWatch());
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    // ListView( reverse:true → "atas" (pesan lebih lama) = maxScrollExtent.
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      if (admin.chatMessagesHasMore && !admin.chatsLoading) {
        admin.fetchMoreChatMessages(widget.chatId).then((_) {
          if (mounted) _applyMessages();
        });
      }
    }
  }

  /// Re-map dari provider ke _msgs (dipakai setelah load-more / fetch).
  void _applyMessages() {
    if (!mounted) return;
    final admin = context.read<AdminProvider>();
    final list = _mapMessages(admin.chatMessages);
    // Pertahankan imageData yang sudah di-load
    final oldMap = <String, String>{};
    for (final m in _msgs) {
      if (m.imageData.isNotEmpty) oldMap[m.id] = m.imageData;
    }
    for (final m in list) {
      final kept = oldMap[m.id];
      if (kept != null && kept.isNotEmpty && m.imageData.isEmpty) {
        list[list.indexOf(m)] = m.copyWith(imageData: kept);
      }
    }
    final senders = <String>[];
    for (final m in list) {
      if (!senders.contains(m.senderId)) senders.add(m.senderId);
    }
    setState(() {
      _msgs = list;
      _leftUid = _computeLeftUid(senders);
      _error = null;
    });
    _markDummyRead();
    _loadPhotos();
  }

  // ── Voice: VoiceBubble cache disk sendiri (play pertama download
  // sekali, sesi berikutnya dari lokal). imageData = voice_path.

  /// Sisi kiri = peserta pertama sesuai urutan judul (mis. judul
  /// "A & B" → bubble A di kiri, B di kanan). Konsisten, tidak tergantung
  /// siapa yang terakhir kirim pesan. Fallback ke chatId (di-sort) bila
  /// urutan peserta tidak tersedia.
  String? _computeLeftUid(List<String> senders) {
    if (widget.participantOrder.length >= 2)
      return widget.participantOrder.first;
    final parts = widget.chatId.split('_');
    if (parts.length == 2) return parts.first;
    return senders.isNotEmpty ? senders.first : null;
  }

  /// Tandai chat sudah dibaca atas nama dummy/pemilik akun (bukan lawan
  /// bicara) — badge unread di tab admin dummy hilang setelah monitor dibuka.
  /// Sekali per sesi buka screen; poll 5 detik tidak menandai ulang.
  void _markDummyRead() {
    if (_markedRead) return;
    final left = _leftUid;
    if (left == null) return;
    final parts = widget.chatId.split('_');
    if (parts.length != 2) return;
    final dummyUid = parts[0] == left ? parts[1] : parts[0];
    if (dummyUid == left) return;
    _markedRead = true;
    context.read<ChatProvider>().markAsReadAdmin(widget.chatId, dummyUid);
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final admin = context.read<AdminProvider>();
    try {
      final ok = await admin.fetchChatMessages(widget.chatId);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          _error = 'fetchChatMessages returned false';
        });
        return;
      }
      _applyMessages();
      _loading = false;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'EXCEPTION: $e';
      });
    }
  }

  Future<void> _poll() async {
    final admin = context.read<AdminProvider>();
    await admin.refreshChatMessages(widget.chatId);
    if (!mounted) return;
    _applyMessages();
  }

  List<MessageModel> _mapMessages(List<Map<String, dynamic>> raw) {
    return raw.map(_toMessageModel).where((m) => m.id.isNotEmpty).toList();
  }

  // ── Photo Loading (lazy, background) ─────────────────────────────────────

  void _loadPhotos() {
    for (final m in _msgs) {
      final isPhoto =
          m.type == 'image' ||
          m.type == 'view_once' ||
          m.type == 'view_once_expired';
      if (isPhoto && m.imageData.isEmpty && !_photoLoading.contains(m.id)) {
        _loadOnePhoto(m);
      }
    }
  }

  Future<void> _loadOnePhoto(MessageModel msg) async {
    _photoLoading.add(msg.id);
    var data = '';
    // Coba PhotoCache dulu (thumbnail yang sudah ada di device ini)
    try {
      data = await PhotoCache.instance.load(_chatKey, msg.id) ?? '';
    } catch (_) {}
    // Kalau belum ada di cache, fetch dari server via admin RPC
    if (data.isEmpty) {
      final msgId = int.tryParse(msg.id);
      if (msgId != null) {
        final admin = context.read<AdminProvider>();
        var raw = await admin.fetchMessageImage(msgId);
        // image_data berupa PATH storage (foto baru) → download dari bucket.
        if (raw.isNotEmpty && StoragePhotoService.instance.isPath(raw)) {
          raw = await StoragePhotoService.instance.download(raw) ?? '';
        }
        data = raw;
        if (data.isNotEmpty) {
          try {
            await PhotoCache.instance.save(_chatKey, msg.id, data);
          } catch (_) {}
        }
      }
    }
    // Decode + buat thumbnail dari full-res
    if (data.isNotEmpty) {
      var thumb = '';
      try {
        thumb = await PhotoCache.instance.loadThumb(_chatKey, msg.id) ?? '';
      } catch (_) {}
      if (thumb.isEmpty) {
        try {
          thumb = await compute(genThumbB64, data);
        } catch (_) {}
      }
      if (thumb.isEmpty) thumb = '';
      if (!mounted) {
        _photoLoading.remove(msg.id);
        return;
      }
      final idx = _msgs.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        // Gunakan thumbnail kalau ada, fallback ke full-res
        final imgData = thumb.isNotEmpty ? thumb : data;
        if (_msgs[idx].imageData.isEmpty || _msgs[idx].imageData != imgData) {
          _msgs[idx] = _msgs[idx].copyWith(imageData: imgData);
          if (mounted) setState(() {});
        }
      }
    }
    _photoLoading.remove(msg.id);
  }

  Future<void> _retryImage(String msgId) async {
    final msg = _msgs.where((m) => m.id == msgId).firstOrNull;
    if (msg == null) return;
    await _loadOnePhoto(msg);
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    final sb = Supabase.instance.client;
    _channel = sb.channel('admin-${widget.chatId.hashCode}');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'private_messages',
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'private_messages',
      callback: (_) => _poll(),
    );
    _channel!.subscribe();
  }

  // ── Mapping ───────────────────────────────────────────────────────────────

  MessageModel _toMessageModel(Map<String, dynamic> m) {
    return MessageModel(
      id: '${m['id']}',
      senderId: '${m['sender_id'] ?? ''}',
      senderName: '${m['sender_name'] ?? 'Anon'}',
      senderGender: '${m['sender_gender'] ?? 'other'}',
      isRegistered: false,
      text: '${m['text'] ?? ''}',
      type: '${m['type'] ?? 'text'}',
      // Voice: RPC kirim voice_path → disimpan di imageData (dipakai
      // VoiceBubble dengan disk cache-nya sendiri).
      imageData: m['type'] == 'voice'
          ? '${m['voice_path'] ?? ''}'
          : '${m['image_data'] ?? ''}',
      durationMs: m['duration_ms'] is int
          ? m['duration_ms'] as int
          : int.tryParse('${m['duration_ms'] ?? ''}'),
      timestamp: parseDate(m['created_at']),
      repliedToId: m['replied_to_id'] is String ? m['replied_to_id'] : null,
      repliedToText: m['replied_to_text'],
      repliedToSenderName: m['replied_to_sender_name'],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final watchingVideo = _watch != null && _watch!.isVideo;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        title: Text(
          widget.chatLabel,
          style: AppText.titleEmphasis.copyWith(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 6),
              color: AppTheme.danger.withValues(alpha: 0.1),
              child: Text(
                s.adminChatError,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: AppTheme.danger),
              ),
            ),
          // Chip "mendengarkan" untuk call audio — masuk chat = mulai dengar,
          // keluar dari layar ini = berhenti.
          if (_watch != null && !_watch!.isVideo)
            _AudioListenChip(session: _watch!),
          Expanded(
            child: Stack(
              children: [
                _msgs.isEmpty && !_loading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              s.adminChatNoChats,
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          padding: EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            MediaQuery.of(context).padding.bottom + 16,
                          ),
                          itemCount:
                              _items.length +
                              (admin.chatMessagesHasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            }
                            final item = _items[_items.length - 1 - i];
                            if (item.dateLabel != null)
                              return DateChip(label: item.dateLabel!);
                            final msg = item.msg!;
                            final isMe = msg.senderId != _leftUid;
                            final isImageDeferred =
                                msg.type == 'image' && msg.imageData.isEmpty;
                            return MessageBubble(
                              key: ValueKey(msg.id),
                              link: _linkFor(msg.id),
                              msg: msg,
                              chatKey: _chatKey,
                              isMe: isMe,
                              isRead: isMe,
                              isAdminView: true,
                              isImageDeferred: isImageDeferred,
                              onRetryImage: isImageDeferred
                                  ? _retryImage
                                  : null,
                            );
                          },
                        ),
                      ),
                // Call video aktif → overlay setengah layar seperti private
                // chat; bisa di-expand ke fullscreen.
                if (watchingVideo)
                  Positioned.fill(
                    child: AdminCallWatchOverlay(
                      session: _watch!,
                      onExpand: _expandWatch,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip indikator mendengarkan panggilan audio di monitor chat admin.
class _AudioListenChip extends StatefulWidget {
  final WatchSession session;
  const _AudioListenChip({required this.session});

  @override
  State<_AudioListenChip> createState() => _AudioListenChipState();
}

class _AudioListenChipState extends State<_AudioListenChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.55,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _ctrl.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final sess = widget.session;
    final names = sess.participants.map((p) => p.name).join(' & ');
    final sec = sess.call.elapsedSeconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E5B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E9E5B), width: 1),
      ),
      child: Row(
        children: [
          FadeTransition(
            opacity: _ctrl,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF2E9E5B),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.graphic_eq, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  s.adminListening,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call, size: 14, color: const Color(0xFF2E9E5B)),
              const SizedBox(width: 4),
              Text(
                '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                style: AppText.label.copyWith(color: const Color(0xFF2E9E5B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Top-level untuk compute() — generate thumbnail dari base64 ──────────────
String genThumbB64(String base64) {
  try {
    final bytes = base64Decode(base64);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return '';
    final w = decoded.width > 512 ? 512 : decoded.width;
    final h = (decoded.height * (w / decoded.width)).round();
    final thumb = img.copyResize(decoded, width: w, height: h);
    return base64Encode(img.encodeJpg(thumb, quality: 70));
  } catch (_) {
    return base64;
  }
}
