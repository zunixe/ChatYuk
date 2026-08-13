import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../models/message_model.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../services/photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import '../widgets/date_chip.dart';
import '../widgets/private_chat_message.dart';

class AdminChatViewScreen extends StatefulWidget {
  final String chatId;
  final String chatLabel;
  const AdminChatViewScreen({super.key, required this.chatId, required this.chatLabel});

  @override
  State<AdminChatViewScreen> createState() => _AdminChatViewScreenState();
}

class _AdminChatViewScreenState extends State<AdminChatViewScreen> {
  List<MessageModel> _msgs = [];
  bool _loading = true;
  String? _error;
  String? _leftUid;
  String get _chatKey => cacheKeyFor(widget.chatId);
  late Timer _pollTimer;
  RealtimeChannel? _channel;
  final _photoLoading = <String>{};
  final _scrollCtrl = ScrollController();

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
        items.add(ChatItem.date(dateChipLabel(m.timestamp, context.read<LocaleProvider>().s)));
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
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    _channel?.unsubscribe();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    // ListView reverse:true → "atas" (pesan lebih lama) = maxScrollExtent.
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
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
    for (final m in list) { if (!senders.contains(m.senderId)) senders.add(m.senderId); }
    setState(() {
      _msgs = list;
      _leftUid = senders.isNotEmpty ? senders.first : null;
      _error = null;
    });
    _loadPhotos();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final admin = context.read<AdminProvider>();
    try {
      final ok = await admin.fetchChatMessages(widget.chatId);
      if (!mounted) return;
      if (!ok) {
        setState(() { _loading = false; _error = 'fetchChatMessages returned false'; });
        return;
      }
      _applyMessages();
      _loading = false;
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'EXCEPTION: $e'; });
    }
  }

  Future<void> _poll() async {
    final admin = context.read<AdminProvider>();
    await admin.refreshChatMessages(widget.chatId);
    if (!mounted) return;
    _applyMessages();
  }

  List<MessageModel> _mapMessages(List<Map<String, dynamic>> raw) {
    return raw
        .map(_toMessageModel)
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  // ── Photo Loading (lazy, background) ─────────────────────────────────────

  void _loadPhotos() {
    for (final m in _msgs) {
      final isPhoto = m.type == 'image' ||
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
      if (!mounted) { _photoLoading.remove(msg.id); return; }
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
      imageData: '${m['image_data'] ?? ''}',
      timestamp: parseDate(m['created_at']),
      repliedToId: m['replied_to_id'] is String ? m['replied_to_id'] : null,
      repliedToText: m['replied_to_text'],
      repliedToSenderName: m['replied_to_sender_name'],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.read<AdminProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
            ),
          ),
        ),
        title: Text(widget.chatLabel,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: AppTheme.danger.withValues(alpha: 0.1),
              child: Text(s.adminChatError, textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          Expanded(
            child: _msgs.isEmpty && !_loading
                ? Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.forum_outlined, size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text(s.adminChatNoChats, style: const TextStyle(color: AppTheme.textSecondary)),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: _fetch,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).padding.bottom + 16),
                      itemCount: _items.length + (admin.chatMessagesHasMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                          );
                        }
                        final item = _items[_items.length - 1 - i];
                        if (item.dateLabel != null) return DateChip(label: item.dateLabel!);
                        final msg = item.msg!;
                        final isMe = msg.senderId != _leftUid;
                        final isImageDeferred =
                            msg.type == 'image' && msg.imageData.isEmpty;
                        return MessageBubble(
                          key: ValueKey(msg.id),
                          msg: msg,
                          chatKey: _chatKey,
                          isMe: isMe,
                          isRead: isMe,
                          isAdminView: true,
                          isImageDeferred: isImageDeferred,
                          onRetryImage: isImageDeferred ? _retryImage : null,
                        );
                      },
                    ),
                  ),
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
