import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/widgets/profile_form_card.dart';

/// Functional: form profil nyata (dipakai entry screen & popup profil) —
/// ketik nickname meneruskan nilai, tombol submit memicu callback,
/// tombol nonaktif saat loading.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = S(isId: true);

  Widget build({
    required TextEditingController ctrl,
    required FocusNode focus,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmit,
    VoidCallback? onSubmitted,
    bool loading = false,
    String gender = 'male',
    int age = 20,
    String country = 'Indonesia',
    String city = 'Jakarta',
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileFormCard(
              s: s,
              nicknameCtrl: ctrl,
              nicknameFocus: focus,
              nicknameError: null,
              onNicknameChanged: onChanged ?? (_) {},
              onNicknameSubmitted: onSubmitted ?? () {},
              gender: gender,
              onGenderChanged: (_) {},
              age: age,
              onAgeChanged: (_) {},
              country: country,
              onCountryChanged: (_) {},
              city: city,
              onCityChanged: (_) {},
              loading: loading,
              submitLabel: s.btnStartChat,
              onSubmit: onSubmit ?? () {},
            ),
          ),
        ),
      );

  testWidgets('ketik nickname → onChanged menerima nilai', (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    final typed = <String>[];
    await tester.pumpWidget(build(
      ctrl: ctrl,
      focus: focus,
      onChanged: typed.add,
    ));

    await tester.enterText(find.byType(TextField).first, 'Budi');
    await tester.pump();

    expect(typed, contains('Budi'));
    ctrl.dispose();
    focus.dispose();
  });

  testWidgets('tap tombol submit → onSubmit terpanggil 1×', (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    var submitted = 0;
    await tester.pumpWidget(build(
      ctrl: ctrl,
      focus: focus,
      onSubmit: () => submitted++,
    ));

    await tester.tap(find.text(s.btnStartChat));
    await tester.pump();
    expect(submitted, 1);
    ctrl.dispose();
    focus.dispose();
  });

  testWidgets('loading=true → tombol submit nonaktif', (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    var submitted = 0;
    await tester.pumpWidget(build(
      ctrl: ctrl,
      focus: focus,
      loading: true,
      onSubmit: () => submitted++,
    ));

    // Saat loading, label diganti spinner → tombol disabled (onPressed null).
    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(submitted, 0);
    ctrl.dispose();
    focus.dispose();
  });

  testWidgets('nilai gender/umur/negara/kota ikut tampil', (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(build(
      ctrl: ctrl,
      focus: focus,
      gender: 'female',
      age: 27,
      country: 'Indonesia',
      city: 'Bandung',
    ));

    expect(find.textContaining('27'), findsWidgets);
    expect(find.textContaining('Bandung'), findsWidgets);
    ctrl.dispose();
    focus.dispose();
  });
}
