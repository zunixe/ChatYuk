import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/mixins/chat_selection_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/chat_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/message_reaction_service.dart';

import '../supabase_test_client.dart';

class MockAuthService extends Mock implements AuthService {}

class MockAuthProvider extends Mock implements AuthProvider {}

/// Harness minimal untuk `ChatSelectionMixin` — kontraknya mandiri (tidak
/// bergantung mixin lain), jadi cukup host kecil.
class SelHost extends StatefulWidget {
  final AuthProvider auth;
  final ChatNotifier chat;
  final bool showAppBar;
  const SelHost({
    super.key,
    required this.auth,
    required this.chat,
    this.showAppBar = false,
  });
  @override
  State<SelHost> createState() => SelHostState();
}

class SelHostState extends State<SelHost> with ChatSelectionMixin<SelHost> {
  @override
  String get chatKind => 'private';
  @override
  String get chatId => 'chat_1';
  @override
  AuthProvider get chatAuth => widget.auth;
  @override
  ChatNotifier get chatProvider => widget.chat;
  final TextEditingController msgCtrl = TextEditingController();
  @override
  TextEditingController get chatMsgCtrl => msgCtrl;
  int focusCount = 0;
  int scrollCount = 0;
  final List<String> deleted = [];
  final List<String> undeleted = [];

  /// Hasil hapus per-id (untuk kunci cabang failCount). Default sukses.
  static final Map<String, bool> deleteResults = {};

  /// Hasil batal-hapus per-id. Default sukses.
  static final Map<String, bool> undeleteResults = {};
  @override
  void chatFocusComposer() => focusCount++;
  @override
  void chatScrollToBottom() => scrollCount++;
  @override
  Future<bool> chatDeleteMessage(String id) async {
    deleted.add(id);
    return deleteResults[id] ?? true;
  }

  @override
  Future<bool> chatUndeleteMessage(String id) async {
    undeleted.add(id);
    return undeleteResults[id] ?? true;
  }

  @override
  String chatDeletedLabel(dynamic s) => 'x';
  @override
  Map<String, String> get chatReactionKnownNames => const {};

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) return const SizedBox.shrink();
    return Scaffold(
      appBar: inSelection
          ? buildSelectionAppBar()
          : AppBar(title: const Text('normal')),
    );
  }
}

MessageModel msg({
  String id = 'm1',
  String senderId = 'u-me',
  String text = 'halo',
  bool isDeleted = false,
  String type = 'text',
}) =>
    MessageModel(
      id: id,
      senderId: senderId,
      senderName: 'Me',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: type,
      imageData: '',
      isDeleted: isDeleted,
      timestamp: DateTime.now(),
    );

Future<SelHostState> pumpSel(WidgetTester tester,
    {bool showAppBar = false}) async {
  final auth = AuthProvider(autoInit: false);
  final chat = ChatNotifier();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
          home: SelHost(auth: auth, chat: chat, showAppBar: showAppBar)),
    ),
  );
  return tester.state<SelHostState>(find.byType(SelHost));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => MessageReactionService.restoreInstance());

  group('ChatSelectionMixin — seleksi dasar', () {
    testWidgets('toggleSelect menambah & mengeluarkan pesan', (tester) async {
      final s = await pumpSel(tester);
      expect(s.inSelection, isFalse);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.selectedIds, {'a'});
      expect(s.selectedMsgs.containsKey('a'), isTrue);
      expect(s.inSelection, isTrue);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.selectedIds, isEmpty);
      expect(s.selectedMsgs, isEmpty);
    });

    testWidgets('toggleSelect menolak pesan terhapus & pending', (tester) async {
      final s = await pumpSel(tester);

      s.toggleSelect(msg(id: 'x', isDeleted: true));
      await tester.pump();
      expect(s.selectedIds, isEmpty, reason: 'pesan terhapus tidak boleh dipilih');

      s.toggleSelect(msg(id: 'pending-123'));
      await tester.pump();
      expect(s.selectedIds, isEmpty, reason: 'pesan pending tidak boleh dipilih');
    });

    testWidgets('onMessageLongPress menambah; id sama = tidak dobel',
        (tester) async {
      final s = await pumpSel(tester);
      final m = msg(id: 'b');

      s.onMessageLongPress(LongPressStartDetails(), m, LayerLink());
      await tester.pump();
      expect(s.selectedIds, {'b'});

      // Tekan lama lagi pada pesan yang sudah terpilih → tidak menambah.
      s.onMessageLongPress(LongPressStartDetails(), m, LayerLink());
      await tester.pump();
      expect(s.selectedIds.length, 1);
    });

    testWidgets('onMessageLongPress menolak pesan terhapus', (tester) async {
      final s = await pumpSel(tester);
      s.onMessageLongPress(
        LongPressStartDetails(),
        msg(id: 'del', isDeleted: true),
        LayerLink(),
      );
      await tester.pump();
      expect(s.selectedIds, isEmpty);
    });

    testWidgets('clearSelection mengosongkan dua koleksi', (tester) async {
      final s = await pumpSel(tester);
      s.toggleSelect(msg(id: 'a'));
      s.toggleSelect(msg(id: 'b'));
      await tester.pump();
      expect(s.selectedIds.length, 2);

      s.clearSelection();
      await tester.pump();
      expect(s.selectedIds, isEmpty);
      expect(s.selectedMsgs, isEmpty);
    });

    testWidgets('singleSelected hanya saat tepat 1 terpilih', (tester) async {
      final s = await pumpSel(tester);
      expect(s.singleSelected, isNull);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.singleSelected?.id, 'a');

      s.toggleSelect(msg(id: 'b'));
      await tester.pump();
      expect(s.singleSelected, isNull, reason: '2 terpilih → bukan single');
    });

    testWidgets('linkFor stabil per id (LayerLink sama)', (tester) async {
      final s = await pumpSel(tester);
      final l1 = s.linkFor('m1');
      final l2 = s.linkFor('m1');
      expect(identical(l1, l2), isTrue);
      expect(identical(s.linkFor('m2'), l1), isFalse);
    });

    testWidgets('linkFor membatasi peta agar tidak tumbuh tanpa batas',
        (tester) async {
      final s = await pumpSel(tester);
      // Isi melewati cap 500 → entri lama harus mulai dibuang.
      for (var i = 0; i < 520; i++) {
        s.linkFor('id_$i');
      }
      expect(s.msgLinks.length, lessThanOrEqualTo(501));
    });
  });

  group('ChatSelectionMixin — edit & balas', () {
    testWidgets('editMessage mengisi composer + fokus + fokus count naik',
        (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e', text: 'teks lama'));
      await tester.pump();

      expect(s.editingMessage?.id, 'e');
      expect(s.chatMsgCtrl.text, 'teks lama');
      expect(s.chatMsgCtrl.selection.baseOffset, 'teks lama'.length);
      expect(s.focusCount, 1);
    });

    testWidgets('editMessage membatalkan mode balas (saling eksklusif)',
        (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.replyingTo, isNotNull);

      s.editMessage(msg(id: 'e'));
      await tester.pump();
      expect(s.replyingTo, isNull, reason: 'edit membatalkan balas');
      expect(s.editingMessage, isNotNull);
      // Siram timer penegasan fokus reply (guard menolak: sudah mode edit).
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('replyMessage memicu fokus + scroll composer', (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();

      expect(s.replyingTo?.id, 'r');
      expect(s.focusCount, 1);
      expect(s.scrollCount, 1);
      // Siram timer penegasan fokus.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('replyMessage membatalkan mode edit', (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e'));
      await tester.pump();
      expect(s.editingMessage, isNotNull);

      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.editingMessage, isNull);
      // Siram timer penegasan fokus.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('replyMessage menegasan fokus setelah jeda (anti tap dua kali)',
        (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(s.replyingTo?.id, 'r');
      // Fokus 1× langsung + 1× penegasan pasca-jeda.
      expect(s.focusCount, 2);
    });

    testWidgets('tap ikon reply di AppBar SEKALI → tutup + reply langsung',
        (tester) async {
      // Auth di-mock (uid tanpa Supabase) supaya test ini tidak butuh
      // initSupabaseForTest (yang meninggalkan timer periodik).
      final mockAuth = MockAuthProvider();
      when(() => mockAuth.uid).thenReturn('u-me');
      final chat = ChatNotifier();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>(
                create: (_) => LocaleProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ],
          child: MaterialApp(
              home: SelHost(auth: mockAuth, chat: chat, showAppBar: true)),
        ),
      );
      final s = tester.state<SelHostState>(find.byType(SelHost));
      s.toggleSelect(msg(id: 'r', senderId: 'u-me', text: 'halo'));
      await tester.pump();
      expect(s.inSelection, isTrue);

      await tester.tap(find.byIcon(Icons.reply));
      await tester.pump();

      expect(s.inSelection, isFalse, reason: 'seleksi harus tertutup');
      expect(s.replyingTo?.id, 'r',
          reason: 'reply harus jalan dalam SATU tap');
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('replyMessage TIDAK refokus bila balasan sudah dibatalkan',
        (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.focusCount, 1);

      s.cancelReply();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(s.replyingTo, isNull);
      expect(s.focusCount, 1, reason: 'jangan rebut fokus setelah cancel');
    });

    testWidgets('cancelEdit reset state + kosongkan composer', (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e', text: 'abc'));
      await tester.pump();

      s.cancelEdit();
      await tester.pump();
      expect(s.editingMessage, isNull);
      expect(s.chatMsgCtrl.text, isEmpty);
    });

    testWidgets('cancelReply reset replyingTo', (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();

      s.cancelReply();
      await tester.pump();
      expect(s.replyingTo, isNull);
      // Siram timer penegasan fokus (guard menolak: sudah cancel).
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets(
        'editSelected masuk mode edit + tegaskan fokus setelah jeda '
        '(anti tap dua kali)', (tester) async {
      final s = await pumpSel(tester);
      s.toggleSelect(msg(id: 'e', text: 'lama'));
      await tester.pump();

      // Jeda 300ms di editSelected memakai fake-clock: majukan eksplisit.
      final fut = s.editSelected();
      await tester.pump(const Duration(milliseconds: 300));
      await fut;
      await tester.pump();

      expect(s.editingMessage?.id, 'e');
      expect(s.chatMsgCtrl.text, 'lama');
      // Fokus 1× dari editMessage + 1× penegasan pasca-jeda.
      expect(s.focusCount, 2);
    });

    testWidgets('editSelected TIDAK refokus bila edit sudah dibatalkan',
        (tester) async {
      final s = await pumpSel(tester);
      s.toggleSelect(msg(id: 'e', text: 'lama'));
      await tester.pump();

      final fut = s.editSelected();
      await tester.pump();
      expect(s.editingMessage?.id, 'e');
      expect(s.focusCount, 1);

      s.cancelEdit();
      await tester.pump(const Duration(milliseconds: 300));
      await fut;
      await tester.pump();

      expect(s.editingMessage, isNull);
      expect(s.focusCount, 1, reason: 'jangan rebut fokus setelah cancel');
    });
  });

  group('ChatSelectionMixin — deleteSelected failCount', () {
    Future<SelHostState> pumpSelWithUid(
      WidgetTester tester,
      String uid, {
      String lang = 'id',
    }) async {
      final mockSvc = MockAuthService();
      when(() => mockSvc.uid).thenReturn(uid);
      final auth = AuthProvider(authService: mockSvc, autoInit: false);
      final chat = ChatNotifier();
      SelHostState.deleteResults.clear();
      SelHostState.undeleteResults.clear();
      SharedPreferences.setMockInitialValues({});
      final lp = LocaleProvider();
      await lp.setLang(lang);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: lp),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            home: Scaffold(body: SelHost(auth: auth, chat: chat)),
          ),
        ),
      );
      return tester.state<SelHostState>(find.byType(SelHost));
    }

    testWidgets('1-tap hapus langsung + snackbar UNDO (tanpa dialog)',
        (tester) async {
      final s = await pumpSelWithUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
      s.toggleSelect(msg(id: 'm2', senderId: 'u-me'));
      await tester.pump();
      expect(s.selectedIds.length, 2);

      SelHostState.deleteResults['m1'] = true;
      SelHostState.deleteResults['m2'] = true;
      await s.deleteSelected();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(s.deleted, containsAll(['m1', 'm2']));
      expect(find.text('x'), findsOneWidget);
      expect(find.text('Urungkan'), findsOneWidget);
      expect(s.selectedIds, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('tap UNDO → pesan dikembalikan', (tester) async {
      final s = await pumpSelWithUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
      await tester.pump();

      SelHostState.deleteResults['m1'] = true;
      SelHostState.undeleteResults['m1'] = true;
      await s.deleteSelected();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Urungkan'), findsOneWidget);

      await tester.tap(find.text('Urungkan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(s.undeleted, contains('m1'));
      await tester.pump(const Duration(seconds: 5));
    });

    // Snackbar gagal tahan locale: ID dan EN wajib benar.
    for (final lang in ['id', 'en']) {
      testWidgets('campur sukses+gagal → tetap gagal ($lang)', (tester) async {
        final s = await pumpSelWithUid(tester, 'u-me', lang: lang);
        s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
        s.toggleSelect(msg(id: 'm2', senderId: 'u-me'));
        await tester.pump();

        SelHostState.deleteResults['m1'] = true;
        SelHostState.deleteResults['m2'] = false;
        await s.deleteSelected();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text(
            lang == 'id' ? 'Gagal menghapus pesan' : 'Failed to delete message',
          ),
          findsOneWidget,
        );
        // Gagal parsial → tidak ada UNDO.
        expect(find.text('Urungkan'), findsNothing);
        expect(find.text('Undo'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });

  group('ChatSelectionMixin — cabang delete/copy/react', () {
    Future<SelHostState> pumpUid(WidgetTester tester, String uid) async {
      final mockSvc = MockAuthService();
      when(() => mockSvc.uid).thenReturn(uid);
      final auth = AuthProvider(authService: mockSvc, autoInit: false);
      final chat = ChatNotifier();
      SelHostState.deleteResults.clear();
      SelHostState.undeleteResults.clear();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: SelHost(auth: auth, chat: chat))),
        ),
      );
      return tester.state<SelHostState>(find.byType(SelHost));
    }

    testWidgets('seleksi kosong → diam, tanpa snackbar', (tester) async {
      final s = await pumpUid(tester, 'u-me');
      await s.deleteSelected();
      await tester.pump();

      expect(s.selectedIds, isEmpty);
      expect(s.deleted, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('hanya pesan orang → dibersihkan, tanpa hapus', (tester) async {
      final s = await pumpUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm9', senderId: 'u-other'));
      await tester.pump();
      expect(s.selectedIds, isNotEmpty);

      await s.deleteSelected();
      await tester.pump();

      expect(s.selectedIds, isEmpty, reason: 'seleksi dibersihkan');
      expect(s.deleted, isEmpty, reason: 'pesan orang tak dihapus');
    });

    testWidgets('hapus 1-tap tanpa dialog konfirmasi', (tester) async {
      final s = await pumpUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
      await tester.pump();

      SelHostState.deleteResults['m1'] = true;
      await s.deleteSelected();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(s.deleted, contains('m1'));
      expect(s.selectedIds, isEmpty, reason: 'seleksi langsung tertutup');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('copy → clipboard terisi + snackbar + seleksi bersih',
        (tester) async {
      // Handler eksplisit: mock clipboard bawaan macet bila ada widget
      // tree ter-pump (diam tanpa reply) — dengan ini deterministik SEKALIGUS
      // isi teksnya bisa diassert.
      String? got;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          got = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final s = await pumpUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me', text: 'rahasia'));
      await tester.pump();

      await s.copySelected();
      await tester.pump();

      expect(got, 'rahasia');
      expect(find.text(s.context.read<LocaleProvider>().s.msgMessageCopied),
          findsOneWidget);
      expect(s.selectedIds, isEmpty);
    });

    testWidgets('react gagal (tanpa sesi) → seleksi bersih, tanpa crash',
        (tester) async {
      MessageReactionService.overrideInstance(
        MessageReactionService.forTest(fakeSupabaseClientNoTicker()),
      );
      final s = await pumpUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
      await tester.pump();

      await s.reactToSelected('❤️');
      await tester.pump();

      expect(s.selectedIds, isEmpty);
      expect(s.reactions['m1'], isNull);
    });
  });
}
