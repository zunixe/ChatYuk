// String khusus ADMIN — JANGAN di-import dari kode build rilis.
// Extension on S: karena hanya modul admin yang meng-import file
// ini, tree shaker membuang seluruh string bersama layar admin.
import 'strings.dart';
import '../core/admin_err.dart';

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
  String get adminDeviceSearch =>
      isId ? 'Cari user/device...' : 'Search user/device...';
  String get adminDeviceNoData =>
      isId ? 'Belum ada device terdeteksi' : 'No devices detected yet';
  String get adminDeviceNoResult =>
      isId ? 'Tidak ada yang cocok' : 'No match found';
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
  String get adminDeviceLocation =>
      isId ? 'Riwayat Lokasi' : 'Location History';
  String get adminDeviceNoDevices =>
      isId ? 'Belum ada perangkat tercatat' : 'No devices recorded';
  String get adminDeviceNoChats => isId ? 'Belum ada chat' : 'No chats yet';
  String get adminDeviceCopyId => isId ? 'Salin' : 'Copy';
  String get adminDeviceCopied => isId ? 'Disalin' : 'Copied';
  String get adminDeviceUsersUsed =>
      isId ? 'User yang pernah login' : 'Users who logged in';
  String get adminDeviceNoUsers =>
      isId ? 'Belum ada user tercatat' : 'No users recorded';
  String get adminDeviceOpenUser =>
      isId ? 'Lihat detail user' : 'View user detail';
  String get adminDeviceCount => isId ? 'user' : 'user';
  String get adminDeviceByUser => isId ? 'Per User' : 'By User';
  String get adminDeviceByDevice => isId ? 'Per Device' : 'By Device';

  String get adminStorageTitle =>
      isId ? 'Penggunaan Data Supabase' : 'Supabase Data Usage';
  String get adminStorageDb => isId ? 'Database' : 'Database';
  String get adminStorageImages =>
      isId ? 'Gambar (chat & publik)' : 'Images (chat & public)';
  String get adminStorageFree => isId ? 'Tersedia' : 'Free';
  String get adminStorageTotal => isId ? 'Total Terpakai' : 'Total Used';
  String get adminStorageFiles => isId ? 'File gambar' : 'Image files';
  String get adminStorageGrowth => isId ? 'Pertumbuhan Data' : 'Data Growth';
  String get adminGrowthDay => isId ? 'Hari ini' : 'Today';
  String get adminGrowthWeek => isId ? '7 hari' : '7 days';
  String get adminGrowthMonth => isId ? '30 hari' : '30 days';
  String get adminGrowthMessages => isId ? 'Pesan' : 'Messages';
  String get adminGrowthSignals => isId ? 'Sinyal call' : 'Call signals';
  String get adminGrowthImages => isId ? 'Gambar' : 'Images';
  String get adminGrowthRegistrations => isId ? 'Registrasi' : 'Registrations';
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
  String get adminTableSizesTitle =>
      isId ? 'Rincian Ukuran Tabel' : 'Table Size Breakdown';
  String get adminTableSizesTapHint =>
      isId ? 'Ketuk untuk rincian tabel' : 'Tap for table breakdown';
  String get adminTableColTable => isId ? 'Tabel' : 'Table';
  String get adminTableColSize => isId ? 'Ukuran' : 'Size';
  String get adminTableColRows => isId ? 'Baris' : 'Rows';
  String get adminTableSizesEmpty =>
      isId ? 'Belum ada data ukuran' : 'No size data yet';

  String get adminDeletedTab => isId ? 'Terhapus' : 'Deleted';
  String get adminDeletedTitle => isId ? 'User Terhapus' : 'Deleted Users';
  String get adminDeletedSearch => isId
      ? 'Cari user terhapus / anon...'
      : 'Search deleted / anon users...';
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
  String get adminDeletedAdmin => isId ? 'Dihapus admin' : 'Deleted by admin';
  String get adminDeletedDummy => isId ? 'Dummy dihapus' : 'Dummy deleted';
  String get adminDeletedClaimedBy => isId ? 'Diambil oleh' : 'Claimed by';
  String get adminDeletedNewNick => isId ? 'Nickname baru' : 'New nickname';
  String get adminDeletedDeviceHistory =>
      isId ? 'Riwayat Device' : 'Device History';
  String get adminDeletedNoDevice =>
      isId ? 'Tidak ada device tercatat' : 'No devices recorded';
  String get adminDeletedUid => isId ? 'UID Asli' : 'Original UID';

  // ── Anon belum terhapus (pending) di tab Terhapus ──
  String get adminDeletedPending =>
      isId ? 'Belum dihapus (anon)' : 'Not deleted (anon)';
  String get adminDeletedPendingReason =>
      isId ? 'Anon aktif' : 'Active anon';
  String get adminDeletedStillUsed =>
      isId ? 'Nickname masih dipakai' : 'Nickname still in use';
  String get adminDeletedDeleteAction =>
      isId ? 'Hapus user ini' : 'Delete this user';
  String get adminDeletedDeleteTitle => isId
      ? 'Hapus user anon ini?'
      : 'Delete this anon user?';
  String get adminDeletedDeleteBody => isId
      ? 'Nickname akan bebas dipakai user lain. Tindakan ini tidak bisa dibatalkan.'
      : 'The nickname will become available for others. This cannot be undone.';
  String get adminDeletedDeleteDone =>
      isId ? 'User anon dihapus, nickname bebas' : 'Anon user deleted, nickname free';
  String get adminDeletedDeleteRegistered => isId
      ? 'Akun terdaftar tidak bisa dihapus dari sini'
      : 'Registered accounts cannot be deleted here';
  String get adminDeletedDeleteDummy =>
      isId ? 'Akun dummy — hapus dari tab Dummy' : 'Dummy account — delete from Dummy tab';
  String get adminDeletedDeleteFailed =>
      isId ? 'Gagal menghapus user' : 'Failed to delete user';
  String get adminDeletedFilterAll => isId ? 'Semua' : 'All';
  String get adminDeletedFilterDeleted => isId ? 'Terhapus' : 'Deleted';
  String get adminDeletedFilterPending => isId ? 'Belum dihapus' : 'Not deleted';
  String adminDeletedSelected(int n) => isId ? '$n dipilih' : '$n selected';
  String get adminDeletedSelectAll => isId ? 'Pilih Semua' : 'Select All';
  String adminDeletedBatchDeleteTitle(int n) =>
      isId ? 'Hapus $n user terpilih?' : 'Delete $n selected users?';
  String get adminDeletedBatchDeleteBody => isId
      ? 'User yang dipilih akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.'
      : 'Selected users will be permanently deleted. This cannot be undone.';
  String adminDeletedBatchDeleteDone(int n) =>
      isId ? '$n user berhasil dihapus' : '$n users successfully deleted';
  String get adminDeletedBatchDeleting =>
      isId ? 'Menghapus user...' : 'Deleting users...';

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
  String get privateRoomsJoinedBody => isId
      ? 'Kamu resmi jadi member room ini.'
      : 'You are now a member of this room.';
  String get roomHandRaised => isId
      ? 'Tangan diangkat — tunggu admin mengizinkan'
      : 'Hand raised — waiting for admin approval';
  String get privateRoomsLiveConnecting =>
      isId ? 'Menyambungkan...' : 'Connecting...';
  String get roomShowChat => isId ? 'Chat' : 'Chat';
  String get roomShowMembers => isId ? 'Anggota' : 'Members';

  String get privateRoomsScanHint => isId
      ? 'Arahkan kamera ke QR undangan room'
      : 'Point the camera at a room invite QR';
  String get privateRoomsShowQr => isId ? 'Kode QR Undangan' : 'Invite QR';
  String get privateRoomsMembersTitle => isId ? 'Anggota' : 'Members';
  String get privateRoomsPendingQueue =>
      isId ? 'Menunggu Persetujuan' : 'Pending Approvals';
  String get roomRoleOwner => isId ? 'Pemilik' : 'Owner';
  String get roomRoleAdmin => isId ? 'Admin' : 'Admin';
  String get roomRoleMember => isId ? 'Member' : 'Member';
  String get roomActionPromote => isId ? 'Jadikan admin' : 'Promote to admin';
  String get roomActionDemote =>
      isId ? 'Turunkan jadi member' : 'Demote to member';
  String get roomActionKick => isId ? 'Keluarkan' : 'Remove';
  String get roomActionBroadcast =>
      isId ? 'Izinkan Broadcast' : 'Allow Broadcast';
  String get roomActionRevokeBroadcast =>
      isId ? 'Batalkan Broadcast' : 'Revoke Broadcast';
  String get roomKickConfirmTitle =>
      isId ? 'Keluarkan dari room?' : 'Remove from room?';
  String get roomKickConfirmBody => isId
      ? 'User bisa request masuk lagi, tapi harus di-approve.'
      : 'They can request again but must be approved.';

  // ── Menu ⋮ grup ala WA ──
  String get menuAddMembers => isId ? 'Tambah anggota' : 'Add members';
  String get menuGroupInfo => isId ? 'Info grup' : 'Group info';
  String get menuGroupMedia => isId ? 'Media grup' : 'Group media';
  String get menuSearchMessages => isId ? 'Cari pesan' : 'Search messages';
  String get menuMuteNotif =>
      isId ? 'Bisukan notifikasi' : 'Mute notifications';
  String get menuUnmuteNotif =>
      isId ? 'Nyalakan notifikasi' : 'Unmute notifications';
  String get menuMore => isId ? 'Lainnya' : 'More';
  String get menuExitGroup => isId ? 'Keluar grup' : 'Exit group';
  String get menuDeleteGroup => isId ? 'Hapus grup' : 'Delete group';
  String get exitGroupTitle => isId ? 'Keluar dari grup?' : 'Exit this group?';
  String get exitGroupBody => isId
      ? 'Kamu tidak lagi menerima pesan dari grup ini.'
      : 'You will stop receiving messages from this group.';
  String get deleteGroupTitle =>
      isId ? 'Hapus grup ini?' : 'Delete this group?';
  String get deleteGroupBody => isId
      ? 'Grup dan semua pesannya hilang permanen untuk semua member.'
      : 'The group and all its messages are permanently gone for everyone.';
  String get groupInfoOwner => isId ? 'Pemilik' : 'Owner';
  String get groupInfoMembers => isId ? 'Anggota' : 'Members';
  String get groupInfoCreated => isId ? 'Dibuat' : 'Created';
  String get groupInfoExpiry => isId ? 'Berlaku sampai' : 'Valid until';
  String get groupInfoPermanent => isId ? 'Permanen' : 'Permanent';
  String get groupInfoExpired => isId ? 'Kedaluwarsa' : 'Expired';
  String get groupInfoToken => isId ? 'Token undangan' : 'Invite token';
  String get groupInfoTokenCopied => isId ? 'Token tersalin' : 'Token copied';
  String get groupMediaEmpty =>
      isId ? 'Belum ada foto di grup ini' : 'No photos in this group yet';
  String get roomSearchHint =>
      isId ? 'Cari di grup ini...' : 'Search in this group...';
  String get roomSearchEmpty =>
      isId ? 'Tidak ada pesan cocok' : 'No matching messages';
  String get roomMutedOn =>
      isId ? 'Notifikasi grup dibisukan' : 'Group notifications muted';
  String get roomMutedOff =>
      isId ? 'Notifikasi grup dinyalakan' : 'Group notifications on';

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

  String get adminCallTitle => isId ? 'Anon Bisa Call' : 'Anon Can Call';
  String get adminCallDesc => isId
      ? 'Saat aktif, tombol panggilan tampil untuk semua user dan user anon/belum daftar bisa menelepon. Saat mati, hanya user terdaftar (+ admin) yang bisa call (anti spam).'
      : 'When enabled, the call button appears for all users and anon/unregistered users can call. When off, only registered users (+ admin) can call (anti-spam).';

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

// ── Exclude Device (Pengaturan Global) ──────────────────────────────
extension SAdminExcludeX on S {
  String get adminExcludeTitle =>
      isId ? 'Exclude Perangkat' : 'Exclude Devices';

  String get adminExcludeSubtitle => isId
      ? 'Perangkat yang di-exclude tidak dihitung di ringkasan (users, aktif, anon) & disembunyikan dari daftar Perangkat'
      : 'Excluded devices are not counted in the summary (users, active, anon) & hidden from the Devices list';

  String get adminExcludeCount =>
      isId ? '%d perangkat ter-exclude' : '%d device(s) excluded';

  String get adminExcludeNone =>
      isId ? 'Belum ada perangkat yang di-exclude' : 'No devices excluded yet';

  String get adminExcludeAddHint =>
      isId ? 'Tempel Install ID...' : 'Paste Install ID...';

  String get adminExcludeAdd => isId ? 'Tambah' : 'Add';

  String get adminExcludeRemove => isId ? 'Hapus' : 'Remove';

  String get adminExcludeEmptyId =>
      isId ? 'Install ID tidak boleh kosong' : 'Install ID cannot be empty';

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

  String get adminExcludeConfirmRemove =>
      isId ? 'Hapus dari daftar exclude?' : 'Remove from exclusion list?';

  String get adminExcludeAddTitle =>
      isId ? 'Kelola Perangkat Ter-exclude' : 'Manage Excluded Devices';

  String get adminPointSettingsSaved =>
      isId ? 'Pengaturan poin tersimpan' : 'Point settings saved';

  String adminSaveFailed(String e) =>
      isId ? 'Gagal menyimpan: $e' : 'Failed to save: $e';

  String get adminShareLinkLabel => isId
      ? 'Link tujuan share (Google Play / apkpure)'
      : 'Share destination link (Google Play / apkpure)';

  // ── Popup update aplikasi ──
  String get adminUpdateTitle =>
      isId ? 'Popup Update Aplikasi' : 'App Update Popup';
  String get adminUpdateDesc => isId
      ? 'Tawarkan update saat app dibuka. Kosongkan versi terbaru untuk mematikan.'
      : 'Offer update on app open. Leave latest version empty to disable.';
  String get adminUpdateEnable =>
      isId ? 'Aktifkan popup update' : 'Enable update popup';
  String get adminUpdateLatest =>
      isId ? 'Versi terbaru (X.Y.Z)' : 'Latest version (X.Y.Z)';
  String get adminUpdateMin =>
      isId ? 'Versi minimum (wajib update)' : 'Minimum version (force update)';
  String get adminUpdateMinHint => isId
      ? 'User di bawah versi ini wajib update (tidak bisa ditutup).'
      : 'Users below this version must update (cannot be dismissed).';
  String get adminUpdateNotes =>
      isId ? 'Catatan rilis (Yang baru)' : 'Release notes (What\'s new)';
  String get adminUpdateSaved =>
      isId ? 'Konfigurasi update tersimpan' : 'Update config saved';

  // ── Pesan error ramah (offline) ──
  // Detail exception mentah TIDAK ditampilkan ke layar (bocorkan URL Supabase
  // + membingungkan). Kategori + teks di bawah ini yang tampil; detail asli
  // tetap ke dlog. Lihat lib/core/admin_err.dart.
  String get adminErrOffline =>
      isId ? 'Tidak ada koneksi internet' : 'No internet connection';
  String get adminErrOfflineHint => isId
      ? 'Menampilkan data terakhir yang tersimpan.'
      : 'Showing the last saved data.';
  String get adminErrUnauthorized =>
      isId ? 'Sesi admin tidak valid' : 'Admin session invalid';
  String get adminErrUnauthorizedHint => isId
      ? 'Masuk ulang sebagai admin untuk melanjutkan.'
      : 'Sign in again as admin to continue.';
  String get adminErrServer =>
      isId ? 'Server sedang bermasalah' : 'Server error';
  String get adminErrServerHint =>
      isId ? 'Coba lagi beberapa saat lagi.' : 'Please try again shortly.';
  String get adminErrUnknown => isId ? 'Gagal memuat data' : 'Failed to load data';
  String get adminErrStaleBanner =>
      isId ? 'Data terakhir — tidak ada koneksi' : 'Last data — offline';
  String get adminErrNoCache => isId
      ? 'Belum ada data tersimpan. Sambungkan internet lalu muat ulang.'
      : 'No saved data yet. Connect to the internet and reload.';
  String get adminNeedsConnection =>
      isId ? 'Butuh koneksi internet' : 'Needs internet connection';
  String get adminClearCache =>
      isId ? 'Bersihkan cache admin' : 'Clear admin cache';
  String get adminClearCacheDesc => isId
      ? 'Hapus data admin yang tersimpan di perangkat ini (statistik, daftar user/perangkat, pesan monitor). Berguna bila HP dipakai bergantian.'
      : 'Delete admin data saved on this device (stats, user/device lists, monitor messages). Useful when the device is shared.';
  String get adminClearCacheDone =>
      isId ? 'Cache admin dibersihkan' : 'Admin cache cleared';
  String get adminClearCacheConfirm => isId
      ? 'Hapus semua data admin yang tersimpan di perangkat ini?'
      : 'Delete all admin data saved on this device?';

  /// Judul pesan ramah untuk kategori kegagalan admin. Detail exception
  /// mentah tidak pernah ditampilkan (lihat lib/core/admin_err.dart).
  String adminErrTextOf(AdminErrKind k) => switch (k) {
    AdminErrKind.offline => adminErrOffline,
    AdminErrKind.unauthorized => adminErrUnauthorized,
    AdminErrKind.server => adminErrServer,
    AdminErrKind.unknown => adminErrUnknown,
  };

  /// Kalimat penjelas di bawah judul (kosong bila tidak perlu).
  String adminErrHintOf(AdminErrKind k) => switch (k) {
    AdminErrKind.offline => adminErrOfflineHint,
    AdminErrKind.unauthorized => adminErrUnauthorizedHint,
    AdminErrKind.server => adminErrServerHint,
    AdminErrKind.unknown => '',
  };
}
