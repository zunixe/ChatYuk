import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/storage_provider.dart';
import 'package:chatyuk/services/storage_photo_service.dart';

class MockStorageService extends Mock implements StoragePhotoService {}

void main() {
  late MockStorageService svc;
  late StorageProvider p;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    svc = MockStorageService();
    p = StorageProvider(service: svc);
  });

  test('upload meneruskan chatId + base64 ke service', () async {
    when(() => svc.upload(chatId: 'c1', base64: 'b64'))
        .thenAnswer((_) async => 'path/1');
    expect(await p.upload(chatId: 'c1', base64: 'b64'), 'path/1');
    verify(() => svc.upload(chatId: 'c1', base64: 'b64')).called(1);
  });

  test('uploadVoice meneruskan bytes', () async {
    when(() => svc.uploadVoice(chatId: 'c1', bytes: any(named: 'bytes')))
        .thenAnswer((_) async => 'voice/1.m4a');
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(await p.uploadVoice(chatId: 'c1', bytes: bytes), 'voice/1.m4a');
  });

  test('predikat path diteruskan (isPath/isAvatarPath/isVoicePath)', () {
    when(() => svc.isPath('x')).thenReturn(true);
    when(() => svc.isAvatarPath('a')).thenReturn(false);
    when(() => svc.isVoicePath('v')).thenReturn(true);
    expect(p.isPath('x'), true);
    expect(p.isAvatarPath('a'), false);
    expect(p.isVoicePath('v'), true);
  });

  test('properti path helper diteruskan', () {
    when(() => svc.avatarPath('u')).thenReturn('avatars/u.jpg');
    when(() => svc.voicePath('c')).thenReturn('voice/c.m4a');
    expect(p.avatarPath('u'), 'avatars/u.jpg');
    expect(p.voicePath('c'), 'voice/c.m4a');
  });
}
