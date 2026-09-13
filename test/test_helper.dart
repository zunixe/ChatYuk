import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Setup bersama untuk test yang menyentuh Supabase.instance / plugin.
/// Supabase di-init dengan URL+key dummy (tidak ada network yang dipakai
/// karena semua service di-mock); SharedPreferences di-mock agar init
/// tidak melempar MissingPluginException.
Future<void> initSupabaseForTest() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async => null,
  );
  try {
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.test',
    );
  } catch (_) {
    // Sudah di-init oleh file test lain dalam run yang sama.
  }
}
