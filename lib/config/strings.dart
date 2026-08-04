// Semua string UI aplikasi dalam Bahasa Indonesia dan English.
// Untuk tambah bahasa baru: tambah getter baru di sini.
class S {
  final bool isId;
  // ignore: prefer_const_constructors_in_immutables
  S({required this.isId});

  // ── Entry Screen ──
  String get appTagline      => isId ? 'Chat Tanpa Registrasi'        : 'Chat Without Registration';
  String get appSubtagline   => isId ? 'Langsung ngobrol, tanpa ribet!' : 'Start chatting, no hassle!';
  String get labelUsername   => isId ? 'Username'                     : 'Username';
  String get hintNickname    => isId ? 'Pilih nickname kamu...'       : 'Choose your nickname...';
  String get labelAge        => isId ? 'Umur'                         : 'Age';
  String get labelCountry    => isId ? 'Negara'                       : 'Country';
  String get labelCity       => isId ? 'Kota'                         : 'City';
  String get labelGenderMale => isId ? 'Laki-laki'                    : 'Male';
  String get labelGenderFemale => isId ? 'Perempuan'                  : 'Female';
  String get btnStartChat    => isId ? 'MULAI CHAT SEKARANG'          : 'START CHATTING NOW';
  String get errNicknameEmpty => isId ? 'Masukkan nickname dulu'      : 'Please enter a nickname';
  String get errNicknameShort => isId ? 'Nickname minimal 3 karakter' : 'Nickname must be at least 3 characters';
  String get errNicknameLong  => isId ? 'Nickname maksimal 20 karakter' : 'Nickname must be at most 20 characters';

  // ── Navigation / Bottom Bar ──
  String get navRooms        => isId ? 'Rooms'                        : 'Rooms';
  String get navOnline       => isId ? 'Online'                       : 'Online';
  String get navChats        => isId ? 'Chat'                         : 'Chats';
  String get navProfile      => isId ? 'Profil'                       : 'Profile';

  // ── Lobby / Rooms ──
  String get titleRooms      => isId ? 'Pilih Room'                   : 'Choose a Room';
  String get roomOnlineCount => isId ? 'online'                       : 'online';
  String get noRooms         => isId ? 'Belum ada room tersedia'      : 'No rooms available';

  // ── Online Users ──
  String get titleOnline     => isId ? 'Pengguna Online'              : 'Online Users';
  String get filterAll       => isId ? 'Semua'                        : 'All';
  String get filterMale      => isId ? 'Laki-laki'                    : 'Male';
  String get filterFemale    => isId ? 'Perempuan'                    : 'Female';
  String get noOnlineUsers   => isId ? 'Tidak ada pengguna online'    : 'No users online';
  String get statusOnline    => isId ? 'Online'                       : 'Online';
  String get statusIdle      => isId ? 'Idle'                         : 'Idle';
  String get statusOffline   => isId ? 'Offline'                      : 'Offline';
  String get genderMale      => isId ? '🧑 Laki-laki'                  : '🧑 Male';
  String get genderFemale    => isId ? '👩 Perempuan'                  : '👩 Female';
  String get genderOther     => isId ? '🧑 Lainnya'                    : '🧑 Other';

  // ── Private Chats ──
  String get titlePrivateChat => isId ? 'Private Chat'                : 'Private Chat';
  String get noPrivateChats  => isId ? 'Belum ada private chat'       : 'No private chats yet';
  String get noPrivateChatsHint => isId ? 'Klik user di chat room untuk mulai' : 'Tap a user in a chat room to start';
  String get startConversation  => isId ? 'Mulai percakapan!'                   : 'Start the conversation!';
  String get noMessages      => isId ? 'Belum ada pesan'              : 'No messages yet';
  String get timeJustNow     => isId ? 'Baru'                         : 'Now';

  // ── Chat Screen (private & room) ──
  String get hintTypeMessage  => isId ? 'Ketik pesan...'              : 'Type a message...';
  String get errSendFailed    => isId ? 'Gagal kirim: '               : 'Send failed: ';
  String get errPhotoRead     => isId ? 'Gagal membaca gambar'        : 'Failed to read image';
  String get errSendPhoto     => isId ? 'Gagal kirim foto: '          : 'Failed to send photo: ';
  String get msgPhoto         => isId ? '[Foto]'                      : '[Photo]';
  String get msgBlocked       => isId ? 'User ini diblokir, tidak bisa kirim pesan' : 'This user is blocked, cannot send message';
  String get btnBlock         => isId ? 'Blokir'                      : 'Block';
  String get btnReport        => isId ? 'Laporkan'                    : 'Report';
  String get btnUnblock       => isId ? 'Buka Blokir'                 : 'Unblock';
  String get labelOnlineUsers => isId ? 'Online'                      : 'Online';
  String get reportTitle      => isId ? 'Laporkan Pengguna'           : 'Report User';
  String get reportHint       => isId ? 'Alasan laporan...'           : 'Reason for report...';
  String get reportBtn        => isId ? 'Kirim Laporan'               : 'Submit Report';
  String get reportSuccess    => isId ? 'Laporan terkirim'            : 'Report submitted';
  String get blockSuccess     => isId ? 'Pengguna diblokir'           : 'User blocked';
  String get unblockSuccess   => isId ? 'Blokir dibuka'               : 'User unblocked';

  // ── Profile ──
  String get titleProfile     => isId ? 'Profil'                      : 'Profile';
  String get btnChangePhoto   => isId ? 'Ganti Foto Profil'           : 'Change Profile Photo';
  String get btnAddPhoto      => isId ? 'Tambah Foto Profil'          : 'Add Profile Photo';
  String get labelStatus      => isId ? 'Status'                      : 'Status';
  String get labelUserId      => isId ? 'User ID'                     : 'User ID';
  String get labelYears       => isId ? 'tahun'                       : 'years';
  String get btnLogout        => isId ? 'Keluar'                      : 'Logout';
  String get genderLabelMale  => isId ? '👨 Laki-laki'                 : '👨 Male';
  String get genderLabelFemale => isId ? '👩 Perempuan'                : '👩 Female';
  String get genderLabelOther => isId ? '🧑 Lainnya'                   : '🧑 Other';

  // ── Avatar Options ──
  String get avatarCamera     => isId ? 'Ambil Foto'                  : 'Take Photo';
  String get avatarGallery    => isId ? 'Dari Galeri'                 : 'From Gallery';
  String get avatarDelete     => isId ? 'Hapus Foto'                  : 'Remove Photo';
  String get errPhotoSave     => isId ? 'Gagal simpan foto: '         : 'Failed to save photo: ';
  String get errPhotoLoad     => isId ? 'Gagal membaca gambar'        : 'Failed to read image';
  String get msgPhotoExpired  => isId ? '⏰ Foto sudah expired'        : '⏰ Photo expired';

  // ── Settings ──
  String get titleSettings    => isId ? 'Pengaturan'                  : 'Settings';
  String get labelLanguage    => isId ? 'Bahasa / Language'           : 'Language / Bahasa';
  String get langId           => isId ? '🇮🇩  Indonesia'               : '🇮🇩  Indonesia';
  String get langEn           => isId ? '🇬🇧  English'                 : '🇬🇧  English';

  // ── Notifications ──
  String get notifChannelName => isId ? 'Notifikasi Chat'             : 'Chat Notifications';
  String get notifChannelDesc => isId ? 'Notifikasi pesan baru dari chat' : 'New message notifications from chat';
  String get notifNewMessage  => isId ? 'Pesan baru'                  : 'New message';
  String get notifNewMessageBody => isId ? 'Pesan baru masuk'         : 'You have a new message';

  // ── Errors / Generic ──
  String get errGeneric       => isId ? 'Gagal: '                     : 'Failed: ';
  String get loading          => isId ? 'Memuat...'                   : 'Loading...';
  String get unknownUser      => isId ? 'Pengguna'                    : 'User';
}
