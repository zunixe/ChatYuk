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

  String get adminContactEmpty =>
      isId ? 'Belum ada pesan kontak' : 'No contact messages yet';

  String get adminContactDeleteMsg =>
      isId ? 'Hapus pesan ini?' : 'Delete this message?';

  String get labelScreenshotAllow =>
      isId ? 'Izinkan screenshot aplikasi' : 'Allow app screenshots';

  String get descScreenshotAdmin => isId
      ? 'Admin — kontrol screenshot untuk semua pengguna'
      : 'Admin — control screenshots for all users';

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

  String get adminRegisteredOnly =>
      isId ? 'Hanya user registered' : 'Registered users only';

  String get adminStuckUsers =>
      isId ? 'user terjebak (0 poin)' : 'users stuck (0 points)';

  String get adminOverview => isId ? 'Ringkasan' : 'Overview';

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
