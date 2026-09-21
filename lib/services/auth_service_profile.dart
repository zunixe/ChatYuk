part of 'auth_service.dart';

/// Domain **profile** AuthService (Fase 17) — dipisah dari file 1278 baris.
/// Satu library via `part`: field privat AuthService tetap bisa diakses,
/// interface `AuthService` tidak berubah (mock test aman).
mixin AuthServiceProfileMx on AuthBase {
  Future<UserModel> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress =
        '', // disimpan di server saja, tidak disimpan di aplikasi
  }) async {
    // Nickname terlarang ditolak sebelum tulis server (kecuali admin).
    if (isBannedNickname(nickname)) {
      final user = _sb.auth.currentUser;
      if (!AdminGate.isRealAdmin(user?.email)) {
        throw Exception('nickname_banned');
      }
    }
    // Kalau session hilang (misal habis logout Google), buat session
    // anonymous baru supaya user baru tetap bisa daftar.
    var user = _sb.auth.currentUser;
    if (user == null) {
      dlog('[AUTH] registerProfile: no session, signInAnonymously first');
      try {
        final res = await _sb.auth.signInAnonymously();
        user = res.user;
      } catch (e) {
        dlog('[AUTH] registerProfile: signInAnonymously error: $e');
        throw Exception('registerProfile: no authenticated user');
      }
    }
    if (user == null) throw Exception('registerProfile: no authenticated user');
    final now = DateTime.now().toUtc();
    final hasEmail = (user.email ?? '').isNotEmpty;
    final profile = UserModel(
      uid: user.id,
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: '', // tidak disimpan di model lokal — hanya di server
      status: 'online',
      avatar: '',
      isRegistered: hasEmail,
      loginAt: now,
      createdAt: now,
      lastSeen: now,
    );

    // Upsert HANYA kolom yang di-grant SELECT (lihat
    // 20260915120000_security_hardening.sql). Kolom sensitif
    // (email/ip_address/fcm_token/lat/lon) TIDAK boleh ikut di upsert:
    // PostgREST `ON CONFLICT DO UPDATE` butuh SELECT pada kolom yang
    // ditulis, dan kolom itu sengaja di-revoke → dulu seluruh registrasi
    // gagal 42501. Setelah upsert, kolom sensitif ditulis lewat UPDATE
    // terpisah (grant UPDATE penuh, RLS `profiles_update_own`).
    await _sb.from('profiles').upsert({
      'id': user.id,
      'nickname': nickname,
      'gender': gender,
      'age': age,
      'country': country,
      'city': city,
      'status': 'online',
      'avatar': '',
      'is_registered': hasEmail,
      'login_at': now.toUtc().toIso8601String(),
      'created_at': now.toUtc().toIso8601String(),
      'last_seen': now.toUtc().toIso8601String(),
    }, onConflict: 'id');

    // Kolom sensitif via UPDATE (tidak butuh SELECT kolom tsb).
    final sensitive = <String, dynamic>{
      'fcm_token': '',
      // Email dari sesi auth — wajib tersinkron agar admin panel melihat
      // email user terdaftar (bug lama: kolom ini tidak pernah diisi).
      if (hasEmail) 'email': user.email,
      // IP dicatat di server untuk keperluan keamanan/moderasi,
      // tidak disimpan di perangkat aplikasi.
      if (ipAddress.isNotEmpty) 'ip_address': ipAddress,
    };
    await _sb.from('profiles').update(sensitive).eq('id', user.id);

    return profile;
  }

  Future<UserModel?> getProfile({bool withAvatar = true}) async {
    final id = uid;
    if (id == null) return null;
    final raw = await _sb.rpc('profile_public', params: {'p_user': id});
    if (raw is! Map || raw.isEmpty) return null;
    final model = UserModel.fromMap(
      id,
      snakeToCamel(Map<String, dynamic>.from(raw)),
    );
    if (!withAvatar || model.avatar.isEmpty) return model;
    // avatar berupa PATH storage → download → isi base64 (UI tetap pakai
    // base64). Pakai AvatarB64Service yang punya cache per path.
    if (StoragePhotoService.instance.isAvatarPath(model.avatar)) {
      final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
      return model.copyWith(avatar: b64);
    }
    return model;
  }

  /// Ambil profil user lain (untuk halaman info pengguna).
  Future<UserModel?> getProfileById(String id) async {
    if (id.isEmpty) return null;
    final raw = await _sb.rpc('profile_public', params: {'p_user': id});
    if (raw is! Map || raw.isEmpty) return null;
    final model = UserModel.fromMap(
      id,
      snakeToCamel(Map<String, dynamic>.from(raw)),
    );
    if (model.avatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(model.avatar)) {
      final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
      return model.copyWith(avatar: b64);
    }
    return model;
  }

  /// Stream realtime profil sendiri — poin, status, email terdaftar, dll.
  /// Dipakai AuthProvider untuk update badge di seluruh app tanpa reload.
  Stream<UserModel> onMyProfileUpdates() {
    final id = uid;
    if (id == null) return const Stream.empty();
    final controller = StreamController<UserModel>.broadcast();

    final channel = _sb.channel('my-profile-$id');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: id,
      ),
      callback: (payload) async {
        if (controller.isClosed) return;
        try {
          final row = payload.newRecord;
          var model = UserModel.fromMap(id, snakeToCamel(row));
          // avatar PATH storage → download → base64 (UI tetap pakai base64).
          // Pakai cache supaya update profil tidak download avatar berulang.
          if (model.avatar.isNotEmpty &&
              StoragePhotoService.instance.isAvatarPath(model.avatar)) {
            final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
            model = model.copyWith(avatar: b64);
          }
          controller.add(model);
        } catch (e) {
          dlog('[AuthService] onMyProfileUpdates ignored: $e');
        }
      },
    );
    channel.subscribe();

    controller.onCancel = () {
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  Future<void> updateHashtags(List<String> hashtags) async {
    final id = uid;
    if (id == null) return;
    await _sb.from('profiles').update({'hashtags': hashtags}).eq('id', id);
  }

  Future<void> updateProfile({
    int? age,
    String? country,
    String? city,
    String? nickname,
    String? about,
  }) async {
    final id = uid;
    if (id == null) return;
    // Nickname terlarang ditolak sebelum tulis server (kecuali admin).
    if (nickname != null &&
        isBannedNickname(nickname) &&
        !AdminGate.isRealAdmin(userEmail)) {
      throw Exception('nickname_banned');
    }
    // About dibatasi 150 karakter (clamp, bukan error) supaya kolom tidak
    // membengkak dan tidak ada pesan gagal yang membingungkan user.
    final aboutText = about?.trim();
    final data = <String, dynamic>{
      if (age != null) 'age': age,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
      if (nickname != null) 'nickname': nickname,
      if (aboutText != null)
        'about': aboutText.length > 150
            ? aboutText.substring(0, 150)
            : aboutText,
    };
    if (data.isEmpty) return;
    await _sb.from('profiles').update(data).eq('id', id);
  }

  /// Update IP address di server (keamanan/moderasi).
  /// IP hanya disimpan di server, tidak disimpan di aplikasi.
  Future<void> updateIpAddress(String ip) async {
    final id = uid;
    if (id == null || ip.isEmpty) return;
    try {
      await _sb.from('profiles').update({'ip_address': ip}).eq('id', id);
    } catch (e) {
      dlog('[AUTH] updateIpAddress error: $e');
    }
  }

  /// Update avatar → server + TULIS KE DISK lokal. Return server path.
  /// Disk = sumber lokal: buka app berikutnya load dari disk, bukan network.
  Future<String> updateAvatar(String base64) async {
    final id = uid;
    if (id == null) return '';
    // Validasi base64 adalah JPEG, PNG, atau WebP yang valid
    if (base64.isNotEmpty && !isValidImageBase64(base64)) {
      throw Exception('Invalid image format');
    }
    // Limit ukuran: max 512KB base64 (~384KB file)
    if (base64.length > 524288) {
      throw Exception('Image too large (max 384KB)');
    }
    // Upload ke Storage — DB hanya simpan path (hemat ruang).
    // Path baru diberi timestamp (cache-buster) — hapus file avatar lama
    // supaya Storage tidak menumpuk file versi lama.
    final oldAvatar =
        (await _sb
                .from('profiles')
                .select('avatar')
                .eq('id', id)
                .maybeSingle())?['avatar']
            as String? ??
        '';
    final path = base64.isEmpty
        ? ''
        : await StoragePhotoService.instance.uploadAvatar(
                uid: id,
                base64: base64,
              ) ??
              '';
    if (oldAvatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(oldAvatar) &&
        oldAvatar != path) {
      try {
        await _sb.storage.from('chat-photos').remove([oldAvatar]);
      } catch (_) {}
    }
    await _sb.from('profiles').update({'avatar': path}).eq('id', id);
    // TULIS KE DISK — bytes WebP/JPEG asli, load berikutnya dari lokal.
    if (path.isNotEmpty && base64.isNotEmpty) {
      try {
        await MediaDiskCache.instance.write(
          path,
          Uint8List.fromList(base64Decode(base64)),
        );
      } catch (_) {}
    }
    return path;
  }

  Future<void> removeAvatar() async {
    final id = uid;
    if (id == null) return;
    await _sb.from('profiles').update({'avatar': ''}).eq('id', id);
  }

  Future<void> updateFcmToken(String? token) async {
    final id = uid;
    if (id == null) return;
    final t = token ?? '';
    // Satu jalur penulis: RPC update_device_fcm_token sudah menulis ke
    // user_devices DAN profiles.fcm_token (kompatibilitas klien lama).
    // Tulis profiles langsung di sini dihapus — duplikat penulis membuat
    // race saat dua pemanggil (main.dart lazy + AuthProvider) jalan serentak.
    try {
      final installId = await DeviceInfoService.instance.installId();
      await _sb.rpc(
        'update_device_fcm_token',
        params: {'p_install_id': installId, 'p_token': t},
      );
    } catch (_) {}
  }

  /// Set status offline saat logout. Pakai timeout pendek — jalur logout
  /// tidak boleh menunggu jaringan tanpa batas (spinner muter selamanya).
  /// Best-effort: kalau gagal, server tetap menandai offline lewat idle
  /// timeout / presence, jadi kegagalan aman.
  Future<void> goOffline() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'offline',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      dlog('[AUTH] goOffline error: $e');
    }
  }

  /// Admin invisible — status khusus 'invisible' di DB. User lain melihatnya
  /// offline (via effectiveStatusOf) & tidak muncul di daftar online.
  Future<void> goInvisible() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'invisible',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      dlog('[AUTH] goInvisible error: $e');
    }
  }

  Future<void> goIdle() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'idle',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      dlog('[AUTH] goIdle error: $e');
    }
  }

  Future<void> goOnline() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'online',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      dlog('[AUTH] goOnline error: $e');
    }
  }

  /// Heartbeat: update last_seen tanpa mengubah status.
  /// Dipanggil berkala supaya kalau app di-kill, last_seen jadi basi
  /// dan bisa dideteksi sebagai offline.
  Future<void> updateLastSeen() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      dlog('[AUTH] updateLastSeen error: $e');
    }
  }

  /// Ambil semua foto galeri milik satu user.
  Future<List<UserPhoto>> getPhotos(String userId) async {
    if (userId.isEmpty) return [];
    final rows = await _sb
        .from('user_photos')
        .select('id,user_id,photo,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final result = <UserPhoto>[];
    for (final row in rows) {
      var photo = row['photo'] as String? ?? '';
      // photo bisa berupa PATH storage (foto baru) → download → base64.
      if (photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        photo = await _galleryPhotoB64(photo);
      }
      result.add(
        UserPhoto.fromMap('${row['id']}', {
          'userId': row['user_id'],
          'photo': photo,
          'createdAt': row['created_at'],
        }),
      );
    }
    return result;
  }

  /// Ambil foto galeri user LAIN dengan kontrol akses paywall.
  /// Index 0 gratis; sisanya terkunci (kirim preview blur) sampai dibuka.
  /// Foto terbuka: field photo = path/base64 asli. Terkunci: photo = preview.
  Future<List<UserPhoto>> getPhotosWithAccess(String userId) async {
    if (userId.isEmpty) return [];
    final res = await _sb.rpc(
      'get_user_photos_access',
      params: {'p_user_id': userId},
    );
    final list = res is List ? res : <dynamic>[];
    final result = <UserPhoto>[];
    for (final row in list) {
      final m = Map<String, dynamic>.from(row as Map);
      final unlocked = m['unlocked'] == true;
      var photo = m['photo'] as String? ?? '';
      // Foto terbuka bisa berupa PATH storage → download jadi base64.
      // Foto terkunci = preview base64 (bukan path) → pakai apa adanya.
      if (unlocked &&
          photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        photo = await _galleryPhotoB64(photo);
      }
      result.add(
        UserPhoto.fromMap('${m['id']}', {
          'userId': userId,
          'photo': photo,
          'unlocked': unlocked,
          'preview': m['preview'] ?? '',
          'createdAt': m['created_at'],
        }),
      );
    }
    return result;
  }

  /// Upload foto galeri milik sendiri. Max 6 foto per user.
  Future<void> uploadPhoto(String base64, {String? preview}) async {
    final id = uid;
    if (id == null) return;
    if (base64.isNotEmpty && !isValidImageBase64(base64)) {
      throw Exception('Invalid image format');
    }
    // Limit ukuran: max 1MB base64 (~768KB file)
    if (base64.length > 1048576) {
      throw Exception('Photo too large (max 768KB)');
    }
    // Batasi jumlah foto per user = 6
    final rows = await _sb.from('user_photos').select('id').eq('user_id', id);
    if (rows.length >= 6) {
      throw Exception('Max 6 photos');
    }
    // Upload ke Storage — DB hanya simpan path (hemat ruang).
    final path =
        await StoragePhotoService.instance.uploadPhoto(
          uid: id,
          base64: base64,
        ) ??
        base64;
    await _sb.from('user_photos').insert({
      'user_id': id,
      'photo': path,
      if (preview != null && preview.isNotEmpty) 'photo_preview': preview,
    });
  }

  /// Hapus foto galeri (hanya punya sendiri, RLS menjamin).
  Future<void> deletePhoto(String photoId) async {
    if (photoId.isEmpty) return;
    try {
      final row = await _sb
          .from('user_photos')
          .select('photo')
          .eq('id', photoId)
          .maybeSingle();
      final photo = row?['photo'] as String? ?? '';
      if (photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        await StoragePhotoService.instance.delete(photo);
      }
    } catch (_) {}
    await _sb.from('user_photos').delete().eq('id', photoId);
  }

  /// Hapus akun sendiri (Google Play account deletion requirement).
  /// RPC server-side: arsip ke deleted_users lalu purge profil + auth user.
  /// Melempar exception dengan kode server: NOT_AUTHENTICATED,
  /// ADMIN_DELETE_FORBIDDEN, PROFILE_NOT_FOUND.
  Future<void> deleteMyAccount() async {
    await _sb.rpc('delete_my_account');
  }

  /// Update flag sesi dummy. Hanya dipanggil dari mekanisme swap dummy.
  void markDummyState({required bool active, String? uid}) {
    _dummySessionActive = active;
    _dummyUid = active ? uid : null;
  }
}
