import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Kolom pencarian admin: bulat 10, isi `bgInput`, ikon kaca pembesar.
/// Menggantikan TextField identik di tab Perangkat/Terhapus/Dummy/Pengguna
/// Online.
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final EdgeInsets padding;

  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hint,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgInput,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
