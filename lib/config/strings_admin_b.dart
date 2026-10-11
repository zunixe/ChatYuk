part of 'strings_admin.dart';

extension SAdminB on S {

  // ── Organisasi monitor chat: pin + kategori (folder) ──
  String get adminChatPin => isId ? 'Sematkan' : 'Pin';
  String get adminChatUnpin => isId ? 'Lepas Sematan' : 'Unpin';
  String get adminChatPinned => isId ? 'Chat disematkan' : 'Chat pinned';
  String get adminChatUnpinned => isId ? 'Sematan dilepas' : 'Chat unpinned';
  String get adminChatCatAll => isId ? 'Semua' : 'All';
  String get adminChatCatNone => isId ? 'Tanpa kategori' : 'Uncategorized';
  String get adminChatMoveToCategory =>
      isId ? 'Pindahkan ke kategori' : 'Move to category';
  String get adminChatChangeCategory =>
      isId ? 'Ganti kategori' : 'Change category';
  String get adminChatRemoveFromCategory =>
      isId ? 'Keluarkan dari kategori' : 'Remove from category';
  String get adminChatNewCategory => isId ? 'Kategori baru' : 'New category';
  String get adminChatRenameCategory =>
      isId ? 'Ganti nama kategori' : 'Rename category';
  String get adminChatDeleteCategory =>
      isId ? 'Hapus kategori' : 'Delete category';
  String get adminChatCategoryNameHint =>
      isId ? 'Nama kategori...' : 'Category name...';
  String get adminChatDelete => isId ? 'Hapus percakapan' : 'Delete conversation';

  String get adminChatNoChats =>
      isId ? 'Belum ada percakapan' : 'No conversations yet';

  String get adminChatMsgs => isId ? 'pesan' : 'messages';

  String get adminChatOpen => isId ? 'Buka Percakapan' : 'Open Conversation';

  String get adminChatLoading =>
      isId ? 'Memuat percakapan...' : 'Loading conversation...';

  String get adminChatError =>
      isId ? 'Gagal memuat percakapan' : 'Failed to load conversation';

  String get adminChatBack => isId ? 'Kembali' : 'Back';

  String get adminViewOnce =>
      isId ? 'Foto Sekali Lihat (Admin)' : 'View-Once Photo (Admin)';

  String get adminLastUpdate => isId ? 'Update terakhir' : 'Last updated';

  String get adminMapTitle => isId ? 'Peta User' : 'User Map';

  String get adminMapSubtitle => isId
      ? 'Posisi user realtime (GPS/IP)'
      : 'Realtime user positions (GPS/IP)';

  String get mapLive => isId ? 'Langsung' : 'Live';

  String get mapSourceGps => isId ? 'GPS' : 'GPS';

  String get mapSourceIp => isId ? 'IP' : 'IP';

  String get mapSourceResolved => isId ? 'IP (online)' : 'IP (live)';

  String get mapOpenMaps => isId ? 'Buka Google Maps' : 'Open Google Maps';

  String get mapNoLocation => isId ? 'Tanpa lokasi' : 'No location';

  String get mapResolving =>
      isId ? 'Mencari lokasi dari IP...' : 'Locating from IP...';

  String get mapTapHint =>
      isId ? 'Ketuk pin untuk detail' : 'Tap a pin for details';

  /// Tombol & judul mode layar penuh peta user.
  String get mapFullscreen => isId ? 'Layar penuh' : 'Full screen';

  String get mapFullscreenTitle =>
      isId ? 'Peta User — Layar Penuh' : 'User Map — Full screen';

  /// Label titik GPS terakhir user (ringkasan → users).
  String get gpsLast => isId ? 'GPS terakhir' : 'Last GPS';

  // ── Fake GPS (mock) — deteksi, bukan bukti pasti ──
  String get mapFakeGps => isId ? 'Fake GPS' : 'Fake GPS';
  String get gpsFake => isId ? 'GPS (Fake)' : 'GPS (Fake)';
  String get mapFakeGpsDesc => isId
      ? 'Lokasi terindikasi palsu (mock/kecepatan mustahil). Cek reason di detail.'
      : 'Location flagged as fake (mock/impossible speed). See reason in detail.';
  String get fakeReasonIsMocked =>
      isId ? 'Provider lokasi dilaporkan mock' : 'Location provider reported mocked';
  String get fakeReasonSpeed =>
      isId ? 'Lompatan kecepatan mustahil' : 'Impossible speed jump';
  String get fakeReasonAccuracy =>
      isId ? 'Akurasi lokasi 0' : 'Location accuracy is 0';
  String get fakeReasonDelta =>
      isId ? 'Jarak GPS vs IP terlalu jauh' : 'GPS vs IP distance too far';
  String get fakeReasonStatic =>
      isId ? 'Koordinat beku (tak berpindah)' : 'Frozen coordinate (never moves)';
  String get fakeReasonEmulator =>
      isId ? 'Lokasi default emulator' : 'Emulator default location';
  String get fakeReasonShared =>
      isId ? 'Koordinat sama dgn banyak user' : 'Same coordinate as many users';

  // Label sumber koordinat (riwayat lokasi).
  String get locSrcGps => 'GPS';
  String get locSrcIp => 'IP';
  String get locSrcGpsHint =>
      isId ? 'GPS asli dari HP (akurat)' : 'Real device GPS (accurate)';
  String get locSrcIpHint => isId
      ? 'Perkiraan dari IP (kasar, bisa meleset)'
      : 'IP estimate (rough, can be off)';

  /// Badge status lokasi di daftar user "Per User".
  String get adminGpsReal => isId ? 'GPS asli' : 'Real GPS';
  String get adminGpsFake => 'Fake GPS';
  String get adminGpsIpOnly => isId ? 'Hanya IP' : 'IP only';

  /// Terjemahkan reason koma-terpisah → label ringkas.
  String fakeReasonLabel(String reason) {
    if (reason.isEmpty) return mapFakeGps;
    final labels = <String>[];
    for (final r in reason.split(',')) {
      final t = r.trim();
      if (t == 'is_mocked') {
        labels.add(fakeReasonIsMocked);
      } else if (t == 'impossible_speed') {
        labels.add(fakeReasonSpeed);
      } else if (t == 'accuracy_zero') {
        labels.add(fakeReasonAccuracy);
      } else if (t == 'spoof_delta') {
        labels.add(fakeReasonDelta);
      } else if (t == 'static_coord') {
        labels.add(fakeReasonStatic);
      } else if (t == 'known_emulator') {
        labels.add(fakeReasonEmulator);
      } else if (t == 'shared_coord') {
        labels.add(fakeReasonShared);
      } else if (t.isNotEmpty) {
        labels.add(t);
      }
    }
    return labels.join(' • ');
  }

  // ── Penjelasan legenda peta (GPS / IP / IP online) ──
  String get mapLegendTitle =>
      isId ? 'Keterangan titik lokasi' : 'Location point legend';

  String get mapLegendGpsDesc => isId
      ? 'Koordinat GPS asli dari HP user (paling akurat).'
      : 'Real GPS coordinates from the user device (most accurate).';

  String get mapLegendIpDesc => isId
      ? 'Perkiraan dari alamat IP saat user login (kasar, bisa meleset jauh / terkena VPN).'
      : 'Approximate from the IP address at login (coarse, may be off / affected by VPN).';

  String get mapLegendResolvedDesc => isId
      ? 'Perkiraan IP yang dihitung admin saat peta dibuka, untuk user yang belum punya koordinat.'
      : 'IP lookup computed by admin when the map opens, for users with no coordinates yet.';

  String get mapLegendNote => isId
      ? 'GPS tidak pernah tertimpa IP. Bila user pernah buka GPS, titik tetap akurat.'
      : 'GPS is never overwritten by IP. Once a user shares GPS, the point stays accurate.';

  String get mapResolveFailed =>
      isId ? 'IP gagal di-resolve' : 'IPs failed to resolve';

  String get adminSearchChat =>
      isId ? 'Cari percakapan...' : 'Search conversations...';

  String get adminUserSingular => isId ? 'user' : 'user';

  String get adminUsersPlural => isId ? 'user' : 'users';

  String get adminDeleteChat => isId ? 'Hapus Chat' : 'Delete Chat';

  String get adminDeleteChatTitle =>
      isId ? 'Hapus Chat & User' : 'Delete Chat & Users';

  String get adminDeleteChatBody => isId
      ? 'Semua history chat antara kedua user akan dihapus permanen (termasuk foto di storage). Pilih user yang juga ingin dihapus akunnya:'
      : 'All chat history between both users will be permanently deleted (including photos in storage). Select users to also delete their accounts:';

  String get adminDeleteChatOnly =>
      isId ? 'Hapus chat saja' : 'Delete chat only';

  String get adminDeleteUser => isId ? 'Hapus akun' : 'Delete account';

  String get adminCannotDeleteAdmin =>
      isId ? '(admin, tidak bisa dihapus)' : '(admin, cannot be deleted)';

  String get adminChatDeleted => isId ? 'Chat dihapus' : 'Chat deleted';

  String get adminDeleteFail =>
      isId ? 'Gagal menghapus chat' : 'Failed to delete chat';

  String get adminDummyTab => isId ? 'Dummy' : 'Dummy';

  String get dummyCreateTitle =>
      isId ? 'Buat Akun Dummy' : 'Create Dummy Account';

  String get dummyNicknameLabel => isId ? 'Nickname' : 'Nickname';

  String get dummyRegisterBtn => isId ? 'Daftarkan Akun' : 'Register Account';

  String get dummyRegisterHint => isId
      ? 'Akun anonymous dibuat otomatis — cukup isi nickname.'
      : 'An anonymous account is created automatically — just enter a nickname.';

  String get dummyRegisterFail =>
      isId ? 'Gagal membuat akun dummy' : 'Failed to create dummy account';

  String get dummyEdit => isId ? 'Edit' : 'Edit';

  String get dummySaveChanges => isId ? 'Simpan Perubahan' : 'Save Changes';

  String get dummyCancelEdit => isId ? 'Batal Edit' : 'Cancel Edit';

  String get dummyAdd => isId ? 'Tambah Dummy' : 'Add Dummy';

  String get dummyUpdated =>
      isId ? 'Profil dummy diperbarui' : 'Dummy profile updated';

  String get dummyUpdateFail =>
      isId ? 'Gagal memperbarui profil' : 'Failed to update profile';

  String get dummyListTitle => isId ? 'Akun Dummy' : 'Dummy Accounts';

  String get dummyEmpty =>
      isId ? 'Belum ada akun dummy' : 'No dummy accounts yet';

  String get dummySearchEmpty =>
      isId ? 'Tidak ada dummy yang cocok' : 'No matching dummy found';

  // Filter tipe akun dummy (kolom `kind`: regular/expert).
  String get dummyKindAll => isId ? 'Semua' : 'All';
  String get dummyKindRegular => isId ? 'Biasa' : 'Regular';
  String get dummyKindExpert => isId ? 'Expert' : 'Expert';

  String get dummyChatAs => isId ? 'Chat Sebagai' : 'Chat As';

  String get dummyChatAsTitle =>
      isId ? 'Jadi Akun Ini?' : 'Become This Account?';

  String get dummyChatAsBody => isId
      ? 'Anda akan keluar dari akun admin dan masuk sebagai %s. Chat dengan siapa saja, lalu kembali ke admin lewat tombol di Profil.'
      : 'You will sign out of admin and sign in as %s. Chat with anyone, then return to admin via the button on your Profile.';

  String get dummyDelete => isId ? 'Hapus' : 'Delete';

  String get dummyDeleteTitle =>
      isId ? 'Hapus Akun Dummy?' : 'Delete Dummy Account?';

  String get dummyDeleteBody => isId
      ? 'Akun %s beserta history chat-nya akan dihapus permanen.'
      : 'Account %s and its chat history will be permanently deleted.';

  String get dummyDeleted =>
      isId ? 'Akun dummy dihapus' : 'Dummy account deleted';

  String get dummyStatusSet => isId ? 'Status diset' : 'Status set';

  String get dummyRegistered =>
      isId ? 'Akun dummy terdaftar' : 'Dummy account registered';

  String get dummySwapFailed =>
      isId ? 'Gagal masuk sebagai dummy' : 'Failed to sign in as dummy';

  String get dummyInvalidInput =>
      isId ? 'Lengkapi nickname terlebih dahulu' : 'Fill in the nickname first';

  String get dummySwapSuccess => isId
      ? 'Sekarang kamu adalah %s — kembali ke admin lewat Profil'
      : 'You are now %s — return to admin via Profile';

  String get dummySetStatusFail =>
      isId ? 'Gagal menyetel status' : 'Failed to set status';

  // ── AI mode dummy ──
  String get dummyAiChip => 'AI';

  String get dummyAiTooltip => isId ? 'Mode AI' : 'AI Mode';

  // ── Bangunkan dummy 30 menit ──
  String get dummyWake => isId ? 'Bangunkan 30 menit' : 'Wake up for 30 min';

  String get dummyWakeDone =>
      isId ? 'Dibangunkan 30 menit' : 'Woken for 30 minutes';

  String get dummyWakeFail => isId ? 'Gagal membangunkan' : 'Failed to wake up';

  String get dummyAwake => isId ? 'Bangun' : 'Awake';

  String get dummyAsleep => isId ? 'Tidur' : 'Asleep';

  String get dummyWakeUntil => isId ? 's/d %s' : 'till %s';

  String get dummyAiTitle => isId ? 'Mode AI Dummy' : 'Dummy AI Mode';

  String get dummyAiDesc => isId
      ? 'AI membalas chat masuk memakai persona dari profil dummy ini (nama, umur, kota, hashtag = hobi).'
      : 'AI replies to incoming chats using this dummy\'s profile (name, age, city, hashtags = hobbies).';

  String get dummyAiPersonality => isId ? 'Kepribadian' : 'Personality';

  String get dummyAiPersonalityAuto => isId
      ? 'Kosong = otomatis (unik per dummy)'
      : 'Empty = auto (unique per dummy)';

  String get dummyAiTone => isId ? 'Gaya bicara' : 'Speaking style';

  String get dummyAiToneAuto => isId
      ? 'Kosong = otomatis (santai, 1-3 kalimat)'
      : 'Empty = auto (casual, 1-3 sentences)';

  String get dummyAiExtra => isId ? 'Prompt tambahan' : 'Extra prompt';

  String get dummyAiExtraHint => isId
      ? 'Instruksi khusus untuk AI...'
      : 'Special instructions for the AI...';

  // ── Kirim Foto (toggle per dummy) ──
  String get dummyPhotosTitle => isId ? 'Kirim Foto' : 'Send Photos';

  String get dummyPhotosLabel =>
      isId ? 'AI bisa kirim foto' : 'AI can send photos';

  String get dummyPhotosDesc => isId
      ? 'Saat dimatikan, AI tidak mengirim foto dan tidak mengarahkan minta foto'
      : 'When off, AI won\'t send photos or direct users to request them';

  String get dummyAiEnabledLabel => isId ? 'AI aktif' : 'AI on';

  String get dummyAiSaved =>
      isId ? 'Pengaturan AI disimpan' : 'AI settings saved';

  String get dummyAiSaveFail =>
      isId ? 'Gagal menyimpan AI' : 'Failed to save AI settings';

  String get dummyAiInstantHint => isId
      ? 'Bagian 1 & 3 tersimpan otomatis saat diubah — tombol Simpan hanya untuk Kepribadian.'
      : 'Sections 1 & 3 save automatically — Save is only for Personality.';

  String get dummyAiSectionStatus => isId ? '1 · Status AI' : '1 · AI Status';

  String get dummyAiSectionPersona =>
      isId ? '2 · Kepribadian (opsional)' : '2 · Personality (optional)';

  String get dummyAiSectionAdvanced =>
      isId ? '3 · Lanjutan (jarang diubah)' : '3 · Advanced (rarely changed)';

  String get dummyAiBadgeRequired => isId ? 'WAJIB' : 'REQUIRED';

  String get dummyAiBadgeOptional => isId ? 'OPSIONAL' : 'OPTIONAL';

  String get dummyAiBadgeAuto => isId ? 'OTO' : 'AUTO';

  String get dummyAiStatusDesc => isId
      ? 'Nyalakan sekali, AI langsung membalas chat masuk. Mati = dummy diam total.'
      : 'Turn on once, AI replies to incoming chats. Off = dummy stays silent.';

  String get dummyAiPersonaDesc => isId
      ? 'Kosongkan semua = AI meniru profil dummy otomatis. Isi hanya kalau mau karakter khusus.'
      : 'Leave all empty = AI follows the dummy profile automatically. Fill only for a custom character.';

  String get dummyNeedAdmin => isId
      ? 'Bukan sesi admin — kembali ke akun admin dulu baru simpan'
      : 'Not an admin session — switch back to the admin account first';

  String get adminPhotoLoadFail => isId
      ? 'Gagal memuat foto — periksa koneksi lalu ketuk lagi'
      : 'Failed to load photo — check connection then tap again';

  String get privacyBypassTitle => isId ? 'Bypass Privasi' : 'Privacy Bypass';
  String get privacyBypassDesc => isId
      ? 'ON = admin melihat semua profil user tanpa filter privasi. User biasa tidak terdampak.'
      : 'ON = admin sees all user profiles with no privacy filter. Regular users unaffected.';

  String get dummyAiScheduleTitle =>
      isId ? 'Jadwal kehadiran AI' : 'AI presence schedule';

  String get dummyStoryList => isId ? 'Story harian' : 'Daily story';

  String get dummyStoryListDesc => isId
      ? 'Riwayat cerita harian dummy biasa (expert tidak punya story).'
      : 'Daily story history for regular dummies (experts have no story).';

  String get dummyStoryExpected => isId
      ? 'Dummy biasa — story harian di-generate tiap 22:00 WIB.'
      : 'Regular dummy — daily story generated daily at 22:00 WIB.';

  String get dummyStoryNotExpected => isId
      ? 'Akun expert — tidak dibuatkan story.'
      : 'Expert account — no story generated.';

  String get dummyStoryEmpty => isId ? 'Belum ada story.' : 'No story yet.';

  String get dummyStoryMissing => isId ? 'KOSONG' : 'MISSING';

  String get dummyStoryFilled => isId ? 'Ada' : 'OK';

  String get dummyStoryMissingCount =>
      isId ? '%s hari belum ke-generate' : '%s day(s) not generated';

  String get dummyStoryLoadFail =>
      isId ? 'Gagal memuat story' : 'Failed to load stories';
  String get dummyStoryGenerate =>
      isId ? 'Generate story hari ini' : 'Generate today\'s story';
  String get dummyStoryGenerating =>
      isId ? 'Sedang membuat story…' : 'Generating story…';
  String get dummyStoryGenerated =>
      isId ? 'Story hari ini berhasil dibuat' : 'Today\'s story generated';
  String get dummyStoryGenerateFail =>
      isId ? 'Gagal membuat story hari ini' : 'Failed to generate today\'s story';

  String get dummyAiScheduleDesc => isId
      ? 'AI online/idle/offline mengikuti jam aktif. Offline = AI tidak membalas sama sekali.'
      : 'AI goes online/idle/offline following active hours. Offline = AI never replies.';

  String get dummyAiScheduleAuto =>
      isId ? 'Jadwal otomatis dari kebiasaan' : 'Auto schedule from habits';

  String get dummyAiScheduleEmpty => isId
      ? 'Belum diatur — presence dikontrol manual'
      : 'Not set — presence controlled manually';

  String get dummyAiScheduleAutoLabel =>
      isId ? 'Jadwal otomatis harian (AI)' : 'Daily auto schedule (AI)';

  String get dummyAiScheduleAutoDesc => isId
      ? 'AI menentukan sendiri jam onlinenya tiap hari. Matikan untuk kontrol manual penuh.'
      : 'AI decides its own online hours daily. Turn off for full manual control.';

  String get aiGlobalTitle => 'AI Bot';

  String get aiGlobalDesc => isId
      ? 'Master switch semua balasan AI dummy + batas rate.'
      : 'Master switch for all dummy AI replies + rate limits.';

  String get aiGlobalMaxReplies =>
      isId ? 'Maks balasan per chat per jam' : 'Max replies per chat per hour';

  String get aiGlobalMinInterval => isId
      ? 'Jeda minimal antar balasan (detik)'
      : 'Min interval between replies (seconds)';

  String get aiGlobalSaved =>
      isId ? 'Pengaturan AI global disimpan' : 'Global AI settings saved';

  String get aiGlobalGuardTitle => isId ? 'Guard NSFW' : 'NSFW guard';

  String get aiGlobalGuardDesc => isId
      ? 'Blokir obrolan vulgar — matikan untuk mode nakal'
      : 'Block vulgar chat — turn off for naughty mode';

  String get aiAiChatTitle => isId ? 'Chat AI ↔ AI' : 'AI ↔ AI chat';

  String get aiAiChatDesc => isId
      ? 'Izinkan dummy AI saling membalas (uji coba bot vs bot). Matikan agar dummy hanya membalas manusia.'
      : 'Allow AI dummies to reply to each other (bot vs bot testing). Turn off so dummies only reply to humans.';

  String get dummyAiGuardHint => isId
      ? 'Global = ikut pengaturan AI Bot; ON/OFF = khusus dummy ini'
      : 'Global = follow AI Bot settings; ON/OFF = this dummy only';

  String get aiGuardGlobal => 'Global';
  String get aiGuardOn => 'ON';
  String get aiGuardOff => 'OFF';

  // ── Font global (tampilan aplikasi) ──
  String get adminFontTitle => isId ? 'Font Aplikasi' : 'App Font';

  String get adminFontDesc => isId
      ? 'Ganti font seluruh aplikasi untuk semua pengguna (realtime).'
      : 'Change the whole app font for all users (realtime).';

  String get adminFontCurrent => isId ? 'Aktif' : 'Active';

  String get adminFontPickTitle => isId ? 'Pilih Font' : 'Choose Font';

  String get adminFontPreviewHeading =>
      isId ? 'Judul Contoh 24' : 'Sample Heading 24';

  String get adminFontPreviewBody => isId
      ? 'Teks isi contoh 14 — tampilan chat, tombol, dan label ikut font ini.'
      : 'Sample body 14 — chat text, buttons, and labels follow this font.';

  String get adminFontPreviewLight => isId
      ? 'Contoh Light 300 — begini rasa teks tipis di chat.'
      : 'Light 300 sample — this is how thin text reads in chat.';

  String get adminFontSampleShort => isId
      ? 'Halo, apa kabar?'
      : 'Hello, how are you?';

  String get adminFontSaved =>
      isId ? 'Font aplikasi diperbarui' : 'App font updated';

  String get adminFontDefaultNote => isId
      ? 'Default = judul/Cta Poppins, isi Roboto (seperti semula).'
      : 'Default = Poppins headings/CTA, Roboto body (unchanged).';

  String get dummyRateTitle => isId ? 'Rate limit' : 'Rate limit';

  String get dummyRateUnlimited =>
      isId ? 'Tanpa batas (unlimited)' : 'Unlimited';

  String get dummyRateMax =>
      isId ? 'Maks balasan per chat per jam' : 'Max replies per chat per hour';

  String get dummyRateMin => isId
      ? 'Jeda antar balasan (detik)'
      : 'Interval between replies (seconds)';

  String get dummyRateGlobalHint => isId
      ? 'Kosongkan = ikut pengaturan AI Bot (global)'
      : 'Empty = follow AI Bot settings (global)';

  String dummyRateGlobalHintVals(int m, int j) => isId
      ? 'Kosongkan = ikut AI Bot ($m/jam, jeda $j dtk)'
      : 'Empty = follow AI Bot ($m/hr, $j s gap)';

  String get dummyScheduleStatusNow =>
      isId ? 'Status sekarang' : 'Current status';

  String get dummyScheduleAlwaysOn => isId
      ? 'Tanpa jadwal otomatis — status dikontrol manual/tombol'
      : 'No auto schedule — status is controlled manually/buttons';

  String get dummyHoursTitle => isId ? 'Jam online' : 'Online hours';

  String get dummyHoursHint => isId
      ? 'Pilih jam online — kosong semua = tanpa jadwal otomatis. Cron menyeting status tiap 5 menit.'
      : 'Pick online hours — empty = no auto schedule. Cron sets status every 5 minutes.';

  String get dummyHoursSelectAll => isId ? 'Semua 24 Jam' : 'All 24 Hours';
  String get dummyHoursClearAll => isId ? 'Hapus Semua' : 'Clear All';

  String get aiGlobalModel => isId ? 'Model default' : 'Default model';

  String get aiGlobalBaseUrl => isId ? 'Base URL' : 'Base URL';

  String get aiGlobalApiKey => isId ? 'API Key' : 'API Key';

  String get aiGlobalProviderHint => isId
      ? 'Kosongkan = pakai default server. Base URL tanpa /chat/completions.'
      : 'Empty = use server default. Base URL without /chat/completions.';

  String get aiProviderListTitle => isId ? 'Provider AI' : 'AI providers';

  String get aiProviderActive => isId ? 'Dipakai' : 'In use';

  String get aiProviderAdd => isId ? 'Tambah provider' : 'Add provider';

  String get aiProviderLabel => isId ? 'Nama provider' : 'Provider name';

  String get aiProviderSave => isId ? 'Simpan provider' : 'Save provider';

  String get aiProviderSaved => isId ? 'Provider disimpan' : 'Provider saved';

  String get aiProviderActivated =>
      isId ? 'Provider diaktifkan' : 'Provider activated';

  String get aiProviderDeleted =>
      isId ? 'Provider dihapus' : 'Provider deleted';

  String get aiProviderDeleteConfirm =>
      isId ? 'Hapus provider ini?' : 'Delete this provider?';

  String get aiProviderDeleteActive => isId
      ? 'Aktifkan provider lain dulu sebelum menghapus yang ini'
      : 'Activate another provider before deleting this one';

  String get aiProviderDeleteLast => isId
      ? 'Tidak bisa hapus satu-satunya provider'
      : 'Cannot delete the only provider';

  String get aiProviderLoadFail =>
      isId ? 'Gagal memuat provider' : 'Failed to load providers';

  String get aiProviderModelPreset =>
      isId ? 'Pilih preset model' : 'Pick a model preset';

  String get aiProviderStoryModel =>
      isId ? 'Model cerita harian' : 'Daily story model';
  String get aiProviderStoryModelHint => isId
      ? 'Model untuk cerita/kegiatan harian AI. Kosong = ikut model chat.'
      : 'Model for the AI daily story/activity. Empty = follow chat model.';
  String get aiProviderFallbackModel =>
      isId ? 'Model cadangan' : 'Fallback model';
  String get aiProviderFallbackModelHint => isId
      ? 'Dipakai bila model utama gagal (saldo habis/limit). Kosong = bawaan gratis.'
      : 'Used when the main model fails (out of balance/limit). Empty = built-in free.';

  String get dummyListFail =>
      isId ? 'Gagal memuat akun dummy' : 'Failed to load dummy accounts';

  String get dummyChatsDeleted =>
      isId ? 'History chat terhapus' : 'Chat history deleted';

  String get dummyBackToAdmin => isId ? 'Kembali ke Admin' : 'Back to Admin';

  String get dummyBackConfirmTitle =>
      isId ? 'Kembali ke Admin?' : 'Back to Admin?';

  String get dummyBackConfirmBody => isId
      ? 'Kembali ke akun admin. Akun dummy tetap login & statusnya tidak berubah.'
      : 'Return to the admin account. The dummy stays signed in and its status is unchanged.';

  String get dummyBackFailed => isId
      ? 'Sesi admin kedaluwarsa — silakan login manual'
      : 'Admin session expired — sign in manually';

  String get dummyBackDone =>
      isId ? 'Kembali ke akun admin' : 'Back to admin account';

  String get dummyBannerTitle =>
      isId ? 'Mode Akun Dummy' : 'Dummy Account Mode';

  String get dummyBannerSubtitle =>
      isId ? 'Kamu sedang tampil sebagai %s' : 'You are appearing as %s';
}
