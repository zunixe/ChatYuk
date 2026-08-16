import 'package:flutter/material.dart';

/// Skala tipografi resmi ChatYuk — 8 ukuran, 11 token.
/// Aturan lengkap ada di AGENTS.md bagian "Tipografi".
/// JANGAN tulis `fontSize:` di file lain — pakai token ini.
class AppText {
  AppText._();

  // 10 — timestamp, badge unread, counter overlay
  static const TextStyle micro = TextStyle(
    fontSize: 10, fontWeight: FontWeight.w500, height: 1.2, color: AppTheme.textPrimary);

  // 11 — label di atas nilai, helper text, chip status
  static const TextStyle caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400, height: 1.3, color: AppTheme.textPrimary);

  // 12 w600 — section label, tab, chip/badge
  static const TextStyle label = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.3, color: AppTheme.textPrimary);

  // 12 w400 — subtitle list, deskripsi, teks sekunder
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, height: 1.35, color: AppTheme.textPrimary);

  // 14 w400 — bubble chat, isi dialog, composer, paragraf
  static const TextStyle body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.35, color: AppTheme.textPrimary);

  // 14 w600 — judul list tile, label setting, nilai info
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: AppTheme.textPrimary);

  // 16 w700 — label tombol CTA (warna ikut foregroundColor tombol)
  static const TextStyle button = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, height: 1.2);

  // 16 w700 — judul kartu / section (admin)
  static const TextStyle titleEmphasis = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, height: 1.25, color: AppTheme.textPrimary);

  // 17 w700 — judul AppBar, dialog, bottom sheet
  static const TextStyle title = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w700, height: 1.25, color: AppTheme.textPrimary);

  // 20 w800 — nama user di header profil
  static const TextStyle headline = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w800, height: 1.2, color: AppTheme.textPrimary);

  // 24 w800 — saldo wallet, angka hero, tagline
  static const TextStyle display = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w800, height: 1.15, color: AppTheme.textPrimary);
}

/// Ukuran emoji & ikon dekoratif (bukan teks). Lihat AGENTS.md.
class AppGlyph {
  AppGlyph._();

  static const double sm = 20; // emoji inline, ikon room list
  static const double md = 24; // emoji bubble, sel emoji picker
  static const double lg = 28; // emoji gift picker
  static const double xl = 40; // emoji empty state

  /// Ukuran inisial avatar proporsional terhadap diameter bulatan.
  /// Rasio tetap 0.38 supaya konsisten di semua avatar.
  static double avatarInitial(double diameter) => diameter * 0.38;
}

class AppTheme {
  // ── Brand ──
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color accent = Color(0xFF00BCD4);

  // ── Light background ──
  static const Color bgScreen = Color(0xFFF0F4F8);
  static const Color bgDark = Color(0xFFF5F5F5);
  static const Color bgCard = Colors.white;
  static const Color bgInput = Color(0xFFF0F0F0);
  static const Color divider = Color(0xFFE0E0E0);

  // ── Text ──
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  // ── Status ──
  static const Color online = Color(0xFF4CAF50);
  static const Color idle = Color(0xFFFFB300);
  static const Color offline = Color(0xFFBDBDBD);
  static const Color danger = Color(0xFFF44336);
  static const Color male = Color(0xFF2196F3);
  static const Color female = Color(0xFFE91E63);

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        primaryColor: primary,
        scaffoldBackgroundColor: bgScreen,
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: bgCard,
          error: danger,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: AppText.title.copyWith(color: Colors.white),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        textTheme: TextTheme(
          displaySmall: AppText.display,
          headlineSmall: AppText.headline,
          titleLarge: AppText.title,
          titleMedium: AppText.titleEmphasis,
          bodyLarge: AppText.bodyStrong,
          bodyMedium: AppText.body,
          bodySmall: AppText.bodySmall,
          labelLarge: AppText.button,
          labelMedium: AppText.label,
          labelSmall: AppText.caption,
        ),
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: divider, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          hintStyle: AppText.body.copyWith(color: textSecondary),
          labelStyle: AppText.body.copyWith(color: textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppText.button,
            elevation: 0,
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: bgCard,
          selectedItemColor: primary,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: AppText.label,
          unselectedLabelStyle: AppText.label.copyWith(fontWeight: FontWeight.w400),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: bgInput,
          selectedColor: primary.withValues(alpha: 0.15),
          labelStyle: AppText.label.copyWith(color: textPrimary, letterSpacing: 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        listTileTheme: ListTileThemeData(
          titleTextStyle: AppText.bodyStrong,
          subtitleTextStyle: AppText.bodySmall.copyWith(color: textSecondary),
        ),
        tabBarTheme: TabBarThemeData(
          labelStyle: AppText.bodyStrong,
          unselectedLabelStyle: AppText.body,
        ),
        dialogTheme: DialogThemeData(
          titleTextStyle: AppText.title,
          contentTextStyle: AppText.body.copyWith(color: textSecondary),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 6,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF424242),
          contentTextStyle: AppText.body.copyWith(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dividerTheme: const DividerThemeData(color: divider),
      );
}
