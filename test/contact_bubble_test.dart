import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/models/chat_contact.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/contact_bubble.dart';
import 'package:chatyuk/widgets/contact_picker_sheet.dart';

/// Kartu KONTAK: nama dari teks (aman surrogate pair), lebar = lebar media
/// chat (anti-overlap), aksi HP pakai Wrap (tak meluber), + merge pemilih.
MessageModel contactMsg(ChatContact c, {String text = '', String id = '77'}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: text.isEmpty ? c.previewText() : text,
      type: 'contact',
      imageData: '',
      timestamp: DateTime(2026, 10, 18, 21),
      contact: c,
    );

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp(home: Scaffold(body: child))),
  );
  await tester.pump();
}

void main() {
  group('contactNameFromText (murni)', () {
    test('buang emoji 📇 tanpa merusak UTF-16 (surrogate pair)', () {
      expect(contactNameFromText('📇 Budi'), 'Budi');
      expect(contactNameFromText('📇  Budi Santoso '), 'Budi Santoso');
      expect(contactNameFromText('📇'), '');
      expect(contactNameFromText('Budi'), 'Budi');
      // Teks dengan emoji di nama tetap utuh.
      expect(contactNameFromText('📇 Budi 🎉'), 'Budi 🎉');
    });
  });

  group('mergePickerUsers (murni)', () {
    test('gabung teman ∪ pernah chat, dedupe, urut nama', () {
      final out = mergePickerUsers(
        friends: [
          {'uid': 'b', 'nickname': 'Budi', 'gender': 'male', 'avatar': 'x'},
          {'uid': '', 'nickname': 'Kosong'},
        ],
        chatted: [
          (uid: 'a', name: 'Ani', gender: 'female'),
          // Sudah ada sebagai teman → tidak menimpa data teman.
          (uid: 'b', name: 'Budi (chat)', gender: 'male'),
          (uid: '', name: 'Rusak', gender: ''),
        ],
      );
      expect(out.map((e) => e.uid).toList(), ['a', 'b']);
      expect(out.first.name, 'Ani');
      expect(out.last.name, 'Budi'); // dari teman (punya avatar)
      expect(out.last.avatar, 'x');
    });
  });

  testWidgets('kontak HP: nomor + aksi, lebar dibatasi lebar media chat', (
    tester,
  ) async {
    await pump(
      tester,
      ContactBubble(
        msg: contactMsg(ChatContact.phone('Budi HP', ['+6281200000001'])),
        timeStr: '21:01',
      ),
    );
    expect(find.text('Budi HP'), findsOneWidget);
    expect(find.textContaining('+6281200000001'), findsOneWidget);
    expect(find.text('Salin nomor'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Telepon'), findsOneWidget);
    expect(find.text('Lihat profil'), findsNothing);
    expect(tester.takeException(), isNull); // tanpa overflow RenderFlex
    // Anti-overlap: kartu tidak lebih lebar dari lebar media chat.
    final size = tester.getSize(find.byType(ContactBubble));
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(size.width, lessThanOrEqualTo(chatMediaWidth(screenW)));
  });

  testWidgets('kontak HP: nama & 3 nomor panjang → aksi Wrap, tanpa overflow', (
    tester,
  ) async {
    await pump(
      tester,
      ContactBubble(
        msg: contactMsg(
          ChatContact.phone('Budi Santoso Wijaya Kusuma Atmaja', [
            '+62812000000011111',
            '+62812000000022222',
            '+62812000000033333',
          ]),
        ),
        timeStr: '21:02',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Salin nomor'), findsOneWidget);
    // Tombol aksi LEBAR SAMA (rapi/sejajar) — permintaan user.
    double w(String label) => tester
        .getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        ).first)
        .width;
    expect((w('Salin nomor') - w('WhatsApp')).abs(), lessThan(0.5));
    expect((w('WhatsApp') - w('Telepon')).abs(), lessThan(0.5));
    final size = tester.getSize(find.byType(ContactBubble));
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(size.width, lessThanOrEqualTo(chatMediaWidth(screenW)));
  });
}
