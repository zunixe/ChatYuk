import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/mixins/chat_selection_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/message_reaction_service.dart';

class MockAuthService extends Mock implements AuthService {}

/// Harness minimal untuk `ChatSelectionMixin` — kontraknya mandiri (tidak
/// bergantung mixin lain), jadi cukup host kecil.
class SelHost extends StatefulWidget {
  final AuthProvider auth;
  final ChatProvider chat;
  const SelHost({super.key, required this.auth, required this.chat});
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
  ChatProvider get chatProvider => widget.chat;
  final TextEditingController msgCtrl = TextEditingController();
  @override
  TextEditingController get chatMsgCtrl => msgCtrl;
  int focusCount = 0;
  int scrollCount = 0;
  final List<String> deleted = [];

  /// Hasil hapus per-id (untuk kunci cabang failCount). Default sukses.
  static final Map<String, bool> deleteResults = {};
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
  String chatDeletedLabel(dynamic s) => 'x';
  @override
  Map<String, String> get chatReactionKnownNames => const {};

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

Future<SelHostState> pumpSel(WidgetTester tester) async {
  final auth = AuthProvider(autoInit: false);
  final chat = ChatProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(home: SelHost(auth: auth, chat: chat)),
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
    });

    testWidgets('replyMessage memicu fokus + scroll composer', (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();

      expect(s.replyingTo?.id, 'r');
      expect(s.focusCount, 1);
      expect(s.scrollCount, 1);
    });

    testWidgets('replyMessage membatalkan mode edit', (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e'));
      await tester.pump();
      expect(s.editingMessage, isNotNull);

      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.editingMessage, isNull);
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
      final chat = ChatProvider();
      SelHostState.deleteResults.clear();
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

    Future<void> confirmDialog(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final deleteBtn = find.text('Hapus');
        if (deleteBtn.evaluate().isNotEmpty) {
          await tester.tap(deleteBtn.last);
          await tester.pump(const Duration(milliseconds: 100));
          return;
        }
        final enBtn = find.text('Delete');
        if (enBtn.evaluate().isNotEmpty) {
          await tester.tap(enBtn.last);
          await tester.pump(const Duration(milliseconds: 100));
          return;
        }
      }
      fail('dialog konfirmasi hapus tidak muncul');
    }

    testWidgets('semua sukses → snackbar messageDeleted (x)', (tester) async {
      final s = await pumpSelWithUid(tester, 'u-me');
      s.toggleSelect(msg(id: 'm1', senderId: 'u-me'));
      s.toggleSelect(msg(id: 'm2', senderId: 'u-me'));
      await tester.pump();
      expect(s.selectedIds.length, 2);

      SelHostState.deleteResults['m1'] = true;
      SelHostState.deleteResults['m2'] = true;
      final fut = s.deleteSelected();
      await confirmDialog(tester);
      await fut;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(s.deleted, containsAll(['m1', 'm2']));
      expect(find.text('x'), findsOneWidget);
      expect(s.selectedIds, isEmpty);
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
        final fut = s.deleteSelected();
        await confirmDialog(tester);
        await fut;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text(
            lang == 'id' ? 'Gagal menghapus pesan' : 'Failed to delete message',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });
}
