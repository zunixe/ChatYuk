import 'package:flutter/material.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import 'search_dropdown.dart';

/// Kartu form profil (nickname/gender/umur/negara/kota/tombol) — dipakai
/// EntryScreen dan RegisterScreen supaya ukuran & tampilan selalu identik.
/// Slot [header] untuk tambahan di atas nickname (field email / judul).
class ProfileFormCard extends StatelessWidget {
  final S s;
  final Widget? header;
  final TextEditingController nicknameCtrl;
  final FocusNode nicknameFocus;
  final String? nicknameError;
  final ValueChanged<String> onNicknameChanged;
  final VoidCallback onNicknameSubmitted;
  final String gender;
  final ValueChanged<String> onGenderChanged;
  final int age;
  final ValueChanged<int> onAgeChanged;
  final String country;
  final ValueChanged<String> onCountryChanged;
  final String city;
  final ValueChanged<String> onCityChanged;
  final bool loading;
  final String submitLabel;
  final VoidCallback onSubmit;

  const ProfileFormCard({
    super.key,
    required this.s,
    this.header,
    required this.nicknameCtrl,
    required this.nicknameFocus,
    required this.nicknameError,
    required this.onNicknameChanged,
    required this.onNicknameSubmitted,
    required this.gender,
    required this.onGenderChanged,
    required this.age,
    required this.onAgeChanged,
    required this.country,
    required this.onCountryChanged,
    required this.city,
    required this.onCityChanged,
    required this.loading,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header case final h?) h,
          // Nickname
          TextField(
            controller: nicknameCtrl,
            focusNode: nicknameFocus,
            onChanged: onNicknameChanged,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.person_outline,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              labelText: s.labelUsername,
              hintText: s.hintNickname,
              suffixIcon: nicknameError != null
                  ? const Icon(Icons.cancel, color: AppTheme.danger)
                  : nicknameCtrl.text.length >= 3
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              enabledBorder: nicknameError != null
                  ? const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppTheme.danger,
                        width: 1.5,
                      ),
                    )
                  : null,
              focusedBorder: nicknameError != null
                  ? const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppTheme.danger,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onNicknameSubmitted(),
          ),
          if (nicknameError != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppTheme.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nicknameError!,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Gender
          Row(
            children: [
              Expanded(
                child: _genderCard(
                  'female',
                  '👩',
                  AppTheme.female,
                  s.labelGenderFemale,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _genderCard(
                  'male',
                  '👨',
                  AppTheme.male,
                  s.labelGenderMale,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Umur & Negara
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ageDropdown()),
              const SizedBox(width: 10),
              Expanded(child: _countryDropdown()),
            ],
          ),
          const SizedBox(height: 10),

          // Kota
          _cityDropdown(),
          const SizedBox(height: 12),

          // Tombol submit
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      submitLabel,
                      style: const TextStyle(letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderCard(String value, String emoji, Color color, String label) {
    final selected = gender == value;
    return GestureDetector(
      onTap: () => onGenderChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppTheme.divider,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : AppTheme.textSecondary,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: AppText.label.copyWith(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: AppGlyph.sm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown() {
    final ages = [for (int i = 18; i <= 60; i++) i];
    return SearchDropdown<int>(
      value: ages.contains(age) ? age : ages.first,
      label: s.labelAge,
      icon: null,
      items: ages,
      labels: [for (final a in ages) '$a'],
      textStyle: AppText.body,
      onChanged: onAgeChanged,
    );
  }

  Widget _countryDropdown() {
    final countries = kotaByNegara.keys.toList();
    return SearchDropdown(
      value: countries.contains(country) ? country : countries.first,
      label: s.labelCountry,
      icon: null,
      items: countries,
      labels: countries,
      textStyle: AppText.body,
      searchHint: s.searchCountry,
      emptyText: s.searchNoResult,
      onChanged: onCountryChanged,
    );
  }

  Widget _cityDropdown() {
    final cities = getCitiesForCountry(country);
    if (cities.isEmpty) return const SizedBox.shrink();
    final validKota = cities.contains(city) ? city : cities.first;
    return SearchDropdown<String>(
      value: validKota,
      label: s.labelCity,
      icon: Icons.location_city_outlined,
      items: cities,
      labels: cities,
      textStyle: AppText.body,
      searchHint: s.searchCity,
      emptyText: s.searchNoResult,
      onChanged: onCityChanged,
    );
  }
}
