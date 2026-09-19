import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fonts.dart';

/// Skala tipografi resmi ChatYuk — 8 ukuran, 11 token.
/// Aturan lengkap ada di AGENTS.md bagian "Tipografi".
/// JANGAN tulis `fontSize:` di file lain — pakai token ini.
/// Token berupa getter supaya warna teks ikut mode terang/gelap.
///
/// Font mengikuti [AppFonts.current] (dipilih admin, global realtime):
/// - key 'default' → judul/CTA Poppins, body Roboto (perilaku lama).
/// - key lain (mis. 'inter') → SEMUA token teks memakai font itu.
/// Blok kode [code] selalu monospace, tidak terpengaruh.
class AppText {
  AppText._();

  // ── Helper font dinamis ──
  /// Token judul/CTA: Poppins saat default, font terpilih saat override.
  static TextStyle _brand(
    double size,
    FontWeight weight, {
    double? height,
    Color? color,
    double? letterSpacing,
  }) {
    final family = AppFonts.family();
    if (family == null) {
      // System: judul pakai font bawaan perangkat (bukan Poppins).
      // Weight: null = biarkan berat natural font sistem (ramping seperti
      // WhatsApp), selain itu pakai hasil pemetaan _systemWeight.
      if (AppFonts.isSystem()) {
        return TextStyle(
          fontSize: size,
          fontWeight: _systemWeight(weight),
          height: height,
          color: color,
          letterSpacing: letterSpacing,
        );
      }
      return GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
        letterSpacing: letterSpacing,
      );
    }
    return GoogleFonts.getFont(
      family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Token body: Roboto (tanpa fontFamily) saat default, font terpilih
  /// saat override.
  ///
  /// PENTING: saat override, WAJIB lewat `the underlying provider Fonts.getFont`
  /// (bukan `TextStyle(fontFamily: 'Inter')`) karena font runtime the underlying provider Fonts
  /// terdaftar dengan nama family internal ber-suffix (mis. `Inter_regular`,
  /// `Inter_700`) + `fontFamilyFallback`. `TextStyle(fontFamily: 'Inter')`
  /// TIDAK memetakan ke font itu → teks jatuh ke default (bug "cuma header
  /// yang berubah").
  static TextStyle _plain(
    double size,
    FontWeight weight, {
    required double height,
    required Color color,
    double? letterSpacing,
  }) {
    final family = AppFonts.family();
    if (family != null) {
      return GoogleFonts.getFont(
        family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    // Ramping ala WA: bobot diteruskan apa adanya supaya w300 benar-benar
    // tipis (Roboto Light). Pemetaan null dulu membuat w300 jatuh ke regular
    // sehingga list pesan tetap terlihat tebal seperti Roboto.
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// Token KHUSUS chat: ramping ala WhatsApp walau global = Default.
  ///
  /// Roboto Regular (w400) bawaan terlihat lebih tebal dari huruf WA. Karena
  /// itu teks percakapan memakai bobot LIGHT (w300/w500) yang dirender dari
  /// font bawaan tanpa fetch jaringan — aman untuk unit test. Bobot
  /// diteruskan apa adanya (TANPA pemetaan null seperti _plain) supaya w300
  /// benar-benar tipis, bukan jatuh ke regular.
  static TextStyle _chatPlain(
    double size,
    FontWeight weight, {
    required double height,
    required Color color,
    double? letterSpacing,
  }) {
    final family = AppFonts.family();
    if (family != null) {
      return GoogleFonts.getFont(
        family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// Weight efektif untuk font bawaan (default & system).
  ///
  /// WhatsApp memakai berat natural REGULAR font perangkat (MiSans di
  /// HyperOS) — fontWeight null. Memaksa weight (w100..w500) justru membuat
  /// sintesis tebal sehingga ChatYuk selalu terlihat lebih tebal dari WA
  /// (temuan capture HP). Jadi untuk teks body (w500 ke bawah) kita TIDAK
  /// memaksa weight — biarkan natural (null = regular asli, ramping seperti
  /// WA); hanya heading tebal (w600+) yang dipetakan ke w500 agar tidak
  /// kelebihan bobot.
  static FontWeight? _systemWeight(FontWeight w) {
    // Body & teks sedang → biarkan natural (null = regular, ramping ala WA).
    if (w.index <= FontWeight.w500.index) return null;
    // Judul/tombol tebal → turunkan satu tingkat agar tidak kelebihan bobot.
    return FontWeight.w500;
  }

  // 10 — timestamp list, badge unread, counter overlay (ramping ala WA)
  static TextStyle get micro =>
      _plain(10, FontWeight.w400, height: 1.2, color: AppTheme.textPrimary);

  // 11 — label di atas nilai, helper text, chip status (ramping ala WA)
  static TextStyle get caption =>
      _plain(11, FontWeight.w300, height: 1.3, color: AppTheme.textPrimary);

  // 12 w500 — section label, tab, chip/badge (ramping ala WA)
  static TextStyle get label => _plain(
    12,
    FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.3,
    color: AppTheme.textPrimary,
  );

  // 12 w300 — subtitle list, preview pesan, deskripsi (ramping ala WA)
  static TextStyle get bodySmall =>
      _plain(12, FontWeight.w300, height: 1.35, color: AppTheme.textPrimary);

  // 12 w400 monospace — isi blok kode di bubble chat.
  // Sengaja TIDAK ikut font global supaya kode tetap rapi.
  static TextStyle get code => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier', 'Menlo', 'monospace'],
    color: AppTheme.textPrimary,
  );

  // 14 w300 — isi dialog, composer, paragraf (ramping ala WA)
  static TextStyle get body =>
      _plain(14, FontWeight.w300, height: 1.35, color: AppTheme.textPrimary);

  // ── Teks chat yang ikut slider ukuran font (setelan user) ──
  // Slider 14–18pt per 0.5 (ChatTextScale). Basis 16 = WhatsApp.
  // bubble 16pt ramping (w300 tipis), timestamp 11pt.
  // Semua teks di dalam percakapan diskalakan supaya proporsional: isi
  // bubble, nama pengirim, jam pesan, kutipan balasan, blok kode, dan kolom
  // ketik pesan. Memakai _chatPlain (bukan _plain) supaya tetap ramping
  // walau global = Default (Roboto tebal).
  static TextStyle get chatBody => _chatPlain(
    ChatTextScale.scale(16),
    FontWeight.w300,
    height: 1.4,
    color: AppTheme.textPrimary,
  );

  /// chatBody pada ukuran pt eksplisit — dipakai PREVIEW slider ukuran font
  /// agar contoh persis mengikuti nilai slider (bukan `current` tersimpan).
  static TextStyle chatBodyAt(double pt) => _chatPlain(
    pt,
    FontWeight.w300,
    height: 1.4,
    color: AppTheme.textPrimary,
  );

  static TextStyle get chatName => _chatPlain(
    ChatTextScale.scale(13),
    FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
    color: AppTheme.textPrimary,
  );

  static TextStyle get chatTime => _chatPlain(
    ChatTextScale.scale(11),
    FontWeight.w300,
    height: 1.2,
    color: AppTheme.textPrimary,
  );

  /// 16 w500 × skala — judul kecil di dalam percakapan (judul kartu link
  /// preview di bubble & di atas kolom ketik).
  static TextStyle get chatBodyStrong => _chatPlain(
    ChatTextScale.scale(16),
    FontWeight.w500,
    height: 1.35,
    color: AppTheme.textPrimary,
  );

  /// 14 w300 × skala — teks sekunder DI DALAM percakapan: kutipan balasan,
  /// placeholder "pesan dihapus", "foto kedaluwarsa", status merekam.
  /// Wajib ikut slider, kalau tidak kutipan balasan tampak terpisah dari
  /// bubble yang membesarkan diri.
  static TextStyle get chatBodySmall => _chatPlain(
    ChatTextScale.scale(14),
    FontWeight.w300,
    height: 1.35,
    color: AppTheme.textPrimary,
  );

  /// 12 w300 × skala — keterangan kecil di dalam percakapan (label bahasa
  /// blok kode, hint view-once, "ketuk untuk memuat foto").
  static TextStyle get chatCaption => _chatPlain(
    ChatTextScale.scale(12),
    FontWeight.w300,
    height: 1.35,
    color: AppTheme.textPrimary,
  );

  /// 14 × skala monospace — isi blok kode di bubble chat. Ikut slider
  /// supaya kode tidak "menyusut" saat teks chat diperbesar.
  static TextStyle get chatCode => TextStyle(
    fontSize: ChatTextScale.scale(14),
    fontWeight: FontWeight.w400,
    height: 1.35,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier', 'Menlo', 'monospace'],
    color: AppTheme.textPrimary,
  );

  // 14 w500 — nama di list, judul tile, label setting (ramping ala WA)
  static TextStyle get bodyStrong =>
      _plain(14, FontWeight.w500, height: 1.35, color: AppTheme.textPrimary);

  // 16 w700 — label tombol CTA (warna ikut foregroundColor tombol)
  // Heading & CTA memakai Poppins (brand) saat default; saat admin memilih
  // font lain, token judul/CTA ikut font itu.
  static TextStyle get button => _brand(16, FontWeight.w700, height: 1.2);

  // 16 w700 — judul kartu / section (admin)
  static TextStyle get titleEmphasis =>
      _brand(16, FontWeight.w700, height: 1.25, color: AppTheme.textPrimary);

  // 17 w700 — judul AppBar, dialog, bottom sheet
  static TextStyle get title =>
      _brand(17, FontWeight.w700, height: 1.25, color: AppTheme.textPrimary);

  // 20 w800 — nama user di header profil
  static TextStyle get headline =>
      _brand(20, FontWeight.w800, height: 1.2, color: AppTheme.textPrimary);

  // 24 w800 — saldo wallet, angka hero, tagline
  static TextStyle get display =>
      _brand(24, FontWeight.w800, height: 1.15, color: AppTheme.textPrimary);
}

/// Skala ukuran teks chat — diatur user lewat slider di Pengaturan.
/// Multiplier diterapkan ke token `AppText.chat*` (chatBody, chatName,
/// chatTime, chatBodySmall, chatCaption, chatCode) saja — yaitu SEMUA teks
/// di dalam percakapan (private, room, grup) + kolom ketik pesan. Tipografi
/// halaman lain (AppBar, dialog, daftar, tombol) tidak ikut berubah.
class ChatTextScale {
  ChatTextScale._();

  static const String prefKey = 'chat_text_scale';

  /// Batas slider: 14pt (min) – 18pt (max), tick per 0.5pt.
  /// Dalam multiplier (basis 16): 0.875 – 1.125.
  static const double min = 0.875;
  static const double max = 1.125;

  /// Langkah diskret slider (9 tick: 14, 14.5, …, 18).
  static const int steps = 8;

  /// Ukuran font chat (pt) pada multiplier 1.0 — dipakai menampilkan angka
  /// di slider (lebih intuitif daripada persen). 16 = basis WhatsApp.
  static const double basePt = 16;

  /// Default install baru: 14.5pt (tick slider ke-2, mult 0.90625) — lebih
  /// ramping ala WA. User lama yang sudah punya simpanan tidak terpengaruh.
  static const double defaultMult = 0.90625;

  /// Nilai aktif (defaultMult = bawaan install baru).
  static double current = defaultMult;

  /// Notifier untuk rebuild subtree chat saat nilai berubah (tanpa
  /// me-restart navigasi). Di-listen di app.dart.
  static final ValueNotifier<double> notifier =
      ValueNotifier<double>(defaultMult);

  /// Ukuran font efektif (pt) untuk nilai saat ini — kelipatan 0.5
  /// (mis. 14, 14.5, 16, 18).
  static double get pt => ptOf(current);

  /// Ukuran (pt) pada multiplier tertentu — dibulatkan ke 0.5 terdekat.
  static double ptOf(double mult) =>
      ((basePt * mult.clamp(min, max)) * 2).round() / 2;

  /// Label ukuran untuk slider (mis. "16", "14.5" — tanpa ".0").
  static String labelOf(double mult) {
    final v = ptOf(mult);
    return v % 1 == 0 ? '${v.toInt()}' : '$v';
  }

  /// Label ukuran saat ini.
  static String get ptLabel => labelOf(current);

  /// Index step slider saat ini (0..steps).
  static int get stepIndex => (indexOf(current)).round();

  /// Multiplier untuk index step tertentu (0..steps).
  static double multOfStep(int index) {
    final i = index.clamp(0, steps);
    return min + (max - min) * (i / steps);
  }

  /// Index step (desimal) untuk multiplier tertentu.
  static double indexOf(double mult) {
    final m = mult.clamp(min, max);
    return ((m - min) / (max - min)) * steps;
  }

  /// Terapkan multiplier aman (clamp ke [min,max]).
  static double scale(double base) =>
      base * current.clamp(min, max);

  /// Normalisasi nilai (bulatkan, clamp). Presisi 5 desimal agar tick
  /// 0.5pt (kelipatan 0.03125) tidak rusak pembulatan.
  static double resolve(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return defaultMult;
    return double.parse(v.clamp(min, max).toStringAsFixed(5));
  }

  /// Inisialisasi sinkron dari SharedPreferences (sebelum runApp).
  static void initSync(SharedPreferences prefs) {
    current = resolve(prefs.getDouble(prefKey));
    notifier.value = current;
  }

  /// Simpan + terapkan.
  static Future<void> set(double v) async {
    current = resolve(v);
    notifier.value = current;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(prefKey, current);
  }

  /// Persentase untuk label UI (mis. 100%).
  static int get percent => (current * 100).round();

  /// Set tanpa menulis prefs (untuk restore realtime, tak perlu).
  static void setLocal(double v) {
    current = resolve(v);
    notifier.value = current;
  }
}

/// Waktu gesture global — dipakai lewat `GestureDetector` yang di-bungkus
/// [AppGesture] di `lib/widgets/app_gesture.dart`.
///
/// Flutter default: long-press 500ms, tap di dalam scrollable menunggu
/// ~tunggu double-tap. App ini tidak punya double-tap-to-zoom, jadi waktu
/// itu murni membuat klik terasa lambat. User minta "klik cepet" & tahan
/// pesan cepat memunculkan toolbar — nilai di bawah ini yang dipakai.
class AppTiming {
  AppTiming._();

  /// Tahan pesan/chat → toolbar seleksi. Default Flutter 500ms → 320ms.
  static const Duration longPress = Duration(milliseconds: 320);

  /// Batas atas tunggu double-tap (tap di dalam list tidak usah menunggu
  /// 300ms untuk tahu ini bukan double-tap). 0 → tap langsung tembak.
  static const Duration doubleTap = Duration.zero;

  /// Delay splash/ripple Material — percepat efek visual tombol.
  static const Duration splash = Duration(milliseconds: 90);
}

/// Ukuran emoji & ikon dekoratif (bukan teks). Lihat AGENTS.md.
class AppGlyph {
  AppGlyph._();

  static const double xs = 16; // emoji badge reaksi di bawah bubble
  static const double sm = 20; // emoji inline, ikon room list
  static const double md = 24; // emoji bubble, sel emoji picker
  static const double lg = 28; // emoji gift picker
  static const double xl = 40; // emoji empty state

  /// Ukuran inisial avatar proporsional terhadap diameter bulatan.
  /// Rasio tetap 0.38 supaya konsisten di semua avatar.
  static double avatarInitial(double diameter) => diameter * 0.38;
}

/// Ukuran teks overlay story (di atas foto) — dipakai composer & viewer
/// lewat widget shared StoryTextOverlay. 3 opsi, ikut skala resmi (16/20/24).
class StoryText {
  StoryText._();

  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  static double size(int i) => i <= 0 ? sm : (i == 1 ? md : lg);

  static const double lineHeight = 1.2;

  /// Palette 8 warna teks overlay (sesuai StoryTextOverlay).
  static const List<Color> palette = [
    Color(0xFFFFFFFF), // putih
    Color(0xFF111111), // hitam
    Color(0xFFF44336), // merah
    Color(0xFFEC407A), // pink
    Color(0xFF9C27B0), // ungu
    Color(0xFF2196F3), // biru
    Color(0xFF00BCD4), // cyan
    Color(0xFFFFEB3B), // kuning
  ];

  /// Warna default overlay (indeks palette).
  static const int defaultColorIndex = 0;
}

class AppTheme {
  AppTheme._();

  /// Mode aktif — di-set oleh ThemeProvider sebelum notifyListeners.
  static bool isDark = false;

  /// Revisi font — di-increment tiap font global berubah supaya ThemeData
  /// getter menghasilkan instance baru (MaterialApp rebuild penuh).
  static int fontRevision = 0;

  /// Inisialisasi sinkron theme dari SharedPreferences.
  /// HARUS dipanggil SEBELUM runApp() supaya frame pertama langsung pakai
  /// tema yang benar (menghilangkan flash putih saat cold start).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isDark = prefs.getBool('app_theme_dark') ?? true;
    // Skala font chat tersimpan — frame pertama bubble pakai ukuran benar.
    ChatTextScale.initSync(prefs);
    // Font global tersimpan — frame pertama langsung pakai font yang benar.
    await AppFonts.init();
  }

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
  static Color get textSecondary =>
      isDark ? _textSecondaryDark : _textSecondaryLight;

  // ── Status (konstan) ──
  static const Color online = Color(0xFF4CAF50);  // Hijau tua untuk badge jumlah online — kontras di atas bgCard terang.
  static const Color onlineDark = Color(0xFF2E7D32);
  static const Color idle = Color(0xFFFFB300);
  static const Color offline = Color(0xFFBDBDBD);
  static const Color danger = Color(0xFFF44336);
  static const Color male = Color(0xFF2196F3);
  static const Color female = Color(0xFFE91E63);

  /// Warna indikator status — SATU sumber untuk seluruh app.
  /// Dulu ada 5 definisi `_statusColor` + belasan nilai inline yang berbeda
  /// (idle `0xFFFFC107` vs `0xFFFFB300`, offline `0xFF9E9E9E` vs `0xFFBDBDBD`)
  /// sehingga titik status terlihat beda antar layar untuk status yang sama.
  /// Jangan hardcode warna status di screen — pakai helper ini.
  static Color statusColor(String? status) => switch (status) {
    'online' => online,
    'idle' => idle,
    _ => offline,
  };

  // ── Avatar fallback inisial (WAJIB OPAQUE) ──
  // Dulu accent/textSecondary @15% yang translusen: di atas AppBar biru vs
  // kartu putih hasilnya beda warna. Nilai solid = campuran 15% di atas
  // bgCard mode masing-masing → tampil identik di permukaan apa pun.
  // List Pesan & header private chat WAJIB pakai token ini (jangan alpha).
  static const _avatarBgLight = Color(0xFFD9F5F9);
  static const _avatarBgDark = Color(0xFF1A3639);
  static Color get avatarBg => isDark ? _avatarBgDark : _avatarBgLight;
  static const _avatarBgBlockedLight = Color(0xFFEAEAEA);
  static const _avatarBgBlockedDark = Color(0xFF313131);
  static Color get avatarBgBlocked =>
      isDark ? _avatarBgBlockedDark : _avatarBgBlockedLight;

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
    // Jaring aman: teks yang tidak lewat token AppText (style bawaan
    // Material/ListTile default, dsb) tetap ikut font global.
    final fontOverride = AppFonts.themeFontOverride();
    return ThemeData(
      brightness: brightness,
      primaryColor: primary,
      fontFamily: fontOverride?.family,
      fontFamilyFallback: fontOverride?.fallback,
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
        // Dark: #1B2A3A = warna pertama headerGradient — flat AppBar
        // (room chat, dialog) menyatu dengan screens bergradient header.
        backgroundColor: isLight ? primary : const Color(0xFF1B2A3A),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppText.title.copyWith(color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // Tooltip langsung muncul saat tahan (default Flutter menunggu ~500ms)
      // — sejalan dengan AppTiming.longPress supaya ikon/tombol terasa
      // responsif, bukan "diam dulu baru muncul label".
      tooltipTheme: const TooltipThemeData(
        waitDuration: AppTiming.longPress,
        showDuration: Duration(seconds: 2),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
        unselectedLabelStyle: AppText.label.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgInput,
        selectedColor: primary.withValues(alpha: 0.15),
        labelStyle: AppText.label.copyWith(
          color: textPrimary,
          letterSpacing: 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        backgroundColor: isLight
            ? const Color(0xFF424242)
            : const Color(0xFF37474F),
        contentTextStyle: AppText.body.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: divider),
      popupMenuTheme: PopupMenuThemeData(
        color: bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: bgCard),
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
