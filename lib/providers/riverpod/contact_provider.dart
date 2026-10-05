import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/contact_service.dart';

/// Kirim pesan dukungan/kontak (Riverpod) — action-only, tanpa state reaktif.
///
/// Migrasi dari ChangeNotifier (yang sebenarnya hanya pembungkus service,
/// tanpa state/notifyListeners) → `Provider` biasa (nilai service).
class ContactNotifier {
  final ContactService service;
  ContactNotifier([ContactService? service])
      : service = service ?? ContactService();

  Future<void> submitMessage({
    required String message,
    String? name,
    String? userId,
  }) =>
      service.submitMessage(message: message, name: name, userId: userId);
}

final contactProvider = Provider<ContactNotifier>((_) => ContactNotifier());
