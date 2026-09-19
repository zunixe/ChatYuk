import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hub terpusat untuk Presence + Broadcast ringan.
/// Dipakai semua fan-out 1→N (online, timeline, room) supaya tidak
/// duplikasi logic channel di tiap provider.
class RealtimeHub {
  final SupabaseClient _sb;

  /// Client opsional supaya test menyuntik client palsu (produksi: singleton).
  RealtimeHub._([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  static RealtimeHub instance = RealtimeHub._();

  /// Test-only: bangun hub dengan client palsu / ganti singleton.
  @visibleForTesting
  factory RealtimeHub.forTest(SupabaseClient sb) => RealtimeHub._(sb);

  @visibleForTesting
  static void overrideInstance(RealtimeHub h) => instance = h;

  @visibleForTesting
  static void restoreInstance() => instance = RealtimeHub._();

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
        return;
      }
      // Channel error/closed: presence mati senyap → user hilang dari daftar
      // online orang lain sampai restart. Bersihkan state supaya heartbeat
      // di auth_provider (cek isOnlineTracking) bisa re-track.
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (identical(_onlineChannel, ch)) {
          _onlineChannel = null;
          _trackedUid = null;
        }
        try {
          await _sb.removeChannel(ch);
        } catch (_) {}
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
        return;
      }
      // Channel error/closed: presence room mati senyap → bersihkan map
      // supaya open berikutnya membuat channel baru.
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (identical(_roomChannels[key], ch)) {
          _roomChannels.remove(key);
        }
        try {
          await _sb.removeChannel(ch);
        } catch (_) {}
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

  /// Lepas semua channel room sekaligus (panggil saat logout/cleanup).
  Future<void> untrackAllRooms() async {
    final keys = _roomChannels.keys.toList();
    for (final k in keys) {
      final ch = _roomChannels.remove(k);
      if (ch != null) {
        try {
          await ch.untrack();
          await _sb.removeChannel(ch);
        } catch (_) {}
      }
    }
  }

  /// Status channel presence online (untuk heartbeat hemat — re-track
  /// hanya bila benar-benar putus, bukan tiap 120 dtk).
  bool get isOnlineTracking =>
      _onlineChannel != null && _trackedUid != null;
}
