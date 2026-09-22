import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/private_room_service.dart';

import 'supabase_test_client.dart';

/// Fase 3 — PrivateRoomService: verifikasi RPC + tabel/params (tanpa jaringan).
/// Logic-only: tidak menyentuh WebRTC/realtime.
void main() {
  late FakeSupabaseHandler handler;
  late PrivateRoomService svc;

  setUp(() {
    handler = FakeSupabaseHandler();
    svc = PrivateRoomService.forTest(fakeSupabaseClient(handler: handler));
  });

  group('query', () {
    test('myRole → RPC fn_room_role + params', () async {
      handler.on('fn_room_role', (_) => 'owner');
      expect(await svc.myRole('r1'), 'owner');
      final p = rpcParamsOf(handler, 'fn_room_role');
      expect(p['p_room_id'], 'r1');
    });

    test('myRole non-string → null', () async {
      handler.on('fn_room_role', (_) => 5);
      expect(await svc.myRole('r1'), isNull);
    });

    test('listMembers → RPC list_room_members_v2 → list', () async {
      handler.on('list_room_members_v2', (_) => [
            {'uid': 'a', 'role': 'owner'}
          ]);
      final out = await svc.listMembers('r1');
      expect(out.length, 1);
      expect(rpcParamsOf(handler, 'list_room_members_v2')['p_room_id'], 'r1');
    });

    test('listJoinRequests → RPC list_room_join_requests', () async {
      handler.on('list_room_join_requests', (_) => [
            {'uid': 'x'}
          ]);
      expect((await svc.listJoinRequests('r1')).length, 1);
    });
  });

  group('moderasi', () {
    test('approveJoin → RPC approve_join_request + params', () async {
      handler.on('approve_join_request', (_) => {});
      await svc.approveJoin('r1', 'u2');
      final p = rpcParamsOf(handler, 'approve_join_request');
      expect(p['p_room_id'], 'r1');
      expect(p['p_uid'], 'u2');
    });

    test('rejectJoin → RPC reject_join_request', () async {
      handler.on('reject_join_request', (_) => {});
      await svc.rejectJoin('r1', 'u2');
      expect(rpcParamsOf(handler, 'reject_join_request')['p_uid'], 'u2');
    });

    test('kick → RPC kick_room_member', () async {
      handler.on('kick_room_member', (_) => {});
      await svc.kick('r1', 'u2');
      expect(rpcParamsOf(handler, 'kick_room_member')['p_uid'], 'u2');
    });

    test('setRole → RPC set_member_role + p_role', () async {
      handler.on('set_member_role', (_) => {});
      await svc.setRole('r1', 'u2', 'admin');
      final p = rpcParamsOf(handler, 'set_member_role');
      expect(p['p_uid'], 'u2');
      expect(p['p_role'], 'admin');
    });

    test('invite → RPC invite_to_room', () async {
      handler.on('invite_to_room', (_) => {});
      await svc.invite('r1', 'u3');
      expect(rpcParamsOf(handler, 'invite_to_room')['p_uid'], 'u3');
    });

    test('leave → RPC leave_private_room', () async {
      handler.on('leave_private_room', (_) => {});
      await svc.leave('r1');
      expect(rpcParamsOf(handler, 'leave_private_room')['p_room_id'], 'r1');
    });
  });

  group('rotateToken', () {
    test('UPDATE rooms set join_token (22 char)', () async {
      handler.on('rooms', (_) => {});
      await svc.rotateToken('r1');
      final req = handler.captured.firstWhere((r) => r.method == 'PATCH');
      expect(req.url.path.contains('/rest/v1/rooms'), isTrue);
      expect(req.url.query.contains('id=eq.r1'), isTrue);
      expect(req.body.contains('join_token'), isTrue);
    });
  });

  group('broadcast grant', () {
    test('grantBroadcast → RPC grant_broadcast', () async {
      handler.on('grant_broadcast', (_) => {});
      await svc.grantBroadcast('r1', 'u2');
      expect(rpcParamsOf(handler, 'grant_broadcast')['p_uid'], 'u2');
    });

    test('revokeBroadcast → RPC revoke_broadcast', () async {
      handler.on('revoke_broadcast', (_) => {});
      await svc.revokeBroadcast('r1', 'u2');
      expect(rpcParamsOf(handler, 'revoke_broadcast')['p_uid'], 'u2');
    });

    test('myBroadcastGranted → SELECT room_members → bool', () async {
      handler.on('room_members', (_) => {'broadcast_granted': true});
      final out = await svc.myBroadcastGranted('r1');
      expect(out, isA<bool>());
    });

    test('broadcastCount → SELECT room_broadcasters → int', () async {
      handler.on('room_broadcasters', (_) => 7);
      expect(await svc.broadcastCount('r1'), isA<int>());
    });

    test('listBroadcasters → list', () async {
      handler.on('room_broadcasters', (_) => [
            {'uid': 'u1'}
          ]);
      expect((await svc.listBroadcasters('r1')).length, 1);
    });
  });

  group('signaling', () {
    test('sendSignal → INSERT room_signals', () async {
      handler.on('room_signals', (_) => {});
      await svc.sendSignal(
        'r1',
        type: 'offer',
        payload: {'sdp': 'x'},
      );
      final req = handler.captured.firstWhere((r) => r.method == 'POST' &&
          r.url.path.contains('/rest/v1/room_signals'));
      expect(req.body.contains('offer'), isTrue);
    });

    test('fetchSignalsSince → SELECT room_signals', () async {
      handler.on('room_signals', (_) => [
            {'id': 1, 'type': 'offer', 'from_uid': 'other'}
          ]);
      final out = await svc.fetchSignalsSince('r1', 0);
      expect(out, isA<List>());
    });
  });
}
