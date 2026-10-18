import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/services/chat_stream_session.dart';

MessageModel _m(String id, {String text = 'halo', bool deleted = false, bool edited = false}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime(2026, 10, 18, 9),
      isDeleted: deleted,
      edited: edited,
    );

/// Mengunci akar "pesan terhapus sempat muncul saat buka chat": tanda tangan
/// cache lama ('jumlah:idTerakhir') TIDAK berubah saat pesan dihapus/diedit →
/// cache tak pernah ditulis ulang.
void main() {
  final base = [_m('1'), _m('2'), _m('3')];

  test('isi sama → tanda tangan sama (tak menulis cache sia-sia)', () {
    expect(messageCacheSignature(base), messageCacheSignature([_m('1'), _m('2'), _m('3')]));
  });

  test('hapus pesan TENGAH (jumlah & id terakhir sama) → tanda tangan berubah', () {
    final after = [_m('1'), _m('2', deleted: true), _m('3')];
    expect(messageCacheSignature(after), isNot(messageCacheSignature(base)));
  });

  test('hapus pesan TERAKHIR → tanda tangan berubah', () {
    final after = [_m('1'), _m('2'), _m('3', deleted: true)];
    expect(messageCacheSignature(after), isNot(messageCacheSignature(base)));
  });

  test('edit teks → tanda tangan berubah', () {
    final after = [_m('1'), _m('2', text: 'halo (edit)', edited: true), _m('3')];
    expect(messageCacheSignature(after), isNot(messageCacheSignature(base)));
  });

  test('list kosong → kosong', () {
    expect(messageCacheSignature(const []), '');
  });
}
