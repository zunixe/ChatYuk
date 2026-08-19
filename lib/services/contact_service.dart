import 'package:supabase_flutter/supabase_flutter.dart';

class ContactService {
  final SupabaseClient _sb;

  ContactService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  Future<void> submitMessage({
    String? name,
    required String message,
    String? userId,
  }) async {
    await _sb.from('contact_messages').insert({
      'name': (name == null || name.trim().isEmpty) ? null : name.trim(),
      'message': message.trim(),
      'user_id': userId,
    });
  }
}