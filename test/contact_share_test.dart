import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/chat_contact.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/services/device_contacts_service.dart';

/// Kirim KONTAK: payload dua bentuk (ChatYuk = uid saja, HP = nama+nomor),
/// ikut cache pesan, label bilingual, dan filter buku kontak.
void main() {
  group('ChatContact payload', () {
    test('ChatYuk: payload HANYA uid (tanpa nama/nomor)', () {
      final c = ChatContact.user('u-1', name: 'Budi');
      expect(c.toJson(), {'t': 'user', 'u': 'u-1'});
      expect(c.toJson().containsKey('n'), isFalse);
      expect(c.toJson().containsKey('p'), isFalse);
      expect(c.previewText(), '📇 Budi');
    });

    test('HP: nama + daftar nomor', () {
      final c = ChatContact.phone('Budi HP', ['+6281', '+6282']);
      expect(c.toJson(), {
        't': 'phone',
        'n': 'Budi HP',
        'p': ['+6281', '+6282'],
      });
      expect(c.previewText(), '📇 Budi HP');
    });

    test('parse toleran (Map & string JSON), tolak tak valid', () {
      expect(ChatContact.tryParse({'t': 'user', 'u': 'x'})!.uid, 'x');
      expect(
        ChatContact.tryParse('{"t":"phone","n":"A","p":["+62"]}')!.phones,
        ['+62'],
      );
      expect(ChatContact.tryParse({'t': 'user'}), isNull);
      expect(ChatContact.tryParse({'t': 'phone', 'n': '', 'p': []}), isNull);
      expect(ChatContact.tryParse('rusak'), isNull);
      expect(ChatContact.tryParse(42), isNull);
    });

    test('nomor per kontak dibatasi (maxPhones) & kosong dibuang', () {
      final c = ChatContact.phone('X', [' ', '+1', '+2', '+3', '+4', '+5', '+6']);
      expect(c.phones.length, ChatContact.maxPhones);
      expect(c.phones.first, '+1');
    });
  });

  group('MessageModel + contact (cache lokal)', () {
    test('roundtrip toMap/fromMap membawa contact', () {
      final m = MessageModel(
        id: '9',
        senderId: 'u1',
        senderName: 'A',
        senderGender: 'male',
        isRegistered: true,
        text: '📇 Budi',
        type: 'contact',
        imageData: '',
        timestamp: DateTime(2026, 10, 18, 20),
        contact: ChatContact.user('u-2', name: 'Budi'),
      );
      final back = MessageModel.fromMap('9', m.toMap());
      expect(back.contact!.uid, 'u-2');
      expect(back.contact!.isUser, isTrue);
    });

    test('contact hilang saat pesan dihapus', () {
      final m = MessageModel(
        id: '9',
        senderId: 'u1',
        senderName: 'A',
        senderGender: 'male',
        isRegistered: true,
        text: '📇 Budi',
        type: 'contact',
        imageData: '',
        timestamp: DateTime(2026, 10, 18, 20),
        contact: ChatContact.phone('Budi', ['+6281']),
      );
      expect(m.copyWith(isDeleted: true).contact, isNull);
    });
  });

  group('Filter buku kontak HP (fungsi murni)', () {
    const all = [
      DeviceContact(id: '1', name: 'Budi', phones: ['+6281']),
      DeviceContact(id: '2', name: 'Ani', phones: ['+6282']),
      DeviceContact(id: '3', name: 'Budi Santoso', phones: ['+6283']),
    ];

    test('query kosong = semua', () {
      expect(DeviceContactsService.filter(all, '  ').length, 3);
    });

    test('cocok substring & case-insensitive', () {
      final r = DeviceContactsService.filter(all, 'bUdI');
      expect(r.map((e) => e.id).toList(), ['1', '3']);
    });

    test('tidak ada hasil', () {
      expect(DeviceContactsService.filter(all, 'zzz'), isEmpty);
    });
  });

  test('label kontak bilingual', () {
    expect(S(isId: true).menuSendContact, 'Kontak');
    expect(S(isId: false).menuSendContact, 'Contact');
    expect(S(isId: true).contactTabPhone, 'Kontak HP');
    expect(S(isId: false).contactTabPhone, 'Phone contacts');
    expect(S(isId: true).btnCopyNumber, 'Salin nomor');
    expect(S(isId: false).btnCopyNumber, 'Copy number');
    expect(S(isId: true).errSendContact, contains('kontak'));
    expect(S(isId: false).errSendContact.toLowerCase(), contains('contact'));
  });
}
