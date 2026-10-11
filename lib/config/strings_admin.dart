// String khusus ADMIN — JANGAN di-import dari kode build rilis.
// Extension on S: karena hanya modul admin yang meng-import file
// ini, tree shaker membuang seluruh string bersama layar admin.
import 'strings.dart';
import '../core/admin_err.dart';

part 'strings_admin_b.dart';

extension SAdminX on S {
  String get adminCallLive => isId ? 'Call aktif' : 'Live call';

  String get adminCallRinging => isId ? 'Memanggil...' : 'Ringing...';

  /// Arah panggilan saat masih ringing — bedakan pemanggil vs penerima
  /// supaya admin tahu siapa yang menunggu dijawab.
  String get adminCallerCalling => isId ? 'Menelepon' : 'Calling';

  String get adminCalleeRinging => isId ? 'Berdering' : 'Ringing';

  String get adminWatching => isId ? 'Memantau' : 'Monitoring';

  String get adminListening => isId ? 'Mendengarkan...' : 'Listening...';

  String get adminWaitingVideo =>
      isId ? 'Menunggu video...' : 'Waiting for video...';

  String get adminCameraOff => isId ? 'Kamera mati' : 'Camera off';

  String get adminMicOff => isId ? 'Mikrofon mati' : 'Mic muted';

  String get adminSwapView => isId ? 'Tukar tampilan' : 'Swap view';

  String get adminWatchConnecting =>
      isId ? 'Menyambungkan...' : 'Connecting...';

  String get adminSpeakerFallback => isId
      ? 'Audio mode telepon (speaker gagal)'
      : 'Phone audio mode (speaker failed)';

  /// Banner di monitor admin: pesan ini sudah dihapus pengirim (isi tetap
  /// ditampilkan sebagai bukti/verifikasi laporan).
  String get adminDeletedMarker =>
      isId ? 'Dihapus oleh pengirim' : 'Deleted by sender';
  String get adminContactTab => isId ? 'Kontak' : 'Contact';

  // ── Monitor Grup (private rooms user) ──
  String get adminRoomMonitor => isId ? 'Monitor Grup' : 'Group Monitor';
  String get adminRoomSearch =>
      isId ? 'Cari grup / pemilik...' : 'Search group / owner...';
  String get adminRoomCountryAll => isId ? 'Semua negara' : 'All countries';
  String get adminRoomNoData =>
      isId ? 'Belum ada grup dibuat user' : 'No user-created groups yet';
  String get adminRoomNoResult =>
      isId ? 'Tidak ada grup cocok' : 'No matching groups';
  String get adminRoomMembers => isId ? 'Anggota' : 'Members';
  String get adminRoomMessages => isId ? 'Pesan' : 'Messages';
  String get adminRoomOwner => isId ? 'Pemilik' : 'Owner';
  String get adminRoomLocked => isId ? 'Pakai sandi' : 'Password';
  String get adminRoomExpired => isId ? 'Kadaluarsa' : 'Expired';
  String get adminRoomActive => isId ? 'Aktif' : 'Active';
  String get adminRoomEmptyChat =>
      isId ? 'Belum ada pesan di grup ini' : 'No messages in this group yet';
  String get adminRoomMemberOwner => isId ? 'Pemilik' : 'Owner';
  String get adminRoomLoadingMembers =>
      isId ? 'Memuat anggota...' : 'Loading members...';
  String get adminRoomDelete => isId ? 'Hapus grup' : 'Delete group';
  String get adminRoomDeleteTitle =>
      isId ? 'Hapus grup ini?' : 'Delete this group?';
  String get adminRoomDeleteBody => isId
      ? 'Semua pesan & anggota grup ini ikut terhapus permanen. Tindakan ini tidak bisa dibatalkan.'
      : 'All messages & members of this group are permanently deleted. This cannot be undone.';
  String get adminRoomDeleted =>
      isId ? 'Grup dihapus' : 'Group deleted';
  String get adminRoomDeleteFailed =>
      isId ? 'Gagal menghapus grup' : 'Failed to delete group';

  String get adminDeviceTab => isId ? 'Perangkat' : 'Devices';
  String get adminDeviceTitle => isId ? 'Perangkat' : 'Devices';
  String get adminDeviceSearch =>
      isId ? 'Cari user/device...' : 'Search user/device...';
  String get adminDeviceNoData =>
      isId ? 'Belum ada device terdeteksi' : 'No devices detected yet';
  String get adminDeviceNoResult =>
      isId ? 'Tidak ada yang cocok' : 'No match found';
  String get adminDeviceNoDevice =>
      isId ? 'Tanpa perangkat terdeteksi' : 'No device detected';
  String get adminDeviceActive => isId ? 'aktif' : 'active';
  String get adminDeviceInactive => isId ? 'lama' : 'inactive';
  String get adminDeviceModel => isId ? 'Device' : 'Device';
  String get adminDeviceOs => isId ? 'OS' : 'OS';
  String get adminDeviceLastSeen => isId ? 'Terakhir aktif' : 'Last seen';
  String get adminDeviceInstallId => isId ? 'Device ID' : 'Device ID';
  String get adminDeviceId => isId ? 'Device ID' : 'Device ID';
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
  String get adminMapViewRoute => isId ? 'Lihat Peta' : 'View Map';
  String get adminMapRouteTitle => isId ? 'Peta Pergerakan' : 'Movement Map';
  String get adminMapStart => isId ? 'Awal' : 'Start';
  String get adminMapEnd => isId ? 'Akhir' : 'End';
  String adminMapPoints(int n) => isId ? '$n titik' : '$n points';
  String get adminMapSatellite => isId ? 'Satelit' : 'Satellite';
  String get adminMapStreets => isId ? 'Peta' : 'Map';
  String get adminMapOpenGoogle => isId ? 'Buka di Google Maps' : 'Open in Google Maps';
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
  String get adminRegSortNewest => isId ? 'Baru daftar' : 'Newest first';
  String get adminRegSortOldest => isId ? 'Lama daftar' : 'Oldest first';
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
  String get adminStorageError => isId
      ? 'Gagal memuat penggunaan data — periksa koneksi lalu coba lagi'
      : 'Failed to load data usage — check connection and retry';
  String get adminRetry => isId ? 'Coba lagi' : 'Retry';
  String get adminStorageBandwidth => isId ? 'Bandwidth (egress)' : 'Bandwidth (egress)';
  String get adminBandwidthHint => isId
      ? 'Pemakaian live hanya terlihat di dashboard Supabase → Usage'
      : 'Live usage is only visible in the Supabase dashboard → Usage';

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
  String get adminDeletedLocationHistory =>
      isId ? 'Riwayat GPS' : 'GPS History';
  String get adminDeletedNoLocation =>
      isId ? 'Tidak ada riwayat GPS tercatat' : 'No GPS history recorded';
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
  // Ganti ikon/avatar grup (owner & admin).
  String get groupChangeIcon => isId ? 'Ganti ikon grup' : 'Change group icon';
  String get groupIconCamera => isId ? 'Kamera' : 'Camera';
  String get groupIconGallery => isId ? 'Galeri' : 'Gallery';
  String get groupIconUpdated => isId ? 'Ikon grup diperbarui' : 'Group icon updated';
  String get groupIconFailed => isId ? 'Gagal memperbarui ikon' : 'Failed to update icon';  String get groupInfoMembers => isId ? 'Anggota' : 'Members';
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
      isId ? 'Pengaturan Tarif YukCoin' : 'YukCoin Pricing Settings';

  String get adminShareLinkHint => isId
      ? 'Klik link share user → redirect ke link ini (Google Play).'
      : 'User share link click → redirects to this link (Google Play).';

  String get adminYukcoinV2 => isId
      ? 'YukCoin v2 (fitur koin generik)'
      : 'YukCoin v2 (generic coin features)';

  String get adminSavePointSettings =>
      isId ? 'Simpan Pengaturan' : 'Save Settings';

  String get adminViewOnMaps => isId ? 'Lihat di Maps' : 'View on Maps';

  String get adminTopEarners =>
      isId ? 'Saldo YukCoin Tertinggi' : 'Top YukCoin Balances';

  /// Ringkasan kartu statistik YukCoin (rata-rata & total saldo).
  String get adminAvgBalance =>
      isId ? 'Rata-rata YukCoin' : 'Avg YukCoin';
  String get adminTotalBalance =>
      isId ? 'Total YukCoin' : 'Total YukCoin';
  String adminCoinAmount(int n) => isId ? '$n koin' : '$n coins';

  String get adminMassBonus => isId ? 'Bonus Massal YukCoin' : 'Mass YukCoin Bonus';

  String get adminForceLogout => isId ? 'Force Logout' : 'Force Logout';

  // ── Toast hasil aksi panel (bilingual, bukan hardcode) ──
  String adminForceLogoutDone(String uid8) =>
      isId ? 'Force logout: $uid8…' : 'Force logout: $uid8…';

  String adminMassBonusDone(int amount, int users) => isId
      ? '+$amount → $users user'
      : '+$amount → $users users';

  String adminResetDone(int users) =>
      isId ? '$users user di-reset' : '$users users reset';

  String get adminFeaturePublished =>
      isId ? 'Fitur dipublish ke semua user' : 'Feature published to all users';

  String get adminFeatureHidden =>
      isId ? 'Fitur disembunyikan' : 'Feature hidden';

  // ── Label fitur yang bisa dipublish (Publish Fitur) ──
  String get adminFlagCallBilling =>
      isId ? 'Call berbayar (per menit)' : 'Paid calls (per minute)';
  String get adminFlagGenderFilter =>
      isId ? 'Filter gender (harian)' : 'Gender filter (daily)';
  String get adminFlagNearby =>
      isId ? 'Orang sekitar (harian)' : 'Nearby people (daily)';
  String get adminFlagPlayTopup =>
      isId ? 'Topup YukCoin (Play Billing)' : 'YukCoin topup (Play Billing)';

  String get adminPublishTitle => isId ? 'Publish Fitur' : 'Publish Features';
  String get adminPublishDesc => isId
      ? 'Fitur baru tampil ke user HANYA setelah dipublish. Sebelum itu hanya akun admin yang bisa memakai (uji di build adminProd).'
      : 'New features appear to users ONLY after publishing. Until then only admin accounts can use them (test in the adminProd build).';

  String get adminYukcoinV2On => isId
      ? 'Aktif · fitur undo / edit / invisible / slot foto tampil ke user'
      : 'Active · undo / edit / invisible / photo-slot features shown to users';
  String get adminYukcoinV2Off => isId
      ? 'Nonaktif · fitur koin generik disembunyikan dari user'
      : 'Inactive · generic coin features hidden from users';

  String get adminPointsSystem => isId ? 'Sistem YukCoin' : 'YukCoin System';

  String get adminReports => isId ? 'Laporan' : 'Reports';

  String get adminNoReports => isId ? 'Tidak ada laporan' : 'No reports';

  String get adminReportedBy => isId ? 'Dilaporkan oleh' : 'Reported by';

  // ── Privasi (kartu Ringkasan) ──
  String get adminPrivacyTitle => isId ? 'Privasi' : 'Privacy';
  String get adminPrivacyEmpty =>
      isId ? 'Tidak ada user pakai privasi' : 'No users use privacy';
  String get adminPrivacyUsers => isId ? 'user' : 'users';
  // Label field privasi.
  String get privPresence => isId ? 'Status online' : 'Online status';
  String get privLastSeen => isId ? 'Terakhir dilihat' : 'Last seen';
  String get privPhoto => isId ? 'Foto profil' : 'Profile photo';
  String get privAbout => isId ? 'Tentang' : 'About';
  String get privStory => isId ? 'Story' : 'Story';
  String get privLeaderboard => isId ? 'Top Aktif' : 'Top Active';
  // Nilai privasi.
  String get privEveryone => isId ? 'Semua' : 'Everyone';
  String get privFriends => isId ? 'Teman' : 'Friends';
  String get privNobody => isId ? 'Sembunyikan' : 'Hidden';
  String get privEveryoneExcept => isId ? 'Semua kecuali' : 'Everyone except';
  String get privFriendsExcept => isId ? 'Teman kecuali' : 'Friends except';
  String get privOnly => isId ? 'Hanya tertentu' : 'Only selected';

  String get adminDangerZone => isId ? 'Zona Bahaya' : 'Danger Zone';

  String get adminResetAllPoints => isId
      ? 'Reset saldo semua user ke 50 YukCoin'
      : 'Reset all users to 50 YukCoin';

  String get adminResetAllTitle => isId
      ? 'Reset Semua Saldo YukCoin?'
      : 'Reset All YukCoin Balances?';

  String get adminResetAllBody => isId
      ? 'Semua user akan memiliki 50 YukCoin.'
      : 'All users will have 50 YukCoin.';

  String get adminWipeAll => isId ? 'Reset Semua' : 'Wipe All';

  String get adminReset => isId ? 'Reset' : 'Reset';

  String get adminLogout => isId ? 'Keluar' : 'Logout';

  String get adminRunning => isId ? 'Berjalan' : 'Running';

  String get adminPaused => isId ? 'Dihentikan' : 'Paused';

  String get adminRealtimeDesc => isId
      ? 'Saklar utama seluruh ekonomi koin (topup, gift, room, foto). '
      'Fitur generik (undo/edit/invisible/slot) diatur di kartu tarif.'
      : 'Master switch for the whole coin economy (topup, gift, room, photo). '
      'Generic features (undo/edit/invisible/slots) are set in the pricing card.';

  String get adminCallTitle => isId ? 'Anon Bisa Call' : 'Anon Can Call';
  String get adminCallDesc => isId
      ? 'Saat aktif, tombol panggilan tampil untuk semua user dan user anon/belum daftar bisa menelepon. Saat mati, hanya user terdaftar (+ admin) yang bisa call (anti spam).'
      : 'When enabled, the call button appears for all users and anon/unregistered users can call. When off, only registered users (+ admin) can call (anti-spam).';

  String get adminRegisteredOnly =>
      isId ? 'Hanya user registered' : 'Registered users only';

  String get adminStuckUsers => isId
      ? 'user terdaftar saldo 0 (7 hari)'
      : 'registered users with 0 balance (7d)';

  String get adminOverview => isId ? 'Ringkasan' : 'Overview';

  String get adminGlobalSettingTab =>
      isId ? 'Pengaturan Global' : 'Global Setting';

  // ── Sebaran geografis (Ringkasan) ──
  String get adminGeoTitle => isId ? 'Sebaran Negara' : 'Country Breakdown';
  String get adminGeoSubtitle =>
      isId ? 'Ketuk negara untuk lihat kota' : 'Tap a country to see cities';
  String get adminGeoEmpty =>
      isId ? 'Tidak ada data lokasi user' : 'No user location data';
  String get adminGeoLoading =>
      isId ? 'Memuat sebaran…' : 'Loading breakdown…';
  String get adminGeoUserSuffix => isId ? 'user' : 'users';
  String get adminGeoUnknown =>
      isId ? 'Tidak diketahui' : 'Unknown';
  String adminGeoCityTitle(String country) =>
      isId ? 'Kota di $country' : 'Cities in $country';
  String get adminGeoRegisteredSuffix =>
      isId ? 'terdaftar' : 'registered';
  String get adminGeoClose => isId ? 'Tutup' : 'Close';

  String get adminRegTitle => isId ? 'Registrasi Email' : 'Email Registrations';

  String get adminRegPerDay => isId ? 'Per hari' : 'Per day';

  String get adminRegTotal => isId ? 'Total' : 'Total';

  String get adminRegEmpty =>
      isId ? 'Tidak ada pendaftaran bulan ini' : 'No registrations this month';

  // ── Insight registrasi (KPI CEO) ──
  String get adminRegKpiTotal =>
      isId ? 'Terdaftar' : 'Registered';
  String get adminRegKpiNewMonth =>
      isId ? 'Baru bulan ini' : 'New this month';
  String get adminRegKpiToday => isId ? 'Hari ini' : 'Today';
  String get adminRegKpiAvgDay =>
      isId ? 'Rata-rata/hari' : 'Avg/day';
  String get adminRegKpiConversion =>
      isId ? 'Konversi anon' : 'Anon conversion';
  String get adminRegKpiActiveToday =>
      isId ? 'Aktif hari ini' : 'Active today';
  String get adminRegKpiBestDay => isId ? 'Hari terbaik' : 'Best day';
  String get adminRegTrendTitle =>
      isId ? 'Tren 12 bulan' : '12-month trend';
  String get adminRegTrendLoading =>
      isId ? 'Memuat tren…' : 'Loading trend…';
  String get adminRegDailyTitle =>
      isId ? 'Harian (bulan terpilih)' : 'Daily (selected month)';
  String get adminRegVsPrevMonth => isId ? 'vs bulan lalu' : 'vs last month';
  String get adminRegInsightError => isId
      ? 'Gagal memuat insight registrasi'
      : 'Failed to load registration insight';
  String get adminRegListTitleShort => isId ? 'Lihat daftar' : 'View list';
  String get adminRegKpiAnonSuffix => isId ? 'anon' : 'anon';
  String get adminRegKpiAvgDayShort => isId ? 'rata²' : 'avg';
  String get adminRegUsersSuffix => isId ? 'user' : 'users';
  String get adminRegTotalUsersSuffix => isId ? 'user (12 bln)' : 'users (12mo)';
  String get adminRegGenderTitle =>
      isId ? 'Gender (terdaftar)' : 'Gender (registered)';
  String get adminRegGenderMale => isId ? 'Laki-laki' : 'Male';
  String get adminRegGenderFemale => isId ? 'Perempuan' : 'Female';
  String get adminRegGenderOther => isId ? 'Lainnya' : 'Other';

  String get adminPointTab => isId ? 'Poin' : 'Points';

  String get adminChatMonitor => isId ? 'Monitor Chat' : 'Chat Monitor';
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
  String get adminUpdatePushBtn =>
      isId ? 'Kirim Popup Update' : 'Push Update Popup';
  String get adminUpdatePushDesc => isId
      ? 'Paksa popup update muncul di aplikasi user saat mereka membuka app — walau sebelumnya sudah menekan "Nanti".'
      : 'Force the update popup to appear in user apps when they open the app — even if they tapped "Later" before.';
  String get adminUpdatePushConfirmTitle =>
      isId ? 'Kirim popup update?' : 'Push update popup?';
  String get adminUpdatePushConfirmBody => isId
      ? 'Semua user akan melihat popup update saat membuka aplikasi. Pastikan versi terbaru sudah benar.'
      : 'All users will see the update popup when they open the app. Make sure the latest version is correct.';
  String get adminUpdatePushDone =>
      isId ? 'Popup update dikirim' : 'Update popup pushed';
  String get adminUpdatePushNever =>
      isId ? 'Belum pernah dikirim' : 'Never pushed';
  String get adminUpdatePushLastAt =>
      isId ? 'Terakhir dikirim' : 'Last pushed';

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

  // ── Tab Atribusi (sumber user: FB/IG/Google/TikTok/referral/organik) ──
  String get adminAttributionTab => isId ? 'Atribusi' : 'Attribution';
  String get adminAttrSubtitle => isId
      ? 'Asal user: iklan atau kanal mana yang membawa mereka install.'
      : 'Where users came from: which ad or channel drove their install.';
  String get adminAttrTotalInstalls =>
      isId ? 'Total install' : 'Total installs';
  String get adminAttrUsers => isId ? 'user' : 'users';
  String get adminAttrEmpty => isId
      ? 'Belum ada data atribusi. Data terkumpul dari instal baru setelah fitur ini aktif.'
      : 'No attribution data yet. Data is collected from new installs after this feature went live.';
  String get adminAttrNoResult =>
      isId ? 'Tidak ada user di kanal ini' : 'No users in this channel';
  String get adminAttrLast7 => isId ? '7 hari' : '7 days';
  String get adminAttrLast30 => isId ? '30 hari' : '30 days';
  String get adminAttrAll => isId ? 'Semua' : 'All';
  String get adminAttrCampaigns => isId ? 'Kampanye' : 'Campaigns';
  String get adminAttrNoCampaign =>
      isId ? 'Tanpa kampanye' : 'No campaign';
  String get adminAttrUsersBySource =>
      isId ? 'User per kanal' : 'Users by channel';
  String get adminAttrLinkHint => isId
      ? 'Menampilkan link/referrer yang membawa user install (dari Play Install Referrer).'
      : 'Shows the link/referrer that brought the user to install (from Play Install Referrer).';

  // ── Kartu Ringkasan: tipe akun (pie) + versi aplikasi ──
  String get adminAppStatsTitle =>
      isId ? 'Tipe Akun & Versi Aplikasi' : 'Account Type & App Version';
  String get adminAppStatsUsers => isId ? 'user' : 'users';
  String get adminAppStatsReg => isId ? 'Terdaftar (email)' : 'Registered (email)';
  String get adminAppStatsAnon => isId ? 'Anonim (guest)' : 'Anonymous (guest)';
  String get adminAppStatsDevices => isId ? 'device' : 'devices';
  String get adminAppVersionAvg =>
      isId ? 'Rata-rata versi aplikasi' : 'Average app version';
  String get adminAppVersionEmpty =>
      isId ? 'Belum ada data versi.' : 'No version data yet.';
  String get adminAttrViewUsers => isId ? 'Lihat user' : 'View users';
  String get adminAttrSourceLabel => isId ? 'Kanal' : 'Channel';
  String get adminAttrCampaignLabel => isId ? 'Kampanye' : 'Campaign';
  String get adminAttrWhen => isId ? 'Saat install' : 'Installed at';
  // Nama kanal (untuk badge) — sengaja sama di kedua bahasa (nama brand).
  String get adminAttrFacebook => 'Facebook';
  String get adminAttrInstagram => 'Instagram';
  String get adminAttrGoogle => 'Google';
  String get adminAttrTiktok => 'TikTok';
  String get adminAttrReferral => isId ? 'Referral (share)' : 'Referral (share)';
  String get adminAttrOrganic => isId ? 'Organik' : 'Organic';
  String get adminAttrUnknown => isId ? 'Tidak diketahui' : 'Unknown';

  /// Label tampilan ramah untuk key sumber dari server.
  String adminAttrSourceName(String key) => switch (key) {
    'facebook' => adminAttrFacebook,
    'instagram' => adminAttrInstagram,
    'google' => adminAttrGoogle,
    'tiktok' => adminAttrTiktok,
    'referral' => adminAttrReferral,
    'organic' => adminAttrOrganic,
    _ => adminAttrUnknown,
  };

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

  // ── Tab Timeline (kelola SEMUA post: lihat lintas user + ubah visibilitas) ──
  String get adminTimelineTab => isId ? 'Timeline' : 'Timeline';
  String get adminTimelineSubtitle => isId
      ? 'Semua postingan user (public & non-public). Ubah visibilitas.'
      : 'All user posts (public & non-public). Change visibility.';
  String get adminTimelineFilterAll => isId ? 'Semua' : 'All';
  String get adminTimelineFilterPublic => isId ? 'Public' : 'Public';
  String get adminTimelineFilterFollowers => isId ? 'Pengikut' : 'Followers';
  String get adminTimelineFilterSubscribers => isId ? 'Subscriber' : 'Subscribers';
  String get adminTimelineEmpty => isId ? 'Belum ada postingan' : 'No posts yet';
  String get adminTimelineVisibilityUpdated =>
      isId ? 'Visibilitas diperbarui' : 'Visibility updated';
  String get adminTimelineSetVisibility =>
      isId ? 'Ubah visibilitas' : 'Change visibility';
  /// Label state visibilitas post (public/followers/subscribers).
  String adminTimelineVisLabel(String state) {
    switch (state) {
      case 'followers':
        return isId ? 'Pengikut' : 'Followers';
      case 'subscribers':
        return isId ? 'Subscriber' : 'Subscribers';
      default:
        return isId ? 'Public' : 'Public';
    }
  }

  // ── Tab Story (kelola story user: lihat semua, atur visibilitas, hapus) ──
  String get adminStoryTab => isId ? 'Story' : 'Stories';  String get adminStorySubtitle => isId
      ? 'Semua story user. Atur visibilitas atau hapus.'
      : 'All user stories. Set visibility or delete.';
  String get adminStoryFilterAll => isId ? 'Semua' : 'All';
  String get adminStoryFilterPublic => isId ? 'Public' : 'Public';
  String get adminStoryFilterFollowers => isId ? 'Pengikut' : 'Followers';
  String get adminStoryFilterFriends => isId ? 'Teman' : 'Friends';
  String get adminStoryFilterPrivate => isId ? 'Private' : 'Private';
  String get adminStoryEmpty => isId ? 'Belum ada story' : 'No stories yet';
  String get adminStoryVisibleTo => isId ? 'Terlihat oleh' : 'Visible to';
  /// Keterangan siapa yang bisa lihat (per state).
  String adminStoryVisibleFor(String state) {
    switch (state) {
      case 'private':
        return isId
            ? 'Hanya pembuat & admin'
            : 'Owner & admin only';
      case 'friends':
        return isId ? 'Teman dua arah saja' : 'Mutual friends only';
      case 'followers':
        return isId ? 'Pengikut saja' : 'Followers only';
      default:
        return isId ? 'Semua orang' : 'Everyone';
    }
  }
  String get adminStorySetVisibility =>
      isId ? 'Atur visibilitas' : 'Set visibility';
  String get adminStoryDelete => isId ? 'Hapus permanen' : 'Delete permanently';
  String get adminStoryDeleteConfirmTitle =>
      isId ? 'Hapus story ini?' : 'Delete this story?';
  String get adminStoryDeleteConfirmMsg => isId
      ? 'Story akan dihapus PERMANEN dari server & storage. Tindakan ini tidak bisa dibatalkan.'
      : 'This story will be PERMANENTLY deleted from server & storage. This cannot be undone.';
  String get adminStoryDeleted => isId ? 'Story dihapus' : 'Story deleted';
  String get adminStoryDeleteFail =>
      isId ? 'Gagal menghapus story' : 'Failed to delete story';
  String get adminStoryVisibilitySaved =>
      isId ? 'Visibilitas diperbarui' : 'Visibility updated';
  String get adminStoryVisibilityFail =>
      isId ? 'Gagal mengubah visibilitas' : 'Failed to update visibility';
  String get adminStoryToggle => isId ? 'Ubah' : 'Change';

  // ── Email Marketing ──────────────────────────────────────────
  String get adminMarketingTab => isId ? 'Marketing' : 'Marketing';
  String get adminMktNewCampaign => isId ? 'Buat Campaign' : 'New Campaign';
  String get adminMktEmpty =>
      isId ? 'Belum ada campaign email' : 'No email campaigns yet';
  String get adminMktCampaignName => isId ? 'Nama campaign' : 'Campaign name';
  String get adminMktSubject => isId ? 'Subjek email' : 'Email subject';
  String get adminMktBody => isId ? 'Isi email' : 'Email body';
  String get adminMktSegment => isId ? 'Penerima' : 'Recipients';
  String get adminMktSegmentAll =>
      isId ? 'Semua user terdaftar' : 'All registered users';
  String get adminMktSegmentActive30 =>
      isId ? 'Aktif 30 hari terakhir' : 'Active last 30 days';
  String get adminMktRecipients => isId ? 'penerima' : 'recipients';
  String get adminMktSaveDraft => isId ? 'Simpan draft' : 'Save draft';
  String get adminMktSend => isId ? 'Kirim' : 'Send';
  String get adminMktSendConfirmTitle =>
      isId ? 'Kirim campaign ini?' : 'Send this campaign?';
  String adminMktSendConfirmMsg(int n) => isId
      ? 'Email akan dikirim ke $n penerima. Lanjutkan?'
      : 'Email will be sent to $n recipients. Continue?';
  String get adminMktSentQueue =>
      isId ? 'Dijadwalkan terkirim' : 'Queued for sending';
  String get adminMktSendFail => isId ? 'Gagal mengirim' : 'Failed to send';
  String get adminMktSaved => isId ? 'Tersimpan' : 'Saved';
  String get adminMktSaveFail => isId ? 'Gagal menyimpan' : 'Failed to save';
  String get adminMktDeleted => isId ? 'Campaign dihapus' : 'Campaign deleted';
  String get adminMktDeleteConfirm =>
      isId ? 'Hapus campaign ini?' : 'Delete this campaign?';
  String get adminMktPreview => isId ? 'Pratinjau' : 'Preview';
  String get adminMktTestSend => isId ? 'Kirim tes' : 'Send test';
  String get adminMktTestHint =>
      isId ? 'Email tes dikirim ke email Anda sendiri' : 'Test email is sent to your own address';
  String get adminMktConfirmSendTitle => isId ? 'Kirim' : 'Send';
  String get adminMktStatusDraft => isId ? 'Draft' : 'Draft';
  String get adminMktStatusQueued => isId ? 'Menunggu' : 'Queued';
  String get adminMktStatusSending => isId ? 'Mengirim' : 'Sending';
  String get adminMktStatusSent => isId ? 'Terkirim' : 'Sent';
  String get adminMktStatusFailed => isId ? 'Gagal' : 'Failed';
  String get adminMktStatSent => isId ? 'Terkirim' : 'Sent';
  String get adminMktStatDelivered => isId ? 'Sampai' : 'Delivered';
  String get adminMktStatOpen => isId ? 'Dibuka' : 'Opened';
  String get adminMktStatClick => isId ? 'Diklik' : 'Clicked';
  String get adminMktStatBounce => isId ? 'Gagal kirim' : 'Bounced';
  String get adminMktStatUnsub => isId ? 'Berhenti langganan' : 'Unsubscribed';
  String get adminMktOpenRate => isId ? 'Rasio buka' : 'Open rate';
  String get adminMktClickRate => isId ? 'Rasio klik' : 'Click rate';
  String get adminMktRecipientList => isId ? 'Daftar penerima' : 'Recipients';
  String get adminMktBold => isId ? 'Tebal' : 'Bold';
  String get adminMktItalic => isId ? 'Miring' : 'Italic';
  String get adminMktUnderline => isId ? 'Garis bawah' : 'Underline';
  String get adminMktBulletList => isId ? 'Daftar' : 'Bullet list';
  String get adminMktNumberList => isId ? 'Daftar angka' : 'Numbered list';
  String get adminMktLink => isId ? 'Tautan' : 'Link';
  String get adminMktHeading => isId ? 'Judul' : 'Heading';
}

