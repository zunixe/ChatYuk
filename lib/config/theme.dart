import 'package:flutter/material.dart';

/// Skala tipografi resmi ChatYuk — 8 ukuran, 11 token.
/// Aturan lengkap ada di AGENTS.md bagian "Tipografi".
/// JANGAN tulis `fontSize:` di file lain — pakai token ini.
/// Token berupa getter supaya warna teks ikut mode terang/gelap.
class AppText {
  AppText._();

  // 10 — timestamp, badge unread, counter overlay
  static TextStyle get micro => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: AppTheme.textPrimary);

  // 11 — label di atas nilai, helper text, chip status
  static TextStyle get caption => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: AppTheme.textPrimary);

  // 12 w600 — section label, tab, chip/badge
  static TextStyle get label => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.3,
        color: AppTheme.textPrimary);

  // 12 w400 — subtitle list, deskripsi, teks sekunder
  static TextStyle get bodySmall => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: AppTheme.textPrimary);

  // 14 w400 — bubble chat, isi dialog, composer, paragraf
  static TextStyle get body => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: AppTheme.textPrimary);

  // 14 w600 — judul list tile, label setting, nilai info
  static TextStyle get bodyStrong => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppTheme.textPrimary);

  // 16 w700 — label tombol CTA (warna ikut foregroundColor tombol)
  static TextStyle get button => const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700, height: 1.2);

  // 16 w700 — judul kartu / section (admin)
  static TextStyle get titleEmphasis => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppTheme.textPrimary);

  // 17 w700 — judul AppBar, dialog, bottom sheet
  static TextStyle get title => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppTheme.textPrimary);

  // 20 w800 — nama user di header profil
  static TextStyle get headline => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: AppTheme.textPrimary);

  // 24 w800 — saldo wallet, angka hero, tagline
  static TextStyle get display => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: AppTheme.textPrimary);
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
  AppTheme._();

  /// Mode aktif — di-set oleh ThemeProvider sebelum notifyListeners.
  static bool isDark = false;

  // ── Brand (konstan di kedua mode) ──
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color accent = Color(0xFF00BCD4);

  // ── Palet light ──
  static const _bgScreenLight = Color(0xFFF0F4F8);
  static const _bgDarkLight = Color(0xFFF5F5F5);
  static const _bgCardLight = Colors.white;
  static const _bgInputLight = Color(0xFFF0F0F0);
  static const _dividerLight = Color(0xFFE0E0E0);
  static const _textPrimaryLight = Color(0xFF212121);
  static const _textSecondaryLight = Color(0xFF757575);

  // ── Palet dark ──
  static const _bgScreenDark = Color(0xFF121212);
  static const _bgDarkDark = Color(0xFF1A1A1A);
  static const _bgCardDark = Color(0xFF1E1E1E);
  static const _bgInputDark = Color(0xFF2A2A2A);
  static const _dividerDark = Color(0xFF333333);
  static const _textPrimaryDark = Color(0xFFE6E6E6);
  static const _textSecondaryDark = Color(0xFF9E9E9E);

  // ── Warna permukaan (dinamis) ──
  static Color get bgScreen => isDark ? _bgScreenDark : _bgScreenLight;
  static Color get bgDark => isDark ? _bgDarkDark : _bgDarkLight;
  static Color get bgCard => isDark ? _bgCardDark : _bgCardLight;
  static Color get bgInput => isDark ? _bgInputDark : _bgInputLight;
  static Color get divider => isDark ? _dividerDark : _dividerLight;

  // ── Teks (dinamis) ──
  static Color get textPrimary => isDark ? _textPrimaryDark : _textPrimaryLight;
  static Color get textSecondary => isDark ? _textSecondaryDark : _textSecondaryLight;

  // ── Status (konstan) ──
  static const Color online = Color(0xFF4CAF50);
  static const Color idle = Color(0xFFFFB300);
  static const Color offline = Color(0xFFBDBDBD);
  static const Color danger = Color(0xFFF44336);
  static const Color male = Color(0xFF2196F3);
  static const Color female = Color(0xFFE91E63);

  /// Gradient header/AppBar — ikut mode (gelap di dark mode).
  static LinearGradient get headerGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF1B2A3A), Color(0xFF223447), Color(0xFF2A3E54)]
            : const [primaryDark, primary, accent],
      );

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        bgScreen: _bgScreenLight,
        bgCard: _bgCardLight,
        bgInput: _bgInputLight,
        divider: _dividerLight,
        textPrimary: _textPrimaryLight,
        textSecondary: _textSecondaryLight,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        bgScreen: _bgScreenDark,
        bgCard: _bgCardDark,
        bgInput: _bgInputDark,
        divider: _dividerDark,
        textPrimary: _textPrimaryDark,
        textSecondary: _textSecondaryDark,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color bgScreen,
    required Color bgCard,
    required Color bgInput,
    required Color divider,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isLight = brightness == Brightness.light;
    return ThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: bgScreen,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        surface: bgCard,
        onSurface: textPrimary,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? primary : const Color(0xFF1B2A3A),
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
          side: BorderSide(color: divider, width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider, width: 1.5),
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
        backgroundColor: bgCard,
        titleTextStyle: AppText.title,
        contentTextStyle: AppText.body.copyWith(color: textSecondary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? const Color(0xFF424242) : const Color(0xFF37474F),
        contentTextStyle: AppText.body.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: divider),
      popupMenuTheme: PopupMenuThemeData(
        color: bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgCard,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStatePropertyAll(
          isLight ? const Color(0xFFBDBDBD) : const Color(0xFF555555),
        ),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}