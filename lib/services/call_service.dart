import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/call/signal_route.dart' as signal_route;
import 'call/call_ui.dart' show CallUi;
import 'call/call_ui_factory.dart' show createCallUi;


/// CallService: tabel `calls` + signaling via Realtime broadcast.
/// SDP/ICE TIDAK lewat DB — broadcast channel `call-signal-<callId>`
/// (ephemeral, pola sama seperti typing indicator).
class CallService {
  /// Client opsional (LAZY) — test menyuntik client palsu.
  final SupabaseClient? _injected;
  CallService._([SupabaseClient? sb]) : _injected = sb;

  /// UI panggilan sistem (ConnectionService Android; stub di platform lain).
  /// Dipakai untuk proximity wake lock saat panggilan AUDIO tersambung.
  CallUi callUi = createCallUi();

  static CallService instance = CallService._();

  @visibleForTesting
  factory CallService.forTest(SupabaseClient sb, {CallUi? callUi}) {
    final s = CallService._(sb);
    if (callUi != null) s.callUi = callUi;
    return s;
  }

  @visibleForTesting
  static void overrideInstance(CallService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = CallService._();

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;
  final Map<String, RealtimeChannel> _signalChannels = {};
  final Map<String, StreamController<Map<String, dynamic>>> _signalStreams = {};
  final Set<String> _signalBound = {};

  String? get uid => _sb.auth.currentUser?.id;

  // ── Tabel calls ──
  Future<String> startCall(String calleeUid, String callType) async {
    final row = await _sb
        .from('calls')
        .insert({
          'caller_id': uid,
          'callee_id': calleeUid,
          'call_type': callType,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Tagih call per menit (server otoritatif). Dipanggil CallSession tiap menit.
  Future<Map<String, dynamic>> callBillingTick(String callId) async {
    final res = await _sb.rpc(
      'call_billing_tick',
      params: {'p_call_id': callId},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': true, 'can_continue': true};
  }

  Future<void> updateStatus(String callId, String status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'status': status};
    if (status == 'answered') patch['answered_at'] = now;
    if (status == 'ended' || status == 'canceled') patch['ended_at'] = now;
    // Status TERMINAL (ended/canceled) pakai retry: kalau penelepon menekan
    // akhiri di jaringan jelek dan update sekali gagal, lawan TIDAK pernah
    // tahu → tetap "menghubungkan…" padahal penelepon sudah gagal/keluar.
    // Status lain (answered/ringing) tidak diulang: berulang bisa menimpa
    // status yang lebih baru (mis. race terima vs tolak).
    if (status == 'ended' || status == 'canceled') {
      await _updateStatusWithRetry(callId, patch);
      return;
    }
    await _sb.from('calls').update(patch).eq('id', callId);
  }

  /// Update status terminal dengan retry singkat (≤3 percobaan, jeda pendek).
  /// Best-effort: menyerah tanpa melempar — UI sudah ditutup optimistis.
  Future<void> _updateStatusWithRetry(
    String callId,
    Map<String, dynamic> patch,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _sb.from('calls').update(patch).eq('id', callId);
        return;
      } catch (e) {
        dlog('[CallService] updateStatus retry $attempt gagal: $e');
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }
  }

  Future<Map<String, dynamic>?> getCall(String callId) async {
    return _sb.from('calls').select('*').eq('id', callId).maybeSingle();
  }

  /// Riwayat panggilan milik user ini (masuk/keluar), terbaru dulu.
  ///
  /// RLS `calls_select` sudah membatasi ke `caller_id`/`callee_id` = user,
  /// jadi cukup satu query gabungan. Dipakai halaman "Panggilan Terbaru".
  Future<List<Map<String, dynamic>>> listMyRecentCalls({int limit = 50}) async {
    final me = uid;
    if (me == null) return const [];
    final rows = await _sb
        .from('calls')
        .select(
          'id, caller_id, callee_id, call_type, status, created_at, '
          'answered_at, ended_at',
        )
        .or('caller_id.eq.$me,callee_id.eq.$me')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Nama tampilan batch untuk daftar riwayat panggilan (hindari N+1 query).
  Future<Map<String, String>> lookupNicknames(List<String> uids) async {
    if (uids.isEmpty) return const {};
    final rows = await _sb
        .from('profiles')
        .select('id, nickname')
        .inFilter('id', uids);
    final out = <String, String>{};
    for (final r in rows) {
      final id = r['id'] as String?;
      final n = r['nickname'] as String?;
      if (id != null && n != null && n.isNotEmpty) out[id] = n;
    }
    return out;
  }

  /// Gender batch (uid → gender) untuk riwayat panggilan — dipakai mewarnai
  /// avatar agar seragam dgn menu Online (biru=laki, pink=perempuan).
  Future<Map<String, String>> lookupGenders(List<String> uids) async {
    if (uids.isEmpty) return const {};
    try {
      final rows = await _sb
          .from('profiles')
          .select('id, gender')
          .inFilter('id', uids);
      final out = <String, String>{};
      for (final r in rows) {
        final id = r['id'] as String?;
        final g = r['gender'] as String?;
        if (id != null && g != null && g.isNotEmpty) out[id] = g;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Heartbeat peserta call (fire-and-forget) — dipakai admin monitor
  /// untuk membedakan call hidup vs zombie.
  void touchCall(String callId) {
    _sb
        .rpc('touch_call', params: {'p_call_id': callId})
        .then((_) {})
        .catchError((_) {});
  }

  /// Buat MediaStream lokal kosong (untuk menampung track remote — mis. mix
  /// audio 2 peserta di monitor admin). Dipakai WatchSession.
  Future<MediaStream> createLocalStream([String label = 'mix']) =>
      createLocalMediaStream(label);

  Future<String?> getNickname(String uid) async {
    final row = await _sb
        .from('profiles')
        .select('nickname')
        .eq('id', uid)
        .maybeSingle();
    return row?['nickname'] as String?;
  }

  /// Cek apakah uid adalah admin ChatYuk — dipakai sebelum melayani
  /// permintaan "watch" dari admin panel (pantau call).
  ///
  /// Cache hanya hasil POSITIF (TTL 30 mnt): uid admin stabil, jadi request
  /// pertama tak perlu bayar RPC tiap sesi call baru. Hasil negatif TIDAK
  /// di-cache → selalu di-recheck, gerbang keamanan tetap ketat.
  static final Map<String, DateTime> _adminUidCache = {};
  static const _adminUidTtl = Duration(minutes: 30);
  static const _adminUidCacheMax = 20;

  Future<bool> isAdminUid(String uid) async {
    final at = _adminUidCache[uid];
    if (at != null && DateTime.now().difference(at) < _adminUidTtl) {
      return true;
    }
    try {
      final r = await _sb.rpc('is_chatyuk_admin', params: {'p_uid': uid});
      if (r == true) {
        if (_adminUidCache.length >= _adminUidCacheMax) {
          _adminUidCache.remove(_adminUidCache.keys.first);
        }
        _adminUidCache[uid] = DateTime.now();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Stream panggilan masuk (insert calls dengan callee_id = aku).
  Stream<Map<String, dynamic>> onIncomingCall() {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final me = uid;
    if (me == null) {
      scheduleMicrotask(controller.close);
      return controller.stream;
    }
    final channel = _sb.channel('calls-incoming-$me');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'calls',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'callee_id',
        value: me,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final row = payload.newRecord;
        if (row['status'] != 'ringing') return;
        controller.add(row);
      },
    );
    channel.subscribe((status, err) {
      if (err != null) dlog('[CallService] incoming realtime error: $err');
    });
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  /// Stream perubahan status satu call (mis. callee melihat caller cancel).
  /// Channel dishare per callId (dulu tiap subscriber bikin channel sendiri —
  /// CallSession + IncomingCallScreen = 2 channel untuk call yang sama).
  final Map<String, StreamController<String>> _statusStreams = {};
  final Set<String> _statusBound = {};
  final Map<String, RealtimeChannel> _statusChannels = {};

  Stream<String> onCallStatus(String callId) {
    final controller = _statusStreams.putIfAbsent(
      callId,
      () => StreamController<String>.broadcast(),
    );
    if (_statusBound.add(callId)) {
      final channel = _sb.channel('call-status-$callId');
      _statusChannels[callId] = channel;
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          if (controller.isClosed) return;
          dlog(
            '[CallService] onCallStatus -> ${payload.newRecord['status']}',
          );
          controller.add(payload.newRecord['status'] as String? ?? '');
        },
      );
      channel.subscribe((status, err) {
        if (err != null) dlog('[CallService] status realtime error: $err');
      });
    }
    return controller.stream;
  }

  /// Bersihkan stream status sharing saat call selesai. Dilewati bila masih
  /// ada listener (sesi lain masih memakai) — pemanggil berikutnya yang
  /// akan membersihkan.
  void releaseCallStatus(String callId) {
    final c = _statusStreams[callId];
    if (c != null && c.hasListener) return;
    _statusBound.remove(callId);
    _statusStreams.remove(callId);
    try {
      c?.close();
    } catch (_) {}
    final ch = _statusChannels.remove(callId);
    if (ch != null) {
      try {
        _sb.removeChannel(ch);
      } catch (_) {}
    }
  }

  // ── Signaling ──
  // Dua jalur:
  //  1. DB `call_signals` + postgres_changes — RELIABLE & replayable
  //     (catch-up SELECT). Dipakai untuk offer/answer/bye yang WAJIB tak
  //     boleh hilang (callee masih ringing → offer harus bisa di-replay).
  //  2. Realtime BROADCAST ephemeral (channel sama) — ephemeral, TIDAK
  //     ditulis ke DB. Dipakai untuk ICE candidate yang high-churn
  //     (puluhan per call). Ini memotong sebagian besar write + egress DB
  //     per call tanpa mengurangi keandalan: candidate yang hilang bisa
  //     diminta ulang lewat re-sync offer/answer (lihat `_syncAll`).
  //
  // Kedua jalur menyatu ke SATU stream (controller) supaya CallSession
  // tak perlu tahu asal sinyal.
  static const String _signalBroadcastEvent = 'sig';

  /// True bila [type] boleh dikirim ephemeral (tanpa persist DB).
  /// Logika murni ada di `core/call/signal_route.dart`.
  static bool isEphemeralSignal(String type) =>
      signal_route.isEphemeralSignal(type);

  Stream<Map<String, dynamic>> onSignal(String callId) {
    final controller = _signalStreams.putIfAbsent(
      callId,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    if (!_signalBound.contains(callId)) {
      _signalBound.add(callId);
      // Catch-up: ambil signal yang sudah ada (dikirim sebelum subscribe).
      _catchUpSignals(callId, controller);
      final channel = _sb.channel('call-signals-$callId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (payload) {
          if (controller.isClosed) return;
          _emitSignal(payload.newRecord, controller);
        },
      );
      // Jalur ephemeral: candidate via broadcast (tidak masuk DB).
      channel.onBroadcast(
        event: _signalBroadcastEvent,
        callback: (msg) {
          if (controller.isClosed) return;
          _emitBroadcastSignal(msg, controller);
        },
      );
      channel.subscribe((status, err) {
        if (err != null) dlog('[CallService] signal realtime error: $err');
      });
      _signalChannels[callId] = channel;
    }
    return controller.stream;
  }

  /// Teruskan sinyal broadcast ephemeral (candidate) ke controller.
  /// Bentuk payload identik dengan sinyal DB: {type, ...payload}.
  void _emitBroadcastSignal(
    Map<String, dynamic> msg,
    StreamController<Map<String, dynamic>> controller,
  ) {
    if (controller.isClosed) return;
    final signal = signal_route.decodeEphemeralEnvelope(msg, myUid: uid);
    if (signal == null) return;
    controller.add(signal);
  }

  Future<void> _catchUpSignals(
    String callId,
    StreamController<Map<String, dynamic>> controller,
  ) async {
    try {
      final rows = await _sb
          .from('call_signals')
          .select()
          .eq('call_id', callId)
          .order('created_at');
      for (final row in rows) {
        _emitSignal(row, controller);
      }
    } catch (_) {}
  }

  void _emitSignal(
    Map<String, dynamic> row,
    StreamController<Map<String, dynamic>> controller,
  ) {
    if (controller.isClosed) return;
    if (row['from_uid'] == uid) return;
    final type = row['type'] as String?;
    final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    controller.add({'id': row['id']?.toString(), 'type': type, ...payload});
  }

  Future<void> sendSignal(
    String callId,
    String type, {
    Map<String, dynamic>? payload,
  }) async {
    final ephemeral = isEphemeralSignal(type);
    dlog(
      '[CallService] sendSignal callId=$callId type=$type ephemeral=$ephemeral',
    );
    if (ephemeral) {
      // Candidate: kirim via realtime broadcast (ephemeral, tanpa DB).
      // Fallback ke DB bila channel belum siap (mis. dipanggil sebelum
      // subscribe) supaya candidate TIDAK pernah hilang diam-diam.
      final ch = _signalChannels[callId];
      if (ch != null) {
        try {
          await ch.sendBroadcastMessage(
            event: _signalBroadcastEvent,
            payload: signal_route.buildEphemeralEnvelope(
              fromUid: uid,
              type: type,
              payload: payload,
              seq: _broadcastSeq++,
              micros: DateTime.now().microsecondsSinceEpoch,
            ),
          );
          return;
        } catch (e) {
          dlog('[CallService] broadcast candidate gagal → fallback DB: $e');
        }
      }
      // Channel belum ada → tetap persist (jarang; setup awal).
    }
    try {
      await _sb.from('call_signals').insert({
        'call_id': callId,
        'from_uid': uid,
        'type': type,
        'payload': {...?payload},
      });
    } catch (e) {
      dlog('[CallService] sendSignal error: $e');
    }
  }

  int _broadcastSeq = 0;

  /// Ambil semua signal (offer/candidates) untuk sebuah call — dipakai untuk
  /// re-sync agar tidak ada kandidat yang terlewat.
  Future<List<Map<String, dynamic>>> syncCallSignals(String callId) async {
    try {
      final rows = await _sb
          .from('call_signals')
          .select()
          .eq('call_id', callId)
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  void disposeSignal(String callId) {
    final controller = _signalStreams.remove(callId);
    if (controller != null && !controller.isClosed) controller.close();
    _signalBound.remove(callId);
    final channel = _signalChannels.remove(callId);
    if (channel != null) _sb.removeChannel(channel);
  }
}

