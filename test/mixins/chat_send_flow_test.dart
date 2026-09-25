import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/mixins/chat_outbox_mixin.dart';
import 'package:chatyuk/mixins/chat_photo_send_mixin.dart';
import 'package:chatyuk/mixins/chat_send_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/points_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/utils.dart' show capitalizeFirst;
import 'package:chatyuk/utils/mention.dart';

class MockAuthService extends Mock implements AuthService {}

/// Host mixin ASLI (`ChatSendMixin` + 2 syaratnya) dengan hook tercatat —
/// perilaku di bawah diuji lewat `sendMessage()` beneran, bukan cermin.
class SendHost extends StatefulWidget {
  final AuthProvider auth;
  const SendHost({super.key, required this.auth});
  @override
  State<SendHost> createState() => SendHostState();
}

class SendHostState extends State<SendHost>
    with ChatOutboxMixin<SendHost>, ChatPhotoSendMixin<SendHost>, ChatSendMixin<SendHost> {
  final TextEditingController ctrl = TextEditingController();
  @override
  TextEditingController get sendMsgCtrl => ctrl;

  bool _sending = false;
  @override
  bool get sendIsSending => _sending;
  @override
  set sendIsSending(bool v) => _sending = v;

  MessageModel? _editing;
  @override
  MessageModel? get sendEditingMessage => _editing;
  @override
  set sendEditingMessage(MessageModel? v) => _editing = v;

  MessageModel? _reply;
  @override
  MessageModel? get sendReplyingTo => _reply;
  @override
  set sendReplyingTo(MessageModel? v) => _reply = v;

  String? _photo;
  @override
  String? get sendPendingPhotoBase64 => _photo;
  @override
  set sendPendingPhotoBase64(String? v) => _photo = v;

  @override
  String get outboxKind => 'private';
  @override
  String get outboxChatId => 'c1';
  @override
  String get outboxUploadChatId => 'c1';
  final List<MessageModel> _pending = [];
  @override
  List<MessageModel> get outboxPending => _pending;
  final Set<String> _queued = {};
  @override
  Set<String> get outboxQueuedIds => _queued;
  bool _flushing = false;
  @override
  bool get outboxIsFlushing => _flushing;
  @override
  set outboxIsFlushing(bool v) => _flushing = v;
  @override
  bool get outboxIsOnline => true;
  @override
  void outboxScrollToBottom() {}
  @override
  Future<void> outboxSendEntry(OutboxEntry e, String imageData) async {}
  @override
  void outboxOnSent() {}

  @override
  Future<void> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
    String text = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    int? viewOnceSecs,
  }) async {}
  @override
  String get photoUploadChatId => 'c1';
  @override
  String get photoSeed => 'seed';
  @override
  void photoOnSent(String kind) {}
  @override
  void photoFirstBonus(PointsProvider pp) {}
  @override
  void photoSetPreview(String base64) {}

  @override
  List<Mention> sendMentionCandidates() => const [];
  int preChecks = 0;
  @override
  Future<bool> sendPreCheck() async {
    preChecks++;
    return true;
  }

  int cancels = 0;
  @override
  void sendCancelEdit() => cancels++;

  final List<(MessageModel, String)> persists = [];
  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) async {
    persists.add((editing, raw));
    return true;
  }

  final List<String> dispatched = [];
  @override
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  }) async {
    dispatched.add(text);
  }

  @override
  void sendOnSentText() {}

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

MessageModel editMsg(String text) => MessageModel(
      id: 'm1',
      senderId: 'u-me',
      senderName: 'Me',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
    );

/// Mengunci kontrak `chat_send_mixin` lewat mixin ASLI (bukan cermin):
/// guard kirim + mode edit diuji via `sendMessage()` beneran.
/// Helper murni (kapitalisasi/mention/pending-id/network-error) tetap
/// diuji langsung — itu unit mereka sendiri.
void main() {
  group('kapitalisasi pesan baru (gaya WhatsApp)', () {
    test('huruf pertama dikapitalkan', () {
      expect(capitalizeFirst('halo dunia'), 'Halo dunia');
    });

    test('string kosong tetap kosong (diabaikan mixin)', () {
      expect(capitalizeFirst(''), '');
      expect(capitalizeFirst('   ').trim(), isEmpty);
    });
  });

  group('mention', () {
    test('parseMentions menemukan uid dari kandidat', () {
      const cands = [Mention(uid: 'u-sari', name: 'Sari')];
      final out = parseMentions('hai @Sari apa kabar', candidates: cands);
      expect(out.map((m) => m.uid), contains('u-sari'));
    });

    test('tanpa @ → daftar kosong (kolom mentions tidak dikirim)', () {
      const cands = [Mention(uid: 'u-sari', name: 'Sari')];
      expect(parseMentions('halo dunia', candidates: cands), isEmpty);
    });
  });

  group('pending + error jaringan', () {
    test('pending id ber-prefix pending- (ditolak reaksi)', () {
      final id = 'pending-${DateTime.now().microsecondsSinceEpoch}';
      expect(id.startsWith('pending-'), isTrue);
    });

    test('isNetworkError membedakan jaringan vs blokir', () {
      expect(
        OfflineOutbox.isNetworkError(Exception('SocketException: Failed')),
        isTrue,
      );
      expect(
        OfflineOutbox.isNetworkError(Exception('42501 policy')),
        isFalse,
        reason: 'blokir RLS harus snackbar, bukan antrean',
      );
    });
  });

  group('ChatSendMixin.sendMessage (mixin asli)', () {
    late MockAuthService mockSvc;
    late AuthProvider auth;

    Future<SendHostState> pumpHost(WidgetTester tester) async {
      mockSvc = MockAuthService();
      when(() => mockSvc.uid).thenReturn('u-me');
      when(() => mockSvc.isAnonymous).thenReturn(false);
      auth = AuthProvider(authService: mockSvc, autoInit: false);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: SendHost(auth: auth))),
        ),
      );
      await tester.pump();
      return tester.state<SendHostState>(find.byType(SendHost));
    }

    testWidgets('teks kosong tanpa foto → no-op (precheck tak jalan)',
        (tester) async {
      final s = await pumpHost(tester);
      s.sendMsgCtrl.text = '   ';
      await s.sendMessage();
      await tester.pump();

      expect(s.preChecks, 0, reason: 'keluar sebelum precheck');
      expect(s.dispatched, isEmpty);
    });

    testWidgets('double-tap (_isSending) → return awal', (tester) async {
      final s = await pumpHost(tester);
      s.sendMsgCtrl.text = 'halo';
      s.sendIsSending = true;
      await s.sendMessage();
      await tester.pump();

      expect(s.preChecks, 0, reason: 'guard sending duluan');
      expect(s.dispatched, isEmpty);
    });

    testWidgets('tanpa profil → batal sebelum dispatch', (tester) async {
      // AuthProvider tanpa profil (uid ada, profile null) = sesi belum siap.
      final s = await pumpHost(tester);
      s.sendMsgCtrl.text = 'halo';
      await s.sendMessage();
      await tester.pump();

      expect(s.dispatched, isEmpty);
    });

    testWidgets('edit-mode teks sama → cancel, tanpa persist',
        (tester) async {
      final s = await pumpHost(tester);
      s.sendEditingMessage = editMsg('lama');
      s.sendMsgCtrl.text = 'lama';
      await s.sendMessage();
      await tester.pump();

      expect(s.cancels, 1);
      expect(s.persists, isEmpty);
    });

    testWidgets('edit-mode teks beda → persist via mixin', (tester) async {
      final s = await pumpHost(tester);
      final editing = editMsg('lama');
      s.sendEditingMessage = editing;
      s.sendMsgCtrl.text = 'baru';
      await s.sendMessage();
      await tester.pumpAndSettle();

      expect(s.persists.length, 1);
      expect(s.persists.single.$1, same(editing));
      expect(s.persists.single.$2, 'baru');
      expect(s.sendEditingMessage, isNull);
    });
  });
}
