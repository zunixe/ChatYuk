// String khusus ADMIN — JANGAN di-import dari kode build rilis.
// Extension on S: karena hanya modul admin yang meng-import file
// ini, tree shaker membuang seluruh string bersama layar admin.
import 'strings.dart';

extension SAdminX on S {
  String get adminCallLive => isId ? 'Call aktif' : 'Live call';

  String get adminCallRinging => isId ? 'Memanggil...' : 'Ringing...';

  String get adminWatching => isId ? 'Memantau' : 'Monitoring';

  String get adminListening => isId ? 'Mendengarkan...' : 'Listening...';

  String get adminWaitingVideo =>
      isId ? 'Menunggu video...' : 'Waiting for video...';

  String get adminCameraOff => isId ? 'Kamera mati' : 'Camera off';

  String get adminMicOff => isId ? 'Mikrofon mati' : 'Mic muted';

  String get adminSwapView => isId ? 'Tukar tampilan' : 'Swap view';

  String get adminWatchConnecting =>
      isId ? 'Menyambungkan...' : 'Connecting...';

  String get adminContactTab => isId ? 'Kontak' : 'Contact';

  String get adminDeviceTab => isId ? 'Perangkat' : 'Devices';
  String get adminDeviceTitle => isId ? 'Perangkat' : 'Devices';
  String get adminDeviceSearch => isId ? 'Cari user/device...' : 'Search user/device...';
  String get adminDeviceNoData =>
      isId ? 'Belum ada device terdeteksi' : 'No devices detected yet';
  String get adminDeviceNoResult => isId ? 'Tidak ada yang cocok' : 'No match found';
  String get adminDeviceActive => isId ? 'aktif' : 'active';
  String get adminDeviceInactive => isId ? 'lama' : 'inactive';
  String get adminDeviceModel => isId ? 'Device' : 'Device';
  String get adminDeviceOs => isId ? 'OS' : 'OS';
  String get adminDeviceLastSeen => isId ? 'Terakhir aktif' : 'Last seen';
  String get adminDeviceInstallId => isId ? 'Install ID' : 'Install ID';
  String get adminDeviceIp => isId ? 'IP' : 'IP';
  String get adminDeviceDetail => isId ? 'Detail User' : 'User Detail';
  String get adminDeviceProfile => isId ? 'Profil' : 'Profile';
  String get adminDeviceUserid => isId ? 'User ID' : 'User ID';
  String get adminDeviceEmail => isId ? 'Email' : 'Email';
  String get adminDeviceRegistered => isId ? 'Terdaftar' : 'Registered';
  String get adminDeviceAnon => isId ? 'Anonim' : 'Anonymous';
  String get adminDeviceGender => isId ? 'Kelamin' : 'Gender';
  String get adminDeviceCity => isId ? 'Kota' : 'City';
  String get adminDeviceAge => isId ? 'Umur' : 'Age';
  String get adminDevicePoints => isId ? 'Poin' : 'Points';
  String get adminDeviceStatus => isId ? 'Status' : 'Status';
  String get adminDeviceLastLogin => isId ? 'Login terakhir' : 'Last login';
  String get adminDeviceCreated => isId ? 'Dibuat' : 'Created';
  String get adminDeviceDevices => isId ? 'Perangkat' : 'Devices';
  String get adminDeviceChats => isId ? 'Chat dengan' : 'Chats with';
  String get adminDeviceLocation => isId ? 'Riwayat Lokasi' : 'Location History';
  String get adminDeviceNoDevices =>
      isId ? 'Belum ada perangkat tercatat' : 'No devices recorded';
  String get adminDeviceNoChats =>
      isId ? 'Belum ada chat' : 'No chats yet';
  String get adminDeviceCopyId => isId ? 'Salin' : 'Copy';
  String get adminDeviceCopied => isId ? 'Disalin' : 'Copied';
  String get adminDeviceUsersUsed =>
      isId ? 'User yang pernah login' : 'Users who logged in';
  String get adminDeviceNoUsers =>
      isId ? 'Belum ada user tercatat' : 'No users recorded';
  String get adminDeviceOpenUser =>
      isId ? 'Lihat detail user' : 'View user detail';
  String get adminDeviceCount =>
      isId ? 'user' : 'user';
  String get adminDeviceByUser => isId ? 'Per User' : 'By User';
  String get adminDeviceByDevice => isId ? 'Per Device' : 'By Device';

  String get adminStorageTitle => isId
      ? 'Penggunaan Data Supabase'
      : 'Supabase Data Usage';
  String get adminStorageDb => isId ? 'Database' : 'Database';
  String get adminStorageImages => isId
      ? 'Gambar (chat & publik)'
      : 'Images (chat & public)';
  String get adminStorageFree => isId ? 'Tersedia' : 'Free';
  String get adminStorageTotal => isId ? 'Total Terpakai' : 'Total Used';
  String get adminStorageFiles => isId ? 'File gambar' : 'Image files';
  String get adminStorageGrowth => isId
      ? 'Pertumbuhan Data'
      : 'Data Growth';
  String get adminGrowthDay => isId ? 'Hari ini' : 'Today';
  String get adminGrowthWeek => isId ? '7 hari' : '7 days';
  String get adminGrowthMonth => isId ? '30 hari' : '30 days';
  String get adminGrowthMessages => isId ? 'Pesan' : 'Messages';
  String get adminGrowthSignals => isId ? 'Sinyal call' : 'Call signals';
  String get adminGrowthImages => isId ? 'Gambar' : 'Images';
  String get adminGrowthRegistrations =>
      isId ? 'Registrasi' : 'Registrations';
  String get adminRegListTitle =>
      isId ? 'User Terdaftar (Email)' : 'Registered Users (Email)';
  String get adminCfTitle =>
      isId ? 'Cloudflare Realtime (TURN)' : 'Cloudflare Realtime (TURN)';
  String get adminCfNotConfigured => isId
      ? 'Belum dikonfigurasi — set CF_ACCOUNT_ID & CF_ANALYTICS_TOKEN di secrets Supabase untuk melihat kuota.'
      : 'Not configured — set CF_ACCOUNT_ID & CF_ANALYTICS_TOKEN in Supabase secrets to see quota.';
  String get adminCfQuota => isId ? 'Kuota 1 TB/bulan' : '1 TB/month quota';
  String get adminCfMonth => isId ? 'Bulan ini' : 'This month';
  String get adminQuotaLabel => isId ? 'Kuota' : 'Quota';

  String get adminDeletedTab => isId ? 'Terhapus' : 'Deleted';
  String get adminDeletedTitle => isId ? 'User Terhapus' : 'Deleted Users';
  String get adminDeletedSearch =>
      isId ? 'Cari user terhapus...' : 'Search deleted users...';
  String get adminDeletedNoData =>
      isId ? 'Belum ada user terhapus' : 'No deleted users yet';
  String get adminDeletedNoResult =>
      isId ? 'Tidak ada yang cocok' : 'No match found';
  String get adminDeletedReason => isId ? 'Alasan' : 'Reason';
  String get adminDeletedAt => isId ? 'Dihapus' : 'Deleted';
  String get adminDeletedStale =>
      isId ? 'Stale (anon >7 hari)' : 'Stale (anon >7 days)';
  String get adminDeletedClaim =>
      isId ? 'Nickname diambil' : 'Nickname claimed';
  String get adminDeletedAdmin =>
      isId ? 'Dihapus admin' : 'Deleted by admin';
  String get adminDeletedDummy =>
      isId ? 'Dummy dihapus' : 'Dummy deleted';
  String get adminDeletedClaimedBy =>
      isId ? 'Diambil oleh' : 'Claimed by';
  String get adminDeletedNewNick =>
      isId ? 'Nickname baru' : 'New nickname';
  String get adminDeletedDeviceHistory =>
      isId ? 'Riwayat Device' : 'Device History';
  String get adminDeletedNoDevice =>
      isId ? 'Tidak ada device tercatat' : 'No devices recorded';
  String get adminDeletedUid => isId ? 'UID Asli' : 'Original UID';

  String get privateRoomsScanQr => isId ? 'Scan QR' : 'Scan QR';
  String get privateRoomsEmpty => isId
      ? 'Belum ada room privat. Buat baru atau scan QR undangan.'
      : 'No private rooms yet. Create one or scan an invite QR.';
  String get privateRoomsYouAreOwner =>
      isId ? 'kamu pemiliknya' : 'you are the owner';
  String get privateRoomsLive => isId ? 'LIVE' : 'LIVE';
  String get privateRoomsMaxNote => isId
      ? 'Maks 20 member · join via QR wajib disetujui admin'
      : 'Max 20 members · QR joins require admin approval';
  String get privateRoomsQrHint => isId
      ? 'Bagikan QR ini. Yang scan akan masuk antrean dan harus di-approve.'
      : 'Share this QR. Scanners join a queue and need your approval.';
  String get privateRoomsCopyLink => isId ? 'Salin Link QR' : 'Copy QR Link';
  String get privateRoomsRotateQr =>
      isId ? 'Ganti Kode QR (QR lama mati)' : 'Rotate QR (old QR dies)';
  String get privateRoomsRotated =>
      isId ? 'QR baru dibuat, QR lama mati' : 'New QR created, old QR revoked';
  String get privateRoomsEnterRoom => isId ? 'Masuk Room' : 'Enter Room';
  String get createRoomNameLabel =>
      isId ? 'Nama Room (3-30 karakter)' : 'Room Name (3-30 chars)';
  String get privateRoomsJoinPendingTitle =>
      isId ? 'Menunggu Persetujuan' : 'Awaiting Approval';
  String get privateRoomsJoinPendingBody => isId
      ? 'Request join terkirim. Tunggu admin menyetujui — kamu akan bisa masuk setelah itu.'
      : 'Join request sent. Wait for admin approval before entering.';
  String get privateRoomsJoinedTitle =>
      isId ? 'Berhasil Masuk' : 'Joined Successfully';
  String get privateRoomsJoinedBody =>
      isId ? 'Kamu resmi jadi member room ini.' : 'You are now a member of this room.';
  String get roomHandRaised => isId
      ? 'Tangan diangkat — tunggu admin mengizinkan'
      : 'Hand raised — waiting for admin approval';
  String get privateRoomsLiveConnecting => isId
      ? 'Menyambungkan...'
      : 'Connecting...';
  String get roomShowChat => isId ? 'Chat' : 'Chat';
  String get roomShowMembers => isId ? 'Anggota' : 'Members';

  String get privateRoomsScanHint => isId
      ? 'Arahkan kamera ke QR undangan room'
      : 'Point the camera at a room invite QR';
  String get privateRoomsShowQr =>
      isId ? 'Kode QR Undangan' : 'Invite QR';
  String get privateRoomsMembersTitle =>
      isId ? 'Anggota' : 'Members';
  String get privateRoomsPendingQueue =>
      isId ? 'Menunggu Persetujuan' : 'Pending Approvals';
  String get roomRoleOwner => isId ? 'Pemilik' : 'Owner';
  String get roomRoleAdmin => isId ? 'Admin' : 'Admin';
  String get roomRoleMember => isId ? 'Member' : 'Member';
  String get roomActionPromote => isId
      ? 'Jadikan admin'
      : 'Promote to admin';
  String get roomActionDemote => isId
      ? 'Turunkan jadi member'
      : 'Demote to member';
  String get roomActionKick => isId ? 'Keluarkan' : 'Remove';
  String get roomActionBroadcast =>
      isId ? 'Izinkan Broadcast' : 'Allow Broadcast';
  String get roomActionRevokeBroadcast =>
      isId ? 'Batalkan Broadcast' : 'Revoke Broadcast';
  String get roomKickConfirmTitle => isId
      ? 'Keluarkan dari room?'
      : 'Remove from room?';
  String get roomKickConfirmBody => isId
      ? 'User bisa request masuk lagi, tapi harus di-approve.'
      : 'They can request again but must be approved.';

  String get adminContactEmpty =>
      isId ? 'Belum ada pesan kontak' : 'No contact messages yet';

  String get adminContactDeleteMsg =>
      isId ? 'Hapus pesan ini?' : 'Delete this message?';

  String get labelScreenshotAllow =>
      isId ? 'Izinkan screenshot aplikasi' : 'Allow app screenshots';

  String get descScreenshotAdmin => isId
      ? 'Admin — kontrol screenshot untuk semua pengguna'
      : 'Admin — control screenshots for all users';

  String get descScreenshotAdminBuild => isId
      ? 'Pengaturan ini hanya berlaku untuk ChatYuk user. ChatYuk Admin selalu bisa screenshot.'
      : 'This setting applies only to ChatYuk user. ChatYuk Admin can always take screenshots.';

  String get labelWatermarkAdmin =>
      isId ? 'Aktifkan watermark forensik' : 'Enable forensic watermark';

  String get descWatermarkAdmin => isId
      ? 'Admin — foto sekali lihat ditandai identitas penerima'
      : 'Admin — view-once photos tagged with receiver identity';

  String get labelInvisibleAdmin => isId ? 'Mode invisible' : 'Invisible mode';

  String get descInvisibleAdmin => isId
      ? 'Admin — tidak muncul di daftar pengguna online'
      : 'Admin — hidden from online users list';

  String get adminPanel => isId ? 'Admin Panel' : 'Admin Panel';

  String get adminNoUsers => isId ? 'Tidak ada user' : 'No users';

  String get adminPointSettings =>
      isId ? 'Pengaturan Nilai Poin' : 'Point Value Settings';

  String get adminSavePointSettings =>
      isId ? 'Simpan Pengaturan' : 'Save Settings';

  String get adminViewOnMaps => isId ? 'Lihat di Maps' : 'View on Maps';

  String get adminTopEarners => isId ? 'Top Earners' : 'Top Earners';

  String get adminMassBonus => isId ? 'Bonus Massal' : 'Mass Bonus';

  String get adminForceLogout => isId ? 'Force Logout' : 'Force Logout';

  String get adminPointsSystem => isId ? 'Sistem Poin' : 'Points System';

  String get adminReports => isId ? 'Laporan' : 'Reports';

  String get adminNoReports => isId ? 'Tidak ada laporan' : 'No reports';

  String get adminDangerZone => isId ? 'Zona Bahaya' : 'Danger Zone';

  String get adminResetAllPoints =>
      isId ? 'Reset semua user ke 50 poin' : 'Reset all users to 50 points';

  String get adminResetAllTitle =>
      isId ? 'Reset Semua Poin?' : 'Reset All Points?';

  String get adminResetAllBody => isId
      ? 'Semua user akan memiliki 50 poin.'
      : 'All users will have 50 points.';

  String get adminWipeAll => isId ? 'Reset Semua' : 'Wipe All';

  String get adminReset => isId ? 'Reset' : 'Reset';

  String get adminLogout => isId ? 'Keluar' : 'Logout';

  String get adminRunning => isId ? 'Berjalan' : 'Running';

  String get adminPaused => isId ? 'Dihentikan' : 'Paused';

  String get adminRealtimeDesc => isId
      ? 'Realtime — efek langsung ke semua device'
      : 'Realtime — immediate effect on all devices';

  String get adminCallAllTitle => isId
      ? 'Tombol Call untuk Semua User'
      : 'Call Button for All Users';
  String get adminCallAllOn => isId ? 'Semua user' : 'All users';
  String get adminCallAllOff => isId ? 'Terdaftar saja' : 'Registered only';
  String get adminCallAllDesc => isId
      ? 'Saat aktif, ikon panggilan (audio/video) tampil untuk semua user termasuk yang belum daftar.'
      : 'When enabled, the call (audio/video) icon appears for all users including unregistered ones.';

  String get adminRegisteredOnly =>
      isId ? 'Hanya user registered' : 'Registered users only';

  String get adminStuckUsers =>
      isId ? 'user terjebak (0 poin)' : 'users stuck (0 points)';

  String get adminOverview => isId ? 'Ringkasan' : 'Overview';

  String get adminGlobalSettingTab =>
      isId ? 'Pengaturan Global' : 'Global Setting';

  String get adminRegTitle => isId ? 'Registrasi Email' : 'Email Registrations';

  String get adminRegPerDay => isId ? 'Per hari' : 'Per day';

  String get adminRegTotal => isId ? 'Total' : 'Total';

  String get adminRegEmpty =>
      isId ? 'Tidak ada pendaftaran bulan ini' : 'No registrations this month';

  String get adminPointTab => isId ? 'Poin' : 'Points';

  String get adminChatMonitor => isId ? 'Monitor Chat' : 'Chat Monitor';

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

  String get dummyUpdated =>
      isId ? 'Profil dummy diperbarui' : 'Dummy profile updated';

  String get dummyUpdateFail =>
      isId ? 'Gagal memperbarui profil' : 'Failed to update profile';

  String get dummyListTitle => isId ? 'Akun Dummy' : 'Dummy Accounts';

  String get dummyEmpty =>
      isId ? 'Belum ada akun dummy' : 'No dummy accounts yet';

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

// ── Exclude Device (Pengaturan Global) ──────────────────────────────
extension SAdminExcludeX on S {
  String get adminExcludeTitle =>
      isId ? 'Exclude Perangkat' : 'Exclude Devices';

  String get adminExcludeSubtitle => isId
      ? 'Perangkat yang di-exclude tidak dihitung di ringkasan (users, aktif, anon) & disembunyikan dari daftar Perangkat'
      : 'Excluded devices are not counted in the summary (users, active, anon) & hidden from the Devices list';

  String get adminExcludeCount => isId
      ? '%d perangkat ter-exclude'
      : '%d device(s) excluded';

  String get adminExcludeNone => isId
      ? 'Belum ada perangkat yang di-exclude'
      : 'No devices excluded yet';

  String get adminExcludeAddHint =>
      isId ? 'Tempel Install ID...' : 'Paste Install ID...';

  String get adminExcludeAdd => isId ? 'Tambah' : 'Add';

  String get adminExcludeRemove => isId ? 'Hapus' : 'Remove';

  String get adminExcludeEmptyId => isId
      ? 'Install ID tidak boleh kosong'
      : 'Install ID cannot be empty';

  String get adminExcludeSaved =>
      isId ? 'Daftar exclude tersimpan' : 'Exclusion list saved';

  String get adminExcludeSaveFailed =>
      isId ? 'Gagal menyimpan' : 'Failed to save';

  String get adminExcludeDeviceAction =>
      isId ? 'Exclude perangkat ini' : 'Exclude this device';

  String get adminExcludeDeviceDone => isId
      ? 'Perangkat di-exclude dari ringkasan'
      : 'Device excluded from summary';

  String get adminExcludedBadge => isId ? 'EXCLUDED' : 'EXCLUDED';

  String get adminExcludeConfirmRemove => isId
      ? 'Hapus dari daftar exclude?'
      : 'Remove from exclusion list?';

  String get adminExcludeAddTitle =>
      isId ? 'Kelola Perangkat Ter-exclude' : 'Manage Excluded Devices';
}
