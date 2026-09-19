import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/core/cache/media_disk_cache.dart';
import 'package:chatyuk/services/post_photo_cache.dart';

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
  mockPathProvider();
  try {
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      // ignore: deprecated_member_use
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.test',
    );
  } catch (_) {
    // Sudah di-init oleh file test lain dalam run yang sama.
  }
}

/// Mock path_provider ke direktori temp — dibutuhkan MediaDiskCache.prewarm
/// dan service lain yang baca direktori dokumen/cache.
void mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        Directory.systemTemp.createTempSync('chatyuk_test_media').path,
  );
}

/// Prewarm cache media sekali di awal supaya widget yang memuat avatar
/// tidak menjadwalkan Future.delayed retry (timer pending → invariant fail).
Future<void> prewarmMediaForTest() async {
  mockPathProvider();
  await MediaDiskCache.instance.prewarm();
  await warmPostPhotoCacheForTest();
}

/// Siapkan folder cache foto post (`post_photos_v2`) di direktori temp.
/// Dipakai tes yang menyentuh PostPhotoCache supaya tidak menulis ke
/// direktori dokumen asli HP/desktop.
Future<void> warmPostPhotoCacheForTest() async {
  mockPathProvider();
  await PostPhotoCache.instance.cleanOldPhotos();
}

/// Reset font global antar test — `AppFonts.current` static dipakai lintas
/// test dalam satu isolate, jadi harus dikembalikan ke default di tearDown.
void resetFontForTest() {
  AppFonts.current = AppFonts.defaultKey;
}
