import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/core/chat/pending_confirm.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/widgets/sticker_sheet.dart';

import 'test_helper.dart';

class _MockAuthService extends Mock implements AuthService {}

class _NoUserAuth extends AuthNotifier {
  _NoUserAuth(AuthService svc) : super(authService: svc);
  @override
  AuthData build() => const AuthData(loading: false);
}

MessageModel _st(String id, String data, {DateTime? at}) => MessageModel(
  id: id,
  senderId: 'me',
  senderName: 'A',
  senderGender: 'male',
  isRegistered: true,
  text: '',
  type: 'sticker',
  imageData: data,
  timestamp: at ?? DateTime(2026, 10, 18, 13),
);

final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
));

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  group('consumeConfirmedSticker', () {
    final opened = DateTime(2026, 10, 18, 12);
    test('path persis didahulukan, lalu FIFO; id server sekali pakai', () {
      final pend = [_st('pending-1', 'BASE64'), _st('pending-2', 'stickers/u/a.png')];
      final used = <String>{};
      final echo = _st('91', 'stickers/u/a.png');
      expect(consumeConfirmedSticker(server: echo, openedAt: opened, consumedIds: used, pendings: pend), 1);
      expect(consumeConfirmedSticker(server: echo, openedAt: opened, consumedIds: used, pendings: pend), -1);
      final echo2 = _st('92', 'stickers/u/new.png');
      expect(consumeConfirmedSticker(server: echo2, openedAt: opened, consumedIds: used, pendings: pend), 0);
    });

    test('history sebelum chat dibuka diabaikan', () {
      expect(
        consumeConfirmedSticker(
          server: _st('5', 'stickers/u/a.png', at: DateTime(2026, 10, 18, 11)),
          openedAt: DateTime(2026, 10, 18, 12),
          consumedIds: <String>{},
          pendings: [_st('pending-1', 'stickers/u/a.png')],
        ),
        -1,
      );
    });
  });

  testWidgets('tap stiker: sheet LANGSUNG tertutup walau kirim belum selesai; tap ganda = 1x',
      (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 900);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    StickerEmojiSheet.debugSeedRecent([_png]);
    var sends = 0;
    final never = Completer<void>(); // kirim "lambat" — tak pernah selesai
    final ctrl = TextEditingController();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => _NoUserAuth(_MockAuthService())),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => StickerEmojiSheet(
                  controller: ctrl,
                  onSendSticker: (b, {String ext = 'png'}) {
                    sends++;
                    return never.future;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Tab).last);
    await t.pumpAndSettle();
    expect(find.byType(StickerEmojiSheet), findsOneWidget);
    final tile = find.byType(Image).first;
    await t.tap(tile);
    await t.tap(tile, warnIfMissed: false); // tap ganda cepat
    await t.pumpAndSettle();
    expect(find.byType(StickerEmojiSheet), findsNothing,
        reason: 'sheet harus tertutup tanpa menunggu kirim selesai');
    expect(sends, 1, reason: 'tap ganda tidak mengirim dua kali');
    ctrl.dispose();
  });
}
