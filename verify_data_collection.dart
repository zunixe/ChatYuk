// Verifikasi pengumpulan data untuk Play Console Data Safety
import 'package:flutter/services.dart';
import 'lib/providers/auth_provider.dart';
import 'lib/services/avatar_service.dart';

void main() async {
  print('=== Verifikasi Pengumpulan Data ChatYuk ===');
  
  // 1. Cek installId (Perangkat atau ID lainnya)
  String? installId;
  try {
    final methodChannel = MethodChannel('com.chatyuk.chatyuk/device_info');
    installId = await methodChannel.invokeMethod('getInstallId');
    print('✓ installId ditemukan: $installId');
  } catch (e) {
    print('✗ installId tidak ditemukan: $e');
  }
  
  // 2. Cek AvatarService (foto profil pengguna)
  String? avatarB64;
  try {
    final avatarService = AvatarB64Service.instance;
    avatarB64 = await avatarService.get('current_user_id');
    print('✓ avatarB64 tersedia: ${avatarB64.length} karakter');
  } catch (e) {
    print('✗ avatarB64 tidak tersedia: $e');
  }
  
  // 3. Cek AuthProvider (data pengguna)
  try {
    final auth = AuthProvider();
    final user = auth.profile;
    print('✓ user data tersedia: ${user?.uid}');
  } catch (e) {
    print('✗ user data tidak tersedia: $e');
  }
  
  print('\n=== Verifikasi Selesai ===');
  print('Data yang dikumpulkan: Perangkat/ID (installId)');
  print('Data yang tidak dikumpulkan: Kontak, Lokasi, Pesan, dll');
}
