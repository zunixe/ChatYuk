// Semua string UI aplikasi dalam Bahasa Indonesia dan English.
// Untuk tambah bahasa baru: tambah getter baru di sini.
class S {
  final bool isId;
  // ignore: prefer_const_constructors_in_immutables
  S({required this.isId});

  // ── Entry Screen ──
  String get appTagline      => isId ? 'Chat Bebas, Dimana Saja'       : 'Chat Freely, Anywhere';
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
  String get errNicknameInvalid => isId ? 'Nickname hanya boleh huruf, angka, spasi, _ atau -' : 'Nickname may only contain letters, numbers, spaces, _ or -';

  // ── Navigation / Bottom Bar ──
  String get navRooms        => isId ? 'Rooms'                        : 'Rooms';
  String get navOnline       => isId ? 'Online'                       : 'Online';
  String get navChats        => isId ? 'Chat'                         : 'Chats';
  String get navProfile      => isId ? 'Profil'                       : 'Profile';

  // ── Lobby / Rooms ──
  String get titleRooms      => isId ? 'Pilih Room'                   : 'Choose a Room';
  String get roomOnlineCount => isId ? 'online'                       : 'online';
  String get noRooms         => isId ? 'Belum ada room tersedia'      : 'No rooms available';

  /// Nama room berdasarkan id (fallback ke nama DB jika tidak ada translasi)
  String roomName(String id) {
    if (isId) return const {
      'general':    'General',
      'curhat':     'Curhat',
      'pertemanan': 'Pertemanan',
      'teknologi':  'Teknologi',
      'gaming':     'Gaming',
      'musik':      'Musik',
      'film':       'Film & TV',
      'joke':       'Joke & Meme',
      'belajar':    'Belajar',
      'flirt':      'Flirt',
    }[id] ?? id;
    return const {
      'general':    'General',
      'curhat':     'Confessions',
      'pertemanan': 'Friendship',
      'teknologi':  'Technology',
      'gaming':     'Gaming',
      'musik':      'Music',
      'film':       'Film & TV',
      'joke':       'Jokes & Memes',
      'belajar':    'Study',
      'flirt':      'Flirt',
    }[id] ?? id;
  }

  String roomDesc(String id) {
    if (isId) return const {
      'general':    'Obrolan umum untuk semua',
      'curhat':     'Cerita dan curhat bareng',
      'pertemanan': 'Cari temen baru di sini',
      'teknologi':  'Diskusi tech & gadget',
      'gaming':     'Main bareng & diskusi game',
      'musik':      'Sharing musik & lagu',
      'film':       'Rekomendasi & review film',
      'joke':       'Yang bikin ngakak',
      'belajar':    'Diskusi belajar & kuliah',
      'flirt':      'Ngobrol santai & asyik',
    }[id] ?? '';
    return const {
      'general':    'General chat for everyone',
      'curhat':     'Share your stories & feelings',
      'pertemanan': 'Find new friends here',
      'teknologi':  'Discuss tech & gadgets',
      'gaming':     'Play together & talk games',
      'musik':      'Share music & songs',
      'film':       'Movie & TV recommendations',
      'joke':       'All the funny stuff',
      'belajar':    'Study & college discussions',
      'flirt':      'Casual & fun conversations',
    }[id] ?? '';
  }

  // ── Online Users ──
  String get titleOnline     => isId ? 'Pengguna Online'              : 'Online Users';
  String get searchHint      => isId ? 'Cari nama pengguna...'        : 'Search username...';
  String get filterAll       => isId ? 'Semua'                        : 'All';
  String get filterMale      => isId ? 'Laki-laki'                    : 'Male';
  String get filterFemale    => isId ? 'Perempuan'                    : 'Female';
  String get noOnlineUsers   => isId ? 'Tidak ada pengguna online'    : 'No users online';
  String get searchNoResult   => isId ? 'Tidak ditemukan'               : 'No results found';
  String get statusOnline    => isId ? 'Online'                       : 'Online';
  String get statusIdle      => isId ? 'Idle'                         : 'Idle';
  String get statusOffline   => isId ? 'Offline'                      : 'Offline';
  String get genderMale      => isId ? '🧑 Laki-laki'                  : '🧑 Male';
  String get genderFemale    => isId ? '👩 Perempuan'                  : '👩 Female';
  String get genderOther     => isId ? '🧑 Lainnya'                    : '🧑 Other';
  String get labelRegistered => isId ? 'Terdaftar'                     : 'Registered';
  String get labelUnregistered => isId ? 'Tanpa daftar'                : 'Guest';

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
  String get msgViewOnce      => isId ? '[Foto Sekali Lihat]'          : '[View Once Photo]';
  String get viewOnceTap      => isId ? 'Tekan untuk melihat (10 detik)' : 'Tap to view (10 seconds)';
  String get viewOnceExpired  => isId ? 'Foto sudah kadaluarsa'        : 'Photo expired';
  String get viewOnceViewing  => isId ? 'Menutup dalam'                : 'Closing in';
  String get msgBlocked       => isId ? 'User ini diblokir, tidak bisa kirim pesan' : 'This user is blocked, cannot send message';
  String get msgBlockedByOther => isId ? 'Kamu diblokir oleh pengguna ini' : 'You have been blocked by this user';
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
  String get btnDeleteChat    => isId ? 'Hapus Chat'                  : 'Delete Chat';
  String get deleteChatSuccess => isId ? 'Chat dihapus'               : 'Chat deleted';
  String get deleteChatConfirm => isId ? 'Hapus percakapan ini? Pesan tidak bisa dipulihkan.' : 'Delete this conversation? Messages cannot be recovered.';

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
  String get btnEditProfile  => isId ? 'Edit Profil'                   : 'Edit Profile';
  String get btnSave         => isId ? 'Simpan'                        : 'Save';
  String get errProfileSave  => isId ? 'Gagal simpan profil: '         : 'Failed to save profile: ';
  String get msgProfileSaved => isId ? 'Profil berhasil disimpan'      : 'Profile saved';

  // ── Avatar Options ──
  String get avatarCamera     => isId ? 'Ambil Foto'                  : 'Take Photo';
  String get avatarGallery    => isId ? 'Dari Galeri'                 : 'From Gallery';
  String get avatarDelete     => isId ? 'Hapus Foto'                  : 'Remove Photo';
  String get errPhotoSave     => isId ? 'Gagal simpan foto: '         : 'Failed to save photo: ';
  String get errPhotoLoad     => isId ? 'Gagal membaca gambar'        : 'Failed to read image';
  String get msgPhotoExpired  => isId ? '⏰ Foto sudah expired'        : '⏰ Photo expired';

  // ── Galeri Foto Pribadi ──
  String get labelGallery     => isId ? 'Foto Saya'                    : 'My Photos';
  String get labelGalleryEmpty => isId ? 'Belum ada foto. Tambahkan foto dirimu.' : 'No photos yet. Add a photo of yourself.';
  String get btnAddGallery    => isId ? 'Tambah Foto'                  : 'Add Photo';
  String get btnDeletePhoto   => isId ? 'Hapus Foto'                   : 'Remove Photo';
  String get dialogDeletePhoto => isId ? 'Yakin ingin menghapus foto ini?' : 'Delete this photo?';
  String get msggalleryLimit => isId ? 'Maksimal 6 foto.'             : 'Maximum 6 photos.';
  String get labelOthersGallery => isId ? 'Foto Profil'                : 'Photos';

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
  String get labelNotifications => isId ? 'Notifikasi'                : 'Notifications';
  String get notifEnabledDesc  => isId ? 'Terima notifikasi pesan baru' : 'Receive new message notifications';

  // ── Errors / Generic ──
  String get btnCancel       => isId ? 'Batal'                        : 'Cancel';
  String get msgStartConversation => isId ? 'Mulai percakapan!'       : 'Start the conversation!';
  String get errGeneric       => isId ? 'Gagal: '                     : 'Failed: ';
  String get loading          => isId ? 'Memuat...'                   : 'Loading...';
  String get unknownUser      => isId ? 'Pengguna'                    : 'User';

  // ── Auth Email / Register / Login ──
  String get labelEmail          => isId ? 'Email'                          : 'Email';
  String get labelPassword       => isId ? 'Password'                       : 'Password';
  String get labelConfirmPassword => isId ? 'Konfirmasi Password'           : 'Confirm Password';
  String get hintEmail           => isId ? 'Masukkan email kamu...'         : 'Enter your email...';
  String get hintPassword        => isId ? 'Minimal 8 karakter'             : 'At least 8 characters';
  String get btnRegister         => isId ? 'DAFTAR'                         : 'REGISTER';
  String get btnLogin            => isId ? 'MASUK'                          : 'LOGIN';
  String get btnRegisterEmail    => isId ? 'Daftar dengan Email'            : 'Register with Email';
  String get btnLoginEmail       => isId ? 'Sudah punya akun? Login'        : 'Already have an account? Login';
  String get btnForgotPassword   => isId ? 'Lupa Password?'                 : 'Forgot Password?';
  String get btnSendReset        => isId ? 'Kirim Link Reset'               : 'Send Reset Link';
  String get titleRegister       => isId ? 'Buat Akun'                      : 'Create Account';
  String get titleLogin          => isId ? 'Masuk'                          : 'Login';
  String get titleForgotPassword => isId ? 'Reset Password'                 : 'Reset Password';
  String get titleLinkEmail      => isId ? 'Amankan Akun'                   : 'Secure Account';
  String get titleAccountSecurity => isId ? 'Keamanan Akun'                 : 'Account Security';
  String get msgVerifyEmail      => isId ? 'Link verifikasi dikirim ke email kamu. Cek inbox dan klik link untuk mengaktifkan akun.' : 'Verification link sent to your email. Check your inbox and click the link to activate your account.';
  String get msgPasswordResetSent => isId ? 'Link reset password dikirim ke email kamu.' : 'Password reset link sent to your email.';
  String get msgEmailNotRegistered => isId ? 'Email belum terdaftar. Daftar dulu untuk membuat akun.' : 'Email is not registered. Register first to create an account.';
  String get msgPasswordResetFailed => isId ? 'Gagal mengirim link reset. Coba lagi nanti.' : 'Failed to send reset link. Please try again later.';
  String get titleSetNewPassword => isId ? 'Buat Password Baru'              : 'Set New Password';
  String get msgSetNewPasswordHint => isId ? 'Masukkan password baru untuk akun kamu' : 'Enter a new password for your account';
  String get btnSavePassword  => isId ? 'Simpan Password'                    : 'Save Password';
  String get msgPasswordChanged => isId ? 'Password berhasil diubah. Silakan login ulang.' : 'Password changed. Please log in again.';
  String get errChangePassword => isId ? 'Gagal mengubah password: '         : 'Failed to change password: ';
  String get msgAccountLinked    => isId ? 'Email berhasil didaftarkan. Akun kamu sekarang aman.' : 'Email registered successfully. Your account is now secured.';
  String get msgAnonymousWarning => isId ? 'Akun anonim tidak bisa dipulihkan jika logout. Daftarkan email untuk mengamankan data kamu.' : 'Anonymous accounts cannot be recovered after logout. Register your email to secure your data.';
  String get labelSecuredAccount => isId ? 'Akun Email'                     : 'Email Account';
  String get btnSecureAccount    => isId ? 'Daftarkan Email'                : 'Register Email';
  String get errEmailEmpty       => isId ? 'Masukkan email dulu'            : 'Please enter your email';
  String get errEmailInvalid     => isId ? 'Format email tidak valid'       : 'Invalid email format';
  String get errPasswordShort    => isId ? 'Password minimal 8 karakter'   : 'Password must be at least 8 characters';
  String get errPasswordMismatch => isId ? 'Password tidak cocok'           : 'Passwords do not match';
  String get errEmailAlreadyUsed => isId ? 'Email sudah digunakan'          : 'Email already in use';
  String get errInvalidCredentials => isId ? 'Email atau password salah'    : 'Invalid email or password';
  String get errNicknameTaken    => isId ? 'Nickname sudah digunakan, pilih yang lain' : 'Nickname already taken, choose another';
  String get errEmailNotVerified => isId ? 'Email belum diverifikasi. Cek inbox kamu.' : 'Email not verified. Check your inbox.';
  String get msgEmailAlreadyRegisteredResend => isId ? 'Email sudah terdaftar tapi belum diverifikasi. Link verifikasi dikirim ulang ke inbox kamu.' : 'Email registered but not verified. Verification link resent to your inbox.';
  String get msgCompleteProfile  => isId ? 'Lengkapi profil untuk melanjutkan'     : 'Complete your profile to continue';
}
