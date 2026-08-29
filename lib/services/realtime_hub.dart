import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hub terpusat untuk Presence + Broadcast ringan.
/// Dipakai semua fan-out 1→N (online, timeline, room) supaya tidak
/// duplikasi logic channel di tiap provider.
class RealtimeHub {
  RealtimeHub._();
  static final RealtimeHub instance = RealtimeHub._();

  SupabaseClient get _sb => Supabase.instance.client;

  // ── Presence global online ───────────────────────────────────────────────
  RealtimeChannel? _onlineChannel;
  final _onlineCtrl = StreamController<Map<String, dynamic>>.broadcast();
  String? _trackedUid;

  Future<void> trackOnline(String uid, String nickname) async {
    if (_trackedUid == uid && _onlineChannel != null) return;
    await untrackOnline();
    _trackedUid = uid;
    final ch = _sb.channel('online-global',
        opts: const RealtimeChannelConfig(self: true));
    ch.onPresenceSync((_) {
      if (!_onlineCtrl.isClosed) {
        _onlineCtrl.add({'event': 'sync', 'state': ch.presenceState()});
      }
    });
    ch.onPresenceJoin((payload) {
      if (!_onlineCtrl.isClosed) {
        _onlineCtrl.add({'event': 'join', 'payload': payload});
      }
    });
    ch.onPresenceLeave((payload) {
      if (!_onlineCtrl.isClosed) {
        _onlineCtrl.add({'event': 'leave', 'payload': payload});
      }
    });
    ch.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'uid': uid, 'nickname': nickname, 'at': DateTime.now().toIso8601String()});
      }
    });
    _onlineChannel = ch;
  }

  Future<void> untrackOnline() async {
    try {
      if (_onlineChannel != null) {
        await _onlineChannel!.untrack();
        await _sb.removeChannel(_onlineChannel!);
      }
    } catch (_) {}
    _onlineChannel = null;
    _trackedUid = null;
  }

  Stream<Map<String, dynamic>> get onlinePresence => _onlineCtrl.stream;

  Map<String, List<Map<String, dynamic>>> get onlinePresenceState {
    final s = _onlineChannel?.presenceState();
    if (s == null) return {};
    try {
      return (s as Map).map((k, v) => MapEntry(k.toString(),
          (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()));
    } catch (_) {
      return {};
    }
  }

  // ── Broadcast timeline ───────────────────────────────────────────────────
  RealtimeChannel? _timelineChannel;
  final _timelineCtrl = StreamController<Map<String, dynamic>>.broadcast();

  RealtimeChannel ensureTimeline() {
    if (_timelineChannel != null) return _timelineChannel!;
    final ch = _sb.channel('timeline-all');
    ch.onBroadcast(event: 'new_post', callback: (payload, {event}) {
      if (!_timelineCtrl.isClosed) {
        _timelineCtrl.add({'event': 'new_post', 'payload': payload});
      }
    });
    ch.onBroadcast(event: 'post_update', callback: (payload, {event}) {
      if (!_timelineCtrl.isClosed) {
        _timelineCtrl.add({'event': 'post_update', 'payload': payload});
      }
    });
    ch.subscribe();
    _timelineChannel = ch;
    return ch;
  }

  Stream<Map<String, dynamic>> get timelineBroadcast => _timelineCtrl.stream;

  Future<void> broadcastTimeline(String event, Map<String, dynamic> payload) async {
    final ch = ensureTimeline();
    await ch.sendBroadcastMessage(event: event, payload: payload);
  }

  // ── Presence room ────────────────────────────────────────────────────────
  final Map<String, RealtimeChannel> _roomChannels = {};
  final _roomCtrl = StreamController<Map<String, dynamic>>.broadcast();

  RealtimeChannel trackRoom(String roomId, String uid) {
    final key = 'room-$roomId';
    if (_roomChannels.containsKey(key)) return _roomChannels[key]!;
    final ch = _sb.channel(key, opts: const RealtimeChannelConfig(self: true));
    ch.onPresenceSync((_) {
      if (!_roomCtrl.isClosed) {
        _roomCtrl.add({'roomId': roomId, 'event': 'sync', 'state': ch.presenceState()});
      }
    });
    ch.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'uid': uid, 'roomId': roomId});
      }
    });
    _roomChannels[key] = ch;
    return ch;
  }

  Future<void> untrackRoom(String roomId) async {
    final ch = _roomChannels.remove('room-$roomId');
    if (ch != null) {
      try {
        await ch.untrack();
        await _sb.removeChannel(ch);
      } catch (_) {}
    }
  }

  Stream<Map<String, dynamic>> get roomPresence => _roomCtrl.stream;
}
