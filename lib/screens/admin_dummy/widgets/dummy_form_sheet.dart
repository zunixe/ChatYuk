import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../widgets/profile_form_card.dart';

/// Isi bottom sheet form dummy: judul + tombol X + form profil.
/// State (controller + nilai + aksi simpan) milik screen — widget ini murni
/// tampil, semua interaksi diteruskan via callback.
class DummyFormSheet extends StatelessWidget {
  final S s;
  final bool isEdit;
  final TextEditingController nickCtrl;
  final FocusNode nicknameFocus;
  final String? nicknameError;
  final String gender;
  final int age;
  final String country;
  final String city;
  final bool busy;
  final VoidCallback onClose;
  final ValueChanged<String> onNicknameChanged;
  final VoidCallback onNicknameSubmitted;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<int> onAgeChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onCityChanged;
  final VoidCallback onSubmit;

  const DummyFormSheet({
    super.key,
    required this.s,
    required this.isEdit,
    required this.nickCtrl,
    required this.nicknameFocus,
    required this.nicknameError,
    required this.gender,
    required this.age,
    required this.country,
    required this.city,
    required this.busy,
    required this.onClose,
    required this.onNicknameChanged,
    required this.onNicknameSubmitted,
    required this.onGenderChanged,
    required this.onAgeChanged,
    required this.onCountryChanged,
    required this.onCityChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isEdit ? '${s.dummyEdit} Dummy' : s.dummyCreateTitle,
                style: AppText.titleEmphasis,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close),
              color: AppTheme.textSecondary,
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          s.dummyRegisterHint,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 10),
        ProfileFormCard(
          s: s,
          nicknameCtrl: nickCtrl,
          nicknameFocus: nicknameFocus,
          nicknameError: nicknameError,
          onNicknameChanged: onNicknameChanged,
          onNicknameSubmitted: onNicknameSubmitted,
          gender: gender,
          onGenderChanged: onGenderChanged,
          age: age,
          onAgeChanged: onAgeChanged,
          country: country,
          onCountryChanged: onCountryChanged,
          city: city,
          onCityChanged: onCityChanged,
          loading: busy,
          submitLabel: isEdit ? s.dummySaveChanges : s.dummyRegisterBtn,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}
