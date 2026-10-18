import 'package:fast_contacts/fast_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils.dart';

/// Status izin baca buku kontak perangkat.
enum ContactsPermission { granted, denied, permanentlyDenied }

/// Kontak HP ringan (hanya yang dipakai fitur "kirim kontak"): nama + nomor.
class DeviceContact {
  final String id;
  final String name;
  final List<String> phones;
  const DeviceContact({
    required this.id,
    required this.name,
    required this.phones,
  });
}

/// Baca buku kontak perangkat untuk fitur **kirim kontak ala WhatsApp**.
///
/// Dipisah dari layar (boundary AGENTS): layar memakai provider pembungkus
/// (`deviceContactsProvider`). Izin diminta di sini (permission_handler);
/// plugin `fast_contacts` sengaja tidak menangani izin.
class DeviceContactsService {
  /// Batas jumlah kontak yang dipegang di RAM (HP dengan 10k+ kontak).
  static const int maxContacts = 3000;

  /// Batas nomor per kontak (kartu hanya menampilkan beberapa).
  static const int maxPhonesPerContact = 5;

  List<DeviceContact>? _cache;
  ContactsPermission _permission = ContactsPermission.denied;

  ContactsPermission get permission => _permission;

  bool get hasCache => _cache != null;

  void clearCache() => _cache = null;

  /// Minta/cek izin kontak. [request] = tampilkan dialog izin bila belum ada.
  Future<ContactsPermission> ensurePermission({bool request = true}) async {
    try {
      var st = await Permission.contacts.status;
      if (!st.isGranted && request) st = await Permission.contacts.request();
      if (st.isGranted || st.isLimited) {
        _permission = ContactsPermission.granted;
      } else if (st.isPermanentlyDenied) {
        _permission = ContactsPermission.permanentlyDenied;
      } else {
        _permission = ContactsPermission.denied;
      }
    } catch (e) {
      dlog('[Contacts] permission error: $e');
      _permission = ContactsPermission.denied;
    }
    return _permission;
  }

  /// Daftar kontak (nama + nomor), di-cache per sesi agar buka sheet berulang
  /// tidak membaca ulang buku kontak. Kosong bila izin belum diberikan.
  Future<List<DeviceContact>> load({bool requestPermission = true}) async {
    final cached = _cache;
    if (cached != null) return cached;
    final p = await ensurePermission(request: requestPermission);
    if (p != ContactsPermission.granted) return const [];
    try {
      final rows = await FastContacts.getAllContacts();
      final out = <DeviceContact>[];
      for (final c in rows) {
        final numbers = [
          for (final ph in c.phones)
            if (ph.number.trim().isNotEmpty) ph.number.trim(),
        ].take(maxPhonesPerContact).toList();
        // Kontak tanpa nomor tidak berguna untuk dibagikan.
        if (numbers.isEmpty) continue;
        final name = c.displayName.trim();
        out.add(
          DeviceContact(
            id: c.id,
            name: name.isEmpty ? numbers.first : name,
            phones: numbers,
          ),
        );
        if (out.length >= maxContacts) break;
      }
      out.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      _cache = out;
      return out;
    } catch (e) {
      dlog('[Contacts] load error: $e');
      return const [];
    }
  }

  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      dlog('[Contacts] openSettings error: $e');
    }
  }

  /// Filter nama untuk kolom cari (fungsi MURNI → mudah diuji).
  static List<DeviceContact> filter(List<DeviceContact> all, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [
      for (final c in all)
        if (c.name.toLowerCase().contains(q)) c,
    ];
  }
}
