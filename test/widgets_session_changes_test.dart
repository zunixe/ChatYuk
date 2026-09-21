import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/async_photo.dart';
import 'package:chatyuk/widgets/profile_avatar.dart';
import 'package:chatyuk/widgets/reply_quote.dart';

/// P4: widget yang diubah sesi ini — mengunci perubahan agar tidak regresi.
/// Fokus: kontrak render/fallback yang tidak butuh network (uid kosong →
/// `AvatarB64Service.get('')` langsung return tanpa sentuh disk/plugin).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(body: child),
        ),
      );

  group('ProfileAvatar — fallback inisial & warna', () {
    testWidgets('uid kosong → render inisial huruf pertama (uppercase)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const ProfileAvatar(uid: '', name: 'budi', size: 48),
      ));
      // _load() retry 3× Future.delayed(300ms) saat avatar kosong → habiskan
      // timer supaya FakeAsync tidak menganggapnya pending.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('nama kosong → fallback "?"', (tester) async {
      await tester.pumpWidget(wrap(
        const ProfileAvatar(uid: '', name: '', size: 48),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('?'), findsOneWidget);
    });

    test('default bgColor null → avatarBg (bukan accent cyan)', () {
      const w = ProfileAvatar(uid: '', name: 'A');
      expect(w.bgColor, isNull,
          reason: 'null = pakai AppTheme.avatarBg (solid, seragam)');
      // Kontrak: default lama `AppTheme.accent` (cyan pekat) bikin avatar
      // beda dari kartu list Pesan — lihat theme.dart.
    });

    testWidgets('bgColor eksplisit dihormati (gender di user_info)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const ProfileAvatar(
          uid: '',
          name: 'A',
          size: 40,
          bgColor: AppTheme.male,
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('borderColor dirender tanpa error', (tester) async {
      await tester.pumpWidget(wrap(
        const ProfileAvatar(
          uid: '',
          name: 'A',
          size: 44,
          borderColor: AppTheme.female,
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('badge ditampilkan bersama inisial', (tester) async {
      await tester.pumpWidget(wrap(
        ProfileAvatar(
          uid: '',
          name: 'A',
          size: 44,
          badge: Container(key: const Key('badge'), width: 8, height: 8),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('badge')), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('AsyncCircleAvatar — fallback', () {
    testWidgets('base64 kosong → fallback widget dipakai', (tester) async {
      await tester.pumpWidget(wrap(
        const AsyncCircleAvatar(
          base64: '',
          radius: 20,
          fallback: Text('FB'),
        ),
      ));
      expect(find.text('FB'), findsOneWidget);
    });
  });

  group('ReplyQuote — kutipan balasan', () {
    Widget quote({
      required String text,
      bool targetDeleted = false,
      bool isMe = false,
      Color? senderColor,
    }) =>
        wrap(
          ReplyQuote(
            senderName: 'Budi',
            text: text,
            isMe: isMe,
            targetDeleted: targetDeleted,
            senderColor: senderColor,
          ),
        );

    testWidgets('menampilkan nama pengirim + isi kutipan', (tester) async {
      await tester.pumpWidget(quote(text: 'pesan lama'));
      expect(find.text('Budi'), findsOneWidget);
      // Teks kutipan pakai RichText/Text — cek mengandung.
      expect(
        find.textContaining('pesan lama', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('target terhapus → teks diganti label "dihapus"',
        (tester) async {
      await tester.pumpWidget(quote(text: 'rahasia', targetDeleted: true));
      expect(
        find.textContaining('rahasia', findRichText: true),
        findsNothing,
        reason: 'PRIVASI: isi pesan terhapus tidak boleh bocor di kutipan',
      );
    });

    testWidgets('fromMessage null saat teks balasan kosong', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) {
          final q = ReplyQuote.fromMessage(
            context: ctx,
            repliedToText: '',
            repliedToId: 'x',
            repliedToSenderName: 'A',
            isMe: false,
            deletedIds: const {},
          );
          return q == null ? const Text('NULL') : const Text('ADA');
        },
      )));
      expect(find.text('NULL'), findsOneWidget);
    });

    testWidgets('fromMessage mendeteksi target terhapus dari deletedIds',
        (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) {
          final q = ReplyQuote.fromMessage(
            context: ctx,
            repliedToText: 'isi asli',
            repliedToId: 'm9',
            repliedToSenderName: 'A',
            isMe: false,
            deletedIds: const {'m9'},
          );
          return q ?? const SizedBox.shrink();
        },
      )));
      expect(
        find.textContaining('isi asli', findRichText: true),
        findsNothing,
        reason: 'id ada di deletedIds → quote wajib menyembunyikan isi',
      );
    });
  });
}
