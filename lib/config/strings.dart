// Semua string UI aplikasi dalam Bahasa Indonesia dan English.
// Untuk tambah bahasa baru: tambah getter baru di sini.
import '../models/legal_section.dart';

class S {
  final bool isId;
  // ignore: prefer_const_constructors_in_immutables
  S({required this.isId});

  // ── Entry Screen ──
  String get appTagline =>
      isId ? 'Ngobrol, Cerita, Ketawa' : 'Chat, Share, Laugh';
  String get appSubtagline =>
      isId ? 'Langsung ngobrol, tanpa ribet!' : 'Start chatting, no hassle!';
  String get labelUsername => isId ? 'Username' : 'Username';
  String get hintNickname =>
      isId ? 'Pilih nickname kamu...' : 'Choose your nickname...';
  String get labelAge => isId ? 'Umur' : 'Age';
  String get labelCountry => isId ? 'Negara' : 'Country';
  String get labelCity => isId ? 'Kota' : 'City';
  String get labelGenderMale => isId ? 'Laki-laki' : 'Male';
  String get labelGenderFemale => isId ? 'Perempuan' : 'Female';
  String get btnStartChat =>
      isId ? 'MULAI CHAT SEKARANG' : 'START CHATTING NOW';
  String get errNicknameEmpty =>
      isId ? 'Masukkan nickname dulu' : 'Please enter a nickname';
  String get errNicknameShort => isId
      ? 'Nickname minimal 3 karakter'
      : 'Nickname must be at least 3 characters';
  String get errNicknameLong => isId
      ? 'Nickname maksimal 20 karakter'
      : 'Nickname must be at most 20 characters';
  String get errNicknameInvalid => isId
      ? 'Nickname hanya boleh huruf, angka, spasi, _ atau -'
      : 'Nickname may only contain letters, numbers, spaces, _ or -';

  // ── Navigation / Bottom Bar ──
  String get navRooms => isId ? 'Rooms' : 'Rooms';
  String get navOnline => isId ? 'Online' : 'Online';
  String get navChats => isId ? 'Chat' : 'Chats';
  String get navProfile => isId ? 'Profil' : 'Profile';

  // ── Lobby / Rooms ──
  String get titleRooms => isId ? 'Pilih Room' : 'Choose a Room';
  String get roomOnlineCount => isId ? 'online' : 'online';
  String get noRooms => isId ? 'Belum ada room tersedia' : 'No rooms available';

  // ── Private Rooms ──
  String get tabGlobalRoom => isId ? 'Room Global' : 'Global Room';
  String get tabPrivateRoom => isId ? 'Room Private' : 'Private Room';
  String get noPrivateRooms =>
      isId ? 'Belum ada room private' : 'No private rooms yet';
  String get noPrivateRoomsHint =>
      isId ? 'Buat room-mu sendiri di bawah' : 'Create your own room below';
  String get btnCreateRoom => isId ? 'Buat Room' : 'Create Room';
  String get roomShowMembers => isId ? 'Lihat anggota' : 'View members';
  String get roomShowChat => isId ? 'Kembali ke chat' : 'Back to chat';
  String get createRoomTitle =>
      isId ? 'Buat Room Private' : 'Create Private Room';
  String get roomNameLabel => isId ? 'Nama room' : 'Room name';
  String get roomNameHint => isId ? '3–30 karakter' : '3–30 characters';
  String get roomIconLabel => isId ? 'Ikon' : 'Icon';
  String get roomPasswordOpt =>
      isId ? 'Password (opsional)' : 'Password (optional)';
  String get roomPasswordHint =>
      isId ? 'Kosongkan bila tanpa password' : 'Leave empty for no password';
  String get labelYourCoins => isId ? 'Koin kamu' : 'Your coins';
  String roomCreateCost(int c) => isId ? 'Biaya: $c koin' : 'Cost: $c coins';
  String get errRoomNameLen => isId
      ? 'Nama room harus 3–30 karakter'
      : 'Room name must be 3–30 characters';
  String get errRoomLimit =>
      isId ? 'Maksimal 2 room aktif' : 'Max 2 active rooms';
  String get roomCreated => isId ? 'Room berhasil dibuat' : 'Room created';
  String get joinRoomTitle => isId ? 'Masuk Room' : 'Join Room';
  String joinRoomCost(int c) =>
      isId ? 'Biaya masuk: $c koin' : 'Entry cost: $c coins';
  String get enterPassword => isId ? 'Masukkan password' : 'Enter password';
  String get errWrongPassword => isId ? 'Password salah' : 'Wrong password';
  String get btnJoin => isId ? 'Masuk' : 'Join';
  String get roomByOwner => isId ? 'oleh' : 'by';
  String get btnExtendRoom =>
      isId ? 'Perpanjang 7 hari (50 koin)' : 'Extend 7 days (50 coins)';
  String get btnDeleteRoom => isId ? 'Hapus Room' : 'Delete Room';
  String get deleteRoomConfirm => isId
      ? 'Hapus room ini? Semua pesan ikut terhapus.'
      : 'Delete this room? All messages will be deleted.';
  String get roomDeleted => isId ? 'Room dihapus' : 'Room deleted';
  String get roomExtended =>
      isId ? 'Room diperpanjang 7 hari' : 'Room extended by 7 days';
  String roomExpiresIn(int days) => isId ? '$days hari lagi' : '${days}d left';
  String get roomExpiresToday => isId ? 'Berakhir hari ini' : 'Ends today';

  // ── Send Coins ──
  String get menuSendPhoto => isId ? 'Kirim Foto' : 'Send Photo';
  String get menuViewOnce => isId ? 'Foto Sekali Lihat' : 'View-once Photo';
  String get menuSendCoin => isId ? 'Kirim Koin' : 'Send Coins';
  String get sendCoinTitle => isId ? 'Kirim Koin' : 'Send Coins';
  String sendCoinTo(String name) => isId ? 'Kirim ke $name' : 'Send to $name';
  String get coinAmountLabel => isId ? 'Jumlah koin' : 'Coin amount';
  String get coinAmountHint =>
      isId ? 'Ketik jumlah sendiri' : 'Type your own amount';
  String get coinDialogHelper =>
      isId ? 'Minimal 5, maksimal saldo kamu' : 'Minimum 5, up to your balance';
  String get errCoinMin => isId ? 'Minimal 5 koin' : 'Minimum 5 coins';
  String get errCoinInsufficient =>
      isId ? 'Koin kamu tidak cukup' : 'Not enough coins';
  String get errCoinRegisterOnly => isId
      ? 'Hanya akun terdaftar yang bisa kirim koin. Daftar email dulu (+100 koin)!'
      : 'Only registered accounts can send coins. Register email first (+100 coins)!';
  String coinSentToast(int n) => isId ? '-$n koin terkirim' : '-$n coins sent';
  String coinBubbleSent(int n) =>
      isId ? '🪙 Kamu mengirim $n koin' : '🪙 You sent $n coins';
  String coinBubbleReceived(int n) =>
      isId ? '🪙 Menerima $n koin' : '🪙 Received $n coins';
  String get errSendCoin => isId ? 'Gagal kirim koin' : 'Failed to send coins';
  // ── Umum ──
  String get btnConfirm => isId ? 'Konfirmasi' : 'Confirm';
  String get errCoinDisabled => isId
      ? 'Sistem koin sedang dinonaktifkan'
      : 'Coin system is currently disabled';

  /// Nama room berdasarkan id (fallback ke nama DB jika tidak ada translasi)
  String roomName(String id) {
    if (isId)
      return const {
            'general': 'General',
            'curhat': 'Curhat',
            'pertemanan': 'Pertemanan',
            'teknologi': 'Teknologi',
            'gaming': 'Gaming',
            'musik': 'Musik',
            'film': 'Film & TV',
            'joke': 'Joke & Meme',
            'belajar': 'Belajar',
            'flirt': 'Flirt',
          }[id] ??
          id;
    return const {
          'general': 'General',
          'curhat': 'Confessions',
          'pertemanan': 'Friendship',
          'teknologi': 'Technology',
          'gaming': 'Gaming',
          'musik': 'Music',
          'film': 'Film & TV',
          'joke': 'Jokes & Memes',
          'belajar': 'Study',
          'flirt': 'Flirt',
        }[id] ??
        id;
  }

  String roomDesc(String id) {
    if (isId)
      return const {
            'general': 'Obrolan umum untuk semua',
            'curhat': 'Cerita dan curhat bareng',
            'pertemanan': 'Cari temen baru di sini',
            'teknologi': 'Diskusi tech & gadget',
            'gaming': 'Main bareng & diskusi game',
            'musik': 'Sharing musik & lagu',
            'film': 'Rekomendasi & review film',
            'joke': 'Yang bikin ngakak',
            'belajar': 'Diskusi belajar & kuliah',
            'flirt': 'Ngobrol santai & asyik',
          }[id] ??
          '';
    return const {
          'general': 'General chat for everyone',
          'curhat': 'Share your stories & feelings',
          'pertemanan': 'Find new friends here',
          'teknologi': 'Discuss tech & gadgets',
          'gaming': 'Play together & talk games',
          'musik': 'Share music & songs',
          'film': 'Movie & TV recommendations',
          'joke': 'All the funny stuff',
          'belajar': 'Study & college discussions',
          'flirt': 'Casual & fun conversations',
        }[id] ??
        '';
  }

  // ── Online Users ──
  String get titleOnline => isId ? 'Pengguna Online' : 'Online Users';
  String get searchHint =>
      isId ? 'Cari nama pengguna...' : 'Search username...';
  String get filterAll => isId ? 'Semua' : 'All';
  String get filterMale => isId ? 'Laki-laki' : 'Male';
  String get filterFemale => isId ? 'Perempuan' : 'Female';
  String get noOnlineUsers =>
      isId ? 'Tidak ada pengguna online' : 'No users online';
  // ── Orang Sekitar (nearby) ──
  String get nearbyTitle => isId ? 'Orang Sekitar' : 'People Nearby';
  String get nearbyRadius => isId ? 'Radius' : 'Radius';
  String get nearbyEmpty =>
      isId ? 'Tidak ada orang di sekitarmu' : 'No one around you';
  String get nearbyEmptyHint => isId
      ? 'Perbesar radius atau coba lagi nanti'
      : 'Increase the radius or try again later';
  String get nearbyNoLocation =>
      isId ? 'Lokasimu belum terdeteksi' : 'Your location is not available yet';
  String get nearbyNeedShare => isId
      ? 'Aktifkan "Bagikan Lokasi" untuk memakai fitur ini'
      : 'Enable "Share Location" to use this feature';
  String get nearbyShareToggle => isId ? 'Bagikan Lokasi' : 'Share Location';
  String get nearbyShareDesc => isId
      ? 'Orang lain bisa menemukanmu di sekitar mereka'
      : 'Others can find you nearby';
  String get nearbyEnableLoc => isId ? 'Aktifkan Lokasi' : 'Enable Location';
  String get nearbyRetry => isId ? 'Coba Lagi' : 'Retry';
  String get nearbySearching =>
      isId ? 'Mencari orang di sekitar…' : 'Searching for people nearby…';
  String nearbyDistanceKm(String km) =>
      isId ? '$km km dari kamu' : '$km km away';
  String nearbyDistanceM(int m) => isId ? '$m m dari kamu' : '$m m away';
  String nearbyCount(int n) =>
      isId ? '$n orang di sekitar' : '$n people nearby';
  String get searchNoResult => isId ? 'Tidak ditemukan' : 'No results found';
  // ── Onboarding poin ──
  String get pointsOnboardTitle =>
      isId ? 'Sistem Poin ChatYuk' : 'ChatYuk Points';
  String get pointsOnboardSub =>
      isId ? 'Cara dapat & pakai poin' : 'How to earn & spend';
  String get pointsOnboardEmail => isId
      ? 'Daftar email = +100, dan data aman!'
      : 'Register email = +100, fully safe!';
  String get pointsOnboardChat => isId
      ? 'Chat = pakai poin (-1 per pesan)'
      : 'Chat = uses points (-1 per msg)';
  String get pointsOnboardDaily =>
      isId ? 'Login tiap hari = +25 poin' : 'Daily login = +25 points';
  String get pointsOnboardOnline =>
      isId ? 'Online 60 menit = +45 bonus' : 'Online 60 min = +45 bonus';
  String get pointsOnboardStart =>
      isId ? 'Mulai dengan 50 poin gratis' : 'Start with 50 free points';
  String get pointsOnboardOk => isId ? 'OK, Paham!' : 'OK, Got it!';
  String get statusOnline => isId ? 'Online' : 'Online';
  String get statusIdle => isId ? 'Idle' : 'Idle';
  String get statusOffline => isId ? 'Offline' : 'Offline';
  String get statusInvisible => isId ? 'Invisible' : 'Invisible';
  String get typingStatus => isId ? 'Sedang mengetik' : 'Typing';
  String get genderMale => isId ? '👨 Laki-laki' : '👨 Male';
  String get genderFemale => isId ? '👩 Perempuan' : '👩 Female';
  String get genderMalePlain => isId ? 'Laki-laki' : 'Male';
  String get genderFemalePlain => isId ? 'Perempuan' : 'Female';
  String get genderOther => isId ? '🧑 Lainnya' : '🧑 Other';
  String get labelRegistered => isId ? 'Terdaftar' : 'Registered';
  String get labelUnregistered => isId ? 'Tanpa daftar' : 'Guest';

  // ── Private Chats ──
  String get titlePrivateChat => isId ? 'Private Chat' : 'Private Chat';
  String get noPrivateChats =>
      isId ? 'Belum ada private chat' : 'No private chats yet';
  String get noPrivateChatsHint => isId
      ? 'Klik user di chat room untuk mulai'
      : 'Tap a user in a chat room to start';
  String get startConversation => msgStartConversation;
  String get noMessages => isId ? 'Belum ada pesan' : 'No messages yet';
  String get timeJustNow => isId ? 'Baru' : 'Now';
  String get labelToday => isId ? 'Hari ini' : 'Today';
  String get labelYesterday => isId ? 'Kemarin' : 'Yesterday';

  // ── Chat Screen (private & room) ──
  String get hintTypeMessage => isId ? 'Ketik pesan...' : 'Type a message...';
  String get errSendFailed => isId ? 'Gagal kirim: ' : 'Send failed: ';
  String get errPhotoRead =>
      isId ? 'Gagal membaca gambar' : 'Failed to read image';
  String get errSendPhoto =>
      isId ? 'Gagal kirim foto: ' : 'Failed to send photo: ';
  String get msgPhoto => isId ? '[Foto]' : '[Photo]';
  String get msgViewOnce => isId ? '[Foto Sekali Lihat]' : '[View Once Photo]';
  String get viewOnceTap =>
      isId ? 'Tekan untuk melihat (10 detik)' : 'Tap to view (10 seconds)';
  String get viewOnceTitle => isId ? 'Foto Sekali Lihat' : 'View Once Photo';
  String get btnView => isId ? 'Lihat' : 'View';
  String get viewOnceExpired =>
      isId ? 'Foto sudah kadaluarsa' : 'Photo expired';
  String get viewOnceExpiredHint =>
      isId ? 'Hanya bisa dilihat sekali' : 'Viewable only once';
  String get viewOnceViewing => isId ? 'Menutup dalam' : 'Closing in';
  String get msgBlocked => isId
      ? 'User ini diblokir, tidak bisa kirim pesan'
      : 'This user is blocked, cannot send message';
  String get labelYou => isId ? 'Kamu' : 'You';
  String get msgBlockedByOther => isId
      ? 'Kamu diblokir oleh pengguna ini'
      : 'You have been blocked by this user';
  String get btnBlock => isId ? 'Blokir' : 'Block';
  String get btnReport => isId ? 'Laporkan' : 'Report';
  String get btnUnblock => isId ? 'Buka Blokir' : 'Unblock';
  String get labelOnlineUsers => isId ? 'Online' : 'Online';
  String get reportTitle => isId ? 'Laporkan Pengguna' : 'Report User';
  String get reportHint => isId ? 'Alasan laporan...' : 'Reason for report...';
  String get reportBtn => isId ? 'Kirim Laporan' : 'Submit Report';
  String get reportSuccess => isId ? 'Laporan terkirim' : 'Report submitted';
  String get blockSuccess => isId ? 'Pengguna diblokir' : 'User blocked';
  String get unblockSuccess => isId ? 'Blokir dibuka' : 'User unblocked';
  String get btnDeleteChat => isId ? 'Hapus Chat' : 'Delete Chat';
  String get deleteChatSuccess => isId ? 'Chat dihapus' : 'Chat deleted';
  String get deleteChatConfirm => isId
      ? 'Hapus percakapan ini? Pesan tidak bisa dipulihkan.'
      : 'Delete this conversation? Messages cannot be recovered.';

  // ── Profile ──
  String get titleProfile => isId ? 'Profil' : 'Profile';
  String get btnChangePhoto =>
      isId ? 'Ganti Foto Profil' : 'Change Profile Photo';
  String get btnAddPhoto => isId ? 'Tambah Foto Profil' : 'Add Profile Photo';
  String get labelStatus => isId ? 'Status' : 'Status';
  String get labelUserId => isId ? 'User ID' : 'User ID';
  String get labelHashtags => isId ? 'Hashtag' : 'Hashtags';
  String get hintHashtag =>
      isId ? 'Tambah hashtag lalu Enter' : 'Add hashtag and press Enter';
  String get errHashtagMax =>
      isId ? 'Maksimal 5 hashtag' : 'Maximum 5 hashtags';
  String get errHashtagFormat => isId
      ? 'Hanya huruf, angka, atau underscore'
      : 'Letters, numbers, or underscore only';
  String get labelYears => isId ? 'tahun' : 'years';
  String get btnLogout => isId ? 'Keluar' : 'Logout';
  String get confirmLogoutBody => isId
      ? 'Yakin ingin keluar dari akun ini?'
      : 'Are you sure you want to log out?';
  String get genderLabelMale => isId ? '👨 Laki-laki' : '👨 Male';
  String get genderLabelFemale => isId ? '👩 Perempuan' : '👩 Female';
  String get genderLabelOther => isId ? '🧑 Lainnya' : '🧑 Other';
  String get btnEditProfile => isId ? 'Edit Profil' : 'Edit Profile';
  String get btnSave => isId ? 'Simpan' : 'Save';
  String get msgEdited => isId ? '(diedit)' : '(edited)';
  String get editMessageTitle => isId ? 'Edit Pesan' : 'Edit Message';
  String get editingMessage =>
      isId ? 'Sedang mengedit pesan' : 'Editing message';
  String get menuReply => isId ? 'Balas' : 'Reply';
  String get messageDeleted => isId ? 'Pesan dihapus' : 'Message deleted';
  String get replyingTo => isId ? 'Membalas' : 'Replying to';
  String get errProfileSave =>
      isId ? 'Gagal simpan profil: ' : 'Failed to save profile: ';
  String get msgProfileSaved =>
      isId ? 'Profil berhasil disimpan' : 'Profile saved';

  // ── Avatar Options ──
  String get avatarCamera => isId ? 'Ambil Foto' : 'Take Photo';
  String get avatarGallery => isId ? 'Dari Galeri' : 'From Gallery';
  String get avatarDelete => isId ? 'Hapus Foto' : 'Remove Photo';
  String get errPhotoSave =>
      isId ? 'Gagal simpan foto: ' : 'Failed to save photo: ';
  String get errPhotoLoad =>
      isId ? 'Gagal membaca gambar' : 'Failed to read image';
  String get msgPhotoExpired =>
      isId ? '⏰ Foto sudah expired' : '⏰ Photo expired';
  String get msgPhotoTapToLoad =>
      isId ? 'Ketuk untuk memuat foto' : 'Tap to load photo';

  // ── Galeri Foto Pribadi ──
  String get labelGallery => isId ? 'Foto Saya' : 'My Photos';
  String get labelGalleryEmpty => isId
      ? 'Belum ada foto. Tambahkan foto dirimu.'
      : 'No photos yet. Add a photo of yourself.';
  String get btnAddGallery => isId ? 'Tambah Foto' : 'Add Photo';
  String get btnDeletePhoto => isId ? 'Hapus Foto' : 'Remove Photo';
  String get dialogDeletePhoto =>
      isId ? 'Yakin ingin menghapus foto ini?' : 'Delete this photo?';
  String get msggalleryLimit => msgGalleryLimit;
  String get msgGalleryLimit => isId ? 'Maksimal 6 foto.' : 'Maximum 6 photos.';
  String get labelOthersGallery => isId ? 'Foto Profil' : 'Photos';
  String get btnShareApp => isId ? 'Ajak Teman' : 'Invite Friends';
  String get msgShareApp => isId
      ? 'Ayo chat bareng di ChatYuk! Download sekarang di Google Play: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk'
      : 'Let\'s chat on ChatYuk! Download now on Google Play: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';

  // ── Settings ──
  String get titleSettings => isId ? 'Pengaturan' : 'Settings';
  String get labelLanguage => isId ? 'Bahasa / Language' : 'Language / Bahasa';
  String get labelTheme => isId ? 'Mode Gelap' : 'Dark Mode';
  String get descTheme => isId
      ? 'Tampilan gelap untuk kenyamanan mata'
      : 'Dark appearance for comfort';
  String get langId => isId ? '🇮🇩  Indonesia' : '🇮🇩  Indonesia';
  String get langEn => isId ? '🇬🇧  English' : '🇬🇧  English';

  // ── Notifications ──
  String get notifChannelName =>
      isId ? 'Notifikasi Chat' : 'Chat Notifications';
  String get notifChannelDesc => isId
      ? 'Notifikasi pesan baru dari chat'
      : 'New message notifications from chat';
  String get notifNewMessage => isId ? 'Pesan baru' : 'New message';
  String get notifNewMessageBody =>
      isId ? 'Pesan baru masuk' : 'You have a new message';
  String get notifOnlineBody => isId ? 'sedang online' : 'is online';
  String get notifFollowBody =>
      isId ? 'mulai mengikuti kamu' : 'started following you';
  String get notifFriendRequestBody =>
      isId ? 'mengirim permintaan teman' : 'sent you a friend request';
  String get notifSubscribeBody =>
      isId ? 'berlangganan ke kamu' : 'subscribed to you';
  String get notifCallingBody =>
      isId ? 'menelpon kamu...' : 'is calling you...';
  String get labelNotifications => isId ? 'Notifikasi' : 'Notifications';
  String get notifEnabledDesc => isId
      ? 'Terima notifikasi pesan baru'
      : 'Receive new message notifications';

  // ── Call 1:1 (audio/video) ──
  String get callAudio => isId ? 'Panggilan Audio' : 'Audio Call';
  String get callVideo => isId ? 'Panggilan Video' : 'Video Call';
  String get callMinimize => isId ? 'Kecilkan' : 'Minimize';
  String get callExpand => isId ? 'Layar penuh' : 'Full screen';
  String get callInChatHint =>
      isId ? 'Tarik video ke mana saja' : 'Drag the video anywhere';
  String get callIncomingAudio =>
      isId ? 'Panggilan audio masuk...' : 'Incoming audio call...';
  String get callIncomingVideo =>
      isId ? 'Panggilan video masuk...' : 'Incoming video call...';
  String get callOutgoingAudio =>
      isId ? 'Panggilan audio...' : 'Calling (audio)...';
  String get callOutgoingVideo =>
      isId ? 'Panggilan video...' : 'Calling (video)...';
  String get callRinging => isId ? 'Menunggu jawaban...' : 'Ringing...';
  String get callConnecting => isId ? 'Menghubungkan...' : 'Connecting...';
  String get btnAcceptCall => isId ? 'Terima' : 'Accept';
  String get btnDeclineCall => isId ? 'Tolak' : 'Decline';
  String get btnEndCall => isId ? 'Akhiri' : 'End';
  String get btnMute => isId ? 'Bisukan' : 'Mute';
  String get btnUnmute => isId ? 'Bunyikan' : 'Unmute';
  String get btnSpeaker => isId ? 'Speaker' : 'Speaker';
  String get btnSwitchCamera => isId ? 'Balik Kamera' : 'Flip';
  String get callNotifActiveAudio =>
      isId ? 'Panggilan suara aktif' : 'Active voice call';
  String get callNotifActiveVideo =>
      isId ? 'Panggilan video aktif' : 'Active video call';
  String get msgCallEnded => isId ? 'Panggilan berakhir' : 'Call ended';
  String get msgCallDeclined => isId ? 'Panggilan ditolak' : 'Call declined';
  String get msgCallBusy => isId ? 'Sedang sibuk' : 'Busy';
  String get msgCallMissed => isId ? 'Panggilan tidak dijawab' : 'Missed call';
  String get msgCallError =>
      isId ? 'Panggilan gagal terhubung' : 'Call failed to connect';
  String get msgCallRegisterOnly => isId
      ? 'Hanya akun terdaftar yang bisa melakukan panggilan.'
      : 'Only registered accounts can make calls.';
  String get msgCallInProgress =>
      isId ? 'Kamu sedang dalam panggilan lain.' : 'You are in another call.';
  String get callBannerTap =>
      isId ? 'Ketuk untuk kembali ke panggilan' : 'Tap to return to call';

  // ── Admin: monitor panggilan ──
  String get recStart =>
      isId ? 'Mulai rekam panggilan' : 'Start recording call';
  String get recStop => isId ? 'Hentikan rekaman' : 'Stop recording';
  String get recSavedTo => isId ? 'Rekaman disimpan di' : 'Recording saved to';
  String get recNoMedia => isId
      ? 'Belum ada media untuk direkam'
      : 'No media connected to record yet';
  String get recStorageDenied => isId
      ? 'Izin akses penyimpanan diperlukan untuk menyimpan rekaman'
      : 'Storage access permission is required to save recordings';

  // ── Errors / Generic ──
  String get btnCancel => isId ? 'Batal' : 'Cancel';
  String get btnClose => isId ? 'Tutup' : 'Close';
  String get msgStartConversation =>
      isId ? 'Mulai percakapan!' : 'Start the conversation!';
  String get errGeneric => isId ? 'Gagal: ' : 'Failed: ';
  String get errUserNotFound =>
      isId ? 'Pengguna tidak ditemukan' : 'User not found';
  String get loading => isId ? 'Memuat...' : 'Loading...';
  String get unknownUser => isId ? 'Pengguna' : 'User';

  // ── Auth Email / Register / Login ──
  String get labelEmail => isId ? 'Email' : 'Email';
  String get labelPassword => isId ? 'Password' : 'Password';
  String get labelConfirmPassword =>
      isId ? 'Konfirmasi Password' : 'Confirm Password';
  String get hintEmail =>
      isId ? 'Masukkan email kamu...' : 'Enter your email...';
  String get hintPassword =>
      isId ? 'Minimal 8 karakter' : 'At least 8 characters';
  String get btnRegister => isId ? 'DAFTAR' : 'REGISTER';
  String get btnLogin => isId ? 'MASUK' : 'LOGIN';
  String get btnRegisterEmail =>
      isId ? 'Daftar dengan Email' : 'Register with Email';
  String get btnLoginEmail =>
      isId ? 'Sudah punya akun? Login' : 'Already have an account? Login';
  String get btnForgotPassword => isId ? 'Lupa Password?' : 'Forgot Password?';
  String get btnSendReset => isId ? 'Kirim Link Reset' : 'Send Reset Link';
  String get titleRegister => isId ? 'Buat Akun' : 'Create Account';
  String get titleLogin => isId ? 'Masuk' : 'Login';
  String get titleForgotPassword => isId ? 'Reset Password' : 'Reset Password';
  String get titleLinkEmail => isId ? 'Amankan Akun' : 'Secure Account';
  String get titleAccountSecurity =>
      isId ? 'Keamanan Akun' : 'Account Security';
  String get msgVerifyEmail => isId
      ? 'Link verifikasi dikirim ke email kamu. Cek inbox dan klik link untuk mengaktifkan akun.'
      : 'Verification link sent to your email. Check your inbox and click the link to activate your account.';
  String get msgPasswordResetSent => isId
      ? 'Link reset password dikirim ke email kamu.'
      : 'Password reset link sent to your email.';
  String get msgEmailNotRegistered => isId
      ? 'Email belum terdaftar. Daftar dulu untuk membuat akun.'
      : 'Email is not registered. Register first to create an account.';
  String get msgPasswordResetFailed => isId
      ? 'Gagal mengirim link reset. Coba lagi nanti.'
      : 'Failed to send reset link. Please try again later.';
  String get titleSetNewPassword =>
      isId ? 'Buat Password Baru' : 'Set New Password';
  String get msgSetNewPasswordHint => isId
      ? 'Masukkan password baru untuk akun kamu'
      : 'Enter a new password for your account';
  String get btnSavePassword => isId ? 'Simpan Password' : 'Save Password';
  String get msgPasswordChanged => isId
      ? 'Password berhasil diubah. Silakan login ulang.'
      : 'Password changed. Please log in again.';
  String get errChangePassword =>
      isId ? 'Gagal mengubah password: ' : 'Failed to change password: ';
  String get btnSetPassword => isId ? 'Set Password' : 'Set Password';
  String get btnChangePassword => isId ? 'Ganti Password' : 'Change Password';
  String get descSetPassword => isId
      ? 'Akun Google kamu belum punya password. Buat sekarang agar bisa login pakai email + password.'
      : 'Your Google account has no password yet. Set one to log in with email + password.';
  String get descChangePassword => isId
      ? 'Ganti password untuk keamanan akun kamu'
      : 'Change your password for better account security';
  String get labelCurrentPassword =>
      isId ? 'Password Saat Ini' : 'Current Password';
  String get msgPasswordSet => isId
      ? 'Password berhasil dibuat. Kamu sekarang bisa login pakai email + password.'
      : 'Password set successfully. You can now log in with email + password.';
  String get errCurrentPasswordWrong =>
      isId ? 'Password saat ini salah' : 'Current password is incorrect';
  String get msgAccountLinked => isId
      ? 'Email berhasil didaftarkan. Akun kamu sekarang aman.'
      : 'Email registered successfully. Your account is now secured.';
  String get msgAnonymousWarning => isId
      ? 'Akun anonim tidak bisa dipulihkan jika logout. Daftarkan email untuk mengamankan data kamu.'
      : 'Anonymous accounts cannot be recovered after logout. Register your email to secure your data.';
  String get labelSecuredAccount => isId ? 'Akun Email' : 'Email Account';
  String get btnSecureAccount => isId ? 'Daftarkan Email' : 'Register Email';
  String get errEmailEmpty =>
      isId ? 'Masukkan email dulu' : 'Please enter your email';
  String get errEmailInvalid =>
      isId ? 'Format email tidak valid' : 'Invalid email format';
  String get errPasswordShort => isId
      ? 'Password minimal 8 karakter'
      : 'Password must be at least 8 characters';
  String get errPasswordMismatch =>
      isId ? 'Password tidak cocok' : 'Passwords do not match';
  String get errEmailAlreadyUsed =>
      isId ? 'Email sudah digunakan' : 'Email already in use';
  String get errInvalidCredentials =>
      isId ? 'Email atau password salah' : 'Invalid email or password';
  String get errNicknameTaken => isId
      ? 'Nickname sudah digunakan, pilih yang lain'
      : 'Nickname already taken, choose another';
  String get errEmailNotVerified => isId
      ? 'Email belum diverifikasi. Cek inbox kamu.'
      : 'Email not verified. Check your inbox.';
  String get msgEmailAlreadyRegisteredResend => isId
      ? 'Email sudah terdaftar tapi belum diverifikasi. Link verifikasi dikirim ulang ke inbox kamu.'
      : 'Email registered but not verified. Verification link resent to your inbox.';
  String get msgCompleteProfile => isId
      ? 'Lengkapi profil untuk melanjutkan'
      : 'Complete your profile to continue';
  String get titleVerifyEmail => isId ? 'Verifikasi Email' : 'Verify Email';
  String get msgVerifyCodeSent => isId
      ? 'Kode verifikasi dikirim ke email kamu. Masukkan kode 6 digit di bawah.'
      : 'A verification code was sent to your email. Enter the 6-digit code below.';
  String get hintVerifyCode => isId ? 'Kode 6 digit' : '6-digit code';
  String get btnVerify => isId ? 'Verifikasi' : 'Verify';
  String get btnResendCode => isId ? 'Kirim Ulang Kode' : 'Resend Code';
  String get msgResendCodeSent => isId
      ? 'Kode baru dikirim ke email kamu.'
      : 'A new code was sent to your email.';
  String get errInvalidCode =>
      isId ? 'Kode tidak valid. Coba lagi.' : 'Invalid code. Please try again.';
  String get msgEmailVerified =>
      isId ? 'Email terverifikasi!' : 'Email verified!';
  String get labelEmailVerified =>
      isId ? 'Email Terverifikasi' : 'Email Verified';
  String get labelEmailUnverified =>
      isId ? 'Email Belum Terverifikasi' : 'Email Not Verified';
  String get msgVerifyToUsePaid => isId
      ? 'Verifikasi email dulu untuk memakai fitur ini.'
      : 'Verify your email to use this feature.';

  // ── Google Sign-In / Account Linking ──
  String get btnLinkAccount => isId ? 'Hubungkan Akun?' : 'Link Account?';
  String get btnCreateNew => isId ? 'Buat Baru' : 'Create New';
  String get btnUseExisting => isId ? 'Pakai Profil Lama' : 'Use Existing';
  String get btnContinueGoogle =>
      isId ? 'Lanjutkan dengan Google' : 'Continue with Google';
  String get errGoogleSignIn =>
      isId ? 'Google sign in gagal: ' : 'Google sign in failed: ';
  String get labelOr => isId ? 'atau' : 'or';

  /// Pesan konfirmasi link akun dengan nickname akun lama.
  String msgLinkPrompt(String nickname) => isId
      ? 'Email ini sudah terdaftar sebagai "$nickname". Mau pakai profil yang sudah ada?'
      : 'This email is already registered as "$nickname". Use the existing profile?';

  // ── Username / Nickname ──
  String get btnChangeUsername => isId ? 'Ganti Username' : 'Change Username';
  String get msgUsernameOldReleased => isId
      ? 'Username lama akan langsung bisa dipakai orang lain.'
      : 'Your old username will be immediately available for others.';

  // ── Donasi ──
  String get titleDonate => isId ? 'Donasi' : 'Donate';
  String get labelQris => isId ? 'QRIS' : 'QRIS';
  String get labelUsdt => isId ? 'USDT Crypto' : 'USDT Crypto';
  String get msgCopied =>
      isId ? ' disalin ke clipboard' : ' copied to clipboard';
  String get btnCopyAddress => isId ? 'Salin Alamat ' : 'Copy Address ';
  String get donateSelectHint => isId
      ? 'Pilih network dan salin alamat wallet'
      : 'Choose a network and copy the wallet address';
  String get donateWrongNetwork => isId
      ? 'Pastikan kamu mengirim ke network yang benar. Mengirim ke network yang salah dapat menyebabkan dana hilang.'
      : 'Make sure you send to the correct network. Sending to the wrong network may cause funds to be lost.';
  String get donateScanQris =>
      isId ? 'Scan QRIS untuk donasi' : 'Scan QRIS to donate';
  String get donateQrisInfo => isId
      ? 'QRIS dapat digunakan di semua aplikasi dompet digital dan mobile banking Indonesia (GoPay, OVO, Dana, BCA, Mandiri, dll)'
      : 'QRIS works with all Indonesian digital wallets and mobile banking apps (GoPay, OVO, Dana, BCA, Mandiri, etc.)';
  String get donateThankYou => isId ? 'Terima Kasih!' : 'Thank You!';
  String get donateThanksMsg => isId
      ? 'Donasi kamu membantu pengembangan ChatYuk agar terus gratis dan bebas iklan.'
      : 'Your donation helps keep ChatYuk free and ad-free.';

  // ── Kontak ──
  String get titleContact => isId ? 'Hubungi Kami' : 'Contact Us';
  String get contactNameLabel => isId ? 'Nama (opsional)' : 'Name (optional)';
  String get contactMessageLabel => isId ? 'Pesan' : 'Message';
  String get contactMessageHint =>
      isId ? 'Tulis pesan kamu...' : 'Write your message...';
  String get contactSend => isId ? 'Kirim' : 'Send';
  String get contactSent => isId ? 'Pesan terkirim' : 'Message sent';
  String get contactFailed =>
      isId ? 'Gagal mengirim. Coba lagi.' : 'Failed to send. Try again.';
  String get contactEmpty =>
      isId ? 'Pesan tidak boleh kosong' : 'Message cannot be empty';
  String get labelNew => isId ? 'Baru' : 'New';
  String get labelRead => isId ? 'Terbaca' : 'Read';

  // ── Legal / Persetujuan ──
  String get legalAgreementPre => isId
      ? 'Dengan melanjutkan untuk masuk, kamu menyetujui '
      : 'By continuing to log in, you agree to our ';
  String get legalAgreementAnd => isId ? ' dan ' : ' and ';
  String get legalPrivacyPolicy =>
      isId ? 'Kebijakan Privasi' : 'Privacy Policy';
  String get legalServiceAgreement =>
      isId ? 'Perjanjian Layanan Pengguna' : 'User Service Agreement';
  String get legalPrivacyTitle => isId ? 'Kebijakan Privasi' : 'Privacy Policy';
  String get legalTermsTitle =>
      isId ? 'Perjanjian Layanan Pengguna' : 'User Service Agreement';
  String get legalLastUpdated => isId
      ? 'Terakhir diperbarui: 18 Agustus 2026'
      : 'Last updated: August 18, 2026';
  String get legalPrivacyDocTitle => isId
      ? 'KEBIJAKAN PRIVASI APLIKASI CHATYUK'
      : 'CHATYUK APPLICATION PRIVACY POLICY';
  String get legalPrivacyEffective => isId
      ? 'Berlaku efektif sejak: [TANGGAL — diisi pada saat peluncuran]'
      : 'Effective as of: [DATE — to be filled at launch]';
  String get legalPrivacyVersion => isId
      ? 'Versi Dokumen: 2.0 (Rancangan — menunggu penelaahan akhir oleh konsultan hukum)'
      : 'Document Version: 2.0 (Draft — pending final review by legal counsel)';
  String get legalNoticeTitle =>
      isId ? 'Pemberitahuan Penyusunan Dokumen' : 'Document Drafting Notice';
  String get legalNoticeText => isId
      ? 'Dokumen ini disusun secara komprehensif dengan merujuk pada prinsip dan ketentuan sebagaimana diatur dalam Undang-Undang Republik Indonesia Nomor 27 Tahun 2022 tentang Pelindungan Data Pribadi ("**UU PDP**"), Undang-Undang Nomor 11 Tahun 2008 sebagaimana diubah dengan Undang-Undang Nomor 19 Tahun 2016 tentang Informasi dan Transaksi Elektronik ("**UU ITE**"), serta — mengingat Aplikasi disediakan dan dapat diakses oleh Pengguna di berbagai negara — prinsip-prinsip pelindungan data pribadi yang bersifat lintas yurisdiksi, termasuk namun tidak terbatas pada *General Data Protection Regulation* Uni Eropa ("**GDPR**"), *California Consumer Privacy Act* sebagaimana diubah dengan *California Privacy Rights Act* ("**CCPA/CPRA**"), serta kerangka pelindungan data pribadi negara-negara lain sebagaimana relevan. Dokumen ini merupakan rancangan kerja (*working draft*) dan **tidak dimaksudkan serta tidak dapat dijadikan sebagai pengganti nasihat hukum profesional**. Mengingat Aplikasi beroperasi secara global, Penyelenggara dengan ini menyarankan agar dokumen ini ditelaah dan disahkan oleh konsultan hukum yang berkompeten di bidang pelindungan data pribadi lintas yurisdiksi (khususnya hukum Indonesia, GDPR Uni Eropa, dan CCPA/CPRA Amerika Serikat), sebelum dipublikasikan secara resmi kepada Pengguna.'
      : 'This document has been comprehensively drafted with reference to the principles and provisions set out in Law of the Republic of Indonesia Number 27 of 2022 on Personal Data Protection (the "**PDP Law**"), Law Number 11 of 2008 as amended by Law Number 19 of 2016 on Electronic Information and Transactions (the "**EIT Law**"), as well as — given that the Application is provided and accessible to Users in various countries — cross-jurisdictional personal data protection principles, including but not limited to the European Union *General Data Protection Regulation* (the "**GDPR**"), the *California Consumer Privacy Act* as amended by the *California Privacy Rights Act* (the "**CCPA/CPRA**"), and the personal data protection frameworks of other countries as relevant. This document is a working draft and is **not intended and cannot be used as a substitute for professional legal advice**. Given that the Application operates globally, the Operator hereby recommends that this document be reviewed and validated by legal counsel competent in cross-jurisdictional personal data protection (in particular Indonesian law, the EU GDPR, and the CCPA/CPRA of the United States), before it is officially published to Users.';
  List<LegalSection> get legalPrivacySections => isId ? _privacyId : _privacyEn;
  String get legalTermsDocTitle => isId
      ? 'SYARAT DAN KETENTUAN LAYANAN APLIKASI CHATYUK'
      : 'CHATYUK APPLICATION TERMS OF SERVICE';
  String get legalTermsEffective => isId
      ? 'Berlaku efektif sejak: [TANGGAL — diisi pada saat peluncuran]'
      : 'Effective as of: [DATE — to be filled at launch]';
  String get legalTermsVersion => isId
      ? 'Versi Dokumen: 1.1 (Rancangan — menunggu penelaahan akhir oleh konsultan hukum)'
      : 'Document Version: 1.1 (Draft — pending final review by legal counsel)';
  String get legalTermsNoticeTitle =>
      isId ? 'Pemberitahuan Penyusunan Dokumen' : 'Document Drafting Notice';
  String get legalTermsNoticeText => isId
      ? 'Dokumen ini disusun secara komprehensif dengan merujuk pada prinsip dan ketentuan sebagaimana diatur dalam Undang-Undang Republik Indonesia Nomor 11 Tahun 2008 sebagaimana diubah dengan Undang-Undang Nomor 19 Tahun 2016 tentang Informasi dan Transaksi Elektronik ("**UU ITE**"), Undang-Undang Republik Indonesia Nomor 27 Tahun 2022 tentang Pelindungan Data Pribadi ("**UU PDP**"), Kitab Undang-Undang Hukum Perdata ("**KUHPerdata**"), serta prinsip-prinsip hukum kontrak elektronik dan pelindungan konsumen yang bersifat lintas yurisdiksi bagi Pengguna di Uni Eropa, Inggris Raya, dan Amerika Serikat. Dokumen ini merupakan rancangan kerja (*working draft*) dan **tidak dimaksudkan serta tidak dapat dijadikan sebagai pengganti nasihat hukum profesional**. Penyelenggara dengan ini menyarankan agar dokumen ini ditelaah dan disahkan oleh konsultan hukum yang berkompeten sebelum dipublikasikan secara resmi kepada Pengguna.'
      : 'This document has been comprehensively drafted with reference to the principles and provisions set out in Law of the Republic of Indonesia Number 11 of 2008 as amended by Law Number 19 of 2016 on Electronic Information and Transactions (the "**EIT Law**"), Law of the Republic of Indonesia Number 27 of 2022 on Personal Data Protection (the "**PDP Law**"), the Indonesian Civil Code (the "**Civil Code**"), as well as cross-jurisdictional electronic contract and consumer protection principles for Users in the European Union, the United Kingdom, and the United States. This document is a working draft and is **not intended and cannot be used as a substitute for professional legal advice**. The Operator hereby recommends that this document be reviewed and validated by competent legal counsel before it is officially published to Users.';
  List<LegalSection> get legalTermsSections => isId ? _termsId : _termsEn;
  // ── Screenshot admin ──

  // ── Watermark admin ──

  // ── Invisible admin ──

  // ── Wajib registrasi admin ──
  String get labelRequireRegistration => isId
      ? 'Wajib daftar sebelum masuk'
      : 'Require registration before entering';
  String get descRequireRegistration => isId
      ? 'Admin — sembunyikan "Mulai Chat Sekarang", hanya Login Google & Daftar Email'
      : 'Admin — hide "Start Chatting Now", only Google Login & Email Sign Up';

  // ── Points ──
  String get pointsTitle => isId ? 'Poin ChatYuk' : 'ChatYuk Points';
  String get pointsBalance => isId ? 'Poin' : 'Points';
  String get pointsSafe => isId ? '✅ Aman selamanya' : '✅ Safe forever';
  String get pointsAnonymousLose => isId
      ? 'Poin akan hilang kalau kamu logout atau ganti HP'
      : 'Points will be lost if you logout or switch phones';
  String get pointsRegisterBonusLabel =>
      isId ? '+100 daftar email' : '+100 register email';
  // Parameterized (Dart tak dukung %d — pakai fungsi)
  String pointsDeduct(int n) => isId ? '-$n Poin' : '-$n Points';
  String pointsGain(int n, String reason) =>
      isId ? '+$n Poin — $reason' : '+$n Points — $reason';
  String pointsStreakToast(int day, int n) => isId
      ? '🔥 Streak $day hari — +$n Poin'
      : '🔥 $day-day streak — +$n Points';
  String pointsMoreMessages(int n) =>
      isId ? '≈ $n pesan lagi' : '≈ $n more messages';
  // Alasan bonus (dipakai pointsGain)
  String get reasonFirstPhoto => isId ? 'Foto pertama' : 'First photo';
  String get reasonRoomRead => isId ? 'Baca room' : 'Room read';
  String get reasonRoomChat => isId ? 'Chat room' : 'Room chat';
  String get reasonProfileComplete =>
      isId ? 'Profil lengkap' : 'Profile complete';
  String get reasonShare => isId ? 'Share' : 'Share';
  String get reasonNewChat => isId ? 'Chat orang baru' : 'New chat';
  String get reasonRegister => isId ? 'Daftar email' : 'Register';
  String get reasonPhotoUpload => isId ? 'Upload foto' : 'Photo upload';
  // ── Share / Ajak teman ──
  String get shareInviteTitle => isId ? 'Ajak Teman' : 'Invite Friends';
  String shareInviteMsg(String link) => isId
      ? 'Ayo chat bareng di ChatYuk! Download sekarang:\n$link'
      : 'Chat with me on ChatYuk! Download now:\n$link';
  String get shareTooltip => isId ? 'Ajak Teman' : 'Invite Friends';
  // ── Foto terkunci (paywall) ──
  String get photoLockedTitle => isId ? 'Foto Terkunci' : 'Locked Photo';
  String get photoLockedHint =>
      isId ? 'Buka foto ini untuk melihatnya' : 'Unlock this photo to view it';
  String photoUnlockOnce(int c) =>
      isId ? 'Lihat sekali · $c koin' : 'View once · $c coins';
  String photoUnlockPerm(int c) =>
      isId ? 'Buka permanen · $c koin' : 'Unlock forever · $c coins';
  String get photoUnlockNeedTopup => isId
      ? 'Koin tidak cukup. Dapatkan koin dari bonus harian & aktivitas.'
      : 'Not enough coins. Earn coins from daily bonuses & activities.';
  String get photoUnlockFailed =>
      isId ? 'Gagal membuka foto' : 'Failed to unlock photo';
  String get photoUnlockedToast => isId ? 'Foto terbuka' : 'Photo unlocked';
  // ── History Poin ──
  String get pointHistoryTitle => isId ? 'History Poin' : 'Point History';
  String get pointHistoryEmpty =>
      isId ? 'Belum ada transaksi' : 'No transactions yet';
  String get pointHistoryCredit => isId ? 'Masuk' : 'In';
  String get pointHistoryDebit => isId ? 'Keluar' : 'Out';
  String get pointHistoryCoin => isId ? 'koin' : 'coins';
  String get pointHistoryDeductText =>
      isId ? 'Kirim pesan teks' : 'Send text message';
  String get pointHistoryDeductImage => isId ? 'Kirim foto' : 'Send photo';
  String get pointHistoryDeductViewOnce =>
      isId ? 'Kirim foto sekali lihat' : 'Send view-once photo';
  String get pointHistoryDailyLogin => isId ? 'Login harian' : 'Daily login';
  String get pointHistoryStreakBonus => isId ? 'Bonus streak' : 'Streak bonus';
  String get pointHistoryNewChat => isId ? 'Chat orang baru' : 'New chat';
  String get pointHistoryRoomRead => isId ? 'Baca room' : 'Room read';
  String get pointHistoryRoomChat => isId ? 'Chat room' : 'Room chat';
  String get pointHistoryRegister => isId ? 'Daftar email' : 'Register email';
  String get pointHistoryFirstPhoto => isId ? 'Foto pertama' : 'First photo';
  String get pointHistoryRateApp => isId ? 'Rating app' : 'Rate app';
  String get pointHistoryShare => isId ? 'Share app' : 'Share app';
  String get pointHistoryProfile =>
      isId ? 'Lengkapi profil' : 'Complete profile';
  String get pointHistoryOnline5 => isId ? 'Online 5 menit' : 'Online 5 min';
  String get pointHistoryOnline30 => isId ? 'Online 30 menit' : 'Online 30 min';
  String get pointHistoryOnline60 => isId ? 'Online 60 menit' : 'Online 60 min';
  String get pointHistoryOnline120 =>
      isId ? 'Online 120 menit' : 'Online 120 min';
  String get pointHistoryWeeklyQuest =>
      isId ? 'Misi mingguan' : 'Weekly mission';
  String get pointHistoryCoinSent => isId ? 'Kirim koin' : 'Send coins';
  String get pointHistoryCoinReceived => isId ? 'Terima koin' : 'Receive coins';
  String get pointHistoryRoomCreate =>
      isId ? 'Buat room private' : 'Create private room';
  String get pointHistoryRoomJoin =>
      isId ? 'Join room private' : 'Join private room';
  String get pointHistoryRoomIncome => isId ? 'Pendapatan room' : 'Room income';
  String get pointHistoryRoomExtend => isId ? 'Perpanjang room' : 'Extend room';
  String get pointHistoryAdminBonus => isId ? 'Bonus admin' : 'Admin bonus';
  String get pointHistoryAdminReset => isId ? 'Reset poin' : 'Points reset';
  String get pointHistoryOther =>
      isId ? 'Transaksi poin' : 'Points transaction';
  // ── Wallet (saldo koin) ──
  String get walletBucketBonus => isId ? 'Koin bonus' : 'Bonus coins';
  String get walletBucketTopup => isId ? 'Koin pro' : 'Pro coins';
  String get walletBucketEarned => isId ? 'Koin hadiah' : 'Gift coins';
  String get walletTitle => isId ? 'Dompet Koin' : 'Coin Wallet';
  String get walletTotal => isId ? 'Total koin' : 'Total coins';
  // ── Gift (hadiah) ──
  String get giftTitle => isId ? 'Kirim Hadiah' : 'Send Gift';
  String get giftPick =>
      isId ? 'Pilih hadiah untuk dikirim' : 'Pick a gift to send';
  String giftBubbleSent(String name) =>
      isId ? '🎁 Kamu mengirim $name' : '🎁 You sent $name';
  String giftBubbleReceived(String name) =>
      isId ? '🎁 Menerima $name' : '🎁 Received $name';
  String giftSentToast(String name) =>
      isId ? 'Hadiah $name terkirim!' : 'Gift $name sent!';
  String get giftInsufficient => isId
      ? 'Koin tidak cukup untuk hadiah ini'
      : 'Not enough coins for this gift';
  String get menuSendGift => isId ? 'Hadiah' : 'Gift';
  // ── Leaderboard ──
  String get lbTitle => isId ? 'Papan Peringkat' : 'Leaderboard';
  String get lbWeekly => isId ? 'Mingguan' : 'Weekly';
  String get lbAllTime => isId ? 'Sepanjang Masa' : 'All-Time';
  String get lbYourRank => isId ? 'Peringkat kamu' : 'Your rank';
  String get lbEmpty =>
      isId ? 'Belum ada data peringkat' : 'No leaderboard data yet';
  String get lbUnranked => isId ? 'Belum masuk peringkat' : 'Not ranked yet';
  String get lbWeeklyHint =>
      isId ? 'Poin didapat 7 hari terakhir' : 'Points earned in last 7 days';
  String get lbAllTimeHint =>
      isId ? 'Total saldo poin' : 'Total points balance';
  // ── Misi Point ──
  String get missionsTitle => isId ? 'Misi Point' : 'Point Missions';
  String get missionsDaily => isId ? 'Harian' : 'Daily';
  String get missionsWeekly => isId ? 'Mingguan' : 'Weekly';
  String get missionsOnce => isId ? 'Sekali' : 'One-Time';
  String get missionsDailyHint => isId
      ? 'Reset tiap hari — otomatis dapat saat selesai'
      : 'Resets daily — auto-awarded on completion';
  String get missionsWeeklyHint => isId
      ? 'Reset tiap minggu — klaim manual saat selesai'
      : 'Resets weekly — claim manually when done';
  String get missionsOnceHint =>
      isId ? 'Hanya bisa didapat sekali' : 'Can only be earned once';
  String get missionsEmpty => isId ? 'Belum ada misi' : 'No missions';
  String get missionDone => isId ? 'Selesai' : 'Done';
  String get missionClaim => isId ? 'Klaim' : 'Claim';
  String get missionClaimed => isId ? 'Sudah diklaim' : 'Claimed';
  String missionClaimedToast(int n) =>
      isId ? '+$n Poin — Misi mingguan!' : '+$n Points — Weekly mission!';
  String get missionsMyPoints => isId ? 'Poin kamu' : 'Your points';
  String missionsProgress(int done, int total) =>
      isId ? '$done dari $total selesai' : '$done of $total done';
  String get missionsAllDone =>
      isId ? 'Semua misi selesai! 🎉' : 'All missions done! 🎉';
  String get missionsReadyClaim => isId ? 'Siap diklaim!' : 'Ready to claim!';
  // Nama misi
  String get mDailyLogin => isId ? 'Login harian' : 'Daily login';
  String get mRoomRead => isId ? 'Baca room' : 'Read rooms';
  String get mNewChat => isId ? 'Chat orang baru' : 'Chat new people';
  String get mOnline5 => isId ? 'Online 5 menit' : 'Online 5 min';
  String get mOnline30 => isId ? 'Online 30 menit' : 'Online 30 min';
  String get mOnline60 => isId ? 'Online 60 menit' : 'Online 60 min';
  String get mOnline120 => isId ? 'Online 120 menit' : 'Online 120 min';
  String get mwLogin => isId ? 'Login 5 hari' : 'Login 5 days';
  String get mwSocial => isId ? 'Chat 10 orang baru' : 'Chat 10 new people';
  String get mwActive => isId ? 'Kirim 100 pesan' : 'Send 100 messages';
  String get mRegistered => isId ? 'Daftar email' : 'Register email';
  String get mRatedApp => isId ? 'Rate aplikasi' : 'Rate the app';
  String get mCompletedProfile => isId ? 'Lengkapi profil' : 'Complete profile';
  String get mInvitedFriend => isId ? 'Invite teman' : 'Invite a friend';
  String get mFirstPhoto => isId ? 'Kirim foto pertama' : 'Send first photo';
  String get mFirstRoomChat => isId ? 'Chat room pertama' : 'First room chat';
  String get btnRetry => isId ? 'Coba Lagi' : 'Retry';
  String get msgServerError =>
      isId ? 'Gagal terhubung ke server' : 'Failed to connect to server';
  String get msgServerErrorHint => isId
      ? 'Periksa koneksi internet kamu, lalu coba lagi.'
      : 'Check your internet connection and try again.';
  String get msgFileTooLarge => isId
      ? 'File terlalu besar. Maksimal 10MB.'
      : 'File too large. Maximum 10MB.';
  String get btnEmoji => isId ? 'Emoji' : 'Emoji';
  String get tooltipResize =>
      isId ? 'Geser untuk mengubah ukuran' : 'Drag to resize';
  String get tooltipPhoto => isId ? 'Foto' : 'Photo';
  String get labelGenderFilter => isId ? 'Gender' : 'Gender';
  String get btnDelete => isId ? 'Hapus' : 'Delete';
  String get confirmDeletePost =>
      isId ? 'Yakin ingin menghapus postingan ini?' : 'Delete this post?';
  String get postDeleted => isId ? 'Postingan dihapus' : 'Post deleted';
  String get errDeletePost =>
      isId ? 'Gagal menghapus postingan' : 'Failed to delete post';
  String get statsUsers => isId ? 'Users' : 'Users';
  String get statsActive => isId ? 'Active' : 'Active';
  String get statsMsgs => isId ? 'Msgs' : 'Msgs';
  String get statsRooms => isId ? 'Rooms' : 'Rooms';
  String get statsReg => isId ? 'Reg.' : 'Reg.';
  String get statsAnon => isId ? 'Anon' : 'Anon';
  String get statsAvg => isId ? 'Avg' : 'Avg';
  String get statsTotal => isId ? 'Total' : 'Total';
  String get roomPrivateLabel => isId ? 'Privat' : 'Private';
  String get btnSend => isId ? 'Kirim' : 'Send';
  String get onlineActiveUsers => isId ? 'pengguna aktif' : 'active users';
  String get labelVerified => isId ? 'Terverifikasi' : 'Verified';
  String get lobbyCountryHint => isId ? 'Negara / Country' : 'Country / Negara';
  String get donateCopyAddress => isId ? 'Salin Alamat ' : 'Copy Address ';
  String get googleSignInFailed =>
      isId ? 'Google sign in gagal: ' : 'Google sign in failed: ';

  // ── Admin Chat Monitor ──
  List<String> get monthShort => isId
      ? const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'Mei',
          'Jun',
          'Jul',
          'Agu',
          'Sep',
          'Okt',
          'Nov',
          'Des',
        ]
      : const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
  String get locPrecisionTitle => isId ? 'Lokasi Presisi' : 'Precise Location';
  String get locPrecisionOff => isId
      ? 'Lokasi presisi nonaktif — posisi hanya perkiraan'
      : 'Precise location off — position is approximate';
  String get locOpenSettings => isId ? 'Buka Pengaturan' : 'Open Settings';
  String get locSharePromptTitle => isId ? 'Aktifkan GPS' : 'Enable GPS';
  String get locSharePromptBody => isId
      ? 'Bagikan lokasi butuh akses GPS. Izinkan akses lokasi supaya posisimu akurat.'
      : 'Sharing your location needs GPS access. Allow location access for an accurate position.';
  String get locOnlinePromptBody => isId
      ? 'Izinkan akses lokasi supaya pengguna lain bisa melihat lokasimu dan fitur orang sekitar berfungsi.'
      : 'Allow location access so others can see your location and the nearby feature works.';
  String get chatMsgCount => isId ? 'pesan' : 'messages';

  // ── Admin Dummy Accounts ──

  // ── Sosial (Follow / Friend / Subscribe) ──
  String get socialFollowers => isId ? 'Pengikut' : 'Followers';
  String get socialFollowing => isId ? 'Mengikuti' : 'Following';
  String get socialFriends => isId ? 'Teman' : 'Friends';
  String get socialSubscribers => isId ? 'Subscriber' : 'Subscribers';
  String get btnFollow => isId ? 'Ikuti' : 'Follow';
  String get btnUnfollow => isId ? 'Berhenti Ikuti' : 'Unfollow';
  String get btnAddFriend => isId ? 'Tambah Teman' : 'Add Friend';
  String get btnFriendRequested => isId ? 'Terkirim' : 'Sent';
  String get btnFriendPending => isId ? 'Terima Permintaan' : 'Accept Request';
  String get btnFriends => isId ? 'Teman' : 'Friends';
  String get btnSubscribe => isId ? 'Subscribe' : 'Subscribe';
  String get btnSubscribed => isId ? 'Berlangganan' : 'Subscribed';
  String get btnUnsubscribe => isId ? 'Berhenti Berlangganan' : 'Unsubscribe';
  String get friendRequestTitle =>
      isId ? 'Permintaan Teman' : 'Friend Requests';
  String get friendRequestEmpty =>
      isId ? 'Belum ada permintaan teman' : 'No friend requests yet';
  String get friendRequestSent =>
      isId ? 'Permintaan teman terkirim' : 'Friend request sent';
  String get friendRequestAccepted =>
      isId ? 'Permintaan teman diterima' : 'Friend request accepted';
  String get subscriptionsTitle => isId ? 'Langganan' : 'Subscriptions';
  String get subscriptionsEmpty =>
      isId ? 'Belum ada langganan' : 'No subscriptions yet';
  String subscribePrice(int c) => isId ? '$c koin / bulan' : '$c coins / month';
  String get subscribePriceSuffix => isId ? '🪙 / bulan' : '🪙 / month';
  String get subscribeConfirmTitle => isId ? 'Subscribe' : 'Subscribe';
  String subscribeConfirmBody(String name, int c, int periods) => isId
      ? 'Berlangganan ke $name selama $periods bulan seharga ${c * periods} koin?'
      : 'Subscribe to $name for $periods months at ${c * periods} coins?';
  String get subscribeSuccess => isId ? 'Berhasil berlangganan' : 'Subscribed';
  String get subscribeNeedPaid => isId
      ? 'Koin pro tidak cukup. Top up dulu.'
      : 'Not enough pro coins. Top up first.';
  String get subscribeNeedRegister => isId
      ? 'Hanya akun terdaftar yang bisa subscribe'
      : 'Only registered accounts can subscribe';
  String get setSubPriceTitle =>
      isId ? 'Harga Subscribe' : 'Subscription Price';
  String get setSubPriceHint =>
      isId ? '0 = nonaktif (gratis diikuti)' : '0 = disabled (free to follow)';
  String get socialListEmpty => isId ? 'Belum ada data' : 'No data yet';
  String get paidBalanceLabel => isId ? 'Koin pro' : 'Pro coins';
  String get bonusBalanceLabel => isId ? 'Koin bonus' : 'Bonus coins';
  String paidOrBonus(int paid, int bonus) => isId
      ? 'Koin pro $paid · atau bonus $bonus'
      : 'Pro $paid · or bonus $bonus';
  String get menuFollow => isId ? 'Ikuti' : 'Follow';
  String get menuAddFriend => isId ? 'Tambah Teman' : 'Add Friend';
  String get needRegisteredForPaid => isId
      ? 'Fitur ini butuh akun terdaftar & koin pro'
      : 'This feature needs a registered account & pro coins';
  // ── Subscribe: penjelasan buat fans & creator ──
  String get subscribeWhatIs =>
      isId ? 'Apa itu Subscribe?' : 'What is Subscribe?';
  String get subscribeExplain => isId
      ? 'Dukung kreator favoritmu setiap bulan. Koin yang kamu bayar menjadi penghasilan kreator, dan platform mengambil potongan kecil untuk biaya operasional.'
      : 'Support your favorite creator monthly. Your coins become the creator\'s income, and the platform takes a small cut for operating costs.';
  String get subscribeFansHint => isId
      ? 'Berlangganan untuk mendukung kreator ini. Koin dibayar pakai koin pro.'
      : 'Subscribe to support this creator. Paid with pro coins.';
  String get subscribeCreatorHint => isId
      ? 'Jadilah kreator: pasang harga langganan bulanan. Fans yang subscribe memberimu penghasilan.'
      : 'Become a creator: set a monthly subscription price. Fans who subscribe become your income.';
  String get subscriptionsEmptyHint => isId
      ? 'Kamu belum berlangganan ke kreator mana pun.\nTemukan kreator di daftar online lalu tap Subscribe.'
      : 'You haven\'t subscribed to any creator yet.\nFind creators in the online list and tap Subscribe.';
  String get setSubPriceExplain => isId
      ? 'Fans membayar harga ini setiap bulan untuk berlangganan. Kamu terima 70%, platform 30%.'
      : 'Fans pay this price monthly to subscribe. You receive 70%, the platform takes 30%.';

  // ── Timeline ──
  String get navTimeline => isId ? 'Timeline' : 'Timeline';
  String get tabAll => isId ? 'Semua' : 'All';
  String get tabFollowing => isId ? 'Mengikuti' : 'Following';
  String get tabMine => isId ? 'Postinganku' : 'My Posts';
  String get tabMessages => isId ? 'Pesan' : 'Messages';
  String get tabRooms => isId ? 'Room' : 'Rooms';
  String get titleTimeline => isId ? 'Timeline' : 'Timeline';
  String get hintWritePost =>
      isId ? 'Tulis sesuatu...' : "Share what's on your mind...";
  String get btnPost => isId ? 'Posting' : 'Post';
  String get btnAdd => isId ? 'Add' : 'Add';
  String get btnCamera => isId ? 'Kamera' : 'Camera';
  String get btnGallery => isId ? 'Galeri' : 'Gallery';
  String get postingAs => isId ? 'Posting sebagai' : 'Posting as';
  String get promptCompleteEmailTitle =>
      isId ? 'Lengkapi email untuk posting' : 'Complete email to post';
  String get promptCompleteEmailMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa membuat postingan.'
      : 'You have not completed your email. Complete your email on the Profile page to create posts.';
  String get promptCompleteEmailTimelineTitle => isId
      ? 'Lengkapi email untuk melihat timeline'
      : 'Complete email to view timeline';
  String get promptCompleteEmailTimelineMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa melihat timeline.'
      : 'You have not completed your email. Complete your email on the Profile page to view the timeline.';
  String get btnGoProfile => isId ? 'Ke Profil' : 'Go to Profile';
  String get photoCountLabel => isId ? 'foto' : 'photos';
  String get btnBoost => isId ? 'Boost' : 'Boost';
  String get btnComment => isId ? 'Komentar' : 'Comments';
  String get btnShare => isId ? 'Bagikan' : 'Share';
  String get labelVisibility =>
      isId ? 'Siapa yang bisa melihat' : 'Who can see this';
  String get visPublic => isId ? 'Publik' : 'Public';
  String get visFollowers => isId ? 'Pengikut' : 'Followers';
  String get visSubscribers => isId ? 'Subscriber' : 'Subscribers';
  String get visPublicDesc => isId ? 'Semua orang' : 'Everyone';
  String get visFollowersDesc => isId
      ? 'Pengikut, teman & subscriber'
      : 'Followers, friends & subscribers';
  String get visSubscribersDesc =>
      isId ? 'Hanya subscriber aktif' : 'Active subscribers only';
  String get hintComment => isId ? 'Tulis komentar...' : 'Write a comment...';
  String hintReplyTo(String name) => isId ? 'Balas $name' : 'Reply to $name';
  String get emptyTimeline => isId ? 'Belum ada postingan' : 'No posts yet';
  String get emptyTimelineHint => isId
      ? 'Jadilah yang pertama posting di timeline!'
      : 'Be the first to post on the timeline!';
  String get emptyTimelineCta =>
      isId ? 'Ketuk + untuk membuat postingan' : 'Tap + to create a post';
  String get emptyFollowing => isId
      ? 'Belum ada postingan dari yang kamu ikuti'
      : 'No posts from people you follow';
  String get emptyFollowingHint => isId
      ? 'Ikuti orang lain untuk melihat postingan mereka di sini.'
      : 'Follow others to see their posts here.';
  String get emptyMine =>
      isId ? 'Belum ada postinganmu' : 'No posts from you yet';
  String get emptyMineHint => isId
      ? 'Buat postingan pertamamu, akan muncul di sini.'
      : 'Create your first post, it will appear here.';
  String get noMorePosts => isId ? 'Tidak ada postingan lagi' : 'No more posts';
  String get errPostEmpty => isId
      ? 'Tulis sesuatu atau pilih foto'
      : 'Write something or pick a photo';
  String get errPostTooLong => isId
      ? 'Postingan maksimal 2000 karakter'
      : 'Post must be at most 2000 characters';
  String get errPostLimit =>
      isId ? 'Batas posting harian tercapai' : 'Daily post limit reached';
  String get boostPaidLabel => isId ? 'Boost (koin pro)' : 'Boost (pro coins)';
  String get boostBonusLabel =>
      isId ? 'Boost (koin bonus)' : 'Boost (bonus coins)';
  String get boostConfirm => isId
      ? 'Boost postingan ini supaya naik ke atas feed?'
      : 'Boost this post to the top of the feed?';
  String get msgBoosted => isId ? 'Postingan di-boost' : 'Post boosted';
  String get msgPosted => isId ? 'Berhasil diposting' : 'Posted';
  String get msgCommented => isId ? 'Komentar terkirim' : 'Comment posted';
  String get msgLiked => isId ? 'Disukai' : 'Liked';
  String get msgUnliked => isId ? 'Batal suka' : 'Unliked';
  String get msgShared => isId ? 'Dibagikan' : 'Shared';
  String get badgeBoosted => isId ? 'Boost' : 'Boost';
  String get badgeFriend => isId ? 'Teman' : 'Friend';
  String get badgeSubscriber => isId ? 'Subscriber' : 'Subscriber';
}

const _privacyId = <LegalSection>[
  LegalSection(
    chapter: 'BAB I — KETENTUAN UMUM',
    article: 'Pasal 1 — Pendahuluan',
    items: [
      LegalItem(
        '1. Kebijakan Privasi ini ("**Kebijakan**") disusun dan diterbitkan oleh pengembang serta penyelenggara aplikasi ChatYuk ("**Penyelenggara**", "**Kami**") sebagai bentuk pemenuhan kewajiban transparansi sebagaimana diamanatkan oleh peraturan perundang-undangan yang berlaku di bidang pelindungan data pribadi.',
      ),
      LegalItem(
        '2. Kebijakan ini merupakan bagian yang tidak terpisahkan dan satu kesatuan dengan Syarat dan Ketentuan Layanan ChatYuk, dan berlaku bagi setiap orang perseorangan yang mengunduh, memasang, mendaftar, mengakses, dan/atau menggunakan aplikasi ChatYuk dalam bentuk dan dengan cara apa pun ("**Pengguna**", "**Anda**").',
      ),
      LegalItem(
        '3. Kebijakan ini disusun dengan tujuan untuk menguraikan secara rinci dan transparan mengenai tata cara Kami memperoleh, mengumpulkan, mencatat, menyimpan, memperbaiki, memperbarui, menampilkan, mengumumkan, mentransfer, menyebarluaskan, mengungkapkan, dan/atau menghapus/memusnahkan Data Pribadi Anda ("**Pemrosesan**") sehubungan dengan penggunaan Aplikasi, termasuk namun tidak terbatas pada fitur percakapan (*chat*), ruang obrolan (*room*), foto sekali lihat (*disappearing photo*), dan fitur sosial.',
      ),
      LegalItem(
        '4. Dengan mengunduh, memasang, mendaftarkan diri, mengakses, dan/atau menggunakan Aplikasi dengan cara apa pun, Anda dengan ini menyatakan dan menjamin bahwa Anda telah membaca, memahami secara utuh, serta menyetujui secara sadar dan sukarela seluruh ketentuan yang termuat dalam Kebijakan ini beserta setiap perubahannya di kemudian hari. Apabila Anda tidak menyetujui salah satu atau seluruh ketentuan dalam Kebijakan ini, Kami dengan hormat meminta agar Anda tidak melanjutkan pengunduhan, pemasangan, dan/atau penggunaan Aplikasi.',
      ),
      LegalItem(
        '5. Kebijakan ini berlaku secara global bagi seluruh Pengguna Aplikasi di mana pun domisili atau lokasi Pengguna berada, tanpa memandang batas negara. Prinsip dan standar pelindungan Data Pribadi sebagaimana diuraikan dalam Kebijakan ini diterapkan secara seragam kepada seluruh Pengguna, dengan tambahan ketentuan khusus bagi Pengguna dari yurisdiksi tertentu yang mensyaratkan hak tambahan berdasarkan hukum yang berlaku di yurisdiksi tersebut, sebagaimana diuraikan lebih lanjut dalam Bab XII Kebijakan ini.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 2 — Definisi dan Istilah',
    items: [
      LegalItem(
        'Kecuali secara tegas ditentukan lain dalam Kebijakan ini, istilah-istilah berikut memiliki pengertian sebagaimana diuraikan di bawah ini:',
      ),
      LegalItem(
        '1. **Data Pribadi** berarti setiap data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya, baik secara langsung maupun tidak langsung, melalui sistem elektronik dan/atau nonelektronik.',
      ),
      LegalItem(
        '2. **Data Pribadi Bersifat Umum** berarti Data Pribadi sebagaimana didefinisikan dalam Pasal 4 ayat (2) UU PDP, antara lain nama lengkap, jenis kelamin, kewarganegaraan, agama, dan/atau Data Pribadi yang dikombinasikan untuk mengidentifikasi seseorang.',
      ),
      LegalItem(
        '3. **Data Pribadi Bersifat Spesifik** berarti Data Pribadi sebagaimana didefinisikan dalam Pasal 4 ayat (2) UU PDP, antara lain data dan informasi kesehatan, data biometrik, data keuangan pribadi, dan/atau data lain sesuai ketentuan peraturan perundang-undangan.',
      ),
      LegalItem(
        '4. **Pemrosesan Data Pribadi** berarti setiap tindakan atau rangkaian tindakan yang dilakukan terhadap Data Pribadi, yang mencakup namun tidak terbatas pada perolehan, pengumpulan, pengolahan, penganalisisan, penyimpanan, perbaikan, pembaruan, penampilan, pengumuman, transfer, penyebarluasan, pengungkapan, dan/atau penghapusan atau pemusnahan.',
      ),
      LegalItem(
        '5. **Pengendali Data Pribadi** berarti setiap pihak yang menentukan tujuan dan melakukan kontrol Pemrosesan Data Pribadi — dalam hal ini adalah Penyelenggara.',
      ),
      LegalItem(
        '6. **Prosesor Data Pribadi** berarti setiap pihak yang melakukan Pemrosesan Data Pribadi atas nama Pengendali Data Pribadi, termasuk namun tidak terbatas pada penyedia infrastruktur teknologi sebagaimana diuraikan dalam Bab V Kebijakan ini.',
      ),
      LegalItem(
        '7. **Pihak Ketiga** berarti setiap perseorangan, badan hukum, badan publik, atau organisasi internasional di luar Penyelenggara yang menerima, memproses, dan/atau memiliki akses terhadap Data Pribadi Pengguna.',
      ),
      LegalItem(
        '8. **Subjek Data Pribadi** berarti orang perseorangan yang melekat padanya Data Pribadi — dalam hal ini adalah Anda sebagai Pengguna.',
      ),
      LegalItem(
        '9. **Persetujuan** berarti pernyataan Anda yang diberikan secara bebas, spesifik, dinyatakan secara tegas dan/atau melalui suatu tindakan afirmatif yang jelas, serta diinformasikan sepenuhnya, atas Pemrosesan Data Pribadi yang menyangkut Anda.',
      ),
      LegalItem(
        '10. **Aplikasi** berarti aplikasi seluler dan/atau layanan daring bernama "ChatYuk" beserta seluruh fitur, pembaruan, dan turunannya.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 3 — Pengendali Data Pribadi',
    items: [
      LegalItem(
        '1. Sehubungan dengan Pemrosesan Data Pribadi yang dilakukan melalui Aplikasi, Penyelenggara bertindak selaku Pengendali Data Pribadi sebagaimana dimaksud dalam UU PDP.',
      ),
      LegalItem(
        '2. Identitas resmi dan alamat kontak Pengendali Data Pribadi, termasuk Petugas/Fungsi Pelindungan Data Pribadi apabila telah ditunjuk, dicantumkan secara lengkap dalam Bab XI Pasal 22 Kebijakan ini.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB II — PENGGUNA DI BAWAH UMUR',
    article: 'Pasal 4 — Batasan dan Verifikasi Usia',
    items: [
      LegalItem(
        '1. Aplikasi ChatYuk diperuntukkan secara eksklusif bagi Pengguna yang telah berusia paling rendah 17 (tujuh belas) tahun pada saat pendaftaran. Setiap orang yang belum mencapai usia tersebut dilarang secara tegas untuk membuat akun, mendaftarkan diri, dan/atau menggunakan Aplikasi dalam bentuk apa pun.',
      ),
      LegalItem(
        '2. Kami menerapkan mekanisme verifikasi usia pada tahap pendaftaran berupa pernyataan mandiri (*self-declaration*) mengenai tanggal lahir.',
      ),
      LegalItem(
        '3. Batas usia 17 (tujuh belas) tahun sebagaimana dimaksud pada ayat (1) berlaku secara seragam bagi seluruh Pengguna di mana pun domisilinya berada dan ditetapkan sebagai standar minimum global Kami. Sepanjang hukum di negara domisili Pengguna menetapkan batas usia minimum yang lebih tinggi daripada 17 (tujuh belas) tahun untuk pemberian Persetujuan atas Pemrosesan Data Pribadi secara mandiri (sebagai contoh, ketentuan usia dewasa digital berdasarkan GDPR yang bervariasi antara 13 hingga 16 tahun di masing-masing negara anggota Uni Eropa dapat berbeda dengan batas usia dewasa penuh yang berlaku umum), maka batas usia yang lebih tinggi di negara domisili Pengguna yang bersifat memaksa (*mandatory*) tersebut yang berlaku bagi Pengguna yang bersangkutan.',
      ),
      LegalItem(
        '4. Kami tidak melakukan, dan tidak bermaksud melakukan, Pemrosesan Data Pribadi secara sengaja terhadap individu yang belum memenuhi batas usia sebagaimana dimaksud pada ayat (1) dan/atau ayat (3), mana yang lebih tinggi.',
      ),
      LegalItem(
        '5. Dalam hal Kami memperoleh pengetahuan atau memiliki alasan yang wajar untuk meyakini bahwa Data Pribadi telah terkumpul dari individu yang belum memenuhi batas usia dimaksud, Kami akan segera dan tanpa penundaan yang tidak semestinya: (a) menangguhkan dan/atau menonaktifkan akun yang bersangkutan; (b) melakukan penghapusan atas seluruh Data Pribadi terkait dari sistem produksi maupun sistem cadangan (*backup*) dalam jangka waktu yang wajar secara teknis dan operasional; dan (c) apabila diwajibkan oleh ketentuan hukum yang berlaku, melaporkan hal tersebut kepada otoritas yang berwenang.',
      ),
      LegalItem(
        '6. Orang tua, wali, atau pihak yang memiliki kewenangan hukum atas seorang anak yang meyakini bahwa anak tersebut telah menggunakan Aplikasi bertentangan dengan ketentuan Pasal ini, dapat mengajukan permohonan penghapusan segera melalui kontak resmi sebagaimana diuraikan dalam Pasal 22 Kebijakan ini.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB III — DATA PRIBADI YANG KAMI PROSES',
    article: 'Pasal 5 — Kategori dan Rincian Data Pribadi',
    items: [
      LegalItem(
        'Dalam rangka penyelenggaraan Aplikasi, Kami memproses kategori-kategori Data Pribadi sebagai berikut:',
      ),
      LegalItem(
        '(1) **Data Akun dan Profil**, meliputi: nama pengguna (*username*), nama tampilan, jenis kelamin, tanggal lahir/umur, negara dan kota domisili, foto profil, foto sampul, biografi atau deskripsi diri, alamat surat elektronik (surel) dalam hal pendaftaran dilakukan melalui surel atau melalui fasilitas masuk dengan akun pihak ketiga, serta kata sandi yang disimpan dalam bentuk terenkripsi/*hash* satu arah dan tidak pernah disimpan maupun ditampilkan dalam bentuk teks biasa (*plaintext*).',
      ),
      LegalItem(
        '(2) **Data Lokasi**, meliputi: (a) negara dan kota yang diturunkan secara otomatis dari alamat Protokol Internet (IP), yang dikumpulkan untuk keperluan lokalisasi konten dan mitigasi risiko keamanan; dan (b) koordinat titik lokasi global (GPS) presisi, yang **hanya** dikumpulkan apabila Anda memberikan izin akses lokasi perangkat secara eksplisit, tegas, dan terpisah dari persetujuan umum penggunaan Aplikasi, serta yang dapat Anda cabut sewaktu-waktu melalui pengaturan sistem operasi perangkat maupun pengaturan dalam Aplikasi.',
      ),
      LegalItem(
        '(3) **Data Konten**, meliputi: pesan teks dalam percakapan pribadi maupun ruang obrolan (*room*), foto dan berkas media, termasuk fitur foto sekali lihat (*disappearing photo*), unggahan, status, komentar, serta metadata teknis yang melekat pada berkas media dimaksud (mis. ukuran dan format berkas), dengan catatan bahwa data *Exchangeable Image File Format* (EXIF) yang berpotensi mengandung informasi lokasi presisi akan dihapus atau dibersihkan sebelum penyimpanan sejauh dapat dilaksanakan secara teknis.',
      ),
      LegalItem(
        '(4) **Data Sosial dan Interaksi**, meliputi: daftar Pengguna yang diikuti dan yang mengikuti Anda, daftar pertemanan, riwayat langganan (*subscription*) antar-Pengguna sepanjang fitur tersebut tersedia, daftar pemblokiran yang Anda tetapkan, serta laporan (*report*) yang Anda ajukan terhadap Pengguna atau konten lain, termasuk laporan yang diajukan pihak lain terhadap Anda.',
      ),
      LegalItem(
        '(5) **Data Teknis dan Catatan Log**, meliputi: alamat IP, jenis dan versi perangkat, sistem operasi, pengenal perangkat (*device identifier*), serta metrik penggunaan Aplikasi dalam cakupan yang seminimal mungkin (*data minimization*) yang diperlukan untuk keperluan keamanan sistem, deteksi dan pencegahan penyalahgunaan, serta pemeliharaan dan perbaikan layanan, termasuk catatan kegagalan sistem dan catatan akses terhadap fitur-fitur yang bersifat sensitif.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 6 — Sumber Perolehan Data Pribadi',
    items: [
      LegalItem(
        '1. **Diperoleh secara langsung dari Anda**, yaitu pada saat Anda mendaftar, melengkapi profil, mengirimkan pesan, dan mengunggah media.',
      ),
      LegalItem(
        '2. **Diperoleh secara otomatis melalui sistem elektronik**, yaitu meliputi alamat IP dan data teknis perangkat sebagaimana dimaksud dalam Pasal 5 ayat (5).',
      ),
      LegalItem(
        '3. **Diperoleh dari Pihak Ketiga**, yaitu meliputi data yang diteruskan oleh penyedia layanan masuk (login) pihak ketiga (sebatas nama, alamat surel, dan foto profil dasar sesuai izin yang Anda berikan pada saat proses masuk/*login*), serta penyedia layanan geolokasi berbasis IP.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 7 — Batasan Pemrosesan Data Sensitif',
    items: [
      LegalItem(
        'Kami tidak secara sengaja mengumpulkan atau memproses data mengenai kondisi kesehatan, afiliasi politik, orientasi seksual, atau keyakinan keagamaan Pengguna.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB IV — TUJUAN DAN DASAR HUKUM PEMROSESAN',
    article: 'Pasal 8 — Dasar Hukum Pemrosesan',
    items: [
      LegalItem(
        'Sesuai dengan ketentuan Pasal 20 UU PDP, setiap Pemrosesan Data Pribadi yang dilakukan oleh Kami senantiasa didasarkan pada salah satu atau lebih dasar hukum sebagai berikut:',
      ),
      LegalItem(
        '',
        table: [
          ['Dasar Hukum', 'Penerapan dalam Aplikasi ChatYuk'],
          [
            'a. Persetujuan eksplisit dari Subjek Data Pribadi',
            'Pengumpulan data lokasi GPS presisi; pemrosesan fitur foto sekali lihat',
          ],
          [
            'b. Pemenuhan kewajiban perjanjian dalam hal Subjek Data Pribadi merupakan pihak dalam perjanjian, atau untuk memenuhi permintaan Subjek Data Pribadi pada saat akan melakukan perjanjian',
            'Pembuatan dan pengelolaan akun; penyediaan fitur percakapan, ruang obrolan, dan fitur sosial',
          ],
          [
            'c. Pemenuhan kewajiban hukum Pengendali Data Pribadi sesuai dengan ketentuan peraturan perundang-undangan',
            'Pemenuhan kewajiban hukum yang berlaku; pelaporan kepada otoritas berwenang sepanjang diwajibkan hukum',
          ],
          [
            'd. Pemenuhan kepentingan yang sah lainnya dengan memperhatikan tujuan, kebutuhan, dan keseimbangan kepentingan Pengendali Data Pribadi dan hak Subjek Data Pribadi',
            'Menjaga keamanan sistem; deteksi dan pencegahan penipuan serta penyalahgunaan; moderasi konten; penegakan Syarat dan Ketentuan Layanan',
          ],
          [
            'e. Kepentingan yang bersifat vital bagi Subjek Data Pribadi',
            'Situasi darurat yang secara nyata mengancam keselamatan jiwa Pengguna, sepanjang berlaku',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 9 — Tujuan Pemrosesan',
    items: [
      LegalItem(
        'Data Pribadi Anda diproses untuk tujuan-tujuan berikut: (a) penyediaan, pemeliharaan, dan penyempurnaan fitur Aplikasi; (b) personalisasi pengalaman pengguna; (c) pencegahan, deteksi, dan penanganan penipuan serta segala bentuk penyalahgunaan Aplikasi; (d) moderasi konten dan penanganan laporan antar-Pengguna; (e) penyampaian komunikasi terkait layanan, termasuk notifikasi dan pemberitahuan keamanan; dan (f) pemenuhan kewajiban hukum dan kepatuhan terhadap peraturan perundang-undangan yang berlaku.',
      ),
      LegalItem(
        'Kami dengan ini menegaskan bahwa Kami tidak menggunakan Data Pribadi Anda untuk pengambilan keputusan yang sepenuhnya otomatis dan menimbulkan akibat hukum yang signifikan terhadap Anda tanpa keterlibatan campur tangan manusia (*human intervention*), kecuali diberitahukan secara terpisah dan tersendiri kepada Anda beserta dasar hukumnya.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB V — PENGUNGKAPAN DATA PRIBADI KEPADA PIHAK KETIGA',
    article: 'Pasal 10 — Prinsip Umum',
    items: [
      LegalItem(
        '1. Kami dengan tegas menyatakan **tidak menjual, menyewakan, atau memperdagangkan** Data Pribadi Anda kepada pihak mana pun untuk tujuan komersial di luar yang diatur dalam Kebijakan ini.',
      ),
      LegalItem(
        '2. Pengungkapan Data Pribadi kepada Pihak Ketiga hanya dilakukan sepanjang secara wajar diperlukan untuk penyelenggaraan Aplikasi, dan senantiasa memperhatikan prinsip minimalisasi data (*data minimization*), yakni sebatas data yang relevan dan diperlukan untuk tujuan dimaksud.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 11 — Rincian Penerima Data Pribadi',
    items: [
      LegalItem(
        '',
        table: [
          ['Pihak Ketiga', 'Kedudukan', 'Cakupan Data yang Diproses'],
          [
            'Penyedia infrastruktur data (basis data, autentikasi, dan penyimpanan awan)',
            'Bertindak selaku Prosesor Data Pribadi',
            'Seluruh Data Pribadi dan konten yang tersimpan pada server, dengan penerapan kontrol akses tingkat baris (Row-Level Security)',
          ],
          [
            'Penyedia layanan masuk (login) pihak ketiga',
            'Penyedia jasa autentikasi pihak ketiga',
            'Token autentikasi; data profil dasar sesuai cakupan izin yang Anda berikan pada saat proses masuk',
          ],
          [
            'Penyedia layanan geolokasi berbasis IP',
            'Penentuan negara dan kota berdasarkan alamat IP',
            'Alamat IP',
          ],
          [
            'Instansi/otoritas yang berwenang',
            'Penegakan hukum dan pemenuhan permintaan yang sah dari lembaga pemerintah',
            'Terbatas pada cakupan permintaan hukum yang sah, dapat diverifikasi, dan sesuai dengan ketentuan peraturan perundang-undangan yang berlaku',
          ],
          [
            'Penasihat profesional (mis. auditor, konsultan hukum)',
            'Kepentingan bisnis yang sah dan tunduk pada kewajiban kerahasiaan',
            'Sebatas yang secara wajar diperlukan untuk pemberian jasa profesional dimaksud',
          ],
        ],
      ),
      LegalItem(
        '3. Setiap Pihak Ketiga sebagaimana disebutkan di atas memiliki kebijakan privasi dan praktik keamanan tersendiri yang berada di luar kendali langsung Kami. Kami berupaya sepatutnya (*reasonable effort*) untuk bekerja sama dengan mitra yang menerapkan standar pelindungan data yang memadai, namun tetap menganjurkan Anda untuk membaca dan memahami kebijakan privasi masing-masing Pihak Ketiga dimaksud.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 12 — Transfer Data Pribadi Lintas Batas Negara',
    items: [
      LegalItem(
        '1. Mengingat penyedia infrastruktur sebagaimana dimaksud dalam Pasal 11 dapat menempatkan server pada yurisdiksi di luar wilayah Negara Kesatuan Republik Indonesia, Data Pribadi Anda berpotensi diproses di luar wilayah yurisdiksi domisili Anda.',
      ),
      LegalItem(
        '2. Dalam hal terjadi transfer Data Pribadi lintas batas negara sebagaimana dimaksud pada ayat (1), Kami akan memastikan terpenuhinya sekurang-kurangnya salah satu persyaratan berikut sebagaimana diatur dalam Pasal 56 UU PDP: (a) negara tempat kedudukan penerima Data Pribadi memiliki tingkat pelindungan Data Pribadi yang setara atau lebih tinggi dibandingkan dengan UU PDP; (b) terdapat pelindungan Data Pribadi yang memadai dan mengikat melalui perjanjian pemrosesan data (*data processing agreement*) antara Kami dan penerima data; dan/atau (c) Kami telah memperoleh Persetujuan Anda atas transfer dimaksud.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VI — PENYIMPANAN, KEAMANAN, DAN PENANGANAN INSIDEN',
    article: 'Pasal 13 — Langkah Teknis dan Organisasional',
    items: [
      LegalItem(
        'Dalam rangka melindungi Data Pribadi Anda dari kehilangan, penyalahgunaan, akses tanpa hak, pengubahan, dan pengungkapan yang tidak sah, Kami menerapkan langkah-langkah teknis dan organisasional sebagai berikut:',
      ),
      LegalItem(
        '1. **Kontrol akses tingkat baris (Row-Level Security)** pada basis data, sehingga setiap Pengguna hanya dapat mengakses data miliknya sendiri sesuai dengan hak akses yang telah ditetapkan.',
      ),
      LegalItem(
        '2. **Enkripsi data tersimpan pada perangkat (at rest)**: pesan dan foto yang disimpan sementara (*cache*) pada perangkat Anda dienkripsi menggunakan algoritma AES-GCM, dengan kunci enkripsi yang disimpan pada Android Keystore (*hardware-backed* apabila didukung oleh perangkat).',
      ),
      LegalItem(
        '3. **Enkripsi data dalam pengiriman (in transit)**: seluruh komunikasi antara Aplikasi dan server Kami dienkripsi menggunakan protokol Transport Layer Security (TLS)/HTTPS.',
      ),
      LegalItem(
        '4. **Penanda air forensik (forensic watermark)**: foto sekali lihat diberikan penanda tersembunyi yang memuat identitas penerima, sebagai jejak forensik dalam hal terjadi penyalahgunaan, termasuk namun tidak terbatas pada tangkapan layar yang berhasil dilakukan meskipun telah melewati mekanisme proteksi.',
      ),
      LegalItem(
        '5. **Proteksi anti-tangkapan layar (anti-screenshot)**: halaman yang menampilkan konten bersifat sensitif, termasuk foto sekali lihat, dilindungi dengan fitur pencegahan tangkapan layar (*screenshot*) dan perekaman layar (*screen recording*) pada tingkat sistem operasi, sepanjang didukung oleh platform perangkat yang bersangkutan.',
      ),
      LegalItem(
        '6. **Kontrol akses internal**: akses staf dan/atau administrator Kami terhadap Data Pribadi dibatasi berdasarkan prinsip kebutuhan untuk mengetahui (*need-to-know basis*) dan dicatat dalam log audit.',
      ),
      LegalItem(
        '7. **Evaluasi kerentanan sistem secara berkala** sebagai bagian dari komitmen Kami terhadap pemeliharaan keamanan sistem elektronik yang berkelanjutan.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 14 — Batasan Pertanggungjawaban Keamanan',
    items: [
      LegalItem(
        'Meskipun Kami telah menerapkan langkah-langkah teknis dan organisasional sebagaimana diuraikan dalam Pasal 13, Anda memahami dan menyetujui bahwa **tidak ada sistem elektronik yang dapat menjamin keamanan secara mutlak** dari segala bentuk ancaman keamanan siber. Oleh karenanya, Kami tidak dapat memberikan jaminan mutlak atas keamanan Data Pribadi yang Anda kirimkan atau simpan melalui Aplikasi, sekalipun Kami senantiasa berupaya secara sepatutnya untuk melindunginya.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Pasal 15 — Prosedur Penanganan Insiden dan Pelanggaran Data Pribadi',
    items: [
      LegalItem(
        '1. Dalam hal terjadi kegagalan pelindungan Data Pribadi yang mengakibatkan risiko kebocoran, kehilangan, penyalahgunaan, akses, atau pengungkapan Data Pribadi secara tidak sah ("**Insiden**"), Kami akan segera melakukan investigasi dan langkah mitigasi yang diperlukan.',
      ),
      LegalItem(
        '2. Sesuai dengan ketentuan yang berlaku, Kami akan menyampaikan pemberitahuan tertulis kepada Subjek Data Pribadi yang terdampak dan kepada lembaga pengawas Pelindungan Data Pribadi/Kementerian yang berwenang, paling lambat dalam waktu 3 x 24 (tiga kali dua puluh empat) jam sejak Insiden diketahui, dengan memuat sekurang-kurangnya: (a) uraian mengenai Data Pribadi yang terdampak; (b) kronologi dan cara terjadinya Insiden; dan (c) upaya penanganan dan pemulihan yang telah dan akan dilakukan Kami.',
      ),
      LegalItem(
        '3. Kami akan memberikan panduan langkah-langkah pengamanan yang dapat Anda lakukan secara mandiri (mis. penggantian kata sandi) sepanjang relevan dengan Insiden yang terjadi.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VII — RETENSI DAN PENGHAPUSAN DATA PRIBADI',
    article: 'Pasal 16 — Jangka Waktu Penyimpanan',
    items: [
      LegalItem(
        '',
        table: [
          ['Kategori Data', 'Jangka Waktu Retensi'],
          [
            'Data akun dan profil',
            'Selama akun tetap aktif; dihapus secara permanen dalam jangka waktu yang wajar setelah penghapusan akun oleh Pengguna',
          ],
          [
            'Data konten (pesan, foto, ruang obrolan)',
            'Selama akun tetap aktif, kecuali foto sekali lihat yang dihapus secara otomatis setelah dilihat atau setelah masa berlakunya berakhir sesuai rancangan fitur',
          ],
          [
            'Catatan log moderasi dan laporan',
            'Disimpan dalam jangka waktu terbatas yang diperlukan untuk keperluan penegakan ketentuan layanan, penyelesaian sengketa, dan pemenuhan kewajiban hukum',
          ],
          [
            'Data teknis dan catatan log keamanan',
            'Disimpan dalam jangka waktu terbatas yang diperlukan untuk keperluan keamanan sistem elektronik',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 17 — Mekanisme Penghapusan',
    items: [
      LegalItem(
        'Penghapusan akun yang dilakukan oleh Pengguna melalui menu profil akan mengakibatkan penghapusan profil dan konten terkait secara permanen dari sistem produksi Kami dalam jangka waktu yang wajar secara teknis, kecuali terhadap data yang wajib Kami pertahankan sehubungan dengan kewajiban hukum sebagaimana dimaksud dalam Pasal 16, atau untuk kepentingan penyelesaian sengketa yang masih berlangsung pada saat permintaan penghapusan diajukan.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VIII — HAK-HAK SUBJEK DATA PRIBADI',
    article: 'Pasal 18 — Uraian Hak',
    items: [
      LegalItem(
        'Sesuai dengan ketentuan Bab VI UU PDP, sebagai Subjek Data Pribadi Anda memiliki hak-hak sebagai berikut:',
      ),
      LegalItem(
        '1. **Hak untuk memperoleh informasi**, yaitu hak untuk mendapatkan penjelasan mengenai identitas Kami selaku Pengendali Data Pribadi, dasar hukum yang sah, dan tujuan permintaan serta penggunaan Data Pribadi Anda.',
      ),
      LegalItem(
        '2. **Hak untuk melengkapi, memperbarui, dan/atau memperbaiki** kekeliruan dan/atau ketidakakuratan Data Pribadi Anda sesuai dengan tujuan Pemrosesan Data Pribadi.',
      ),
      LegalItem(
        '3. **Hak untuk mengakhiri Pemrosesan**, menghapus, dan/atau memusnahkan Data Pribadi Anda, kecuali terhadap Data Pribadi yang wajib dipertahankan sesuai ketentuan peraturan perundang-undangan.',
      ),
      LegalItem(
        '4. **Hak untuk menarik kembali Persetujuan** yang telah diberikan sebelumnya kepada Kami, termasuk mencabut izin akses lokasi GPS presisi, dengan ketentuan bahwa penarikan tersebut tidak memengaruhi keabsahan Pemrosesan yang telah dilakukan sebelum penarikan dimaksud.',
      ),
      LegalItem(
        '5. **Hak untuk mengajukan keberatan** atas tindakan Pemrosesan yang bersifat pengambilan keputusan secara otomatis, termasuk pembuatan profil (*profiling*), yang menimbulkan akibat hukum atau berdampak signifikan bagi Anda.',
      ),
      LegalItem(
        '6. **Hak untuk menunda atau membatasi** Pemrosesan Data Pribadi secara proporsional sesuai dengan tujuan Pemrosesan.',
      ),
      LegalItem(
        '7. **Hak untuk menggugat dan menerima ganti rugi** atas terjadinya pelanggaran Pemrosesan Data Pribadi yang menyangkut dirinya sesuai dengan ketentuan peraturan perundang-undangan yang berlaku.',
      ),
      LegalItem(
        '8. **Hak untuk memperoleh dan/atau menggunakan Data Pribadi (portabilitas data)** dalam bentuk yang sesuai dengan format yang lazim digunakan atau dapat dibaca oleh sistem elektronik.',
      ),
      LegalItem(
        '9. **Hak untuk mengajukan pengaduan** atas dugaan pelanggaran Pemrosesan Data Pribadi yang menyangkut dirinya, baik kepada Kami maupun kepada lembaga pengawas Pelindungan Data Pribadi yang berwenang.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 19 — Mekanisme Pelaksanaan Hak',
    items: [
      LegalItem(
        'Sebagian besar hak sebagaimana dimaksud dalam Pasal 18 dapat Anda laksanakan secara mandiri melalui menu profil dan pengaturan yang tersedia dalam Aplikasi. Untuk permintaan yang tidak tersedia secara langsung melalui fitur Aplikasi, termasuk permintaan portabilitas data dalam format terstruktur, Anda dapat mengajukan permohonan tertulis melalui kontak resmi sebagaimana dimaksud dalam Pasal 22 Kebijakan ini. Kami akan menindaklanjuti setiap permohonan dalam jangka waktu yang wajar dan sesuai dengan ketentuan peraturan perundang-undangan yang berlaku, dan berhak melakukan verifikasi identitas pemohon sebelum menindaklanjuti permintaan dimaksud guna melindungi Data Pribadi dari akses yang tidak sah.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB IX — TEKNOLOGI PELACAKAN',
    article: 'Pasal 20 — Cookie dan Teknologi Serupa',
    items: [
      LegalItem(
        'Dalam hal Aplikasi menggunakan cookie, penyimpanan lokal (*local storage*), perangkat lunak pengembangan (*software development kit*) analitik, atau teknologi pengenal (*identifier*) serupa lainnya untuk keperluan manajemen sesi masuk (*login*) dan/atau analitik penggunaan, Kami akan menguraikan secara tersendiri jenis, tujuan, dan mekanisme pengelolaannya pada bagian ini setelah fitur yang bersangkutan diimplementasikan secara resmi.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB X — PERUBAHAN KEBIJAKAN',
    article: 'Pasal 21 — Tata Cara Perubahan',
    items: [
      LegalItem(
        '1. Kami berhak untuk sewaktu-waktu meninjau dan memperbarui Kebijakan ini guna mencerminkan perubahan fitur Aplikasi, praktik operasional, dan/atau ketentuan peraturan perundang-undangan yang berlaku.',
      ),
      LegalItem(
        '2. Setiap perubahan yang bersifat material akan diberitahukan kepada Anda melalui Aplikasi, baik melalui notifikasi dalam aplikasi (*in-app notification*) maupun pemberitahuan pada saat pembukaan Aplikasi, sebelum perubahan dimaksud berlaku secara efektif.',
      ),
      LegalItem(
        '3. Penggunaan Aplikasi secara berkelanjutan oleh Anda setelah tanggal berlaku efektifnya perubahan Kebijakan dianggap sebagai bentuk persetujuan Anda atas Kebijakan yang telah diperbarui.',
      ),
      LegalItem(
        '4. Sepanjang suatu perubahan secara signifikan memperluas cakupan Pemrosesan Data Pribadi yang bersifat sensitif atau spesifik, Kami akan meminta Persetujuan eksplisit yang baru dari Anda sepanjang diwajibkan oleh ketentuan hukum yang berlaku.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB XI — KONTAK DAN PENGADUAN',
    article: 'Pasal 22 — Kontak Resmi',
    items: [
      LegalItem(
        'Untuk setiap pertanyaan, permohonan, dan/atau pengaduan sehubungan dengan Kebijakan Privasi ini atau Pemrosesan Data Pribadi Anda, silakan hubungi Kami melalui menu **Hubungi Kami** di dalam Aplikasi, yang dapat diakses dari halaman Profil.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 23 — Hak Mengadu kepada Lembaga Pengawas',
    items: [
      LegalItem(
        'Apabila Anda tidak memperoleh penyelesaian yang memuaskan atas permohonan atau pengaduan yang Anda ajukan kepada Kami, Anda berhak untuk mengajukan pengaduan lebih lanjut kepada lembaga pengawas Pelindungan Data Pribadi yang berwenang di Republik Indonesia sesuai dengan ketentuan peraturan perundang-undangan yang berlaku.',
      ),
    ],
  ),
  LegalSection(
    chapter:
        'BAB XII — KETENTUAN TAMBAHAN BAGI PENGGUNA DARI YURISDIKSI TERTENTU',
    article: 'Pasal 24 — Prinsip Umum',
    items: [
      LegalItem(
        '1. Aplikasi disediakan bagi Pengguna di berbagai negara. Standar pelindungan Data Pribadi sebagaimana diuraikan dalam Bab I hingga Bab XI Kebijakan ini berlaku sebagai standar minimum yang seragam bagi seluruh Pengguna.',
      ),
      LegalItem(
        '2. Apabila hukum yang berlaku di negara domisili Anda memberikan hak tambahan, kewajiban tambahan bagi Kami, atau tingkat pelindungan yang lebih tinggi dibandingkan dengan yang diuraikan dalam Kebijakan ini, maka ketentuan tambahan sebagaimana diuraikan dalam Pasal 25 dan Pasal 26 di bawah ini berlaku bagi Anda, sepanjang relevan dengan yurisdiksi Anda, tanpa mengurangi berlakunya ketentuan umum dalam Kebijakan ini.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Pasal 25 — Ketentuan Tambahan bagi Pengguna di Wilayah Uni Eropa/Kawasan Ekonomi Eropa dan Inggris Raya (GDPR)',
    items: [
      LegalItem(
        'Bagi Pengguna yang berdomisili di wilayah Uni Eropa, Kawasan Ekonomi Eropa (EEA), atau Inggris Raya, berlaku ketentuan tambahan sebagai berikut:',
      ),
      LegalItem(
        '1. **Dasar hukum Pemrosesan** mengikuti padanan sebagaimana diatur dalam Pasal 6 GDPR, yaitu Persetujuan, pelaksanaan kontrak, kewajiban hukum, kepentingan vital, dan kepentingan sah (*legitimate interest*), sebagaimana telah diuraikan padanannya dalam Pasal 8 Kebijakan ini.',
      ),
      LegalItem(
        '2. Anda memiliki hak tambahan berupa **hak atas portabilitas data** dalam format terstruktur, lazim digunakan, dan dapat dibaca mesin (*machine-readable*); **hak untuk dilupakan** (*right to be forgotten*) sepanjang tidak bertentangan dengan kewajiban hukum Kami untuk menyimpan data tertentu; serta **hak untuk mengajukan keberatan** atas Pemrosesan yang didasarkan pada kepentingan sah Kami.',
      ),
      LegalItem(
        '3. Anda berhak mengajukan pengaduan kepada otoritas pengawas pelindungan data (*supervisory authority*) yang berwenang di negara domisili Anda, termasuk namun tidak terbatas pada otoritas pengawas di negara anggota Uni Eropa tempat Anda berdomisili atau bekerja, atau tempat dugaan pelanggaran terjadi.',
      ),
      LegalItem(
        '4. Transfer Data Pribadi ke luar wilayah EEA/Inggris Raya, termasuk ke Indonesia, akan dilaksanakan dengan mekanisme pengamanan yang sah, antara lain melalui *Standard Contractual Clauses* atau mekanisme lain yang diakui berdasarkan hukum yang berlaku, sebagaimana selaras dengan prinsip transfer lintas batas dalam Pasal 12 Kebijakan ini.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Pasal 26 — Ketentuan Tambahan bagi Pengguna di Negara Bagian California, Amerika Serikat (CCPA/CPRA)',
    items: [
      LegalItem(
        'Bagi Pengguna yang berdomisili di Negara Bagian California, Amerika Serikat, berlaku ketentuan tambahan sebagai berikut:',
      ),
      LegalItem(
        '1. Anda berhak untuk mengetahui kategori dan sumber Data Pribadi yang Kami kumpulkan, tujuan pengumpulan, serta pihak yang menerima Data Pribadi tersebut, sebagaimana telah diuraikan dalam Bab III dan Bab V Kebijakan ini.',
      ),
      LegalItem(
        '2. Anda berhak meminta penghapusan Data Pribadi Anda, dengan pengecualian terhadap data yang wajib Kami simpan untuk memenuhi kewajiban hukum sebagaimana diuraikan dalam Pasal 16 Kebijakan ini.',
      ),
      LegalItem(
        '3. Anda berhak untuk tidak diperlakukan secara diskriminatif oleh Kami sehubungan dengan pelaksanaan hak-hak Anda berdasarkan CCPA/CPRA.',
      ),
      LegalItem(
        '4. Sebagaimana ditegaskan dalam Pasal 10 Kebijakan ini, Kami tidak menjual (*sell*) maupun membagikan (*share*) Data Pribadi Anda sebagaimana dimaksud dalam CCPA/CPRA untuk kepentingan iklan bertarget lintas konteks.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 27 — Ketentuan bagi Pengguna di Yurisdiksi Lain',
    items: [
      LegalItem(
        'Bagi Pengguna yang berdomisili di negara-negara lain yang memiliki peraturan pelindungan data pribadi tersendiri, termasuk namun tidak terbatas pada Singapura (*Personal Data Protection Act*), Malaysia, Filipina, India, atau negara-negara lain di kawasan Asia Tenggara dan Asia Pasifik, Kami akan berupaya sepatutnya untuk memenuhi persyaratan minimum yang diwajibkan oleh hukum setempat sepanjang tidak bertentangan dengan Kebijakan ini secara keseluruhan. Dalam hal terdapat pertentangan antara ketentuan hukum setempat yang bersifat memaksa (*mandatory*) dengan ketentuan Kebijakan ini, ketentuan hukum setempat yang bersifat memaksa tersebut akan diutamakan sepanjang menyangkut Pengguna dari yurisdiksi yang bersangkutan.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB XIII — HUKUM YANG BERLAKU DAN PENYELESAIAN SENGKETA',
    article: 'Pasal 28 — Hukum yang Berlaku',
    items: [
      LegalItem(
        '1. Kebijakan ini disusun dan ditafsirkan berdasarkan hukum Negara Republik Indonesia, termasuk namun tidak terbatas pada UU PDP dan UU ITE beserta peraturan pelaksanaannya, yang berlaku sebagai kerangka hukum utama (*governing law*) atas hubungan hukum antara Kami dan seluruh Pengguna, di mana pun domisili Pengguna berada.',
      ),
      LegalItem(
        '2. Ketentuan ayat (1) berlaku tanpa mengurangi hak-hak Pengguna yang bersifat memaksa (*mandatory rights*) berdasarkan hukum pelindungan konsumen dan/atau hukum pelindungan data pribadi di negara domisili Pengguna, sebagaimana diuraikan dalam Bab XII Kebijakan ini, sepanjang hukum setempat tersebut tidak dapat dikesampingkan melalui pilihan hukum (*choice of law*).',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 29 — Penyelesaian Sengketa',
    items: [
      LegalItem(
        'Setiap perselisihan, perbedaan pendapat, atau sengketa yang timbul sehubungan dengan Kebijakan ini akan terlebih dahulu diupayakan penyelesaiannya secara musyawarah untuk mencapai mufakat antara para pihak. Dalam hal penyelesaian secara musyawarah tidak tercapai dalam jangka waktu yang wajar, sengketa akan diselesaikan melalui jalur hukum yang berlaku di wilayah hukum Republik Indonesia, tanpa mengurangi hak Pengguna dari yurisdiksi tertentu untuk mengajukan pengaduan kepada otoritas pengawas setempat sebagaimana diuraikan dalam Bab XII.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 30 — Panggilan Audio dan Video',
    items: [
      LegalItem(
        '1. Fitur panggilan audio dan video (1:1) tersedia bagi Pengguna yang telah terdaftar. Saat Anda melakukan atau menerima panggilan, akses mikrofon dan/atau kamera diperlukan dan media panggilan dikirim secara **point-to-point (P2P)** antar perangkat, dengan bantuan server sinyal hanya untuk mengatur koneksi awal.',
      ),
      LegalItem(
        '2. Saat memulai panggilan, Kami menyimpan data teknis panggilan (identitas pemanggil, identitas penerima, jenis panggilan, waktu mulai, waktu selesai, dan status panggilan) sebagai catatan transaksi internal guna keperluan dukungan teknis, penanganan keluhan, dan moderasi.',
      ),
      LegalItem(
        '3. Isi percakapan audio/video tidak direkam, tidak disimpan, dan tidak diproses oleh Kami. Panggilan bersifat langsung (*real-time*) antar Pengguna.',
      ),
      LegalItem(
        '4. Dalam kondisi jaringan tertentu (misalnya NAT simetris atau koneksi tidak stabil), sinyal koneksi panggilan dapat dialihkan melalui server relai (*TURN*) pihak ketiga demi kelancaran panggilan. Server relai hanya meneruskan paket media secara enkripsi dan tidak menyimpan isi panggilan.',
      ),
      LegalItem(
        '5. Fitur panggilan tidak boleh digunakan untuk mengirim konten yang melanggar Syarat Layanan, termasuk konten ilegal atau pelecehan. Pelanggaran dapat berakibat pada pembatasan atau penghentian akun.',
      ),
    ],
  ),
];

const _privacyEn = <LegalSection>[
  LegalSection(
    chapter: 'CHAPTER I — GENERAL PROVISIONS',
    article: 'Article 1 — Introduction',
    items: [
      LegalItem(
        '1. This Privacy Policy (the "Policy") is drafted and published by the developer and operator of the ChatYuk application (the "Operator", "We", "Us") as a form of fulfilling the transparency obligation mandated by applicable laws and regulations in the field of personal data protection.',
      ),
      LegalItem(
        '2. This Policy forms an inseparable and integral part of the ChatYuk Terms of Service, and applies to every individual who downloads, installs, registers, accesses, and/or uses the ChatYuk application in any form and manner (the "User", "You").',
      ),
      LegalItem(
        '3. This Policy is drafted with the aim of describing in a detailed and transparent manner the ways in which We obtain, collect, record, store, correct, update, display, announce, transfer, disseminate, disclose, and/or delete/destroy Your Personal Data ("Processing") in connection with the use of the Application, including but not limited to the chat feature, chat rooms, the disappearing photo feature, and social features.',
      ),
      LegalItem(
        '4. By downloading, installing, registering, accessing, and/or using the Application in any manner, You hereby declare and warrant that You have read, fully understood, and consciously and voluntarily agreed to all provisions contained in this Policy and any future amendments thereof. If You do not agree to any or all of the provisions of this Policy, We respectfully request that You do not continue downloading, installing, and/or using the Application.',
      ),
      LegalItem(
        '5. This Policy applies globally to all Users of the Application regardless of their domicile or location, without regard to national borders. The principles and standards of Personal Data protection described in this Policy are applied uniformly to all Users, with additional specific provisions for Users from certain jurisdictions that require additional rights under the laws applicable in those jurisdictions, as further described in Chapter XII of this Policy.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 2 — Definitions',
    items: [
      LegalItem(
        'Unless expressly provided otherwise in this Policy, the following terms shall have the meanings set out below:',
      ),
      LegalItem(
        '1. **Personal Data** means any data about an individual who is identified or can be identified individually or in combination with other information, either directly or indirectly, through electronic and/or non-electronic systems.',
      ),
      LegalItem(
        '2. **General Personal Data** means Personal Data as defined in Article 4 paragraph (2) of the PDP Law, including full name, gender, nationality, religion, and/or Personal Data combined to identify a person.',
      ),
      LegalItem(
        '3. **Specific Personal Data** means Personal Data as defined in Article 4 paragraph (2) of the PDP Law, including health data and information, biometric data, personal financial data, and/or other data in accordance with laws and regulations.',
      ),
      LegalItem(
        '4. **Personal Data Processing** means any action or series of actions performed on Personal Data, including but not limited to obtaining, collecting, processing, analyzing, storing, correcting, updating, displaying, announcing, transferring, disseminating, disclosing, and/or deleting or destroying.',
      ),
      LegalItem(
        '5. **Personal Data Controller** means any party that determines the purposes and exercises control over Personal Data Processing — in this case, the Operator.',
      ),
      LegalItem(
        '6. **Personal Data Processor** means any party that performs Personal Data Processing on behalf of the Personal Data Controller, including but not limited to technology infrastructure providers as described in Chapter V of this Policy.',
      ),
      LegalItem(
        '7. **Third Party** means any individual, legal entity, public body, or international organization outside the Operator that receives, processes, and/or has access to User Personal Data.',
      ),
      LegalItem(
        '8. **Personal Data Subject** means the individual to whom Personal Data pertains — in this case, You as the User.',
      ),
      LegalItem(
        '9. **Consent** means Your statement given freely, specifically, expressly stated and/or through a clear affirmative action, and fully informed, regarding the Processing of Personal Data concerning You.',
      ),
      LegalItem(
        '10. **Application** means the mobile application and/or online service named "ChatYuk" together with all of its features, updates, and derivatives.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 3 — Personal Data Controller',
    items: [
      LegalItem(
        '1. In connection with the Processing of Personal Data carried out through the Application, the Operator acts as the Personal Data Controller as referred to in the PDP Law.',
      ),
      LegalItem(
        '2. The official identity and contact address of the Personal Data Controller, including the Personal Data Protection Officer/Function if appointed, are set out in full in Chapter XI, Article 22 of this Policy.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER II — MINORS',
    article: 'Article 4 — Age Restrictions and Verification',
    items: [
      LegalItem(
        '1. The ChatYuk Application is intended exclusively for Users who are at least 17 (seventeen) years old at the time of registration. Any person who has not reached that age is expressly prohibited from creating an account, registering, and/or using the Application in any form.',
      ),
      LegalItem(
        '2. We apply an age verification mechanism at the registration stage in the form of a self-declaration of date of birth.',
      ),
      LegalItem(
        '3. The minimum age of 17 (seventeen) years as referred to in paragraph (1) applies uniformly to all Users wherever they are domiciled and is established as Our global minimum standard. To the extent that the law of the User country of domicile sets a higher minimum age than 17 (seventeen) years for giving Consent to Personal Data Processing independently (for example, the digital age of consent under the GDPR, which varies between 13 and 16 years in the respective EU member states, may differ from the generally applicable age of majority), the higher mandatory minimum age in the User country of domicile shall apply to the User concerned.',
      ),
      LegalItem(
        '4. We do not process, and do not intend to process, Personal Data deliberately from individuals who have not met the age limit referred to in paragraph (1) and/or paragraph (3), whichever is higher.',
      ),
      LegalItem(
        '5. If We obtain knowledge or have reasonable grounds to believe that Personal Data has been collected from an individual who has not met the said age limit, We will promptly and without undue delay: (a) suspend and/or deactivate the account concerned; (b) delete all related Personal Data from production systems and backup systems within a technically and operationally reasonable period; and (c) where required by applicable law, report the matter to the competent authority.',
      ),
      LegalItem(
        '6. Parents, guardians, or parties with legal authority over a child who believe that the child has used the Application contrary to the provisions of this Article may submit a request for immediate deletion through the official contact as described in Article 22 of this Policy.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER III — PERSONAL DATA WE PROCESS',
    article: 'Article 5 — Categories and Details of Personal Data',
    items: [
      LegalItem(
        'In the course of operating the Application, We process the following categories of Personal Data:',
      ),
      LegalItem(
        '(1) **Account and Profile Data**, including: username, display name, gender, date of birth/age, country and city of domicile, profile photo, cover photo, bio or self-description, email address where registration is done via email or via a third-party login facility, and passwords stored in encrypted/one-way hash form and never stored or displayed in plaintext.',
      ),
      LegalItem(
        '(2) **Location Data**, including: (a) country and city derived automatically from the Internet Protocol (IP) address, collected for content localization and security risk mitigation purposes; and (b) precise Global Positioning System (GPS) location coordinates, which are **only** collected if You give explicit, unambiguous device location access permission, separate from the general consent to use the Application, and which You may revoke at any time through the operating system settings of Your device or through the settings in the Application.',
      ),
      LegalItem(
        '(3) **Content Data**, including: text messages in private conversations and chat rooms, photos and media files, including the disappearing photo feature, uploads, statuses, comments, and technical metadata attached to such media files (e.g., file size and format), provided that Exchangeable Image File Format (EXIF) data that may contain precise location information will be removed or cleaned before storage to the extent technically feasible.',
      ),
      LegalItem(
        '(4) **Social and Interaction Data**, including: the list of Users You follow and who follow You, friend lists, subscription history between Users to the extent such feature is available, block lists You set, and reports You submit against other Users or content, including reports submitted by others against You.',
      ),
      LegalItem(
        '(5) **Technical Data and Log Records**, including: IP address, device type and version, operating system, device identifier, and Application usage metrics within the minimal scope (data minimization) needed for system security, detection and prevention of abuse, and service maintenance and repair, including system failure records and access records to sensitive features.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 6 — Sources of Personal Data',
    items: [
      LegalItem(
        '1. **Obtained directly from You**, namely when You register, complete Your profile, send messages, and upload media.',
      ),
      LegalItem(
        '2. **Obtained automatically through electronic systems**, namely including IP addresses and technical device data as referred to in Article 5 paragraph (5).',
      ),
      LegalItem(
        '3. **Obtained from Third Parties**, namely including data forwarded by a third-party login service provider (limited to name, email address, and basic profile photo in accordance with the permissions You grant at login), and IP-based geolocation service providers.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 7 — Restrictions on Processing Sensitive Data',
    items: [
      LegalItem(
        'We do not deliberately collect or process data concerning the health conditions, political affiliations, sexual orientation, or religious beliefs of Users.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER IV — PURPOSES AND LEGAL BASES OF PROCESSING',
    article: 'Article 8 — Legal Bases of Processing',
    items: [
      LegalItem(
        'In accordance with Article 20 of the PDP Law, every Processing of Personal Data carried out by Us is always based on one or more of the following legal bases:',
      ),
      LegalItem(
        '',
        table: [
          ['Legal Basis', 'Application in ChatYuk'],
          [
            'a. Explicit consent from the Personal Data Subject',
            'Collection of precise GPS location data; processing of the disappearing photo feature',
          ],
          [
            'b. Performance of a contract to which the Personal Data Subject is a party, or to take steps at the request of the Personal Data Subject prior to entering into a contract',
            'Account creation and management; provision of chat, chat room, and social features',
          ],
          [
            'c. Compliance with a legal obligation of the Personal Data Controller in accordance with laws and regulations',
            'Compliance with applicable legal obligations; reporting to competent authorities where required by law',
          ],
          [
            'd. Pursuit of other legitimate interests while taking into account the purposes, needs, and balance between the interests of the Personal Data Controller and the rights of the Personal Data Subject',
            'Maintaining system security; detection and prevention of fraud and abuse; content moderation; enforcement of the Terms of Service',
          ],
          [
            'e. Vital interests of the Personal Data Subject',
            'Emergency situations that genuinely threaten the life of the User, where applicable',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    article: 'Article 9 — Purposes of Processing',
    items: [
      LegalItem(
        'Your Personal Data is processed for the following purposes: (a) providing, maintaining, and improving Application features; (b) personalizing the user experience; (c) preventing, detecting, and handling fraud and any form of Application abuse; (d) content moderation and handling of reports between Users; (e) delivering service-related communications, including notifications and security notices; and (f) fulfilling legal obligations and complying with applicable laws and regulations.',
      ),
      LegalItem(
        'We hereby confirm that We do not use Your Personal Data for fully automated decision-making that produces significant legal effects on You without human intervention, unless separately and individually notified to You together with its legal basis.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER V — DISCLOSURE OF PERSONAL DATA TO THIRD PARTIES',
    article: 'Article 10 — General Principles',
    items: [
      LegalItem(
        '1. We expressly state that We do **not sell, rent, or trade** Your Personal Data to any party for commercial purposes beyond what is regulated in this Policy.',
      ),
      LegalItem(
        '2. Disclosure of Personal Data to Third Parties is carried out only to the extent reasonably necessary for the operation of the Application, and always observes the principle of data minimization, namely limited to data that is relevant and necessary for the said purpose.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 11 — Details of Personal Data Recipients',
    items: [
      LegalItem(
        '',
        table: [
          ['Third Party', 'Position', 'Scope of Data Processed'],
          [
            'Data infrastructure provider (database, authentication, and cloud storage)',
            'Acting as a Personal Data Processor',
            'All Personal Data and content stored on the servers, with the application of Row-Level Security access controls',
          ],
          [
            'Third-party login service provider',
            'Third-party authentication service provider',
            'Authentication tokens; basic profile data in accordance with the scope of permissions You grant at login',
          ],
          [
            'IP-based geolocation service provider',
            'Determining country and city based on IP address',
            'IP address',
          ],
          [
            'Competent agencies/authorities',
            'Law enforcement and fulfillment of legitimate requests from government institutions',
            'Limited to the scope of legitimate, verifiable legal requests in accordance with applicable laws and regulations',
          ],
          [
            'Professional advisors (e.g., auditors, legal counsel)',
            'Legitimate business interests and subject to confidentiality obligations',
            'Limited to what is reasonably necessary for the provision of such professional services',
          ],
        ],
      ),
      LegalItem(
        '3. Each Third Party mentioned above has its own privacy policy and security practices that are outside Our direct control. We make reasonable efforts to cooperate with partners that apply adequate data protection standards, but still recommend that You read and understand the privacy policy of each such Third Party.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 12 — Cross-Border Transfer of Personal Data',
    items: [
      LegalItem(
        '1. Given that the infrastructure provider referred to in Article 11 may place servers in jurisdictions outside the territory of the Republic of Indonesia, Your Personal Data may be processed outside Your country of domicile.',
      ),
      LegalItem(
        '2. In the event of a cross-border transfer of Personal Data as referred to in paragraph (1), We will ensure that at least one of the following requirements set out in Article 56 of the PDP Law is met: (a) the country where the Personal Data recipient is located has a level of Personal Data protection equal to or higher than the PDP Law; (b) there is adequate and binding Personal Data protection through a data processing agreement between Us and the data recipient; and/or (c) We have obtained Your Consent for such transfer.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VI — STORAGE, SECURITY, AND INCIDENT HANDLING',
    article: 'Article 13 — Technical and Organizational Measures',
    items: [
      LegalItem(
        'In order to protect Your Personal Data from loss, misuse, unauthorized access, alteration, and unlawful disclosure, We apply the following technical and organizational measures:',
      ),
      LegalItem(
        '1. **Row-Level Security access controls** on the database, so that each User can only access data belonging to themselves in accordance with the access rights that have been established.',
      ),
      LegalItem(
        '2. **Encryption of data stored on the device (at rest)**: messages and photos temporarily stored (cached) on Your device are encrypted using the AES-GCM algorithm, with encryption keys stored in the Android Keystore (hardware-backed where supported by the device).',
      ),
      LegalItem(
        '3. **Encryption of data in transit**: all communication between the Application and Our servers is encrypted using the Transport Layer Security (TLS)/HTTPS protocol.',
      ),
      LegalItem(
        '4. **Forensic watermark**: disappearing photos are given a hidden watermark containing the identity of the recipient, as a forensic trace in the event of misuse, including but not limited to screenshots that succeed despite having passed through the protection mechanisms.',
      ),
      LegalItem(
        '5. **Anti-screenshot protection**: pages displaying sensitive content, including disappearing photos, are protected with screenshot and screen recording prevention features at the operating system level, to the extent supported by the device platform concerned.',
      ),
      LegalItem(
        '6. **Internal access controls**: access of Our staff and/or administrators to Personal Data is restricted based on the need-to-know principle and recorded in audit logs.',
      ),
      LegalItem(
        '7. **Periodic system vulnerability assessments** as part of Our commitment to the ongoing maintenance of electronic system security.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 14 — Limitations of Security Liability',
    items: [
      LegalItem(
        'Although We have applied the technical and organizational measures described in Article 13, You understand and agree that **no electronic system can guarantee absolute security** from all forms of cybersecurity threats. Therefore, We cannot provide an absolute guarantee of the security of Personal Data that You send or store through the Application, even though We always make reasonable efforts to protect it.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Article 15 — Incident and Personal Data Breach Handling Procedures',
    items: [
      LegalItem(
        '1. In the event of a Personal Data protection failure that results in the risk of leakage, loss, misuse, unauthorized access, or disclosure of Personal Data (an "Incident"), We will promptly conduct an investigation and take the necessary mitigation measures.',
      ),
      LegalItem(
        '2. In accordance with applicable provisions, We will submit written notification to the affected Personal Data Subjects and to the Personal Data Protection supervisory body/competent Ministry, no later than 3 x 24 (three times twenty-four) hours from the time the Incident becomes known, containing at least: (a) a description of the affected Personal Data; (b) the chronology and manner of the Incident; and (c) the handling and recovery efforts that We have made and will make.',
      ),
      LegalItem(
        '3. We will provide guidance on security measures You can take independently (e.g., password changes) to the extent relevant to the Incident that occurred.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VII — RETENTION AND DELETION OF PERSONAL DATA',
    article: 'Article 16 — Retention Periods',
    items: [
      LegalItem(
        '',
        table: [
          ['Data Category', 'Retention Period'],
          [
            'Account and profile data',
            'For as long as the account remains active; permanently deleted within a reasonable period after account deletion by the User',
          ],
          [
            'Content data (messages, photos, chat rooms)',
            'For as long as the account remains active, except for disappearing photos which are automatically deleted after being viewed or after their validity period ends in accordance with the feature design',
          ],
          [
            'Moderation logs and reports',
            'Retained for the limited period needed for enforcement of the terms of service, dispute resolution, and fulfillment of legal obligations',
          ],
          [
            'Technical data and security logs',
            'Retained for the limited period needed for electronic system security',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    article: 'Article 17 — Deletion Mechanism',
    items: [
      LegalItem(
        'Account deletion performed by the User through the profile menu will result in the permanent deletion of the profile and related content from Our production systems within a technically reasonable period, except for data that We are required to retain in connection with legal obligations as referred to in Article 16, or for the purpose of dispute resolution still ongoing at the time the deletion request is submitted.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VIII — RIGHTS OF PERSONAL DATA SUBJECTS',
    article: 'Article 18 — Description of Rights',
    items: [
      LegalItem(
        'In accordance with Chapter VI of the PDP Law, as a Personal Data Subject You have the following rights:',
      ),
      LegalItem(
        '1. **The right to obtain information**, namely the right to receive an explanation regarding Our identity as the Personal Data Controller, the lawful legal basis, and the purposes of the request and use of Your Personal Data.',
      ),
      LegalItem(
        '2. **The right to complete, update, and/or correct** errors and/or inaccuracies in Your Personal Data in accordance with the purposes of the Personal Data Processing.',
      ),
      LegalItem(
        '3. **The right to terminate Processing**, delete, and/or destroy Your Personal Data, except for Personal Data that must be retained in accordance with laws and regulations.',
      ),
      LegalItem(
        '4. **The right to withdraw Consent** previously given to Us, including revoking access permission to precise GPS location, provided that such withdrawal does not affect the validity of Processing carried out prior to the withdrawal.',
      ),
      LegalItem(
        '5. **The right to object** to Processing actions that constitute automated decision-making, including profiling, that produce legal effects or significantly impact You.',
      ),
      LegalItem(
        '6. **The right to delay or restrict** Personal Data Processing proportionally in accordance with the purposes of the Processing.',
      ),
      LegalItem(
        '7. **The right to sue and receive compensation** for violations of Personal Data Processing concerning oneself in accordance with applicable laws and regulations.',
      ),
      LegalItem(
        '8. **The right to obtain and/or use Personal Data (data portability)** in a form that conforms to commonly used formats or is readable by electronic systems.',
      ),
      LegalItem(
        '9. **The right to lodge a complaint** regarding alleged violations of Personal Data Processing concerning oneself, either to Us or to the competent Personal Data Protection supervisory body.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 19 — Mechanism for Exercising Rights',
    items: [
      LegalItem(
        'Most of the rights referred to in Article 18 can be exercised by You independently through the profile menu and settings available in the Application. For requests not directly available through Application features, including requests for data portability in a structured format, You may submit a written request through the official contact as referred to in Article 22 of this Policy. We will follow up on every request within a reasonable period and in accordance with applicable laws and regulations, and reserve the right to verify the identity of the requester before following up on such request in order to protect Personal Data from unauthorized access.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER IX — TRACKING TECHNOLOGIES',
    article: 'Article 20 — Cookies and Similar Technologies',
    items: [
      LegalItem(
        'Where the Application uses cookies, local storage, analytics software development kits, or other similar identifier technologies for login session management and/or usage analytics purposes, We will describe separately the types, purposes, and management mechanisms thereof in this section after the relevant feature is officially implemented.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER X — CHANGES TO THE POLICY',
    article: 'Article 21 — Procedure for Changes',
    items: [
      LegalItem(
        '1. We reserve the right to review and update this Policy from time to time to reflect changes in Application features, operational practices, and/or applicable laws and regulations.',
      ),
      LegalItem(
        '2. Any material changes will be notified to You through the Application, either through in-app notifications or notifications upon opening the Application, before such changes become effective.',
      ),
      LegalItem(
        '3. Your continued use of the Application after the effective date of a Policy change is deemed a form of Your consent to the updated Policy.',
      ),
      LegalItem(
        '4. To the extent a change significantly expands the scope of Processing of sensitive or specific Personal Data, We will request new explicit Consent from You where required by applicable law.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER XI — CONTACT AND COMPLAINTS',
    article: 'Article 22 — Official Contact',
    items: [
      LegalItem(
        'For any questions, requests, and/or complaints regarding this Privacy Policy or the Processing of Your Personal Data, please contact us through the **Contact Us** menu in the Application, which can be accessed from the Profile page.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 23 — Right to Complain to the Supervisory Body',
    items: [
      LegalItem(
        'If You do not obtain a satisfactory resolution of the request or complaint You submit to Us, You have the right to submit a further complaint to the competent Personal Data Protection supervisory body in the Republic of Indonesia in accordance with applicable laws and regulations.',
      ),
    ],
  ),
  LegalSection(
    chapter:
        'CHAPTER XII — ADDITIONAL PROVISIONS FOR USERS FROM CERTAIN JURISDICTIONS',
    article: 'Article 24 — General Principles',
    items: [
      LegalItem(
        '1. The Application is provided to Users in various countries. The Personal Data protection standards described in Chapters I to XI of this Policy apply as a uniform minimum standard for all Users.',
      ),
      LegalItem(
        '2. If the law applicable in Your country of domicile provides additional rights, additional obligations for Us, or a higher level of protection than described in this Policy, then the additional provisions described in Articles 25 and 26 below apply to You, to the extent relevant to Your jurisdiction, without prejudice to the applicability of the general provisions of this Policy.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Article 25 — Additional Provisions for Users in the European Union/European Economic Area and the United Kingdom (GDPR)',
    items: [
      LegalItem(
        'For Users domiciled in the European Union, the European Economic Area (EEA), or the United Kingdom, the following additional provisions apply:',
      ),
      LegalItem(
        '1. **The legal basis of Processing** follows the counterparts set out in Article 6 of the GDPR, namely Consent, performance of a contract, legal obligation, vital interests, and legitimate interest, as already described by their counterparts in Article 8 of this Policy.',
      ),
      LegalItem(
        '2. You have additional rights in the form of **the right to data portability** in a structured, commonly used, and machine-readable format; **the right to be forgotten** to the extent it does not conflict with Our legal obligations to retain certain data; and **the right to object** to Processing based on Our legitimate interests.',
      ),
      LegalItem(
        '3. You have the right to lodge a complaint with the competent data protection supervisory authority in Your country of domicile, including but not limited to the supervisory authority in the EU member state where You reside or work, or where the alleged violation occurred.',
      ),
      LegalItem(
        '4. Transfers of Personal Data outside the EEA/United Kingdom, including to Indonesia, will be carried out with lawful safeguard mechanisms, including through Standard Contractual Clauses or other mechanisms recognized under applicable law, consistent with the cross-border transfer principles in Article 12 of this Policy.',
      ),
    ],
  ),
  LegalSection(
    article:
        'Article 26 — Additional Provisions for Users in California, United States (CCPA/CPRA)',
    items: [
      LegalItem(
        'For Users domiciled in the State of California, United States, the following additional provisions apply:',
      ),
      LegalItem(
        '1. You have the right to know the categories and sources of Personal Data We collect, the purposes of collection, and the parties that receive such Personal Data, as already described in Chapters III and V of this Policy.',
      ),
      LegalItem(
        '2. You have the right to request the deletion of Your Personal Data, with exceptions for data We are required to retain to fulfill legal obligations as described in Article 16 of this Policy.',
      ),
      LegalItem(
        '3. You have the right not to be treated discriminatorily by Us in connection with the exercise of Your rights under the CCPA/CPRA.',
      ),
      LegalItem(
        '4. As affirmed in Article 10 of this Policy, We do not sell or share Your Personal Data as defined in the CCPA/CPRA for cross-context behavioral advertising purposes.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 27 — Provisions for Users in Other Jurisdictions',
    items: [
      LegalItem(
        'For Users domiciled in other countries that have their own personal data protection regulations, including but not limited to Singapore (Personal Data Protection Act), Malaysia, the Philippines, India, or other countries in the Southeast Asian and Asia-Pacific regions, We will make reasonable efforts to comply with the minimum requirements imposed by local law to the extent they do not conflict with this Policy as a whole. In the event of a conflict between mandatory provisions of local law and the provisions of this Policy, such mandatory provisions of local law will prevail to the extent they concern Users from the relevant jurisdiction.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER XIII — GOVERNING LAW AND DISPUTE RESOLUTION',
    article: 'Article 28 — Governing Law',
    items: [
      LegalItem(
        '1. This Policy is drafted and interpreted in accordance with the laws of the Republic of Indonesia, including but not limited to the PDP Law and the EIT Law together with their implementing regulations, which apply as the main governing law over the legal relationship between Us and all Users, wherever Users are domiciled.',
      ),
      LegalItem(
        '2. The provisions of paragraph (1) apply without prejudice to the mandatory rights of Users under consumer protection law and/or personal data protection law in the User country of domicile, as described in Chapter XII of this Policy, to the extent such local law cannot be overridden by choice of law.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 29 — Dispute Resolution',
    items: [
      LegalItem(
        'Any dispute, difference of opinion, or disagreement arising in connection with this Policy will first be resolved through deliberation to reach consensus between the parties. If deliberation does not reach a resolution within a reasonable period, the dispute will be resolved through the applicable legal channels in the jurisdiction of the Republic of Indonesia, without prejudice to the right of Users from certain jurisdictions to lodge complaints with the local supervisory authority as described in Chapter XII.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 30 — Audio and Video Calls',
    items: [
      LegalItem(
        '1. The audio and video calling feature (1:1) is available to registered Users. When You make or receive a call, microphone and/or camera access is required, and call media is transmitted **point-to-point (P2P)** between devices, with signaling servers used only to establish the initial connection.',
      ),
      LegalItem(
        '2. When a call is initiated, We store call technical data (caller identity, recipient identity, call type, start time, end time, and call status) as an internal transaction record for technical support, complaint handling, and moderation purposes.',
      ),
      LegalItem(
        '3. The content of audio/video conversations is not recorded, stored, or processed by Us. Calls are real-time and direct between Users.',
      ),
      LegalItem(
        '4. Under certain network conditions (for example symmetric NAT or unstable connections), call connection traffic may be relayed through a third-party relay server (TURN) to keep the call working. Relay servers only forward encrypted media packets and do not store call content.',
      ),
      LegalItem(
        '5. The calling feature must not be used to send content that violates the Terms of Service, including illegal content or harassment. Violations may result in account restrictions or termination.',
      ),
    ],
  ),
];

const _termsId = <LegalSection>[
  LegalSection(
    chapter: 'BAB I — KETENTUAN UMUM',
    article: 'Pasal 1 — Pendahuluan dan Penerimaan Perjanjian',
    items: [
      LegalItem(
        '1. Syarat dan Ketentuan Layanan ini ("**Perjanjian**", "**Syarat Layanan**") merupakan perjanjian yang sah dan mengikat secara hukum antara Anda selaku pengguna perseorangan ("**Pengguna**", "**Anda**") dengan pengembang dan penyelenggara aplikasi ChatYuk ("**Penyelenggara**", "**Kami**") sehubungan dengan pengunduhan, pemasangan, pendaftaran, akses, dan/atau penggunaan aplikasi ChatYuk beserta seluruh fitur di dalamnya ("**Aplikasi**", "**Layanan**").',
      ),
      LegalItem(
        '2. Dengan mengunduh, memasang, mendaftarkan diri, mengakses, dan/atau menggunakan Aplikasi dengan cara apa pun, Anda menyatakan dan menjamin bahwa Anda telah membaca, memahami secara utuh, dan menyetujui secara sadar serta sukarela untuk terikat pada seluruh ketentuan dalam Perjanjian ini beserta Kebijakan Privasi ChatYuk yang merupakan bagian tidak terpisahkan dari Perjanjian ini. Apabila Anda tidak menyetujui salah satu atau seluruh ketentuan dalam Perjanjian ini, Kami dengan hormat meminta agar Anda tidak melanjutkan pengunduhan, pemasangan, dan/atau penggunaan Aplikasi.',
      ),
      LegalItem(
        '3. Perjanjian ini berlaku secara global bagi seluruh Pengguna di mana pun domisili atau lokasinya berada, dengan ketentuan tambahan bagi Pengguna dari yurisdiksi tertentu sebagaimana diuraikan dalam Bab XIII Perjanjian ini.',
      ),
      LegalItem(
        '4. Kami berhak menolak permohonan pendaftaran, membatasi, menangguhkan, atau mengakhiri akses Anda terhadap Aplikasi sewaktu-waktu sesuai dengan ketentuan dalam Perjanjian ini.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 2 — Definisi',
    items: [
      LegalItem(
        '',
        table: [
          ['Istilah', 'Penjelasan'],
          [
            'Akun',
            'Akun pengguna terdaftar yang dibuat melalui proses pendaftaran pada Aplikasi.',
          ],
          [
            'Konten',
            'Segala bentuk pesan, teks, foto, gambar, video, audio, tautan, atau materi lain yang diunggah, dikirim, atau dibagikan oleh Pengguna melalui Aplikasi.',
          ],
          [
            'Konten Pengguna',
            'Konten yang dibuat, diunggah, atau dikirimkan oleh Pengguna, termasuk namun tidak terbatas pada pesan dalam obrolan, ruang obrolan (Room), status, komentar, dan foto sekali lihat.',
          ],
          [
            'Ruang Obrolan (Room)',
            'Fitur dalam Aplikasi yang memungkinkan interaksi antar-Pengguna dalam suatu forum atau ruang bersama.',
          ],
          [
            'Foto Sekali Lihat',
            'Fitur pengiriman foto yang bersifat sementara dan akan hilang atau tidak dapat diakses kembali setelah dilihat atau setelah jangka waktu tertentu.',
          ],
          [
            'Hari Kerja',
            'Hari kerja yang berlaku umum di Indonesia, tidak termasuk hari Sabtu, Minggu, dan hari libur nasional.',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB II — KELAYAKAN DAN PENDAFTARAN AKUN',
    article: 'Pasal 3 — Persyaratan Usia dan Kecakapan Hukum',
    items: [
      LegalItem(
        '1. Aplikasi ChatYuk hanya diperuntukkan bagi individu yang telah berusia paling rendah 17 (tujuh belas) tahun. Dengan mendaftar dan menggunakan Aplikasi, Anda menyatakan dan menjamin bahwa Anda telah memenuhi persyaratan usia tersebut.',
      ),
      LegalItem(
        '2. Sepanjang hukum di negara domisili Anda menetapkan batas usia minimum atau batas kecakapan hukum (*legal capacity*) untuk mengikatkan diri dalam perjanjian elektronik yang lebih tinggi daripada 17 (tujuh belas) tahun, maka batas usia yang lebih tinggi tersebut yang berlaku bagi Anda.',
      ),
      LegalItem(
        '3. Anda menyatakan dan menjamin bahwa Anda memiliki kecakapan hukum penuh untuk mengikatkan diri pada Perjanjian ini berdasarkan hukum yang berlaku di negara domisili Anda.',
      ),
      LegalItem(
        '4. Kami berhak, namun tidak berkewajiban, untuk meminta bukti tambahan guna memverifikasi usia dan kecakapan hukum Anda.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 4 — Pendaftaran dan Keamanan Akun',
    items: [
      LegalItem(
        '1. Untuk menggunakan fitur tertentu dalam Aplikasi, Anda diwajibkan membuat Akun melalui pendaftaran dengan surat elektronik atau melalui fasilitas masuk dengan akun pihak ketiga.',
      ),
      LegalItem(
        '2. Anda bertanggung jawab penuh untuk memberikan informasi pendaftaran yang benar, akurat, terkini, dan lengkap, serta memperbarui informasi tersebut apabila terjadi perubahan.',
      ),
      LegalItem(
        '3. Anda bertanggung jawab penuh untuk menjaga kerahasiaan kata sandi dan kredensial Akun Anda, serta untuk seluruh aktivitas yang terjadi melalui Akun Anda, baik dilakukan oleh Anda sendiri maupun oleh pihak lain yang menggunakan Akun Anda dengan atau tanpa izin Anda.',
      ),
      LegalItem(
        '4. Anda wajib segera memberitahukan Kami apabila mengetahui atau memiliki alasan untuk menduga terjadinya akses tidak sah terhadap Akun Anda.',
      ),
      LegalItem(
        '5. Satu individu hanya diperkenankan memiliki 1 (satu) Akun, kecuali diperjanjikan lain secara tertulis dengan Kami. Kami berhak menangguhkan atau menghapus Akun ganda (*duplicate account*) yang terdeteksi.',
      ),
      LegalItem(
        '6. Anda dilarang mengalihkan, menjual, menyewakan, atau memindahtangankan Akun Anda kepada pihak lain dengan cara apa pun tanpa persetujuan tertulis terlebih dahulu dari Kami.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB III — LISENSI PENGGUNAAN APLIKASI',
    article: 'Pasal 5 — Pemberian Lisensi',
    items: [
      LegalItem(
        '1. Tunduk pada kepatuhan Anda terhadap Perjanjian ini, Kami memberikan kepada Anda lisensi yang bersifat terbatas, tidak eksklusif, tidak dapat dialihkan (*non-transferable*), tidak dapat disublisensikan, dan dapat dicabut sewaktu-waktu (*revocable*), untuk mengunduh, memasang, dan menggunakan Aplikasi semata-mata untuk keperluan pribadi dan non-komersial Anda, sesuai dengan tujuan penyediaan Aplikasi.',
      ),
      LegalItem(
        '2. Lisensi sebagaimana dimaksud pada ayat (1) tidak memberikan hak kepemilikan apa pun kepada Anda atas Aplikasi, kecuali hak penggunaan sebagaimana diatur dalam Perjanjian ini.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 6 — Pembatasan Penggunaan',
    items: [
      LegalItem(
        'Anda dilarang untuk: (a) melakukan rekayasa balik (*reverse engineering*), dekompilasi, atau membongkar Aplikasi, kecuali sepanjang diizinkan oleh peraturan perundang-undangan yang bersifat memaksa; (b) menyalin, memodifikasi, mendistribusikan, menjual, atau menyewakan bagian mana pun dari Aplikasi; (c) menggunakan Aplikasi untuk tujuan komersial tanpa izin tertulis dari Kami; (d) menggunakan robot, *spider*, *scraper*, atau alat otomatis lain untuk mengakses Aplikasi tanpa izin; dan/atau (e) mengganggu atau membebani infrastruktur teknis yang mendukung Aplikasi.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB IV — KETENTUAN PERILAKU PENGGUNA DAN KONTEN',
    article: 'Pasal 7 — Standar Perilaku',
    items: [
      LegalItem(
        'Anda setuju untuk menggunakan Aplikasi secara bertanggung jawab dan sesuai dengan hukum yang berlaku, serta setuju untuk tidak:',
      ),
      LegalItem(
        '1. Mengunggah, mengirim, atau menyebarkan Konten yang bersifat melanggar hukum, memfitnah, mencemarkan nama baik, mengandung ujaran kebencian, diskriminatif, mengandung unsur pornografi, eksploitasi seksual anak, kekerasan, atau ancaman kekerasan;',
      ),
      LegalItem(
        '2. Melakukan tindakan pelecehan (*harassment*), perundungan (*bullying*), intimidasi, penguntitan (*stalking*), atau tindakan lain yang mengganggu, mengancam, atau merugikan Pengguna lain;',
      ),
      LegalItem(
        '3. Meniru identitas pihak lain, menyamarkan afiliasi dengan pihak tertentu, atau melakukan tindakan penipuan (*fraud*) terhadap Pengguna lain;',
      ),
      LegalItem(
        '4. Menyebarkan informasi palsu atau menyesatkan (*misinformation*) yang berpotensi merugikan pihak lain atau masyarakat;',
      ),
      LegalItem(
        '5. Melanggar hak kekayaan intelektual, hak privasi, atau hak lain milik pihak ketiga;',
      ),
      LegalItem(
        '6. Mengunggah perangkat lunak berbahaya (*malware*), tautan mencurigakan, atau melakukan tindakan yang dapat merusak, mengganggu, atau membahayakan sistem Aplikasi maupun perangkat Pengguna lain;',
      ),
      LegalItem(
        '7. Menggunakan Aplikasi untuk kegiatan yang melanggar hukum dalam bentuk apa pun, termasuk namun tidak terbatas pada perjudian ilegal atau perdagangan barang/jasa terlarang;',
      ),
      LegalItem(
        '8. Meminta, mendistribusikan, atau menyebarkan Konten yang melibatkan atau mengeksploitasi individu di bawah umur dalam bentuk apa pun.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 8 — Moderasi Konten dan Penanganan Laporan',
    items: [
      LegalItem(
        '1. Kami berhak, namun tidak berkewajiban, untuk memantau, meninjau, menghapus, atau membatasi akses terhadap Konten yang melanggar Perjanjian ini, tanpa perlu memberikan pemberitahuan terlebih dahulu, sepanjang secara wajar diperlukan untuk menjaga integritas dan keamanan Aplikasi.',
      ),
      LegalItem(
        '2. Anda dapat melaporkan Konten atau Pengguna lain yang diduga melanggar Perjanjian ini melalui fitur pelaporan yang tersedia dalam Aplikasi. Kami akan menindaklanjuti laporan tersebut sesuai dengan kebijakan moderasi internal Kami.',
      ),
      LegalItem(
        '3. Kami berhak mengambil tindakan terhadap Pengguna yang melanggar Perjanjian ini, berupa peringatan, pembatasan fitur tertentu, penangguhan sementara, hingga penghapusan permanen Akun, sebagaimana diatur lebih lanjut dalam Bab X.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 9 — Fitur Foto Sekali Lihat',
    items: [
      LegalItem(
        '1. Fitur Foto Sekali Lihat disediakan untuk memungkinkan Pengguna mengirimkan foto yang bersifat sementara. Meskipun Kami menerapkan langkah teknis berupa penanda air forensik dan proteksi anti-tangkapan layar sebagaimana diuraikan dalam Kebijakan Privasi, Anda memahami dan menyetujui bahwa **Kami tidak dapat menjamin secara mutlak** bahwa penerima tidak akan menyimpan, memotret, merekam, atau menyebarluaskan foto dimaksud dengan cara lain di luar kendali teknis Kami.',
      ),
      LegalItem(
        '2. Anda bertanggung jawab penuh atas keputusan Anda untuk mengirimkan Konten apa pun, termasuk melalui fitur Foto Sekali Lihat, kepada Pengguna lain. Kami tidak bertanggung jawab atas penyalahgunaan Konten yang telah Anda kirimkan oleh penerima di luar kendali sistem Kami.',
      ),
      LegalItem(
        '3. Penyalahgunaan fitur ini, termasuk pengiriman Konten yang melanggar Pasal 7, dapat dikenakan tindakan sebagaimana diatur dalam Pasal 8 ayat (3) dan/atau dilaporkan kepada pihak berwenang sepanjang diwajibkan hukum.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB V — HAK ATAS KONTEN',
    article: 'Pasal 10 — Kepemilikan Konten Pengguna',
    items: [
      LegalItem(
        '1. Anda tetap memegang seluruh hak kepemilikan atas Konten Pengguna yang Anda buat dan unggah ke Aplikasi.',
      ),
      LegalItem(
        '2. Dengan mengunggah Konten Pengguna ke Aplikasi, Anda memberikan kepada Kami lisensi yang bersifat non-eksklusif, dapat disublisensikan secara terbatas, berlaku secara global, dan bebas royalti, untuk menyimpan, mereproduksi, menampilkan, mengirimkan, dan mendistribusikan Konten Pengguna dimaksud semata-mata sepanjang secara wajar diperlukan untuk menyediakan dan mengoperasikan fitur-fitur Aplikasi (mis. menampilkan pesan kepada penerima yang dituju, menyimpan riwayat percakapan).',
      ),
      LegalItem(
        '3. Lisensi sebagaimana dimaksud pada ayat (2) akan berakhir pada saat Konten Pengguna dimaksud dihapus dari Aplikasi, kecuali sepanjang: (a) Konten tersebut telah dibagikan kepada Pengguna lain yang menyimpannya secara sah dalam sistem; atau (b) Kami diwajibkan menyimpan Konten dimaksud berdasarkan kewajiban hukum sebagaimana diuraikan dalam Kebijakan Privasi.',
      ),
      LegalItem(
        '4. Anda menyatakan dan menjamin bahwa Anda memiliki seluruh hak yang diperlukan atas Konten Pengguna yang Anda unggah, dan bahwa Konten dimaksud tidak melanggar hak pihak ketiga mana pun, termasuk hak kekayaan intelektual dan hak privasi.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 11 — Hak Kekayaan Intelektual Kami',
    items: [
      LegalItem(
        'Seluruh hak kekayaan intelektual atas Aplikasi, termasuk namun tidak terbatas pada kode sumber, tampilan antarmuka (*user interface*), logo, merek dagang, ikon, maskot, dan elemen desain lainnya, merupakan milik Kami atau pemberi lisensi Kami, dan dilindungi oleh peraturan perundang-undangan di bidang hak kekayaan intelektual. Tidak ada satu pun ketentuan dalam Perjanjian ini yang dapat ditafsirkan sebagai pengalihan hak kekayaan intelektual dimaksud kepada Anda.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VI — LAYANAN DAN MITRA PIHAK KETIGA',
    article: 'Pasal 12 — Integrasi Pihak Ketiga',
    items: [
      LegalItem(
        '1. Aplikasi terintegrasi dengan sejumlah layanan pihak ketiga untuk mendukung operasionalnya, termasuk namun tidak terbatas pada penyedia infrastruktur basis data dan autentikasi, serta penyedia layanan masuk (login) pihak ketiga, sebagaimana diuraikan lebih rinci dalam Kebijakan Privasi ChatYuk.',
      ),
      LegalItem(
        '2. Penggunaan layanan pihak ketiga tersebut oleh Anda dapat tunduk pada syarat dan ketentuan serta kebijakan privasi masing-masing penyedia layanan, yang berada di luar kendali Kami. Kami menganjurkan Anda untuk membaca dan memahami ketentuan masing-masing pihak ketiga dimaksud.',
      ),
      LegalItem(
        '3. Kami tidak bertanggung jawab atas tindakan, kelalaian, gangguan layanan, atau kerugian yang timbul akibat kegagalan sistem pada pihak penyedia layanan ketiga di luar kendali wajar Kami, meskipun Kami akan berupaya sepatutnya untuk memitigasi dampaknya terhadap Pengguna.',
      ),
      LegalItem(
        '4. Kami berhak menambah, mengganti, atau menghentikan kerja sama dengan penyedia layanan pihak ketiga tertentu sewaktu-waktu.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VII — PENGHENTIAN, PENANGGUHAN, DAN PENGHAPUSAN AKUN',
    article: 'Pasal 13 — Penghentian oleh Pengguna',
    items: [
      LegalItem(
        'Anda dapat menghentikan penggunaan Aplikasi dan menghapus Akun Anda kapan pun melalui menu pengaturan profil dalam Aplikasi. Penghapusan Akun akan diproses sesuai dengan ketentuan retensi dan penghapusan data sebagaimana diuraikan dalam Kebijakan Privasi ChatYuk.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 14 — Penangguhan dan Penghapusan oleh Kami',
    items: [
      LegalItem(
        '1. Kami berhak menangguhkan sementara atau menghapus permanen Akun Anda, dengan atau tanpa pemberitahuan terlebih dahulu, apabila: (a) Anda melanggar salah satu atau lebih ketentuan dalam Perjanjian ini; (b) terdapat indikasi wajar bahwa Anda menggunakan Aplikasi untuk kegiatan yang melanggar hukum; (c) diwajibkan oleh perintah pengadilan atau otoritas yang berwenang; atau (d) diperlukan untuk melindungi keamanan Aplikasi, Kami, atau Pengguna lain.',
      ),
      LegalItem(
        '2. Dalam hal penangguhan atau penghapusan Akun dilakukan sehubungan dengan dugaan pelanggaran, Kami akan berupaya sepatutnya untuk memberikan pemberitahuan kepada Anda mengenai alasan tindakan tersebut, kecuali apabila pemberitahuan dimaksud dapat menghambat proses investigasi atau dilarang oleh ketentuan hukum yang berlaku.',
      ),
      LegalItem(
        '3. Penghapusan atau penangguhan Akun tidak menghapuskan kewajiban Anda yang telah timbul sebelum tanggal penghapusan/penangguhan.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB VIII — PENAFIAN DAN BATASAN TANGGUNG JAWAB',
    article: 'Pasal 15 — Penafian Jaminan',
    items: [
      LegalItem(
        '1. APLIKASI DISEDIAKAN "SEBAGAIMANA ADANYA" (*AS IS*) DAN "SEBAGAIMANA TERSEDIA" (*AS AVAILABLE*), TANPA JAMINAN DALAM BENTUK APA PUN, BAIK TERSURAT MAUPUN TERSIRAT, SEPANJANG DIIZINKAN OLEH HUKUM YANG BERLAKU, TERMASUK NAMUN TIDAK TERBATAS PADA JAMINAN KELAYAKAN UNTUK DIPERDAGANGKAN (*MERCHANTABILITY*), KESESUAIAN UNTUK TUJUAN TERTENTU, DAN TIDAK ADANYA PELANGGARAN.',
      ),
      LegalItem(
        '2. Kami tidak menjamin bahwa Aplikasi akan berfungsi tanpa gangguan, bebas dari kesalahan, atau bebas dari ancaman keamanan siber, dan tidak menjamin keakuratan, kelengkapan, atau keandalan Konten yang dibuat oleh Pengguna lain.',
      ),
      LegalItem(
        '3. Kami tidak bertanggung jawab atas interaksi antar-Pengguna yang terjadi melalui Aplikasi, termasuk namun tidak terbatas pada perselisihan, penipuan, atau kerugian yang timbul dari interaksi tersebut, meskipun Kami akan berupaya sepatutnya untuk memfasilitasi penanganan laporan sebagaimana diuraikan dalam Pasal 8.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 16 — Batasan Tanggung Jawab',
    items: [
      LegalItem(
        '1. SEPANJANG DIIZINKAN OLEH HUKUM YANG BERLAKU, KAMI, TERMASUK DIREKTUR, PEGAWAI, DAN AFILIASI KAMI, TIDAK BERTANGGUNG JAWAB ATAS KERUGIAN TIDAK LANGSUNG, INSIDENTAL, KHUSUS, KONSEKUENSIAL, ATAU BERSIFAT PUNITIF, TERMASUK NAMUN TIDAK TERBATAS PADA KEHILANGAN KEUNTUNGAN, DATA, ATAU GOODWILL, YANG TIMBUL DARI ATAU SEHUBUNGAN DENGAN PENGGUNAAN ATAU KETIDAKMAMPUAN MENGGUNAKAN APLIKASI.',
      ),
      LegalItem(
        '2. TANGGUNG JAWAB TOTAL KAMI KEPADA ANDA SEHUBUNGAN DENGAN PERJANJIAN INI, UNTUK SEBAB APA PUN, TIDAK AKAN MELEBIHI JUMLAH SETARA RP500.000,00 (LIMA RATUS RIBU RUPIAH), KECUALI SEPANJANG DILARANG OLEH HUKUM YANG BERSIFAT MEMAKSA.',
      ),
      LegalItem(
        '3. Batasan tanggung jawab sebagaimana dimaksud pada ayat (1) dan ayat (2) tidak berlaku terhadap kerugian yang timbul akibat kesengajaan (*wilful misconduct*) atau kelalaian berat (*gross negligence*) yang dapat dibuktikan secara sah dilakukan oleh Kami, atau sepanjang dilarang oleh ketentuan hukum yang bersifat memaksa di yurisdiksi Anda, termasuk namun tidak terbatas pada hukum pelindungan konsumen yang berlaku bagi Pengguna di Uni Eropa dan yurisdiksi lain yang tidak mengizinkan pengecualian atau pembatasan tanggung jawab tertentu.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 17 — Ganti Rugi (*Indemnification*)',
    items: [
      LegalItem(
        'Anda setuju untuk membebaskan dan mengganti kerugian Kami, direktur, pegawai, dan afiliasi Kami dari segala klaim, kerugian, kewajiban, dan biaya (termasuk biaya hukum yang wajar) yang timbul akibat: (a) pelanggaran Anda terhadap Perjanjian ini; (b) Konten Pengguna yang Anda unggah; atau (c) pelanggaran Anda terhadap hak pihak ketiga, sepanjang diizinkan oleh hukum yang berlaku.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB IX — PERUBAHAN LAYANAN DAN PERJANJIAN',
    article: 'Pasal 18 — Perubahan Aplikasi',
    items: [
      LegalItem(
        'Kami berhak untuk mengubah, menambah, mengurangi, atau menghentikan fitur tertentu dalam Aplikasi sewaktu-waktu, dengan atau tanpa pemberitahuan sebelumnya.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 19 — Perubahan Perjanjian',
    items: [
      LegalItem(
        '1. Kami berhak meninjau dan memperbarui Perjanjian ini sewaktu-waktu untuk mencerminkan perubahan fitur Aplikasi, praktik operasional, dan/atau ketentuan hukum yang berlaku.',
      ),
      LegalItem(
        '2. Perubahan yang bersifat material akan diberitahukan kepada Anda melalui notifikasi dalam Aplikasi sebelum berlaku efektif. Penggunaan Aplikasi secara berkelanjutan setelah perubahan berlaku efektif dianggap sebagai persetujuan Anda atas Perjanjian yang telah diperbarui.',
      ),
      LegalItem(
        '3. Apabila Anda tidak menyetujui perubahan dimaksud, satu-satunya upaya yang tersedia bagi Anda adalah menghentikan penggunaan Aplikasi dan menghapus Akun Anda sebagaimana diatur dalam Pasal 13.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB X — PELANGGARAN DAN PENEGAKAN KETENTUAN',
    article: 'Pasal 20 — Tahapan Penegakan',
    items: [
      LegalItem(
        '1. Kami menerapkan pendekatan bertahap dalam penegakan Perjanjian ini, yang meliputi: (a) peringatan; (b) pembatasan fitur tertentu; (c) penangguhan sementara Akun; dan/atau (d) penghapusan permanen Akun, dengan mempertimbangkan tingkat keparahan dan frekuensi pelanggaran.',
      ),
      LegalItem(
        '2. Terlepas dari ketentuan ayat (1), Kami berhak segera menangguhkan atau menghapus Akun tanpa melalui tahapan tersebut apabila pelanggaran yang dilakukan bersifat serius, termasuk namun tidak terbatas pada pelanggaran sebagaimana dimaksud dalam Pasal 7 ayat (1) dan ayat (8).',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 21 — Keluhan dan Banding',
    items: [
      LegalItem(
        'Apabila Anda merasa suatu tindakan penegakan terhadap Akun Anda tidak tepat, Anda dapat mengajukan keberatan melalui kontak resmi sebagaimana diuraikan dalam Pasal 29 Perjanjian ini dalam jangka waktu yang wajar. Kami akan meninjau keberatan dimaksud dan memberikan tanggapan dalam jangka waktu yang wajar.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB XI — HUBUNGAN ANTAR-PENGGUNA',
    article: 'Pasal 22 — Interaksi Pihak Ketiga dan Pertemuan Langsung',
    items: [
      LegalItem(
        '1. Aplikasi berfungsi sebagai sarana untuk memfasilitasi komunikasi antar-Pengguna dan bukan merupakan pihak dalam interaksi pribadi antar-Pengguna.',
      ),
      LegalItem(
        '2. Anda memahami dan menyetujui bahwa Kami tidak melakukan pemeriksaan latar belakang (*background check*) terhadap Pengguna lain, dan bahwa Anda bertanggung jawab penuh atas keputusan Anda untuk berinteraksi dengan Pengguna lain, baik secara daring maupun apabila diputuskan untuk bertemu secara langsung. Kami sangat menganjurkan Anda untuk senantiasa mengutamakan keselamatan diri dalam berinteraksi dengan Pengguna lain yang tidak Anda kenal secara pribadi.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB XII — HUKUM YANG BERLAKU DAN PENYELESAIAN SENGKETA',
    article: 'Pasal 23 — Hukum yang Berlaku',
    items: [
      LegalItem(
        '1. Perjanjian ini disusun dan ditafsirkan berdasarkan hukum Negara Republik Indonesia, yang berlaku sebagai kerangka hukum utama (*governing law*) atas hubungan hukum antara Kami dan seluruh Pengguna, di mana pun domisili Pengguna berada.',
      ),
      LegalItem(
        '2. Ketentuan ayat (1) berlaku tanpa mengurangi hak-hak Pengguna yang bersifat memaksa (*mandatory rights*) berdasarkan hukum pelindungan konsumen di negara domisili Pengguna, sepanjang hukum setempat tersebut tidak dapat dikesampingkan melalui pilihan hukum (*choice of law*).',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 24 — Penyelesaian Sengketa',
    items: [
      LegalItem(
        'Setiap perselisihan, perbedaan pendapat, atau sengketa yang timbul sehubungan dengan Perjanjian ini akan terlebih dahulu diupayakan penyelesaiannya secara musyawarah untuk mencapai mufakat antara para pihak dalam jangka waktu 30 (tiga puluh) Hari Kerja sejak salah satu pihak menyampaikan pemberitahuan tertulis mengenai adanya sengketa. Dalam hal penyelesaian secara musyawarah tidak tercapai, sengketa akan diselesaikan melalui jalur hukum yang berlaku di wilayah hukum Republik Indonesia, tanpa mengurangi hak Pengguna dari yurisdiksi tertentu untuk menempuh upaya hukum di hadapan pengadilan yang berwenang di negara domisilinya sepanjang diwajibkan oleh hukum yang bersifat memaksa di yurisdiksi tersebut.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 25 — Keterpisahan Ketentuan (*Severability*)',
    items: [
      LegalItem(
        'Apabila salah satu ketentuan dalam Perjanjian ini dinyatakan tidak sah, batal, atau tidak dapat dilaksanakan oleh pengadilan atau otoritas yang berwenang, maka ketentuan tersebut akan ditafsirkan sedemikian rupa untuk mencerminkan maksud awal para pihak sedekat mungkin sesuai dengan hukum yang berlaku, sementara ketentuan lain dalam Perjanjian ini akan tetap berlaku penuh.',
      ),
    ],
  ),
  LegalSection(
    chapter:
        'BAB XIII — KETENTUAN TAMBAHAN BAGI PENGGUNA DARI YURISDIKSI TERTENTU',
    article: 'Pasal 26 — Pengguna di Wilayah Uni Eropa/EEA dan Inggris Raya',
    items: [
      LegalItem(
        'Bagi Pengguna yang berdomisili di wilayah Uni Eropa, Kawasan Ekonomi Eropa, atau Inggris Raya, ketentuan dalam Pasal 16 (Batasan Tanggung Jawab) tidak mengesampingkan hak Anda yang bersifat memaksa berdasarkan hukum pelindungan konsumen setempat, termasuk hak atas Layanan yang sesuai dengan deskripsi dan kualitas yang wajar, serta hak untuk mengajukan keberatan melalui mekanisme penyelesaian sengketa daring (*Online Dispute Resolution*) yang disediakan oleh otoritas yang berwenang di wilayah tersebut, sepanjang berlaku.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 27 — Pengguna di Negara Bagian California, Amerika Serikat',
    items: [
      LegalItem(
        'Bagi Pengguna yang berdomisili di Negara Bagian California, ketentuan dalam Perjanjian ini tidak mengesampingkan hak-hak Anda berdasarkan *California Consumer Legal Remedies Act* dan ketentuan hukum pelindungan konsumen California lain yang bersifat memaksa.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 28 — Ketentuan Umum bagi Yurisdiksi Lain',
    items: [
      LegalItem(
        'Bagi Pengguna di yurisdiksi lain yang memiliki ketentuan hukum pelindungan konsumen atau hukum kontrak elektronik tersendiri yang bersifat memaksa, ketentuan hukum setempat yang bersifat memaksa tersebut akan diutamakan di atas ketentuan Perjanjian ini sepanjang menyangkut Pengguna dari yurisdiksi yang bersangkutan dan sepanjang terjadi pertentangan yang tidak dapat dihindarkan.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'BAB XIV — KETENTUAN LAIN-LAIN',
    article: 'Pasal 29 — Kontak Resmi',
    items: [
      LegalItem(
        'Untuk setiap pertanyaan, permohonan, dan/atau pengaduan sehubungan dengan Perjanjian ini, silakan hubungi Kami melalui menu **Hubungi Kami** yang tersedia pada halaman profil dalam Aplikasi. Kami akan menindaklanjuti setiap permohonan yang disampaikan dalam jangka waktu yang wajar.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 30 — Perjanjian Keseluruhan (*Entire Agreement*)',
    items: [
      LegalItem(
        'Perjanjian ini, bersama dengan Kebijakan Privasi ChatYuk dan setiap ketentuan tambahan yang secara tegas dirujuk di dalamnya, merupakan keseluruhan kesepakatan antara Anda dan Kami sehubungan dengan penggunaan Aplikasi, dan menggantikan seluruh kesepakatan, pernyataan, atau pemahaman sebelumnya, baik lisan maupun tertulis, mengenai pokok yang sama.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 31 — Pengesampingan Hak (*Waiver*)',
    items: [
      LegalItem(
        'Kegagalan atau keterlambatan Kami dalam melaksanakan atau menegakkan hak atau ketentuan mana pun dalam Perjanjian ini tidak dapat ditafsirkan sebagai pengesampingan (*waiver*) atas hak atau ketentuan dimaksud.',
      ),
    ],
  ),
  LegalSection(
    article: 'Pasal 32 — Bahasa',
    items: [
      LegalItem(
        'Perjanjian ini disusun dalam Bahasa Indonesia sebagai versi utama (*governing language*). Apabila disediakan versi terjemahan dalam bahasa lain untuk kemudahan Pengguna internasional, dan terdapat pertentangan penafsiran antara versi Bahasa Indonesia dengan versi terjemahan dimaksud, maka versi Bahasa Indonesia yang akan berlaku, kecuali diwajibkan lain secara tegas oleh hukum yang bersifat memaksa di yurisdiksi Pengguna tertentu.',
      ),
    ],
  ),
];

const _termsEn = <LegalSection>[
  LegalSection(
    chapter: 'CHAPTER I — GENERAL PROVISIONS',
    article: 'Article 1 — Introduction and Acceptance of the Agreement',
    items: [
      LegalItem(
        '1. These Terms of Service (the "Agreement", "Terms of Service") constitute a valid and legally binding agreement between You as an individual user (the "User", "You") and the developer and operator of the ChatYuk application (the "Operator", "We", "Us") in connection with the download, installation, registration, access, and/or use of the ChatYuk application together with all of its features (the "Application", "Services").',
      ),
      LegalItem(
        '2. By downloading, installing, registering, accessing, and/or using the Application in any manner, You declare and warrant that You have read, fully understood, and consciously and voluntarily agreed to be bound by all provisions of this Agreement together with the ChatYuk Privacy Policy, which forms an inseparable part of this Agreement. If You do not agree to any or all of the provisions of this Agreement, We respectfully request that You do not continue downloading, installing, and/or using the Application.',
      ),
      LegalItem(
        '3. This Agreement applies globally to all Users wherever they are domiciled or located, with additional provisions for Users from certain jurisdictions as described in Chapter XIII of this Agreement.',
      ),
      LegalItem(
        '4. We reserve the right to reject registration applications, restrict, suspend, or terminate Your access to the Application at any time in accordance with the provisions of this Agreement.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 2 — Definitions',
    items: [
      LegalItem(
        '',
        table: [
          ['Term', 'Description'],
          [
            'Account',
            'A registered user account created through the registration process in the Application.',
          ],
          [
            'Content',
            'Any form of messages, text, photos, images, videos, audio, links, or other material uploaded, sent, or shared by Users through the Application.',
          ],
          [
            'User Content',
            'Content created, uploaded, or sent by Users, including but not limited to messages in chats, chat rooms, statuses, comments, and disappearing photos.',
          ],
          [
            'Chat Room',
            'A feature in the Application that enables interaction between Users in a forum or shared space.',
          ],
          [
            'Disappearing Photo',
            'A photo-sending feature that is temporary in nature and will disappear or become inaccessible after being viewed or after a certain period of time.',
          ],
          [
            'Business Day',
            'Business days generally applicable in Indonesia, excluding Saturdays, Sundays, and national holidays.',
          ],
        ],
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER II — ELIGIBILITY AND ACCOUNT REGISTRATION',
    article: 'Article 3 — Age Requirements and Legal Capacity',
    items: [
      LegalItem(
        '1. The ChatYuk Application is intended only for individuals who are at least 17 (seventeen) years old. By registering and using the Application, You declare and warrant that You have met this age requirement.',
      ),
      LegalItem(
        '2. To the extent that the law of Your country of domicile sets a higher minimum age or legal capacity requirement for entering into electronic contracts than 17 (seventeen) years, the higher age limit shall apply to You.',
      ),
      LegalItem(
        '3. You declare and warrant that You have full legal capacity to enter into this Agreement under the laws applicable in Your country of domicile.',
      ),
      LegalItem(
        '4. We have the right, but not the obligation, to request additional evidence to verify Your age and legal capacity.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 4 — Registration and Account Security',
    items: [
      LegalItem(
        '1. To use certain features in the Application, You are required to create an Account by registering with an email address or through a third-party login facility.',
      ),
      LegalItem(
        '2. You are fully responsible for providing true, accurate, current, and complete registration information, and for updating such information when changes occur.',
      ),
      LegalItem(
        '3. You are fully responsible for maintaining the confidentiality of Your Account password and credentials, and for all activities that occur through Your Account, whether carried out by You or by another party using Your Account with or without Your permission.',
      ),
      LegalItem(
        '4. You must promptly notify Us if You become aware of or have reason to suspect unauthorized access to Your Account.',
      ),
      LegalItem(
        '5. One individual is only permitted to have 1 (one) Account, unless otherwise agreed in writing with Us. We reserve the right to suspend or delete detected duplicate accounts.',
      ),
      LegalItem(
        '6. You are prohibited from transferring, selling, renting, or assigning Your Account to another party in any manner without prior written consent from Us.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER III — LICENSE TO USE THE APPLICATION',
    article: 'Article 5 — Grant of License',
    items: [
      LegalItem(
        '1. Subject to Your compliance with this Agreement, We grant You a limited, non-exclusive, non-transferable, non-sublicensable, and revocable license to download, install, and use the Application solely for Your personal and non-commercial purposes, in accordance with the purpose of providing the Application.',
      ),
      LegalItem(
        '2. The license referred to in paragraph (1) does not grant You any ownership rights in the Application, except for the right of use as set out in this Agreement.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 6 — Restrictions on Use',
    items: [
      LegalItem(
        'You are prohibited from: (a) reverse engineering, decompiling, or disassembling the Application, except to the extent permitted by mandatory laws and regulations; (b) copying, modifying, distributing, selling, or renting any part of the Application; (c) using the Application for commercial purposes without Our written permission; (d) using robots, spiders, scrapers, or other automated tools to access the Application without permission; and/or (e) interfering with or overburdening the technical infrastructure supporting the Application.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER IV — USER CONDUCT AND CONTENT',
    article: 'Article 7 — Standards of Conduct',
    items: [
      LegalItem(
        'You agree to use the Application responsibly and in accordance with applicable law, and agree not to:',
      ),
      LegalItem(
        '1. Upload, send, or distribute Content that is unlawful, defamatory, disparaging, containing hate speech, discriminatory, containing pornographic elements, child sexual exploitation, violence, or threats of violence;',
      ),
      LegalItem(
        '2. Engage in harassment, bullying, intimidation, stalking, or other actions that disturb, threaten, or harm other Users;',
      ),
      LegalItem(
        '3. Impersonate another party, disguise affiliation with a particular party, or commit fraud against other Users;',
      ),
      LegalItem(
        '4. Spread false or misleading information that may harm other parties or the public;',
      ),
      LegalItem(
        '5. Infringe the intellectual property rights, privacy rights, or other rights of third parties;',
      ),
      LegalItem(
        '6. Upload malicious software, suspicious links, or take actions that may damage, disrupt, or endanger the Application system or the devices of other Users;',
      ),
      LegalItem(
        '7. Use the Application for unlawful activities in any form, including but not limited to illegal gambling or trade in prohibited goods/services;',
      ),
      LegalItem(
        '8. Request, distribute, or spread Content involving or exploiting minors in any form.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 8 — Content Moderation and Handling of Reports',
    items: [
      LegalItem(
        '1. We have the right, but not the obligation, to monitor, review, delete, or restrict access to Content that violates this Agreement, without prior notice, to the extent reasonably necessary to maintain the integrity and security of the Application.',
      ),
      LegalItem(
        '2. You may report Content or other Users suspected of violating this Agreement through the reporting feature available in the Application. We will follow up on such reports in accordance with Our internal moderation policy.',
      ),
      LegalItem(
        '3. We reserve the right to take action against Users who violate this Agreement, in the form of warnings, restriction of certain features, temporary suspension, up to permanent deletion of the Account, as further regulated in Chapter X.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 9 — Disappearing Photo Feature',
    items: [
      LegalItem(
        '1. The Disappearing Photo feature is provided to enable Users to send temporary photos. Although We apply technical measures in the form of forensic watermarks and anti-screenshot protection as described in the Privacy Policy, You understand and agree that **We cannot guarantee absolutely** that the recipient will not store, photograph, record, or disseminate such photos by other means outside Our technical control.',
      ),
      LegalItem(
        '2. You are fully responsible for Your decision to send any Content, including through the Disappearing Photo feature, to other Users. We are not responsible for the misuse by the recipient of Content that You have sent outside the control of Our system.',
      ),
      LegalItem(
        '3. Misuse of this feature, including sending Content that violates Article 7, may be subject to action as regulated in Article 8 paragraph (3) and/or reported to the authorities to the extent required by law.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER V — RIGHTS TO CONTENT',
    article: 'Article 10 — Ownership of User Content',
    items: [
      LegalItem(
        '1. You retain all ownership rights to the User Content that You create and upload to the Application.',
      ),
      LegalItem(
        '2. By uploading User Content to the Application, You grant Us a non-exclusive, limited sublicensable, worldwide, and royalty-free license to store, reproduce, display, transmit, and distribute such User Content solely to the extent reasonably necessary to provide and operate the Application features (e.g., displaying messages to the intended recipient, storing conversation history).',
      ),
      LegalItem(
        '3. The license referred to in paragraph (2) will terminate when such User Content is deleted from the Application, except to the extent: (a) the Content has been shared with other Users who lawfully retain it in the system; or (b) We are required to retain such Content based on legal obligations as described in the Privacy Policy.',
      ),
      LegalItem(
        '4. You declare and warrant that You hold all necessary rights to the User Content You upload, and that such Content does not infringe any third-party rights, including intellectual property rights and privacy rights.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 11 — Our Intellectual Property Rights',
    items: [
      LegalItem(
        'All intellectual property rights in the Application, including but not limited to source code, user interface, logos, trademarks, icons, mascots, and other design elements, belong to Us or Our licensors, and are protected by laws and regulations in the field of intellectual property. No provision of this Agreement may be interpreted as transferring such intellectual property rights to You.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VI — SERVICES AND THIRD-PARTY PARTNERS',
    article: 'Article 12 — Third-Party Integrations',
    items: [
      LegalItem(
        '1. The Application is integrated with a number of third-party services to support its operations, including but not limited to database and authentication infrastructure providers, and third-party login service providers, as described in more detail in the ChatYuk Privacy Policy.',
      ),
      LegalItem(
        '2. Your use of such third-party services may be subject to the terms and conditions and privacy policies of each service provider, which are outside Our control. We recommend that You read and understand the terms of each such third party.',
      ),
      LegalItem(
        '3. We are not responsible for the acts, omissions, service disruptions, or losses arising from system failures of third-party service providers beyond Our reasonable control, although We will make reasonable efforts to mitigate the impact on Users.',
      ),
      LegalItem(
        '4. We reserve the right to add, replace, or terminate cooperation with certain third-party service providers at any time.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VII — TERMINATION, SUSPENSION, AND ACCOUNT DELETION',
    article: 'Article 13 — Termination by the User',
    items: [
      LegalItem(
        'You may stop using the Application and delete Your Account at any time through the profile settings menu in the Application. Account deletion will be processed in accordance with the retention and deletion provisions described in the ChatYuk Privacy Policy.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 14 — Suspension and Deletion by Us',
    items: [
      LegalItem(
        '1. We reserve the right to temporarily suspend or permanently delete Your Account, with or without prior notice, if: (a) You violate one or more provisions of this Agreement; (b) there are reasonable indications that You are using the Application for unlawful activities; (c) required by court order or a competent authority; or (d) necessary to protect the security of the Application, Ourselves, or other Users.',
      ),
      LegalItem(
        '2. Where the suspension or deletion of an Account is carried out in connection with an alleged violation, We will make reasonable efforts to notify You of the reasons for such action, unless such notification may impede an investigation or is prohibited by applicable law.',
      ),
      LegalItem(
        '3. The deletion or suspension of an Account does not extinguish Your obligations that arose before the date of deletion/suspension.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER VIII — DISCLAIMERS AND LIMITATION OF LIABILITY',
    article: 'Article 15 — Disclaimer of Warranties',
    items: [
      LegalItem(
        '1. THE APPLICATION IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED, TO THE EXTENT PERMITTED BY APPLICABLE LAW, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.',
      ),
      LegalItem(
        '2. We do not warrant that the Application will function without interruption, be free of errors, or be free of cybersecurity threats, and do not warrant the accuracy, completeness, or reliability of Content created by other Users.',
      ),
      LegalItem(
        '3. We are not responsible for interactions between Users that occur through the Application, including but not limited to disputes, fraud, or losses arising from such interactions, although We will make reasonable efforts to facilitate the handling of reports as described in Article 8.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 16 — Limitation of Liability',
    items: [
      LegalItem(
        '1. TO THE EXTENT PERMITTED BY APPLICABLE LAW, WE, INCLUDING OUR DIRECTORS, EMPLOYEES, AND AFFILIATES, SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA, OR GOODWILL, ARISING FROM OR IN CONNECTION WITH THE USE OR INABILITY TO USE THE APPLICATION.',
      ),
      LegalItem(
        '2. OUR TOTAL LIABILITY TO YOU IN CONNECTION WITH THIS AGREEMENT, FOR ANY CAUSE WHATSOEVER, SHALL NOT EXCEED AN AMOUNT EQUIVALENT TO RP500.000,00 (FIVE HUNDRED THOUSAND RUPIAH), EXCEPT TO THE EXTENT PROHIBITED BY MANDATORY LAW.',
      ),
      LegalItem(
        '3. The limitation of liability referred to in paragraphs (1) and (2) does not apply to losses arising from wilful misconduct or gross negligence proven to be committed by Us, or to the extent prohibited by mandatory legal provisions in Your jurisdiction, including but not limited to consumer protection law applicable to Users in the European Union and other jurisdictions that do not allow certain exclusions or limitations of liability.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 17 — Indemnification',
    items: [
      LegalItem(
        'You agree to release and indemnify Us, Our directors, employees, and affiliates from any claims, losses, liabilities, and costs (including reasonable legal fees) arising from: (a) Your breach of this Agreement; (b) the User Content You upload; or (c) Your infringement of third-party rights, to the extent permitted by applicable law.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER IX — CHANGES TO THE SERVICES AND THE AGREEMENT',
    article: 'Article 18 — Changes to the Application',
    items: [
      LegalItem(
        'We reserve the right to change, add, reduce, or discontinue certain features in the Application at any time, with or without prior notice.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 19 — Changes to the Agreement',
    items: [
      LegalItem(
        '1. We reserve the right to review and update this Agreement at any time to reflect changes in Application features, operational practices, and/or applicable laws and regulations.',
      ),
      LegalItem(
        '2. Material changes will be notified to You through in-Application notifications before becoming effective. Your continued use of the Application after a change becomes effective is deemed Your acceptance of the updated Agreement.',
      ),
      LegalItem(
        '3. If You do not agree to such changes, the only recourse available to You is to stop using the Application and delete Your Account as set out in Article 13.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER X — VIOLATIONS AND ENFORCEMENT',
    article: 'Article 20 — Enforcement Stages',
    items: [
      LegalItem(
        '1. We apply a staged approach to enforcing this Agreement, which includes: (a) warnings; (b) restriction of certain features; (c) temporary suspension of the Account; and/or (d) permanent deletion of the Account, taking into account the severity and frequency of the violation.',
      ),
      LegalItem(
        '2. Notwithstanding paragraph (1), We reserve the right to immediately suspend or delete the Account without going through such stages if the violation committed is serious, including but not limited to violations as referred to in Article 7 paragraphs (1) and (8).',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 21 — Complaints and Appeals',
    items: [
      LegalItem(
        'If You believe that an enforcement action against Your Account is inappropriate, You may submit an objection through the official contact as described in Article 29 of this Agreement within a reasonable period. We will review the objection and provide a response within a reasonable period.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER XI — RELATIONSHIPS BETWEEN USERS',
    article: 'Article 22 — Third-Party Interactions and In-Person Meetings',
    items: [
      LegalItem(
        '1. The Application serves as a means to facilitate communication between Users and is not a party to personal interactions between Users.',
      ),
      LegalItem(
        '2. You understand and agree that We do not conduct background checks on other Users, and that You are fully responsible for Your decision to interact with other Users, whether online or should You decide to meet in person. We strongly recommend that You always prioritize Your personal safety when interacting with other Users You do not know personally.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER XII — GOVERNING LAW AND DISPUTE RESOLUTION',
    article: 'Article 23 — Governing Law',
    items: [
      LegalItem(
        '1. This Agreement is drafted and interpreted in accordance with the laws of the Republic of Indonesia, which apply as the main governing law over the legal relationship between Us and all Users, wherever Users are domiciled.',
      ),
      LegalItem(
        '2. The provisions of paragraph (1) apply without prejudice to the mandatory rights of Users under consumer protection law in the User country of domicile, to the extent such local law cannot be overridden by choice of law.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 24 — Dispute Resolution',
    items: [
      LegalItem(
        'Any dispute, difference of opinion, or disagreement arising in connection with this Agreement will first be resolved through deliberation to reach consensus between the parties within 30 (thirty) Business Days from the date one party sends written notice of the dispute. If deliberation does not reach a resolution, the dispute will be resolved through the applicable legal channels in the jurisdiction of the Republic of Indonesia, without prejudice to the right of Users from certain jurisdictions to pursue legal remedies before the competent courts in their country of domicile to the extent required by mandatory law in that jurisdiction.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 25 — Severability',
    items: [
      LegalItem(
        'If any provision of this Agreement is held to be invalid, void, or unenforceable by a competent court or authority, such provision will be interpreted in a manner that reflects the original intent of the parties as closely as possible in accordance with applicable law, while the other provisions of this Agreement will remain in full force.',
      ),
    ],
  ),
  LegalSection(
    chapter:
        'CHAPTER XIII — ADDITIONAL PROVISIONS FOR USERS FROM CERTAIN JURISDICTIONS',
    article:
        'Article 26 — Users in the European Union/EEA and the United Kingdom',
    items: [
      LegalItem(
        'For Users domiciled in the European Union, the European Economic Area, or the United Kingdom, the provisions of Article 16 (Limitation of Liability) do not override Your mandatory rights under local consumer protection law, including the right to Services that conform to their description and reasonable quality, and the right to submit objections through the Online Dispute Resolution mechanism provided by the competent authorities in that region, where applicable.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 27 — Users in California, United States',
    items: [
      LegalItem(
        'For Users domiciled in the State of California, the provisions of this Agreement do not override Your rights under the California Consumer Legal Remedies Act and other mandatory California consumer protection laws.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 28 — General Provisions for Other Jurisdictions',
    items: [
      LegalItem(
        'For Users in other jurisdictions that have their own mandatory consumer protection laws or electronic contract laws, such mandatory local legal provisions will prevail over the provisions of this Agreement to the extent they concern Users from the relevant jurisdiction and to the extent an unavoidable conflict occurs.',
      ),
    ],
  ),
  LegalSection(
    chapter: 'CHAPTER XIV — MISCELLANEOUS PROVISIONS',
    article: 'Article 29 — Official Contact',
    items: [
      LegalItem(
        'For any questions, requests, and/or complaints regarding this Agreement, please contact us through the **Contact Us** menu available on the profile page in the Application. We will follow up on every request submitted within a reasonable period.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 30 — Entire Agreement',
    items: [
      LegalItem(
        'This Agreement, together with the ChatYuk Privacy Policy and any additional provisions expressly referred to therein, constitutes the entire agreement between You and Us in connection with the use of the Application, and supersedes all prior agreements, statements, or understandings, whether oral or written, on the same subject matter.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 31 — Waiver',
    items: [
      LegalItem(
        'Our failure or delay in exercising or enforcing any right or provision of this Agreement may not be interpreted as a waiver of such right or provision.',
      ),
    ],
  ),
  LegalSection(
    article: 'Article 32 — Language',
    items: [
      LegalItem(
        'This Agreement is drafted in Indonesian as the governing language. If a translated version in another language is provided for the convenience of international Users, and there is a conflict of interpretation between the Indonesian version and such translated version, the Indonesian version shall prevail, unless expressly required otherwise by mandatory law in the jurisdiction of a particular User.',
      ),
    ],
  ),
];
