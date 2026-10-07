import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/riverpod/avatar_provider.dart';
import 'package:chatyuk/services/avatar_service.dart';
import 'package:chatyuk/widgets/story_viewer_avatar.dart';

class MockAvatarService extends Mock implements AvatarB64Service {}

/// Regresi: daftar penonton story tidak menampilkan foto avatar karena
/// `avatar` dari RPC berupa PATH STORAGE (`avatars/...`) — bukan base64 —
/// dan jalur lama hanya men-decode base64 (gagal → inisial huruf).
///
/// Widget harus: base64 → decode langsung; path/kosong → ambil via
/// AvatarNotifier (yang mengunduh path → base64).
void main() {
  Widget host(AvatarNotifier prov,
      {required String avatar, String uid = 'u-1'}) {
    return ProviderScope(
      overrides: [avatarProvider.overrideWithValue(prov)],
      child: MaterialApp(
        home: Scaffold(
          body: StoryViewerAvatar(
            viewerId: uid,
            avatar: avatar,
            nickname: 'Budi',
          ),
        ),
      ),
    );
  }

  testWidgets('avatar base64 → decode langsung (tak panggil provider)', (
    tester,
  ) async {
    final svc = MockAvatarService();
    final prov = AvatarNotifier(svc);
    // 1x1 PNG transparan (base64).
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
    await tester.pumpWidget(host(prov, avatar: png));
    await tester.pump();
    // Provider TIDAK boleh dipanggil untuk base64 inline.
    verifyNever(() => svc.get(any()));
    expect(find.text('B'), findsNothing, reason: 'foto tampil, bukan inisial');
  });

  testWidgets('avatar PATH storage → ambil via provider (foto muncul)', (
    tester,
  ) async {
    final svc = MockAvatarService();
    when(() => svc.get('u-1')).thenAnswer((_) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      );
      return base64Encode(png);
    });
    final prov = AvatarNotifier(svc);
    await tester.pumpWidget(
      host(prov, avatar: 'avatars/u-1_12345.jpg'),
    );
    await tester.pump(); // frame awal
    await tester.pump(); // selesaikan future provider
    verify(() => svc.get('u-1')).called(1);
    expect(
      find.text('B'),
      findsNothing,
      reason: 'setelah provider mengembalikan base64 → foto, bukan inisial',
    );
  });

  testWidgets('avatar kosong + tidak ada foto → inisial huruf', (
    tester,
  ) async {
    final svc = MockAvatarService();
    when(() => svc.get('u-9')).thenAnswer((_) async => '');
    final prov = AvatarNotifier(svc);
    await tester.pumpWidget(
      host(prov, avatar: '', uid: 'u-9'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
  });
}
