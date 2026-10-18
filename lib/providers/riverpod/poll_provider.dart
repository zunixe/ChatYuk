import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../models/chat_poll.dart';
import '../../services/poll_service.dart';

/// Hasil poll untuk bubble (lazy, ringan, tanpa kedip).
///
/// - [listen] mengembalikan ValueListenable per pesan → hanya bubble poll itu
///   yang rebuild (bukan seluruh list chat).
/// - [request] dikumpulkan 60ms lalu SATU RPC untuk semua poll yang terlihat.
/// - Cache bounded (LRU 200) → buka ulang chat langsung pakai hasil terakhir.
/// - [vote] optimistik (UI langsung berubah) lalu disinkron server.
/// - Realtime per chat dinyalakan TERTUNDA (setelah transisi layar) agar
///   masuk private chat tidak tersendat.
class PollController {
  final PollService service;

  /// true = poll ROOM (tabel/RPC terpisah: room_poll_votes). WAJIB instance
  /// terpisah dari poll private: id pesan beda tabel bisa bertabrakan.
  final bool room;
  PollController([PollService? service, this.room = false])
      : service = service ?? PollService.instance;

  /// Instance untuk poll ROOM (grup & global room).
  PollController.room([PollService? service]) : this(service, true);

  static const int _cap = 200;
  final Map<String, _PollNode> _nodes = {};
  final Set<String> _pending = {};
  Timer? _batch;
  RealtimeChannel? _channel;
  String? _channelChat;
  Timer? _subscribeTimer;

  ValueListenable<PollResult?> listen(String messageId) => _node(messageId);

  _PollNode _node(String id) {
    final n = _nodes.remove(id) ?? _PollNode();
    _nodes[id] = n; // LRU: paling baru di akhir
    while (_nodes.length > _cap) {
      final k = _nodes.keys.first;
      // Jangan buang node yang masih didengar bubble.
      final old = _nodes[k]!;
      _nodes.remove(k);
      if (old.inUse) {
        _nodes[k] = old;
        break;
      }
      old.dispose();
    }
    return n;
  }

  /// Minta hasil (dikumpulkan). [force] = abaikan cache.
  void request(String messageId, {bool force = false}) {
    if (messageId.isEmpty || messageId.startsWith('pending-')) return;
    if (!force && _node(messageId).value != null) return;
    _pending.add(messageId);
    _batch ??= Timer(const Duration(milliseconds: 60), _flush);
  }

  Future<void> _flush() async {
    _batch = null;
    if (_pending.isEmpty) return;
    final ids = _pending.toList();
    _pending.clear();
    final res = room
        ? await service.resultsRoom(ids)
        : await service.results(ids);
    res.forEach((id, r) => _node(id).value = r);
  }

  Future<bool> vote(String messageId, ChatPoll poll, Set<int> picked) async {
    final node = _node(messageId);
    final before = node.value ?? PollResult.empty(poll.options.length);
    // Optimistik: hitung ulang counts dari pilihan lama → baru.
    final counts = List<int>.of(before.counts.length == poll.options.length
        ? before.counts
        : List.filled(poll.options.length, 0));
    for (final i in before.mine) {
      if (i < counts.length && counts[i] > 0) counts[i]--;
    }
    for (final i in picked) {
      if (i < counts.length) counts[i]++;
    }
    final hadVote = before.mine.isNotEmpty;
    final voters = before.voters +
        (picked.isNotEmpty && !hadVote ? 1 : 0) -
        (picked.isEmpty && hadVote ? 1 : 0);
    node.value = PollResult(counts: counts, mine: picked, voters: voters);
    final r = room
        ? await service.voteRoom(messageId, picked.toList()..sort())
        : await service.vote(messageId, picked.toList()..sort());
    if (r == null) {
      node.value = before; // rollback
      return false;
    }
    node.value = r;
    return true;
  }

  /// Nyalakan realtime suara untuk chat yang dibuka (tertunda [delay]).
  void attachChat(String chatId, {Duration delay = const Duration(milliseconds: 900)}) =>
      _attach(chatId, service.subscribe, delay);

  /// Nyalakan realtime suara untuk ROOM yang dibuka (pola sama attachChat).
  void attachRoom(String roomId, {Duration delay = const Duration(milliseconds: 900)}) =>
      _attach(roomId, service.subscribeRoom, delay);

  void _attach(
    String scopeId,
    RealtimeChannel Function(String, void Function(String)) subscribe,
    Duration delay,
  ) {
    if (_channelChat == scopeId) return;
    detachChat();
    _channelChat = scopeId;
    _subscribeTimer = Timer(delay, () {
      if (_channelChat != scopeId) return;
      _channel = subscribe(scopeId, (id) => request(id, force: true));
    });
  }

  void detachChat() {
    _subscribeTimer?.cancel();
    _subscribeTimer = null;
    final ch = _channel;
    _channel = null;
    _channelChat = null;
    if (ch != null) unawaited(service.unsubscribe(ch));
  }

  @visibleForTesting
  int get cachedCount => _nodes.length;
}

class _PollNode extends ValueNotifier<PollResult?> {
  _PollNode() : super(null);
  bool get inUse => hasListeners;
}

final pollProvider = Provider<PollController>((_) => PollController());

/// Poll untuk GRUP & GLOBAL ROOM (RPC/tabel room_poll_votes).
final roomPollProvider =
    Provider<PollController>((_) => PollController.room());
