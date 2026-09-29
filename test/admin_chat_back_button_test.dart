import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/core/cache/message_cache.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';
import 'package:chatyuk/screens/admin_chat_view_screen.dart'
    show AdminChatViewScreen, computeMonitorLeftUid, tryClaimChatPush, releaseChatPush;
import 'package:chatyuk/services/admin_service.dart';
import 'package:chatyuk/services/avatar_service.dart';

class MockAdminService extends Mock implements AdminService {}

class MockSbClient extends Mock implements SupabaseClient {}

class MockChannel extends Mock implements RealtimeChannel {}

/// Regresi tombol back monitor chat.
///
/// Kasus nyata: buka chat "Anggi & Jaky" → panah back (←) ditekan tidak ada
/// reaksi (scroll jalan = bukan freeze). Akar: tap 2× cepat saat transisi
/// push menumpuk 2 route identik → 1× back terlihat mati. Dikunci oleh
/// [tryClaimChatPush]/[releaseChatPush] + widget test di bawah.
void main() {
  const uidAnggi = '11111111-1111-1111-1111-111111111111';
  const uidJaky = '22222222-2222-2222-2222-222222222222';
  const chatId = '${uidAnggi}_$uidJaky';

  // PNG 1×1 transparan — seed cache RAM supaya avatar header tidak menyentuh
  // network/disk di test.
  const tinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  Map<String, dynamic> msg(int id, String sender, String name, String text) =>
      {
        'id': id,
        'chat_id': chatId,
        'sender_id': sender,
        'sender_name': name,
        'sender_gender': 'male',
        'text': text,
        'type': 'text',
        'image_data': '',
        'image_path': '',
        'voice_path': '',
        'created_at': DateTime.utc(2026, 9, 27, 10, id).toIso8601String(),
      };

  late MockAdminService service;
  late MockSbClient sb;
  late MockChannel channel;
  late AdminProvider admin;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(PostgresChangeEvent.insert);
    registerFallbackValue((PostgresChangePayload _) {});
  });

  setUp(() {
    service = MockAdminService();
    sb = MockSbClient();
    channel = MockChannel();
    when(() => sb.channel(any())).thenReturn(channel);
    when(
      () => channel.onPostgresChanges(
        event: any(named: 'event'),
        schema: any(named: 'schema'),
        table: any(named: 'table'),
        filter: any(named: 'filter'),
        callback: any(named: 'callback'),
      ),
    ).thenReturn(channel);
    when(() => channel.subscribe(any())).thenReturn(channel);
    when(() => channel.unsubscribe()).thenAnswer((_) async => 'ok');

    when(
      () => service.getChatMessages(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer(
      (_) async => [
        msg(2, uidJaky, 'Jaky', 'halo'),
        msg(1, uidAnggi, 'Anggi', 'hai'),
      ],
    );
    when(() => service.getChatLastRead(any()))
        .thenAnswer((_) async => <String, String>{});
    when(() => service.getActiveCalls()).thenAnswer((_) async => []);
    when(() => service.sweepStaleCalls()).thenAnswer((_) async => 0);

    AvatarB64Service.instance.setForUid(uidAnggi, tinyPng);
    AvatarB64Service.instance.setForUid(uidJaky, tinyPng);

    admin = AdminProvider(service: service, sb: sb);
  });

  tearDown(() => admin.dispose());

  Future<void> pumpHost(WidgetTester tester) async {
    // MessageCache SQLite/Keystore tidak jalan di test env (future menggantung)
    // — seed mem-cache sinkron supaya layar langsung terisi seperti produksi.
    // Bagian sinkron saveMessages (update memori) jalan seketika; sisanya
    // (disk) menggantung tanpa mengganggu test.
    unawaited(
      MessageCache.instance.saveMessages('private_$chatId', [
        MessageModel(
          id: '1',
          senderId: uidAnggi,
          senderName: 'Anggi',
          senderGender: 'male',
          isRegistered: false,
          text: 'hai',
          type: 'text',
          imageData: '',
          timestamp: DateTime.utc(2026, 9, 27, 10, 1),
        ),
        MessageModel(
          id: '2',
          senderId: uidJaky,
          senderName: 'Jaky',
          senderGender: 'male',
          isRegistered: false,
          text: 'halo',
          type: 'text',
          imageData: '',
          timestamp: DateTime.utc(2026, 9, 27, 10, 2),
        ),
      ]),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminProvider>.value(value: admin),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    if (!tryClaimChatPush(chatId)) return;
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const AdminChatViewScreen(
                          chatId: chatId,
                          chatLabel: 'Anggi & Jaky',
                          participantOrder: [uidAnggi, uidJaky],
                          participantNames: {
                            uidAnggi: 'Anggi',
                            uidJaky: 'Jaky',
                          },
                        ),
                      ),
                    ).then((_) => releaseChatPush(chatId));
                  },
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('panah back AppBar kembali ke daftar', (tester) async {
    await pumpHost(tester);

    expect(find.text('Anggi & Jaky'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Anggi & Jaky'), findsNothing);
    expect(find.text('buka'), findsOneWidget);
  });

  testWidgets('bubble terbagi kiri-kanan (tidak semua kanan)', (tester) async {
    await pumpHost(tester);

    expect(find.text('Anggi & Jaky'), findsOneWidget);
    // Bubble memakai RichText (span mention/link), bukan Text polos.
    expect(find.text('hai', findRichText: true), findsOneWidget);
    expect(find.text('halo', findRichText: true), findsOneWidget);
  });

  testWidgets('pesan terhapus: ISI tetap tampil + banner dihapus', (tester) async {
    unawaited(
      MessageCache.instance.saveMessages('private_${chatId}_del', [
        MessageModel(
          id: '9',
          senderId: uidAnggi,
          senderName: 'Anggi',
          senderGender: 'male',
          isRegistered: false,
          // Isi ASLI tetap ada (server tidak mengosongkan) — admin harus
          // bisa melihatnya walau pengirim sudah menghapus.
          text: 'rahasia penting',
          type: 'text',
          imageData: '',
          timestamp: DateTime.utc(2026, 9, 27, 10, 5),
          isDeleted: true,
        ),
      ]),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminProvider>.value(value: admin),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const AdminChatViewScreen(
                          chatId: '${chatId}_del',
                          chatLabel: 'Anggi & Jaky',
                          participantOrder: [uidAnggi, uidJaky],
                          participantNames: {
                            uidAnggi: 'Anggi',
                            uidJaky: 'Jaky',
                          },
                        ),
                      ),
                    );
                  },
                  child: const Text('buka-del'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka-del'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // Isi asli TETAP tampil + banner "Dihapus oleh pengirim".
    expect(
      find.text('rahasia penting', findRichText: true),
      findsWidgets,
      reason: 'isi pesan terhapus harus tetap terlihat admin',
    );
    expect(
      find.textContaining('Dihapus oleh pengirim', findRichText: true),
      findsWidgets,
      reason: 'harus ada penanda bahwa pesan sudah dihapus',
    );
  });

  group('tryClaimChatPush', () {
    const id = 'test-chat-guard';

    test('tap pertama lolos, tap kedua cepat ditolak', () {
      releaseChatPush(id);
      final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
      expect(tryClaimChatPush(id, now: t0), isTrue);
      expect(
        tryClaimChatPush(id, now: t0.add(const Duration(milliseconds: 500))),
        isFalse,
      );
      releaseChatPush(id);
    });

    test('tap ulang setelah pop (release) lolos lagi', () {
      final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
      expect(tryClaimChatPush(id, now: t0), isTrue);
      releaseChatPush(id);
      expect(
        tryClaimChatPush(id, now: t0.add(const Duration(milliseconds: 500))),
        isTrue,
      );
      releaseChatPush(id);
    });

    test('tap ulang setelah >2 detik lolos (klaim basi)', () {
      final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
      expect(tryClaimChatPush(id, now: t0), isTrue);
      expect(
        tryClaimChatPush(id, now: t0.add(const Duration(seconds: 3))),
        isTrue,
      );
      releaseChatPush(id);
    });

    test('chatId kosong selalu lolos', () {
      expect(tryClaimChatPush(''), isTrue);
    });
  });

  group('computeMonitorLeftUid abaikan string kosong', () {
    test('sender kosong tidak jadi sisi kiri', () {
      expect(
        computeMonitorLeftUid(
          participantOrder: const [],
          chatId: 'tanpa-separator',
          senders: ['', 'u-b'],
        ),
        'u-b',
      );
    });

    test('semua kosong → null', () {
      expect(
        computeMonitorLeftUid(
          participantOrder: const ['', ''],
          chatId: '_',
          senders: const ['', ''],
        ),
        isNull,
      );
    });
  });
}
