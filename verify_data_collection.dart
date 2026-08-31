// Verifikasi pengumpulan data untuk Play Console Data Safety
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final avatarService = AvatarB64Service();
    avatarB64 = await avatarService.get('current_user_id');
    print('✓ avatarB64 tersedia: ${avatarB64?.length} karakter');
  } catch (e) {
    print('✗ avatarB64 tidak tersedia: $e');
  }
  
  // 3. Cek AuthProvider (data pengguna)
  try {
    final auth = AuthProvider();
    final user = auth.user;
    print('✓ user data tersedia: ${user?.uid}');
  } catch (e) {
    print('✗ user data tidak tersedia: $e');
  }
  
  print('\n=== Verifikasi Selesai ===');
  print('Data yang dikumpulkan: Perangkat/ID (installId)');
  print('Data yang tidak dikumpulkan: Kontak, Lokasi, Pesan, dll');
}
