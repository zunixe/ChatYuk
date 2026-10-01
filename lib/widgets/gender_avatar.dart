import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'profile_avatar.dart';

/// Avatar dengan **lingkaran latar berwarna gender** + ring gender untuk
/// pengguna yang TIDAK punya foto — tampilan ini identik dengan daftar
/// "Pengguna Online" (online_users_screen).
///
/// Modular supaya admin panel (monitor chat, detail user, dsb.) bisa memakai
/// gaya yang SAMA PERSIS tanpa menyalin kode & menyimpang.
///
/// Aturan warna (sama dengan online):
///   male   → [AppTheme.male]   (biru)
///   female → [AppTheme.female] (pink)
///   lain   → [AppTheme.accent]
///
/// Catatan: ring gender HANYA tampil saat placeholder inisial (tanpa foto);
/// begitu foto tampil, ring disembunyikan oleh [ProfileAvatar] supaya foto
/// gelap tidak terlihat bercacat.
class GenderAvatar extends StatelessWidget {
  final String uid;
  final String name;

  /// Gender mentah dari server ('male' / 'female' / lainnya).
  final String gender;
  final double size;

  /// Ketebalan ring saat placeholder inisial (default sama dengan online: 1.5).
  final double borderWidth;

  /// Radius sudut bingkai LUAR (0 = lingkaran penuh). Untuk avatar bulat
  /// (daftar online / monitor), biarkan 0.
  final double borderRadius;

  const GenderAvatar({
    super.key,
    required this.uid,
    required this.name,
    required this.gender,
    this.size = 40,
    this.borderWidth = 1.5,
    this.borderRadius = 0,
  });

  /// Warna gender — satu-satunya sumber kebenaran (samakan dgn online).
  static Color colorFor(String gender) {
    switch (gender) {
      case 'male':
        return AppTheme.male;
      case 'female':
        return AppTheme.female;
      default:
        return AppTheme.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(gender);
    return ProfileAvatar(
      uid: uid,
      name: name,
      size: size,
      borderRadius: borderRadius,
      // Placeholder inisial: latar + huruf + ring warna gender (sama persis
      // dengan daftar "Pengguna Online"). Ring digambar DI DALAM bounds.
      bgColor: color.withValues(alpha: 0.15),
      textColor: color,
      borderColor: color,
      borderWidth: borderWidth,
    );
  }
}
