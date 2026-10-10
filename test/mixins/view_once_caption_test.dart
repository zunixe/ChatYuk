import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/mixins/chat_outbox_mixin.dart';
import 'package:chatyuk/mixins/chat_photo_send_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/points_service.dart';
import 'package:chatyuk/services/storage_photo_service.dart';

class MockAuthService extends Mock implements AuthService {}
class MockStorage extends Mock implements StoragePhotoService {}
class MockPointsService extends Mock implements PointsService {}

class TestAuth extends AuthNotifier {
  final UserModel? prof;
  TestAuth(this.prof, MockAuthService svc) : super(authService: svc);
  @override
  AuthData build() =>
      AuthData(profile: prof, uid: prof?.uid, loading: false);
  @override
  UserModel? get profile => prof;
  @override
  String? get uid => prof?.uid;
}

class TestPoints extends PointsNotifier {
  TestPoints(MockPointsService svc) : super(service: svc);
  @override
  PointsState build() => const PointsState();
  @override
  Future<int> deductBeforeSend(String _) async => 100;
  @override
  Future<void> refundChatPoint(String _) async {}
}

/// Host mixin ASLI: `ChatPhotoSendMixin` di atas `ChatOutboxMixin`.
/// `pickViewOnceImage` di-override supaya alur caption bisa diuji tanpa
/// plugin image_picker; `photoDispatch` mencatat `text` yang benar-benar
/// diteruskan (sink akhir).
class ViewOnceHost extends StatefulWidget {
  const ViewOnceHost({super.key});
  @override
  State<ViewOnceHost> createState() => ViewOnceHostState();
}

class ViewOnceHostState extends State<ViewOnceHost>
    with ChatOutboxMixin<ViewOnceHost>, ChatPhotoSendMixin<ViewOnceHost> {
  // Composer tiruan.
  String composer = '';
  MessageModel? reply;
  int cleared = 0;

  @override
  String get photoComposerText => composer;
  @override
  MessageModel? get photoReplyingTo => reply;
  @override
  void photoClearComposerText() {
    cleared++;
    composer = '';
    reply = null;
  }

  // Bytes gambar tiruan (bukan gambar valid → processChatPhoto null).
  // Karena itu kita override pickViewOnceImage & proses watermark dimatikan
  // lewat watermarkEnabled=false → jalur processChatPhoto juga null.
  // Untuk menguji CAPTION saja, kita override `_sendImageLike` behavior
  // lewat photoDispatch setelah upload mock mengembalikan path.
  // Bytes gambar valid kecil (biar processChatPhoto menghasilkan base64).
  Uint8List? fakeBytes = Uint8List.fromList(img.encodePng(
    img.Image(width: 4, height: 4),
  ));

  @override
  Future<Uint8List?> pickViewOnceImage() async => fakeBytes;

  // Hindari compute()/isolate di test (bisa menggantung di fake-async).
  @override
  Future<String?> processViewOnceBytes(Uint8List bytes) async => 'ZmFrZQ==';

  // Rekam dispatch akhir (imageData, type, text).
  final List<(String type, String text)> dispatched = [];

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
  }) async {
    dispatched.add((type, text));
  }

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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

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

void main() {
  late MockAuthService mockSvc;
  late MockStorage mockStorage;

  setUp(() {
    mockSvc = MockAuthService();
    when(() => mockSvc.uid).thenReturn('u-me');
    when(() => mockSvc.isAnonymous).thenReturn(false);

    mockStorage = MockStorage();
    StoragePhotoService.overrideInstance(mockStorage);
    when(() => mockStorage.upload(
          chatId: any(named: 'chatId'),
          base64: any(named: 'base64'),
        )).thenAnswer((_) async => 'storage/path.jpg');

    // Points hermetic via Riverpod override (dibuat di pump).
  });

  tearDown(() {
    StoragePhotoService.restoreInstance();
  });

  Future<ViewOnceHostState> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        pointsProvider.overrideWith(() => TestPoints(MockPointsService())),
        authProvider.overrideWith(
          () => TestAuth(profileForTest(), mockSvc),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ViewOnceHost())),
      ),
    );
    await tester.pump();
    return tester.state<ViewOnceHostState>(find.byType(ViewOnceHost));
  }

  testWidgets('view-once + caption terketik → caption IKUT terkirim',
      (tester) async {
    final s = await pump(tester);
    s.composer = 'ini caption rahasia';
    await s.sendViewOnceFromPicker();
    await tester.pump();

    expect(s.dispatched, hasLength(1),
        reason: 'view-once harus terkirim');
    expect(s.dispatched.single.$1, 'view_once');
    // Regresi: dulu caption diabaikan → teks user hilang saat kirim foto
    // sekali-lihat. Sekarang caption WAJIB terbawa + dikapitalkan.
    expect(s.dispatched.single.$2, 'Ini caption rahasia');
    expect(s.cleared, greaterThan(0), reason: 'composer dibersihkan');
    expect(s.composer, isEmpty);
  });

  testWidgets('view-once tanpa caption → tetap kirim (caption kosong)',
      (tester) async {
    final s = await pump(tester);
    s.composer = '   ';
    await s.sendViewOnceFromPicker();
    await tester.pump();

    expect(s.dispatched, hasLength(1));
    expect(s.dispatched.single.$1, 'view_once');
    expect(s.dispatched.single.$2, isEmpty);
  });

  testWidgets('view-once + balasan aktif → balasan dipakai untuk view-once',
      (tester) async {
    final s = await pump(tester);
    s.composer = 'balas ini';
    s.reply = MessageModel(
      id: 'm0',
      senderId: 'u-other',
      senderName: 'Budi',
      senderGender: 'male',
      isRegistered: true,
      text: 'pesan lama',
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
    );
    await s.sendViewOnceFromPicker();
    await tester.pump();

    expect(s.dispatched, hasLength(1));
    expect(s.dispatched.single.$2, 'Balas ini');
    expect(s.reply, isNull, reason: 'status balas dibersihkan');
  });

  testWidgets('picker batal (bytes null) → tidak kirim, composer utuh',
      (tester) async {
    final s = await pump(tester);
    s.composer = 'tetap ada';
    s.fakeBytes = null;
    await s.sendViewOnceFromPicker();
    await tester.pump();

    expect(s.dispatched, isEmpty);
    expect(s.composer, 'tetap ada', reason: 'batal → jangan hapus teks');
    expect(s.cleared, 0);
  });
}
