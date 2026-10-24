part of 'strings.dart';

mixin SScreenMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
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
  String get searchCountry => isId ? 'Cari negara...' : 'Search country...';
  String get searchCity => isId ? 'Cari kota...' : 'Search city...';
  String selCountriesCount(int n) => isId ? '$n negara' : '$n countries';
  String selGendersCount(int n) => isId ? '$n dipilih' : '$n selected';
  String get filterReset => isId ? 'Reset' : 'Reset';
  String get filterApply => isId ? 'Terapkan' : 'Apply';
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
  String get titleRooms => isId ? 'Global Room' : 'Global Room';
  /// Sub-label kapsul samping → pintasan masuk Global Room (General).
  String get roomEnterHint => isId ? 'Masuk ke' : 'Enter';
  String get searchRoom => isId ? 'Cari Room' : 'Search Room';
  String get roomOnlineCount => isId ? 'online' : 'online';
  String get noRooms => isId ? 'Belum ada room tersedia' : 'No rooms available';
  String get noRoomsHint => isId
      ? 'Room akan muncul saat ada yang membuat'
      : 'Rooms will appear once someone creates one';

  // ── Private Rooms ──
  String get tabGlobalRoom => isId ? 'Room Global' : 'Global Room';
  String get tabPrivateRoom => isId ? 'Room Private' : 'Private Room';
  String get noGroups => isId ? 'Belum ada grup' : 'No groups yet';
  String get noGroupsHint =>
      isId ? 'Buat grup-mu sendiri' : 'Create your own group';
  String get btnCreateGroup => isId ? 'Buat Grup' : 'Create Group';
  String get roomShowMembers => isId ? 'Lihat anggota' : 'View members';
  String get roomShowChat => isId ? 'Kembali ke chat' : 'Back to chat';
  String get createGroupTitle => isId ? 'Buat Grup' : 'Create Group';
  // Layar QR private room (admin build) — tetap "Room", bukan "Grup".
  String get createPrivateRoomTitle =>
      isId ? 'Buat Room Private' : 'Create Private Room';
  String get groupNameLabel => isId ? 'Nama grup' : 'Group name';
  String get groupNameHint => isId ? '3–30 karakter' : '3–30 characters';
  String get roomNameLabel => isId ? 'Nama room' : 'Room name';
  String get roomNameHint => isId ? '3–30 karakter' : '3–30 characters';
  String get roomIconLabel => isId ? 'Ikon' : 'Icon';
  String get roomPasswordHint =>
      isId ? 'Minimal 4 karakter' : 'At least 4 characters';
  String get createGroupSubtitle =>
      isId ? 'Ruang chat untuk komunitasmu' : 'A chat space for your community';
  String get groupAccessLabel => isId ? 'Akses grup' : 'Group access';
  String get groupNoPwTitle => isId ? 'Tanpa password' : 'No password';
  String get groupNoPwDesc =>
      isId ? 'Permanen · tidak kedaluwarsa' : 'Permanent · never expires';
  String get groupPwTitle => isId ? 'Dengan password' : 'With password';
  String get groupPwDesc =>
      isId ? 'Berlaku 7 hari · bisa diperpanjang' : 'Valid 7 days · extendable';
  String get errPasswordRequired =>
      isId ? 'Isi password grup dulu' : 'Enter a group password first';
  String get labelYourCoins => isId ? 'YukCoin kamu' : 'Your YukCoin';
  String roomCreateCost(int c) => isId ? 'Biaya: $c YukCoin' : 'Cost: $c YukCoin';
  String get errRoomNameLen => isId
      ? 'Nama room harus 3–30 karakter'
      : 'Room name must be 3–30 characters';
  String get errGroupLimit =>
      isId ? 'Maksimal 2 grup aktif' : 'Max 2 active groups';
  String get groupCreated => isId ? 'Grup berhasil dibuat' : 'Group created';
  // ── Sheet Buat Grup (desain 2026-10-18) ──
  String get groupNameExample =>
      isId ? 'Contoh: Futsal Bogor' : 'e.g. Weekend Futsal';
  String get groupNameHelper => isId
      ? 'Minimal 3 karakter. Nama bisa diubah nanti.'
      : 'At least 3 characters. You can rename it later.';
  String get groupIconTitle => isId ? 'Ikon grup' : 'Group icon';
  String get groupNoPwSubtitle =>
      isId ? 'Siapa saja bisa bergabung' : 'Anyone can join';
  String get groupPwSubtitle => isId
      ? 'Berlaku 7 hari, bisa diperpanjang'
      : 'Valid for 7 days, extendable';
  String get groupPasswordLabel => isId ? 'Password grup' : 'Group password';
  String get groupPasswordHint =>
      isId ? 'Minimal 6 karakter' : 'At least 6 characters';
  String get groupPasswordHelper => isId
      ? 'Pengguna perlu password ini untuk bergabung. Berlaku 7 hari, bisa diperpanjang.'
      : 'People need this password to join. Valid for 7 days, extendable.';
  String get errCreateGroupRetry =>
      isId ? 'Gagal membuat grup. Coba lagi.' : 'Could not create the group. Try again.';
  String groupCreatedNamed(String name) =>
      isId ? 'Grup "$name" berhasil dibuat' : 'Group "$name" created';
  String groupIconLabel(String key) {
    switch (key) {
      case 'chat':
        return isId ? 'Obrolan' : 'Chat';
      case 'users':
        return isId ? 'Komunitas' : 'Community';
      case 'sparkle':
        return isId ? 'Seru-seruan' : 'Fun';
      case 'game':
        return 'Gaming';
      case 'music':
        return isId ? 'Musik' : 'Music';
      case 'heart':
        return isId ? 'Komunitas kasih' : 'Love';
      case 'flame':
        return isId ? 'Populer' : 'Popular';
      case 'star':
        return isId ? 'Favorit' : 'Favorite';
      case 'moon':
        return isId ? 'Malam' : 'Night';
      case 'crown':
        return isId ? 'Eksklusif' : 'Exclusive';
      case 'coffee':
        return isId ? 'Ngobrol santai' : 'Chill';
      case 'lock':
        return isId ? 'Privat' : 'Private';
      default:
        return key;
    }
  }
  String get joinRoomTitle => isId ? 'Masuk Room' : 'Join Room';
  String joinRoomCost(int c) =>
      isId ? 'Biaya masuk: $c YukCoin' : 'Entry cost: $c YukCoin';
  String get enterPassword => isId ? 'Masukkan password' : 'Enter password';
  String get errWrongPassword => isId ? 'Password salah' : 'Wrong password';
  String get btnJoin => isId ? 'Masuk' : 'Join';
  String get resetPasswordTitle =>
      isId ? 'Atur Ulang Password Room' : 'Reset Room Password';
  String get resetPasswordHint => isId
      ? 'Password baru 4-30 karakter (kosongkan untuk hapus)'
      : 'New password 4-30 chars (empty to remove)';
  String get msgPasswordReset =>
      isId ? 'Password diperbarui' : 'Password updated';
  String get btnResetPassword => isId ? 'Reset Password' : 'Reset Password';
  String get btnRemovePassword => isId ? 'Hapus Password' : 'Remove Password';
  String get roomByOwner => isId ? 'oleh' : 'by';
  String get btnExtendRoom =>
      isId ? 'Perpanjang 7 hari (50 YukCoin)' : 'Extend 7 days (50 YukCoin)';
  String get btnDeleteRoom => isId ? 'Hapus Room' : 'Delete Room';
  String get deleteRoomConfirm => isId
      ? 'Hapus room ini? Semua pesan ikut terhapus.'
      : 'Delete this room? All messages will be deleted.';
  String get roomDeleted => isId ? 'Room dihapus' : 'Room deleted';

  // ── Sematan & hapus/keluar GRUP di daftar Pesan (geser kanan = semat,
  //    geser kiri = hapus/keluar) ──
  /// Label pembeda GRUP vs chat personal di daftar Pesan (`Grup · 12`).
  String groupMemberCountLabel(int n) =>
      isId ? 'Grup · $n' : 'Group · $n';
  String get btnDeleteGroup => isId ? 'Hapus Grup' : 'Delete Group';
  String get deleteGroupConfirm => isId
      ? 'Hapus grup ini untuk SEMUA anggota? Semua pesan ikut terhapus.'
      : 'Delete this group for ALL members? All messages will be deleted.';
  String get groupDeleted => isId ? 'Grup dihapus' : 'Group deleted';
  String get btnLeaveGroup => isId ? 'Keluar Grup' : 'Leave Group';
  String get leaveGroupConfirm => isId
      ? 'Keluar dari grup ini? Kamu tidak akan menerima pesannya lagi.'
      : 'Leave this group? You will no longer receive its messages.';
  String get groupLeft => isId ? 'Kamu keluar dari grup' : 'You left the group';
  String get errGroupAction =>
      isId ? 'Aksi grup gagal. Coba lagi.' : 'Group action failed. Try again.';
  String get roomExtended =>
      isId ? 'Room diperpanjang 7 hari' : 'Room extended by 7 days';
  String roomExpiresIn(int days) => isId ? '$days hari lagi' : '${days}d left';
  String get roomExpiresToday => isId ? 'Berakhir hari ini' : 'Ends today';

  // ── Explore Room (chip kategori + satu list + buat room) ──
  String get exploreRame => isId ? 'Rame' : 'Trending';
  String get btnCreateRoom => isId ? 'Buat Room' : 'Create Room';
  String get roomCategoryLabel => isId ? 'Kategori' : 'Category';
  String roomMembersOnline(String m, String o) =>
      isId ? '$m member • $o online' : '$m members • $o online';
  String get exploreEmptyRame => isId
      ? 'Belum ada room yang rame'
      : 'No trending rooms yet';
  String get exploreEmptyRameHint => isId
      ? 'Jadilah yang pertama ngobrol'
      : 'Be the first to chat';
  String get exploreRoomCreated =>
      isId ? 'Room berhasil dibuat' : 'Room created';
  String get exploreLive => isId ? 'Live' : 'Live';
  String get roomIconPhotoLabel => isId ? 'Foto sendiri' : 'Custom photo';
  String get roomIconPick => isId ? 'Pilih foto' : 'Choose photo';
  String get roomIconChange => isId ? 'Ganti foto' : 'Change photo';
  String get roomIconUploading =>
      isId ? 'Mengupload ikon...' : 'Uploading icon...';
  String get roomIconUploadFail =>
      isId ? 'Upload gagal, pakai emoji' : 'Upload failed, using emoji';

  // ── Send Coins ──
  String get menuSendPhoto => isId ? 'Gallery' : 'Gallery';
  String get menuTakePhoto => isId ? 'Ambil Foto' : 'Take Photo';
  String get menuTakePhotoVideo => isId ? 'Kamera' : 'Camera';
  String get menuRecordVideo => isId ? 'Rekam Video' : 'Record Video';
  String get menuRecordVideoHint =>
      isId ? 'Maksimal 60 detik' : 'Up to 60 seconds';
  String get labelPhoto => isId ? 'FOTO' : 'PHOTO';
  String get labelVideo => isId ? 'VIDEO' : 'VIDEO';
  String get menuViewOnce => isId ? 'Foto Sekali Lihat' : 'View-once Photo';

  // ── Video chat (maks 60 dtk, hasil kompres ≤8 MB) ──
  String get menuSendVideo => isId ? 'Kirim Video' : 'Send Video';
  String get videoTooLong => isId
      ? 'Video maksimal 60 detik'
      : 'Video is 60 seconds max';
  String get videoTooLarge => isId
      ? 'Video terlalu besar setelah dikompres (maks 8 MB)'
      : 'Video too large after compression (8 MB max)';
  String get videoCompressing =>
      isId ? 'Mengompres video…' : 'Compressing video…';
  String get videoCompressFail =>
      isId ? 'Gagal memproses video' : 'Failed to process video';
  String get videoPreviewTitle => isId ? 'Pratinjau video' : 'Video preview';
  String videoDurationLabel(int secs) => isId
      ? '$secs detik'
      : '$secs seconds';
  String get viewTimerOff => isId ? 'Tanpa timer' : 'No timer';
  String get viewTimerOnce => isId ? '1x lihat' : 'View once';
  String viewTimerSecs(int n) => isId ? '$n detik' : '$n seconds';
  String get viewTimerHint =>
      isId ? 'Foto hilang otomatis sesuai timer' : 'Photo disappears per timer';
  String get menuSendCoin => isId ? 'Kirim YukCoin' : 'Send YukCoin';
  String get sendCoinTitle => isId ? 'Kirim YukCoin' : 'Send YukCoin';
  String sendCoinTo(String name) => isId ? 'Kirim ke $name' : 'Send to $name';
  String get coinAmountLabel => isId ? 'Jumlah YukCoin' : 'YukCoin amount';
  String get coinAmountHint =>
      isId ? 'Ketik jumlah sendiri' : 'Type your own amount';
  String get coinDialogHelper =>
      isId ? 'Minimal 5, maksimal saldo kamu' : 'Minimum 5, up to your balance';
  String get errCoinMin => isId ? 'Minimal 5 YukCoin' : 'Minimum 5 YukCoin';
  String get errCoinInsufficient =>
      isId ? 'YukCoin kamu tidak cukup' : 'Not enough YukCoin';
  String get errCoinRegisterOnly => isId
      ? 'Hanya akun terdaftar yang bisa kirim YukCoin. Daftar email dulu (+100 YukCoin)!'
      : 'Only registered accounts can send YukCoin. Register email first (+100 YukCoin)!';
  String coinSentToast(int n) => isId ? '-$n YukCoin terkirim' : '-$n YukCoin sent';
  String coinBubbleSent(int n) =>
      isId ? '🪙 You sent $n YukCoin' : '🪙 You sent $n YukCoin';
  String coinBubbleReceived(int n) =>
      isId ? '🪙 Received $n YukCoin' : '🪙 Received $n YukCoin';
  String get errSendCoin => isId ? 'Gagal kirim YukCoin' : 'Failed to send YukCoin';
  // ── Umum ──
  String get btnConfirm => isId ? 'Konfirmasi' : 'Confirm';
  String get errCoinDisabled => isId
      ? 'Sistem YukCoin sedang dinonaktifkan'
      : 'YukCoin system is currently disabled';

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
            'jualbeli': 'Jual Beli',
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
          'jualbeli': 'Buy & Sell',
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
            'jualbeli': 'Jual beli barang & jasa',
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
          'jualbeli': 'Buy & sell goods & services',
        }[id] ??
        '';
  }

  // ── Online Users ──
  String get titleOnline => isId ? 'Pengguna Online' : 'Online Users';
  String get searchHint =>
      isId ? 'Cari nama pengguna...' : 'Search username...';
  String get chatSearchHint =>
      isId ? 'Cari di percakapan...' : 'Search conversation...';
  String get btnSearch => isId ? 'Cari' : 'Search';
  String get searchRoomHint =>
      isId ? 'Cari room atau grup...' : 'Search rooms or groups...';
  String get filterAll => isId ? 'Semua' : 'All';
  String get filterMale => isId ? 'Laki-laki' : 'Male';
  String get filterFemale => isId ? 'Perempuan' : 'Female';
  String get noOnlineUsers =>
      isId ? 'Tidak ada pengguna online' : 'No users online';
  String get noOnlineFriends =>
      isId ? 'Belum ada teman yang online' : 'No friends online yet';
  // Keterangan channel daftar Online (muncul saat ganti channel).
  String get channelAllDesc => isId
      ? 'Menampilkan semua pengguna online. Status online kamu ikut pengaturan di Kelola Privasi.'
      : 'Showing all online users. Your online status follows your Privacy settings.';
  String get channelFriendsDesc => isId
      ? 'Hanya menampilkan teman yang online. Status online kamu hanya terlihat oleh teman.'
      : 'Only friends online are shown. Your online status is visible to friends only.';
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
  String get nearbyNeedShareDesc => isId
      ? 'Untuk melihat orang sekitar, kamu juga perlu ikut membagikan lokasi.'
      : 'To see people nearby, you also need to share your location.';
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
  // ── Onboarding YukCoin ──
  String get pointsOnboardTitle =>
      isId ? 'YukCoin' : 'YukCoin';
  String get pointsOnboardSub =>
      isId ? 'Cara dapat & pakai YukCoin' : 'How to earn & spend';
  String get pointsOnboardEmail => isId
      ? 'Daftar email = +100, dan data aman!'
      : 'Register email = +100, fully safe!';
  String get pointsOnboardChat => isId
      ? 'Chat = pakai YukCoin (-1 per pesan)'
      : 'Chat = uses YukCoin (-1 per msg)';
  String get pointsOnboardDaily =>
      isId ? 'Login tiap hari = +25 YukCoin' : 'Daily login = +25 YukCoin';
  String get pointsOnboardOnline =>
      isId ? 'Online 60 menit = +45 bonus' : 'Online 60 min = +45 bonus';
  String get pointsOnboardSpend => isId
      ? 'Fitur berbayar: undo, edit, mode hantu, slot foto'
      : 'Paid features: undo, edit, ghost mode, photo slots';
  String get pointsOnboardStart =>
      isId ? 'Mulai dengan 50 YukCoin gratis' : 'Start with 50 free YukCoin';
  String get pointsOnboardOk => isId ? 'OK, Paham!' : 'OK, Got it!';
  String get statusOnline => isId ? 'Online' : 'Online';
  String get statusIdle => isId ? 'Idle' : 'Idle';
  String get statusOffline => isId ? 'Offline' : 'Offline';
  String get statusInvisible => isId ? 'Invisible' : 'Invisible';
  String get lastSeenAt => isId ? 'Terakhir dilihat' : 'Last seen';
  String get typingStatus => isId ? 'Sedang mengetik' : 'Typing';
  String get recordingStatus =>
      isId ? 'Merekam suara...' : 'Recording voice...';
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
  String get noMessages => isId ? 'Belum ada pesan' : 'No messages yet';
  // Lawan bicara sudah menghapus akunnya (penanda lokal — server sudah
  // menghapus chat-nya demi privasi).
  String get accountDeleted => isId ? 'Akun dihapus' : 'Account deleted';
  String get accountDeletedHint => isId
      ? 'Pengguna ini telah menghapus akunnya. Kamu tidak bisa mengirim pesan lagi.'
      : 'This user has deleted their account. You can no longer send messages.';
  String get timeJustNow => isId ? 'Baru' : 'Now';
  String get labelToday => isId ? 'Hari ini' : 'Today';
  String get labelYesterday => isId ? 'Kemarin' : 'Yesterday';
  String get btnPin => isId ? 'Sematkan' : 'Pin';
  String get btnUnpin => isId ? 'Lepas Sematan' : 'Unpin';
  String get msgPinned =>
      isId ? 'Chat disematkan di atas' : 'Chat pinned to top';
  String get msgUnpinned => isId ? 'Sematan dilepas' : 'Chat unpinned';

  // ── Chat Screen (private & room) ──
  String get hintTypeMessage => isId ? 'Ketik pesan...' : 'Type a message...';
  String get errSendFailed => isId ? 'Gagal kirim: ' : 'Send failed: ';
  String get errPhotoRead =>
      isId ? 'Gagal membaca gambar' : 'Failed to read image';
  String get errSendPhoto =>
      isId ? 'Gagal kirim foto: ' : 'Failed to send photo: ';
  String get errVoiceUploadFailed =>
      isId ? 'Gagal upload voice note' : 'Voice note upload failed';
  String get errVoicePermission =>
      isId ? 'Izin mikrofon ditolak' : 'Microphone permission denied';
  String get errVoiceTooShort =>
      isId ? 'Rekaman terlalu pendek' : 'Recording too short';
  /// Rekaman gagal DIMULAI (mic dipakai app lain / error hardware). Dulu
  /// exception ditelan `catch (_) {}` → tombol voice terasa "rusak" tanpa pesan.
  String get errVoiceStartFailed => isId
      ? 'Gagal mulai merekam. Coba lagi (mikrofon mungkin dipakai aplikasi lain).'
      : 'Could not start recording. Try again (microphone may be in use).';
  String get msgVoice => isId ? '[Voice]' : '[Voice]';
  String get hintHoldToRecord => isId ? 'Tahan untuk rekam' : 'Hold to record';
  String get hintSlideToCancel =>
      isId ? 'Geser untuk batal' : 'Slide to cancel';
  String get msgPhoto => isId ? '[Foto]' : '[Photo]';
  // Label media di pratinjau daftar chat (padanan label server, bilingual).
  String get previewSticker => isId ? '[Stiker]' : '[Sticker]';
  String get previewVoice => isId ? '[Pesan suara]' : '[Voice message]';
  String get previewVideo => isId ? '[Video]' : '[Video]';
  String get previewCoin => isId ? '[Koin]' : '[Coin]';
  String get previewGift => isId ? '[Hadiah]' : '[Gift]';
  String get previewLocation => isId ? '[Lokasi]' : '[Location]';
  // ── Kirim Lokasi (ala WhatsApp) ──
  String get menuSendLocation => isId ? 'Lokasi' : 'Location';
  String get galleryAllowAccess =>
      isId ? 'Izinkan akses galeri' : 'Allow gallery access';
  // ── Kirim File / Dokumen ──
  String get menuSendFile => isId ? 'Dokumen' : 'Document';
  String errFileTooLarge(int mb) => isId
      ? 'File terlalu besar (maks $mb MB)'
      : 'File too large (max $mb MB)';
  String get errSendFile =>
      isId ? 'Gagal mengirim file' : 'Failed to send file';
  String get errOpenFile =>
      isId ? 'Gagal membuka file' : 'Could not open file';
  String get fileUploading => isId ? 'Mengirim...' : 'Sending...';
  String get fileDownloading => isId ? 'Mengunduh...' : 'Downloading...';
  // ── Polling (ala WhatsApp) ──
  // ── Kirim KONTAK (ala WhatsApp): kontak ChatYuk (uid) & kontak HP ──
  String get menuSendContact => isId ? 'Kontak' : 'Contact';
  String get contactPickerTitle => isId ? 'Kirim kontak' : 'Send contact';
  String get contactTabChatYuk => 'ChatYuk';
  String get contactTabPhone => isId ? 'Kontak HP' : 'Phone contacts';
  String get contactPickerSearch => isId ? 'Cari nama…' : 'Search name…';
  String get contactPickerEmpty =>
      isId ? 'Belum ada yang bisa dikirim' : 'Nothing to send yet';
  String get contactPickerEmptyHint => isId
      ? 'Hanya teman atau yang pernah chat yang bisa dikirim kontaknya.'
      : 'Only friends or people you have chatted with can be shared.';
  String get contactPhoneEmpty =>
      isId ? 'Buku kontak kosong' : 'No contacts found';
  String get contactPermissionTitle =>
      isId ? 'Izin akses kontak' : 'Contacts permission';
  String get contactPermissionBody => isId
      ? 'ChatYuk butuh akses buku kontak untuk mengirim kontak HP ke chat.'
      : 'ChatYuk needs access to your contacts to send a phone contact.';
  String get contactPermissionDenied => isId
      ? 'Izin kontak ditolak. Aktifkan di Setelan.'
      : 'Contacts permission denied. Enable it in Settings.';
  String get btnAllow => isId ? 'Izinkan' : 'Allow';
  String get btnOpenSettings => isId ? 'Buka Setelan' : 'Open Settings';
  String get contactPickNumber =>
      isId ? 'Pilih nomor' : 'Pick a number';
  String get btnChatContact => isId ? 'Chat' : 'Chat';
  String get btnViewProfile => isId ? 'Lihat profil' : 'View profile';
  String get btnCopyNumber => isId ? 'Salin nomor' : 'Copy number';
  String get btnCallContact => isId ? 'Telepon' : 'Call';
  String get contactUnavailable =>
      isId ? 'Pengguna tidak tersedia' : 'User unavailable';
  String get contactNumberCopied => isId ? 'Nomor disalin' : 'Number copied';
  String get errSendContact =>
      isId ? 'Gagal kirim kontak' : 'Failed to send contact';
  String get contactCardLabel => isId ? 'Kontak' : 'Contact';
  String get menuPoll => isId ? 'Polling' : 'Poll';
  String get pollCreateTitle => isId ? 'Buat polling' : 'Create poll';
  String get pollQuestion => isId ? 'Pertanyaan' : 'Question';
  String get pollQuestionHint => isId ? 'Ajukan pertanyaan' : 'Ask question';
  String get pollOptions => isId ? 'Opsi' : 'Options';
  String get pollAddOption => isId ? '+ Tambah' : '+ Add';
  String pollOptionHint(int n) => isId ? 'Opsi $n' : 'Option $n';
  String get pollAllowMultiple =>
      isId ? 'Izinkan beberapa jawaban' : 'Allow multiple answers';
  String get pollSelectOne => isId ? 'Pilih satu' : 'Select one';
  String get pollSelectMany =>
      isId ? 'Pilih satu atau lebih' : 'Select one or more';
  String pollVotes(int n) => isId ? '$n suara' : (n == 1 ? '1 vote' : '$n votes');
  String get pollNeedQuestion =>
      isId ? 'Tulis pertanyaannya dulu' : 'Write a question first';
  String get pollNeedOptions =>
      isId ? 'Minimal 2 opsi berbeda' : 'At least 2 different options';
  String get errSendPoll =>
      isId ? 'Gagal mengirim polling' : 'Failed to send poll';
  String get errVotePoll =>
      isId ? 'Gagal menyimpan pilihan' : 'Failed to save your vote';
  // ── Pemilih galeri (ala WhatsApp) ──
  String get galleryRecents => isId ? 'Terbaru' : 'Recents';
  // ── Timeline: baris 'Apa yang baru?' (ala Threads) ──
  String get whatsNewHint => isId ? 'Apa yang baru?' : "What's new?";
  String gallerySelectMax(int n) =>
      isId ? 'Maksimal $n foto' : 'Up to $n photos';
  String get galleryNoAccess => isId
      ? 'Izinkan ChatYuk mengakses foto untuk memilih dari galeri.'
      : 'Allow ChatYuk to access photos to pick from your gallery.';
  String get galleryOpenSettings => isId ? 'Buka Setelan' : 'Open Settings';
  String get msgLocation => isId ? '[Lokasi]' : '[Location]';
  // ── Kutipan balasan (reply quote) untuk pesan MEDIA ──
  // WhatsApp menampilkan nama + ikon jenis + thumbnail di kutipan; label ini
  // dipakai saat pesan asli tidak punya caption.
  String get previewPoll => isId ? '[Polling]' : '[Poll]';
  String get msgCall => isId ? '[Panggilan]' : '[Call]';
  String get replyVideoOnce =>
      isId ? '[Video sekali lihat]' : '[View once video]';
  String get replyPhotoOnce =>
      isId ? '[Foto sekali lihat]' : '[View once photo]';
  String get locSendTitle => isId ? 'Kirim Lokasi' : 'Send Location';
  String get locFetching =>
      isId ? 'Mendeteksi lokasi...' : 'Detecting location...';
  String get locSendConfirm =>
      isId ? 'Kirim Lokasi Ini' : 'Send This Location';
  String get locAttach => isId ? 'Lampirkan' : 'Attach';
  String get locSendCancel => isId ? 'Batal' : 'Cancel';
  String get locOpenMaps =>
      isId ? 'Buka di Google Maps' : 'Open in Google Maps';
  String get locPermissionDenied => isId
      ? 'Izin lokasi ditolak. Aktifkan di Pengaturan untuk kirim lokasi.'
      : 'Location permission denied. Enable it in Settings to send a location.';
  String get locFetchFailed => isId
      ? 'Lokasi tidak terdeteksi. Pastikan GPS aktif.'
      : 'Location not detected. Make sure GPS is on.';
  String get locSendRoomConfirm => isId
      ? 'Kirim lokasi ini ke semua anggota room?'
      : 'Send this location to everyone in the room?';
  String get locSendRoomTitle => isId ? 'Kirim Lokasi' : 'Send Location';
  String get locSendCurrent =>
      isId ? 'Kirim lokasi saat ini' : 'Send your current location';
  String get locLiveTitle =>
      isId ? 'Bagikan lokasi live' : 'Share live location';
  String get locNearbyTitle => isId ? 'Tempat sekitar' : 'Nearby places';
  String locAccuracyTo(int m) =>
      isId ? 'Akurasi ±$m meter' : 'Accurate to $m meters';
  // ── Status pencarian lokasi di sheet (reaktif, bukan blocking) ──
  String get locRefining => isId ? 'Memperbarui posisi...' : 'Updating position...';
  String get locApproximate =>
      isId ? 'Perkiraan posisi — menunggu GPS' : 'Approximate — waiting for GPS';
  String get locNoPlaces =>
      isId ? 'Tidak ada tempat terdekat' : 'No nearby places found';
  String get locTapToPick =>
      isId ? 'Geser / ketuk peta untuk pindah titik' : 'Drag or tap the map to move the pin';

  String locLiveMin(int m) => isId ? '$m menit' : '$m min';
  String locLiveHour(int h) => isId ? '$h jam' : '$h hr';
  String get locLiveEnded =>
      isId ? 'Lokasi live berakhir' : 'Live location ended';
  String get locLiveActive => isId ? 'Lokasi live' : 'Live location';
  String locLiveRemaining(int m) => isId ? 'berakhir $m menit' : '$m min left';
  String get msgViewOnce => isId ? '[Foto Sekali Lihat]' : '[View Once Photo]';
  String get viewOnceHdUnavailable => isId
      ? 'Versi HD belum siap — coba lagi sebentar'
      : 'HD version not ready — try again in a moment';
  String get viewOnceViewed => isId ? 'Sudah dilihat' : 'Viewed';
  /// Label aksi kartu foto sekali-lihat. Durasi HANYA ditulis bila memang
  /// bertimer; mode "1× lihat" (tanpa timer) tidak menyebut detik.
  /// [secs] = total detik nyata dari pesan (0 = sampai ditutup).
  String viewOnceTap(int secs) => secs <= 0
      ? (isId ? 'Tekan untuk melihat' : 'Tap to view')
      : (isId ? 'Tekan untuk melihat ($secs detik)' : 'Tap to view ($secs seconds)');
  String get viewOnceTitle => isId ? 'Foto Sekali Lihat' : 'View Once Photo';
  String get btnView => isId ? 'Lihat' : 'View';
  String get viewOnceExpired =>
      isId ? 'Foto sudah kadaluarsa' : 'Photo expired';
  String get videoOnceExpired =>
      isId ? 'Video sudah kadaluarsa' : 'Video expired';
  String get viewOnceExpiredHint =>
      isId ? 'Hanya bisa dilihat sekali' : 'Viewable only once';
  String get viewOnceViewing => isId ? 'Menutup dalam' : 'Closing in';
  String viewOnceClosingIn(int secs) =>
      isId ? 'Menutup dalam $secs dtk' : 'Closing in ${secs}s';
  String get msgBlocked => isId
      ? 'User ini diblokir, tidak bisa kirim pesan'
      : 'This user is blocked, cannot send message';
  String get labelYou => isId ? 'Kamu' : 'You';
  String get snackUserIdCopied =>
      isId ? 'User ID disalin' : 'User ID copied';
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
  String get blockConfirmTitle => isId ? 'Blokir pengguna?' : 'Block this user?';
  String get blockConfirmBody => isId
      ? '{name} tidak akan bisa mengirim pesan atau melihat profilmu. '
          'Kamu bisa membuka blokir kapan saja.'
      : "{name} won't be able to message you or see your profile. "
          'You can unblock them anytime.';
  /// Gagal blokir: [offline] = tidak ada koneksi (bukan ditolak server).
  String blockFailed({required bool offline}) => offline
      ? (isId
          ? 'Tidak ada koneksi internet. Coba blokir lagi setelah online.'
          : "No internet connection. Try blocking again once you're online.")
      : (isId
          ? 'Gagal memblokir pengguna. Coba lagi nanti.'
          : "Couldn't block this user. Please try again later.");
  String get unblockSuccess => isId ? 'Blokir dibuka' : 'User unblocked';
  String get btnDeleteChat => isId ? 'Hapus Chat' : 'Delete Chat';
  String get deleteChatSuccess => isId ? 'Chat dihapus' : 'Chat deleted';
  String get deleteChatConfirm => isId
      ? 'Hapus percakapan ini? Pesan tidak bisa dipulihkan.'
      : 'Delete this conversation? Messages cannot be recovered.';
  String get btnSelectAll => isId ? 'Pilih Semua' : 'Select All';
  String get btnDeselectAll => isId ? 'Batal Pilih' : 'Deselect All';
  String get btnDeleteAll => isId ? 'Hapus Semua' : 'Delete All';
  String get btnDeleteSelected => isId ? 'Hapus Terpilih' : 'Delete Selected';
  String get deleteAllConfirm => isId
      ? 'Hapus SEMUA percakapan? Tidak bisa dipulihkan.'
      : 'Delete ALL conversations? Cannot be recovered.';
  String deleteSelectedConfirm(int n) => isId
      ? 'Hapus $n percakapan terpilih?'
      : 'Delete $n selected conversations?';
  String get deleteAllSuccess =>
      isId ? 'Semua chat dihapus' : 'All chats deleted';
  String deleteSelectedSuccess(int n) =>
      isId ? '$n chat dihapus' : '$n chats deleted';
  String selectedCount(int n) => isId ? '$n terpilih' : '$n selected';

  /// Badge jumlah pesan baru pada mini-preview (mis. "3 baru").
  String newCount(int n) => isId ? '$n baru' : '$n new';

  /// Label jumlah penonton siaran langsung (mis. "4 peers").
  String viewerCount(int n) => isId ? '$n penonton' : '$n viewers';
  String get btnArchive => isId ? 'Arsipkan' : 'Archive';
  String get btnUnarchive => isId ? 'Keluarkan dari Arsip' : 'Unarchive';
  String get msgArchived => isId ? 'Chat diarsipkan' : 'Chat archived';
  String get msgUnarchived =>
      isId ? 'Chat dikeluarkan dari arsip' : 'Chat unarchived';
  String get msgMuted =>
      isId ? 'Notifikasi chat dimatikan' : 'Chat notifications muted';
  String get msgUnmuted =>
      isId ? 'Notifikasi chat dinyalakan' : 'Chat notifications unmuted';
  String labelArchived(int n) => isId ? 'Diarsipkan ($n)' : 'Archived ($n)';
  String get btnHide => isId ? 'Sembunyikan' : 'Hide';
  String get btnUnhide => isId ? 'Tampilkan' : 'Unhide';
  String get btnUndo => isId ? 'Urungkan' : 'Undo';
  String get msgHidden => isId ? 'Pengguna disembunyikan' : 'User hidden';
  String get msgUnhidden =>
      isId ? 'Pengguna ditampilkan lagi' : 'User unhidden';
  String labelHidden(int n) => isId ? 'Disembunyikan ($n)' : 'Hidden ($n)';

  // ── Filter daftar chat (Semua / Belum dibaca / Teman / Anon / Terdaftar) ──
  // `filterAll` sudah ada di atas (dipakai filter lain) — dipakai ulang.
  String get filterUnread => isId ? 'Belum dibaca' : 'Unread';
  String get filterFriends => isId ? 'Teman' : 'Friends';
  String get filterAnon => isId ? 'Anon' : 'Anon';
  String get filterRegistered => isId ? 'Terdaftar' : 'Registered';
  String filterAllCount(int n) => '$filterAll ($n)';
  String filterUnreadCount(int n) => '$filterUnread ($n)';
  String filterFriendsCount(int n) => '$filterFriends ($n)';
  String filterAnonCount(int n) => '$filterAnon ($n)';
  String filterRegisteredCount(int n) => '$filterRegistered ($n)';
  String get filterGroups => isId ? 'Grup' : 'Groups';
  String filterGroupsCount(int n) => '$filterGroups ($n)';
  // Empty-state per filter: daftar kosong BUKAN berarti tak ada chat sama
  // sekali — hanya tak ada yang cocok dengan filter aktif. Tanpa teks ini
  // layar tampak "blank" (insiden chip Teman (1) vs list kosong).
  String get noFriendChats =>
      isId ? 'Belum ada chat dengan teman' : 'No chats with friends yet';
  String get noFriendChatsHint => isId
      ? 'Chat yang lawan bicaranya sudah berteman akan muncul di sini'
      : 'Chats with befriended users will show up here';
  String get noAnonChats =>
      isId ? 'Belum ada chat anonim' : 'No anonymous chats yet';
  String get noAnonChatsHint => isId
      ? 'Chat dengan pengguna yang belum terdaftar akan muncul di sini'
      : 'Chats with unregistered users will show up here';
  String get noRegisteredChats =>
      isId ? 'Belum ada chat terdaftar' : 'No registered chats yet';
  String get noRegisteredChatsHint => isId
      ? 'Chat dengan pengguna terdaftar akan muncul di sini'
      : 'Chats with registered users will show up here';
  String get noUnreadChats =>
      isId ? 'Tidak ada pesan belum dibaca' : 'No unread messages';
  String get noUnreadChatsHint =>
      isId ? 'Semua chat sudah kamu baca' : 'You have read all chats';
  String get noGroupChats => isId ? 'Belum ada grup' : 'No groups yet';
  String get noGroupChatsHint => isId
      ? 'Grup yang kamu ikuti akan muncul di sini'
      : 'Groups you joined will show up here';
  // ── Antrean offline (pesan menunggu koneksi) ──
  String get msgQueuedOffline => isId
      ? 'Disimpan — terkirim otomatis saat online'
      : 'Saved — will send automatically when online';
  String get msgWaitingConnection =>
      isId ? 'Menunggu koneksi' : 'Waiting for connection';
  String msgQueuedCount(int n) => isId
      ? '$n menunggu koneksi — terkirim otomatis'
      : '$n waiting for connection — will send automatically';
  String msgQueueSent(int n) => isId ? '$n pesan terkirim' : '$n messages sent';

}
