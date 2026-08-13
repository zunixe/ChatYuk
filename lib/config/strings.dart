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
  String get statusInvisible => isId ? 'Invisible'                    : 'Invisible';
  String get typingStatus    => isId ? 'Sedang mengetik'              : 'Typing';
  String get genderMale      => isId ? '👨 Laki-laki'                  : '👨 Male';
  String get genderFemale    => isId ? '👩 Perempuan'                  : '👩 Female';
  String get genderOther     => isId ? '🧑 Lainnya'                    : '🧑 Other';
  String get labelRegistered => isId ? 'Terdaftar'                     : 'Registered';
  String get labelUnregistered => isId ? 'Tanpa daftar'                : 'Guest';

  // ── Private Chats ──
  String get titlePrivateChat => isId ? 'Private Chat'                : 'Private Chat';
  String get noPrivateChats  => isId ? 'Belum ada private chat'       : 'No private chats yet';
  String get noPrivateChatsHint => isId ? 'Klik user di chat room untuk mulai' : 'Tap a user in a chat room to start';
  String get startConversation => msgStartConversation;
  String get noMessages      => isId ? 'Belum ada pesan'              : 'No messages yet';
  String get timeJustNow     => isId ? 'Baru'                         : 'Now';
  String get labelToday      => isId ? 'Hari ini'                     : 'Today';
  String get labelYesterday  => isId ? 'Kemarin'                      : 'Yesterday';

  // ── Chat Screen (private & room) ──
  String get hintTypeMessage  => isId ? 'Ketik pesan...'              : 'Type a message...';
  String get errSendFailed    => isId ? 'Gagal kirim: '               : 'Send failed: ';
  String get errPhotoRead     => isId ? 'Gagal membaca gambar'        : 'Failed to read image';
  String get errSendPhoto     => isId ? 'Gagal kirim foto: '          : 'Failed to send photo: ';
  String get msgPhoto         => isId ? '[Foto]'                      : '[Photo]';
  String get msgViewOnce      => isId ? '[Foto Sekali Lihat]'          : '[View Once Photo]';
  String get viewOnceTap      => isId ? 'Tekan untuk melihat (10 detik)' : 'Tap to view (10 seconds)';
  String get viewOnceTitle    => isId ? 'Foto Sekali Lihat'              : 'View Once Photo';
  String get btnView          => isId ? 'Lihat'                          : 'View';
  String get viewOnceExpired  => isId ? 'Foto sudah kadaluarsa'        : 'Photo expired';
  String get viewOnceExpiredHint => isId ? 'Hanya bisa dilihat sekali' : 'Viewable only once';
  String get viewOnceViewing  => isId ? 'Menutup dalam'                : 'Closing in';
  String get msgBlocked       => isId ? 'User ini diblokir, tidak bisa kirim pesan' : 'This user is blocked, cannot send message';
  String get labelYou => isId ? 'Kamu' : 'You';
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
  String get labelHashtags    => isId ? 'Hashtag'                     : 'Hashtags';
  String get hintHashtag      => isId ? 'Tambah hashtag lalu Enter'   : 'Add hashtag and press Enter';
  String get errHashtagMax    => isId ? 'Maksimal 5 hashtag'          : 'Maximum 5 hashtags';
  String get errHashtagFormat => isId ? 'Hanya huruf, angka, atau underscore' : 'Letters, numbers, or underscore only';
  String get labelYears       => isId ? 'tahun'                       : 'years';
  String get btnLogout        => isId ? 'Keluar'                      : 'Logout';
  String get confirmLogoutBody => isId ? 'Yakin ingin keluar dari akun ini?' : 'Are you sure you want to log out?';
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
  String get msgPhotoTapToLoad => isId ? 'Ketuk untuk memuat foto'     : 'Tap to load photo';

  // ── Galeri Foto Pribadi ──
  String get labelGallery     => isId ? 'Foto Saya'                    : 'My Photos';
  String get labelGalleryEmpty => isId ? 'Belum ada foto. Tambahkan foto dirimu.' : 'No photos yet. Add a photo of yourself.';
  String get btnAddGallery    => isId ? 'Tambah Foto'                  : 'Add Photo';
  String get btnDeletePhoto   => isId ? 'Hapus Foto'                   : 'Remove Photo';
  String get dialogDeletePhoto => isId ? 'Yakin ingin menghapus foto ini?' : 'Delete this photo?';
  String get msggalleryLimit => msgGalleryLimit;
  String get msgGalleryLimit => isId ? 'Maksimal 6 foto.'             : 'Maximum 6 photos.';
  String get labelOthersGallery => isId ? 'Foto Profil'                : 'Photos';
  String get btnShareApp       => isId ? 'Ajak Teman'                  : 'Invite Friends';
  String get msgShareApp       => isId ? 'Ayo chat bareng di ChatYuk! Download sekarang di Google Play: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk' : 'Let\'s chat on ChatYuk! Download now on Google Play: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';

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
  String get btnClose        => isId ? 'Tutup'                        : 'Close';
  String get msgStartConversation => isId ? 'Mulai percakapan!'       : 'Start the conversation!';
  String get errGeneric       => isId ? 'Gagal: '                     : 'Failed: ';
  String get errUserNotFound  => isId ? 'Pengguna tidak ditemukan'    : 'User not found';
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

  // ── Google Sign-In / Account Linking ──
  String get btnLinkAccount     => isId ? 'Hubungkan Akun?'                    : 'Link Account?';
  String get btnCreateNew       => isId ? 'Buat Baru'                          : 'Create New';
  String get btnUseExisting     => isId ? 'Pakai Profil Lama'                  : 'Use Existing';
  String get btnContinueGoogle  => isId ? 'Lanjutkan dengan Google'            : 'Continue with Google';
  String get errGoogleSignIn    => isId ? 'Google sign in gagal: '             : 'Google sign in failed: ';
  String get labelOr            => isId ? 'atau'                               : 'or';

  /// Pesan konfirmasi link akun dengan nickname akun lama.
  String msgLinkPrompt(String nickname) =>
      isId ? 'Email ini sudah terdaftar sebagai "$nickname". Mau pakai profil yang sudah ada?'
           : 'This email is already registered as "$nickname". Use the existing profile?';

  // ── Username / Nickname ──
  String get btnChangeUsername  => isId ? 'Ganti Username'                     : 'Change Username';
  String get msgUsernameOldReleased => isId ? 'Username lama akan langsung bisa dipakai orang lain.' : 'Your old username will be immediately available for others.';

  // ── Donasi ──
  String get titleDonate        => isId ? 'Donasi'                             : 'Donate';
  String get labelQris          => isId ? 'QRIS'                              : 'QRIS';
  String get labelUsdt          => isId ? 'USDT Crypto'                       : 'USDT Crypto';
  String get msgCopied          => isId ? ' disalin ke clipboard'              : ' copied to clipboard';
  String get btnCopyAddress     => isId ? 'Salin Alamat '                      : 'Copy Address ';
  String get donateSelectHint   => isId ? 'Pilih network dan salin alamat wallet' : 'Choose a network and copy the wallet address';
  String get donateWrongNetwork => isId ? 'Pastikan kamu mengirim ke network yang benar. Mengirim ke network yang salah dapat menyebabkan dana hilang.' : 'Make sure you send to the correct network. Sending to the wrong network may cause funds to be lost.';
  String get donateScanQris     => isId ? 'Scan QRIS untuk donasi'            : 'Scan QRIS to donate';
  String get donateQrisInfo     => isId ? 'QRIS dapat digunakan di semua aplikasi dompet digital dan mobile banking Indonesia (GoPay, OVO, Dana, BCA, Mandiri, dll)' : 'QRIS works with all Indonesian digital wallets and mobile banking apps (GoPay, OVO, Dana, BCA, Mandiri, etc.)';
  String get donateThankYou     => isId ? 'Terima Kasih!'                     : 'Thank You!';
  String get donateThanksMsg    => isId ? 'Donasi kamu membantu pengembangan ChatYuk agar terus gratis dan bebas iklan.' : 'Your donation helps keep ChatYuk free and ad-free.';

  // ── Screenshot admin ──
  String get labelScreenshotAllow => isId ? 'Izinkan screenshot aplikasi'      : 'Allow app screenshots';
  String get descScreenshotAdmin  => isId ? 'Admin — kontrol screenshot untuk semua pengguna' : 'Admin — control screenshots for all users';

  // ── Watermark admin ──
  String get labelWatermarkAdmin => isId ? 'Aktifkan watermark forensik'       : 'Enable forensic watermark';
  String get descWatermarkAdmin  => isId ? 'Admin — foto sekali lihat ditandai identitas penerima' : 'Admin — view-once photos tagged with receiver identity';

  // ── Invisible admin ──
  String get labelInvisibleAdmin => isId ? 'Mode invisible'                : 'Invisible mode';
  String get descInvisibleAdmin  => isId ? 'Admin — tidak muncul di daftar pengguna online' : 'Admin — hidden from online users list';

  // ── Points ──
  String get pointsTitle          => isId ? 'Poin ChatYuk'          : 'ChatYuk Points';
  String get pointsBalance        => isId ? 'Poin'                  : 'Points';
  String get pointsEstimate       => isId ? '≈ %d pesan lagi'       : '≈ %d more messages';
  String get pointsSafe           => isId ? '✅ Aman selamanya'      : '✅ Safe forever';
  String get pointsAnonymousLose  => isId ? 'Poin akan hilang kalau kamu logout atau ganti HP' : 'Points will be lost if you logout or switch phones';
  String get pointsSecureHeader   => isId ? 'Amankan Poin Kamu'     : 'Secure Your Points';
  String get pointsSecureBody     => isId ? '%d poin. Daftar = aman + bonus 100!' : '%d points. Register = safe + 100 bonus!';
  String get pointsLow            => isId ? '⚠️ %d poin'             : '⚠️ %d points';
  String get pointsEmptyTitle     => isId ? 'Poin Habis!'           : 'Out of Points!';
  String get pointsDailyLoginTxt  => isId ? '+25 login harian'     : '+25 daily login';
  String get pointsOnlineBonus    => isId ? '+55 online bonus'     : '+55 online bonus';
  String get pointsRegisterBonusLabel => isId ? '+100 daftar email' : '+100 register email';
  String get pointsRateAppLabel   => isId ? '+20 rate aplikasi'    : '+20 rate app';
  String get pointsShareAppLabel  => isId ? '+10 share ke teman'    : '+10 share app';
  String get pointsInviteLabel    => isId ? '+30 invite teman'     : '+30 invite friend';
  String get pointsProfileLabel   => isId ? '+10 lengkapi profil'   : '+10 complete profile';
  String get pointsNewChatLabel   => isId ? '+5 chat orang baru'    : '+5 chat new person';
  String get pointsFirstPhotoLabel => isId ? '+10 kirim foto pertama' : '+10 first photo';
  String get pointsRegisterBonusText => isId ? 'Daftarkan email untuk klaim poin' : 'Register email to claim points';
  String get pointsDeductToast    => isId ? '-%d Poin'             : '-%d Points';
  String get pointsEarned         => isId ? '+%d Poin'             : '+%d Points';
  String get btnRetry           => isId ? 'Coba Lagi'                          : 'Retry';
  String get msgServerError     => isId ? 'Gagal terhubung ke server'          : 'Failed to connect to server';
  String get msgServerErrorHint => isId ? 'Periksa koneksi internet kamu, lalu coba lagi.' : 'Check your internet connection and try again.';
  String get msgFileTooLarge    => isId ? 'File terlalu besar. Maksimal 10MB.' : 'File too large. Maximum 10MB.';
  String get btnEmoji         => isId ? 'Emoji'                       : 'Emoji';
  String get tooltipPhoto       => isId ? 'Foto'                               : 'Photo';
  String get labelGenderFilter  => isId ? 'Gender'                             : 'Gender';
  String get btnDelete          => isId ? 'Hapus'                              : 'Delete';
  String get adminPanel          => isId ? 'Admin Panel'                        : 'Admin Panel';
  String get statsUsers          => isId ? 'Users'                              : 'Users';
  String get statsActive         => isId ? 'Active'                             : 'Active';
  String get statsMsgs           => isId ? 'Msgs'                               : 'Msgs';
  String get statsRooms          => isId ? 'Rooms'                              : 'Rooms';
  String get statsReg            => isId ? 'Reg.'                               : 'Reg.';
  String get statsAnon           => isId ? 'Anon'                               : 'Anon';
  String get statsAvg            => isId ? 'Avg'                                : 'Avg';
  String get statsTotal          => isId ? 'Total'                              : 'Total';
  String get adminNoUsers        => isId ? 'Tidak ada user'                    : 'No users';
  String get adminTopEarners     => isId ? 'Top Earners'                        : 'Top Earners';
  String get adminMassBonus      => isId ? 'Bonus Massal'                       : 'Mass Bonus';
  String get adminForceLogout    => isId ? 'Force Logout'                       : 'Force Logout';
  String get adminPointsSystem   => isId ? 'Sistem Poin'                        : 'Points System';
  String get adminReports        => isId ? 'Laporan'                            : 'Reports';
  String get adminNoReports      => isId ? 'Tidak ada laporan'                  : 'No reports';
  String get adminDangerZone     => isId ? 'Zona Bahaya'                        : 'Danger Zone';
  String get adminResetAllPoints => isId ? 'Reset semua user ke 50 poin'       : 'Reset all users to 50 points';
  String get adminResetAllTitle  => isId ? 'Reset Semua Poin?'                  : 'Reset All Points?';
  String get adminResetAllBody   => isId ? 'Semua user akan memiliki 50 poin.' : 'All users will have 50 points.';
  String get adminWipeAll        => isId ? 'Reset Semua'                        : 'Wipe All';
  String get adminReset          => isId ? 'Reset'                              : 'Reset';
  String get adminLogout         => isId ? 'Keluar'                             : 'Logout';
  String get adminRunning        => isId ? 'Berjalan'                           : 'Running';
  String get adminPaused         => isId ? 'Dihentikan'                          : 'Paused';
  String get adminRealtimeDesc   => isId ? 'Realtime — efek langsung ke semua device' : 'Realtime — immediate effect on all devices';
  String get adminRegisteredOnly => isId ? 'Hanya user registered'              : 'Registered users only';
  String get btnSend              => isId ? 'Kirim'                               : 'Send';
  String get adminStuckUsers     => isId ? 'user terjebak (0 poin)'             : 'users stuck (0 points)';
  String get onlineActiveUsers   => isId ? 'pengguna aktif'                     : 'active users';
  String get labelVerified       => isId ? 'Terverifikasi'                      : 'Verified';
  String get lobbyCountryHint    => isId ? 'Negara / Country'                   : 'Country / Negara';
  String get donateCopyAddress   => isId ? 'Salin Alamat '                      : 'Copy Address ';
  String get googleSignInFailed  => isId ? 'Google sign in gagal: '             : 'Google sign in failed: ';

  // ── Admin Chat Monitor ──
  String get adminOverview       => isId ? 'Ringkasan'                        : 'Overview';
  String get adminChatMonitor   => isId ? 'Monitor Chat'                     : 'Chat Monitor';
  String get adminChatNoChats   => isId ? 'Belum ada percakapan'             : 'No conversations yet';
  String get adminChatMsgs      => isId ? 'pesan'                            : 'messages';
  String get adminChatOpen      => isId ? 'Buka Percakapan'                  : 'Open Conversation';
  String get adminChatLoading   => isId ? 'Memuat percakapan...'             : 'Loading conversation...';
  String get adminChatError     => isId ? 'Gagal memuat percakapan'          : 'Failed to load conversation';
  String get adminChatBack      => isId ? 'Kembali'                          : 'Back';
  String get adminViewOnce      => isId ? 'Foto Sekali Lihat (Admin)'        : 'View-Once Photo (Admin)';
  String get adminLastUpdate    => isId ? 'Update terakhir'                  : 'Last updated';
  String get adminSearchChat    => isId ? 'Cari percakapan...'               : 'Search conversations...';
  String get adminUserSingular  => isId ? 'user'                             : 'user';
  String get adminUsersPlural   => isId ? 'user'                             : 'users';
  String get chatMsgCount       => isId ? 'pesan'                            : 'messages';
  String get adminDeleteChat    => isId ? 'Hapus Chat'                        : 'Delete Chat';
  String get adminDeleteChatTitle => isId ? 'Hapus Chat & User'               : 'Delete Chat & Users';
  String get adminDeleteChatBody => isId ? 'Semua history chat antara kedua user akan dihapus permanen (termasuk foto di storage). Pilih user yang juga ingin dihapus akunnya:' : 'All chat history between both users will be permanently deleted (including photos in storage). Select users to also delete their accounts:';
  String get adminDeleteChatOnly => isId ? 'Hapus chat saja'                  : 'Delete chat only';
  String get adminDeleteUser     => isId ? 'Hapus akun'                       : 'Delete account';
  String get adminCannotDeleteAdmin => isId ? '(admin, tidak bisa dihapus)'   : '(admin, cannot be deleted)';
  String get adminChatDeleted    => isId ? 'Chat dihapus'                     : 'Chat deleted';
  String get adminDeleteFail     => isId ? 'Gagal menghapus chat'             : 'Failed to delete chat';
}
