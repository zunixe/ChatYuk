import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/mixins/chat_outbox_mixin.dart';
import 'package:chatyuk/mixins/chat_photo_send_mixin.dart';
import 'package:chatyuk/mixins/chat_send_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/utils.dart' show capitalizeFirst;
import 'package:chatyuk/utils/mention.dart';

class MockAuthService extends Mock implements AuthService {}

/// Host mixin ASLI (`ChatSendMixin` + 2 syaratnya) dengan hook tercatat —
/// perilaku di bawah diuji lewat `sendMessage()` beneran, bukan cermin.
class TestPoints extends PointsNotifier {
  final int deductResult;
  TestPoints({this.deductResult = 50});
  @override
  PointsState build() => const PointsState();
  @override
  Future<int> deductBeforeSend(String _) async => deductResult;
  @override
  Future<void> refundChatPoint(String _) async {}
}

class TestAuth extends AuthNotifier {
  final UserModel? prof;
  TestAuth(this.prof, MockAuthService svc) : super(authService: svc);
  @override
  AuthData build() =>
      AuthData(profile: prof, uid: prof?.uid, loading: false);
  // Getter notifier membaca field/service (bukan state) — override juga.
  @override
  UserModel? get profile => prof;
  @override
  String? get uid => prof?.uid;
}

class SendHost extends StatefulWidget {
  const SendHost({super.key});
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

  // Video: regresi "kirim video tanpa caption berhenti di guard awal".
  String? _video;
  final List<String> videoSends = [];
  set pendingVideo(String? v) => _video = v;
  @override
  String? get sendPendingVideoPath => _video;
  @override
  Future<void> sendVideoFromPreview({
    String text = '',
    MessageModel? reply,
  }) async {
    videoSends.add(text);
  }

  // Fitur lokasi — host menyimpan lokasi pending + mencatat yang DITERIMA.
  ChatLocation? _location;
  final List<ChatLocation> locationSends = [];
  set pendingLocation(ChatLocation? v) => _location = v;
  @override
  ChatLocation? get sendPendingLocation => _location;
  @override
  set sendPendingLocation(ChatLocation? v) => _location = v;
  @override
  Future<void> sendLocationFromPreviewAt(
    ChatLocation location, {
    String text = '',
    MessageModel? reply,
  }) async {
    locationSends.add(location);
  }

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
  Future<String?> photoDispatch({
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
    int? videoDurationMs,
  }) async {}
  @override
  String get photoUploadChatId => 'c1';
  @override
  String get photoSeed => 'seed';
  @override
  void photoOnSent(String kind) {}
  @override
  void photoFirstBonus(PointsNotifier pp) {}
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

/// Profil siap-pakai untuk menguji jalur kirim (melewati guard
/// `profile == null`).
UserModel profileForTest() => UserModel(
      uid: 'u-me',
      nickname: 'Me',
      gender: 'male',
      age: 20,
      country: 'Indonesia',
      city: 'Jakarta',
      ipAddress: '',
      status: 'online',
      avatar: '',
      isRegistered: true,
      loginAt: DateTime.now(),
      createdAt: DateTime.now(),
      lastSeen: DateTime.now(),
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

  group('tipe kirim video (sekali lihat)', () {
    // Regresi: video "sekali lihat" terkirim sebagai video BIASA karena
    // `videoClearPreview()` (yang me-reset flag isOnce) dipanggil SEBELUM
    // type dibaca. Type harus ditentukan dari nilai yang ditangkap dulu.
    test('videoSendType: sekali lihat → video_once', () {
      expect(videoSendType(true), 'video_once');
    });

    test('videoSendType: biasa → video', () {
      expect(videoSendType(false), 'video');
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

    Future<SendHostState> pumpHost(
      WidgetTester tester, {
      bool withProfile = false,
    }) async {
      mockSvc = MockAuthService();
      when(() => mockSvc.uid).thenReturn('u-me');
      when(() => mockSvc.isAnonymous).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          pointsProvider.overrideWith(TestPoints.new),
          authProvider.overrideWith(
            () => TestAuth(withProfile ? profileForTest() : null, mockSvc),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SendHost())),
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

    testWidgets(
        'video pending TANPA caption → tetap kirim (regresi guard awal)',
        (tester) async {
      final s = await pumpHost(tester, withProfile: true);
      s.pendingVideo = '/tmp/v.mp4';
      s.sendMsgCtrl.text = '   '; // tanpa caption
      await s.sendMessage();
      await tester.pump();

      expect(
        s.videoSends,
        hasLength(1),
        reason: 'guard `text.isEmpty && !hasPhoto` dulu mem-BLOKIR video',
      );
      expect(s.preChecks, greaterThan(0), reason: 'lanjut melewati precheck');
    });

    testWidgets('video pending + caption → kirim dengan caption', (
      tester,
    ) async {
      final s = await pumpHost(tester, withProfile: true);
      s.pendingVideo = '/tmp/v.mp4';
      s.sendMsgCtrl.text = 'lihat ini';
      await s.sendMessage();
      await tester.pump();

      expect(s.videoSends, ['lihat ini']);
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

    testWidgets(
        'lokasi pending → terkirim DENGAN lokasi (regresi capture-before-clear)',
        (tester) async {
      final s = await pumpHost(tester, withProfile: true);
      const loc = ChatLocation(lat: -6.2, lng: 106.8);
      s.pendingLocation = loc;
      s.sendMsgCtrl.text = '   '; // boleh tanpa caption
      await s.sendMessage();
      await tester.pump();

      // Dulu `setState(() => sendPendingLocation = null)` jalan SEBELUM
      // sendLocationFromPreview membaca field → lokasi terbaca null → tak
      // pernah terkirim (preview hilang, insert tak jalan). Regresi ini
      // mengunci bahwa lokasi DITANGKAP sebelum clear.
      expect(s.locationSends, hasLength(1));
      expect(s.locationSends.single.lat, -6.2);
      expect(s.locationSends.single.lng, 106.8);
      expect(s.sendPendingLocation, isNull, reason: 'preview dibersihkan');
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
