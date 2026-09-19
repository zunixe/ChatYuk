import 'package:flutter/foundation.dart';

import '../services/contact_service.dart';

/// Provider kontak/kirim pesan dukungan — screen tidak import `services/`.
class ContactProvider extends ChangeNotifier {
  final ContactService service;
  ContactProvider({ContactService? service})
      : service = service ?? ContactService();

  Future<void> submitMessage({
    required String message,
    String? name,
    String? userId,
  }) =>
      service.submitMessage(message: message, name: name, userId: userId);
}
