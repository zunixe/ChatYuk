import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/room_categories.dart';
import '../../../config/theme.dart';
import '../../../providers/locale_provider.dart';

/// Baris chip kategori horizontal: Rame (agregat) + 10 kategori.
/// Scroll ke pinggir ala gambar — chip aktif tint primary.
class CategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const CategoryChips({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: roomCategories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final bool isRame = i == 0;
          final String id =
              isRame ? 'rame' : '${roomCategories[i - 1]['id']}';
          final String icon =
              isRame ? '🔥' : '${roomCategories[i - 1]['icon']}';
          final String label =
              isRame ? s.exploreRame : s.roomName(id);
          final active = selected == id;
          return ChoiceChip(
            label: Text('$icon $label'),
            labelStyle: AppText.label.copyWith(
              color: active ? AppTheme.primary : AppTheme.textSecondary,
            ),
            selected: active,
            onSelected: (_) => onSelect(id),
            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
            backgroundColor: AppTheme.bgCard,
            side: BorderSide(
              color: active
                  ? AppTheme.primary
                  : AppTheme.textSecondary.withValues(alpha: 0.3),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}
