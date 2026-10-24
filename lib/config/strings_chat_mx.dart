part of 'strings.dart';

mixin SChatMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
  // ── Profile ──
  String get titleProfile => isId ? 'Profil' : 'Profile';
  String get btnChangePhoto =>
      isId ? 'Ganti Foto Profil' : 'Change Profile Photo';
  String get btnAddPhoto => isId ? 'Tambah Foto Profil' : 'Add Profile Photo';
  String get labelStatus => isId ? 'Status' : 'Status';
  String get labelUserId => isId ? 'User ID' : 'User ID';
  String get labelHashtags => isId ? 'Hashtag' : 'Hashtags';
  // ── Halaman Profil (redesign) ──
  String get hashtagAdd => isId ? 'Tambah hashtag' : 'Add hashtag';
  String get hashtagAddShort => isId ? 'Tambah' : 'Add';
  String get titleMyPhotos => isId ? 'Foto Saya' : 'My Photos';
  String get photoAddLabel => isId ? 'Tambah' : 'Add';
  String get photoEmptyTitle => isId ? 'Belum ada foto' : 'No photos yet';
  String get photoEmptyBody => isId
      ? 'Profil dengan foto lebih sering disapa. Foto ini tampil besar di profilmu.'
      : 'Profiles with photos get more greetings. Photos appear large on your profile.';
  String get ofLabel => isId ? 'dari' : 'of';
  String get titleOthers => isId ? 'Lainnya' : 'Others';
  String get titleContactUs => isId ? 'Hubungi Kami' : 'Contact Us';
  String get contactUsSubtitle =>
      isId ? 'Bantuan, masukan & laporan' : 'Help, feedback & reports';
  String get settingsSubtitle => isId
      ? 'Akun, privasi, notifikasi & lainnya'
      : 'Account, privacy, notifications & more';
  String get hintHashtag =>
      isId ? 'Tambah hashtag lalu Enter' : 'Add hashtag and press Enter';
  String get errHashtagMax =>
      isId ? 'Maksimal 5 hashtag' : 'Maximum 5 hashtags';
  String get errHashtagFormat => isId
      ? 'Hanya huruf, angka, atau underscore'
      : 'Letters, numbers, or underscore only';
  String get labelYears => isId ? 'tahun' : 'years';
  String get btnLogout => isId ? 'Keluar' : 'Logout';
  String get btnOk => isId ? 'OK' : 'OK';
  String get offlineBanner =>
      isId ? 'Tidak ada koneksi internet' : 'No internet connection';
  String get confirmLogoutBody => isId
      ? 'Yakin ingin keluar dari akun ini?'
      : 'Are you sure you want to log out?';
  String get errLogoutFailed => isId
      ? 'Keluar gagal — sesi masih aktif. Coba lagi.'
      : 'Logout failed — session still active. Try again.';
  String get btnDeleteAccount => isId ? 'Hapus Akun' : 'Delete Account';
  String get confirmDeleteAccountBody => isId
      ? 'Akun, pesan, story, dan semua datamu akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.'
      : 'Your account, messages, stories, and all your data will be permanently deleted. This cannot be undone.';
  String get labelDeleteAccountConfirm => isId
      ? 'Ketik HAPUS / DELETE untuk konfirmasi'
      : 'Type HAPUS / DELETE to confirm';
  String get deleteAccountConfirmHint => 'HAPUS / DELETE';
  String get errDeleteAccount => isId
      ? 'Gagal menghapus akun. Coba lagi.'
      : 'Failed to delete account. Try again.';
  String get errDeleteAccountForbidden => isId
      ? 'Akun admin tidak bisa dihapus dari app.'
      : 'Admin accounts cannot be deleted from the app.';
  String get msgDeleteAccountSuccess =>
      isId ? 'Akun berhasil dihapus' : 'Account deleted';
  String get genderLabelMale => isId ? '👨 Laki-laki' : '👨 Male';
  String get genderLabelFemale => isId ? '👩 Perempuan' : '👩 Female';
  String get genderLabelOther => isId ? '🧑 Lainnya' : '🧑 Other';
  String get btnEditProfile => isId ? 'Edit Profil' : 'Edit Profile';
  String get btnSave => isId ? 'Simpan' : 'Save';
  String get msgEdited => isId ? '(diedit)' : '(edited)';
  String get editMessageTitle => isId ? 'Edit Pesan' : 'Edit Message';
  String get msgDeletedRoom => isId ? 'Pesan dihapus' : 'Message deleted';
  String get editingMessage =>
      isId ? 'Sedang mengedit pesan' : 'Editing message';
  String get menuReply => isId ? 'Balas' : 'Reply';
  String get messageDeleted => isId ? 'Pesan dihapus' : 'Message deleted';
  String get msgDeleteFailed =>
      isId ? 'Gagal menghapus pesan' : 'Failed to delete message';
  String get confirmDeleteMessage => isId
      ? 'Hapus pesan ini? Pesan tidak bisa dipulihkan.'
      : 'Delete this message? It cannot be recovered.';
  String get replyingTo => isId ? 'Membalas' : 'Replying to';
  // ── Mention @ ──
  String get mentionAll => isId ? 'Semua orang' : 'Everyone';
  String mentionHint(String q) =>
      isId ? 'Sebut pengguna: @$q' : 'Mention someone: @$q';
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
  String get linkPreviewLoading =>
      isId ? 'Memuat pratinjau...' : 'Loading preview...';
  String get linkPreviewTapToLoad =>
      isId ? 'Ketuk untuk memuat pratinjau' : 'Tap to load preview';
  String get errPhotoProcess =>
      isId ? 'Gagal proses foto' : 'Failed to process photo';
  String get errPhotoUpload => isId ? 'Gagal upload: ' : 'Failed to upload: ';
  String get errPhotoLoad =>
      isId ? 'Gagal membaca gambar' : 'Failed to read image';
  String get errPhotoPermission => isId
      ? 'Izin kamera/galeri belum diizinkan — aktifkan di Pengaturan HP'
      : 'Camera/gallery permission denied — enable it in device Settings';
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
  String get labelAbout => isId ? 'Tentang' : 'About';
  String get hintAbout =>
      isId ? 'Tulis sesuatu tentang kamu…' : 'Write something about you…';
  String get aboutEmpty => isId ? 'Belum ada tentang kamu' : 'No about yet';
  String get aboutPrivacyHint => isId
      ? 'Siapa yang melihat diatur di Pengaturan › Privasi'
      : 'Who can see this is set in Settings › Privacy';
  String get titleSettings => isId ? 'Pengaturan' : 'Settings';
  String get descSettings => isId
      ? 'Akun, privasi, notifikasi & lainnya'
      : 'Account, privacy, notifications & more';
  String get titleAccount => isId ? 'Akun' : 'Account';
  String get descAccount =>
      isId ? 'Keamanan, email, keluar & hapus akun' : 'Security, email, logout & delete account';
  String get menuDisplay => isId ? 'Tampilan' : 'Appearance';
  String get descDisplay =>
      isId ? 'Bahasa, tema & font chat' : 'Language, theme & chat font';
  String get menuHelp => isId ? 'Bantuan' : 'Help';
  String get descHelp =>
      isId ? 'Hubungi kami, donasi & versi' : 'Contact us, donate & version';
  String get menuChatFont => isId ? 'Font chat' : 'Chat font';
  String get privacyTitle => isId ? 'Privasi' : 'Privacy';
  String get privacyHint => isId
      ? 'Atur siapa yang dapat melihat aktivitas dan informasi profil kamu.'
      : 'Choose who can see your activity and profile information.';
  String get privacyEveryone => isId ? 'Semua orang' : 'Everyone';
  String get privacyEveryoneExcept =>
      isId ? 'Semua orang kecuali...' : 'Everyone except...';
  String get privacyFriends => isId ? 'Teman saya' : 'My friends';
  String get privacyFriendsExcept =>
      isId ? 'Teman saya kecuali...' : 'My friends except...';
  String get privacyOnly => isId ? 'Hanya orang tertentu' : 'Only certain people';
  String get privacyNobody => isId ? 'Tidak ada' : 'Nobody';
  // Deskripsi tiap opsi (sub-judul di sheet pemilih).
  String get privacyEveryoneDesc =>
      isId ? 'Siapa pun bisa melihat' : 'Anyone can see';
  String get privacyEveryoneExceptDesc =>
      isId ? 'Semua bisa melihat, kecuali orang terpilih'
          : 'Anyone except selected people';
  String get privacyFriendsDesc =>
      isId ? 'Hanya teman kamu' : 'Only your friends';
  String get privacyFriendsExceptDesc =>
      isId ? 'Hanya teman, kecuali orang terpilih'
          : 'Only friends, except selected people';
  String get privacyOnlyDesc =>
      isId ? 'Hanya orang yang kamu pilih' : 'Only people you pick';
  String get privacyNobodyDesc =>
      isId ? 'Tidak ada yang bisa melihat' : 'No one can see';
  String get privacyPresence => isId ? 'Status online' : 'Online status';
  String get privacyLastSeen => isId ? 'Terakhir dilihat' : 'Last seen';
  String get privacyProfilePhoto => isId ? 'Foto profil' : 'Profile photo';
  String get privacyAbout => isId ? 'About' : 'About';
  String get privacyStory => isId ? 'Story' : 'Story';
  String get privacyLeaderboard => isId ? 'Top Aktif' : 'Top Active';
  String get privacyLeaderboardDesc => isId
      ? 'Apakah kamu muncul di peringkat Top Aktif.'
      : 'Whether you appear in the Top Active ranking.';
  String get privacyCalls => isId ? 'Panggilan' : 'Calls';
  String get privacyCallsDesc => isId
      ? 'Siapa yang boleh menelepon kamu (audio & video).'
      : 'Who can call you (audio & video).';
  // Pesan saat call ditolak oleh privasi penerima.
  String get callNotAllowed => isId
      ? 'Pengguna ini tidak menerima panggilan.'
      : 'This user does not accept calls.';
  String get privacyReadReceipts => isId ? 'Laporan dibaca' : 'Read receipts';
  String get privacyReadReceiptsDesc => isId
      ? 'Pesan tetap terkirim, tetapi pengirim tidak melihat centang biru.'
      : 'Messages still send, but senders will not see blue read checks.';
  String get privacyExceptTitle =>
      isId ? 'Yang dikecualikan' : 'Excluded';
  String get privacyExceptDesc => isId
      ? 'Orang yang dipilih di sini TIDAK bisa melihat bagian ini.'
      : 'People picked here CANNOT see this.';
  String get privacyOnlyPickerTitle =>
      isId ? 'Hanya orang tertentu' : 'Only certain people';
  String get privacyOnlyPickerDesc => isId
      ? 'Hanya orang yang dipilih di sini yang bisa melihat bagian ini.'
      : 'Only people picked here CAN see this.';
  String get privacyNoFriends =>
      isId ? 'Belum ada yang bisa dipilih' : 'Nobody to pick yet';
  String get privacyNoFriendsHint => isId
      ? 'Tambahkan teman atau mulai chat supaya bisa memakai opsi ini.'
      : 'Add friends or start a chat to use this option.';
  String privacyEveryoneExceptCount(int n) =>
      isId ? '$privacyEveryoneExcept ($n)' : '$privacyEveryoneExcept ($n)';
  String privacyFriendsExceptCount(int n) =>
      isId ? '$privacyFriendsExcept ($n)' : '$privacyFriendsExcept ($n)';
  String privacyOnlyCount(int n) =>
      isId ? '$privacyOnly ($n)' : '$privacyOnly ($n)';
  String get privacyBadgeFriend => isId ? 'Teman' : 'Friend';
  String get privacyBadgeAnon => isId ? 'Anon' : 'Anon';
  String get privacyBadgeOther => isId ? 'Orang' : 'Person';
  String get privacySaveFailed =>
      isId ? 'Gagal menyimpan privasi' : 'Failed to save privacy';
  String get privacyReadReceiptsTitle =>
      isId ? 'Laporan dibaca' : 'Read receipts';
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
  String get notifActionMarkRead => isId ? 'Tandai dibaca' : 'Mark as read';
  String notifSummary(int chats, int msgs) => isId
      ? '$msgs pesan dari $chats chat'
      : '$msgs messages from $chats chats';
  String get notifOnlineBody => isId ? 'sedang online' : 'is online';
  String get notifFollowBody =>
      isId ? 'mulai mengikuti kamu' : 'started following you';
  String get notifFriendRequestBody =>
      isId ? 'mengirim permintaan teman' : 'sent you a friend request';
  String get notifSubscribeBody =>
      isId ? 'berlangganan ke kamu' : 'subscribed to you';
  String notifBroadcastBody(String roomName) =>
      isId ? 'Sedang broadcast di $roomName' : 'is broadcasting in $roomName';
  String get notifCallingBody =>
      isId ? 'menelpon kamu...' : 'is calling you...';
  String get notifCallingVideoBody =>
      isId ? '📹 panggilan video...' : '📹 video calling...';
  String get notifCallingVoiceBody =>
      isId ? '📞 panggilan suara...' : '📞 voice calling...';
  String get notifTimelineBody =>
      isId ? 'membuat postingan baru' : 'created a new post';
  String get notifMissedCallBody =>
      isId ? 'panggilan tak terjawab' : 'missed call';
  String get notifCallEndedBody => isId ? 'Panggilan berakhir' : 'Call ended';
  // ── Notifikasi Detail (per-jenis toggle) ──
  String get notifDetailTitle =>
      isId ? 'Pengaturan Notifikasi' : 'Notification Settings';
  String get notifDetailHint => isId
      ? 'Pilih notifikasi yang ingin kamu terima'
      : 'Choose which notifications to receive';
  String get notifTypeCall => isId ? 'Panggilan' : 'Calls';
  String get notifTypeCallDesc =>
      isId ? 'Panggilan suara & video' : 'Voice & video calls';
  String get notifTypeChat => isId ? 'Chat' : 'Chats';
  String get notifTypeChatDesc =>
      isId ? 'Pesan private baru' : 'New private messages';
  String get notifTypeOnline => isId ? 'Pesan Online' : 'Online Alerts';
  String get notifTypeOnlineDesc =>
      isId ? 'Teman chat sedang online' : 'Chat contact is online';
  String get notifTypeBroadcast => isId ? 'Live Broadcast' : 'Live Broadcast';
  String get notifTypeBroadcastDesc => isId
      ? 'Ada yang mulai broadcast di room'
      : 'Someone starts broadcasting in a room';
  String get notifTypeTimeline => isId ? 'Timeline' : 'Timeline';
  String get notifTypeTimelineDesc =>
      isId ? 'Postingan baru di timeline' : 'New timeline posts';
  String get notifTypeFollower => isId ? 'Pengikut' : 'Followers';
  String get notifTypeFollowerDesc =>
      isId ? 'Seseorang mengikuti kamu' : 'Someone followed you';
  String get notifTypeFollowing => isId ? 'Mengikuti' : 'Following';
  String get notifTypeFollowingDesc => isId
      ? 'Langganan & update mengikuti'
      : 'Subscriptions & following updates';
  String get notifTypeFriend => isId ? 'Teman' : 'Friends';
  String get notifTypeFriendDesc =>
      isId ? 'Permintaan & update teman' : 'Friend requests & updates';
  String get chatOnlineBadge => isId ? 'Online' : 'Online';
  String get chatOnlineSubtitle => isId ? '● Online sekarang' : '● Online now';
  String get labelNotifications => isId ? 'Notifikasi' : 'Notifications';
  String get notifEnabledDesc => isId
      ? 'Terima notifikasi pesan baru'
      : 'Receive new message notifications';

  // ── Ukuran font chat (slider di profil) ──
  String get labelChatFontSize => isId ? 'Ukuran font chat' : 'Chat font size';
  String get descChatFontSize => isId
      ? 'Atur besar teks di pesan chat'
      : 'Adjust text size in chat messages';
  String get chatFontPreview =>
      isId ? 'Contoh: Halo, apa kabar? 👋' : 'Preview: Hi, how are you? 👋';

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
  // ── Riwayat Panggilan (menu titik-3 tab Pesan) ──
  String get menuRecentCalls => isId ? 'Riwayat Panggilan' : 'Call History';
  String get callHistoryEmpty =>
      isId ? 'Belum ada riwayat panggilan' : 'No call history yet';
  String get callHistoryEmptyHint => isId
      ? 'Panggilan masuk dan keluar akan muncul di sini'
      : 'Incoming and outgoing calls will appear here';
  String get callHistoryToday => isId ? 'Hari ini' : 'Today';
  String get callHistoryYesterday => isId ? 'Kemarin' : 'Yesterday';
  String get callDirOutgoing => isId ? 'Keluar' : 'Outgoing';
  String get callDirIncoming => isId ? 'Masuk' : 'Incoming';
  String get callRedial => isId ? 'Panggil ulang' : 'Call back';
  String get errCallPermission =>
      isId ? 'Izin kamera & mikrofon diperlukan untuk panggilan' : 'Camera & microphone permission needed for calls';
  String get errCallPermissionVideo =>
      isId ? 'Izin kamera diperlukan untuk panggilan video' : 'Camera permission needed for video calls';
  String get errCallMediaInUse =>
      isId ? 'Kamera/mikrofon sedang dipakai aplikasi lain' : 'Camera/microphone is used by another app';
  String get errCallMediaNotFound =>
      isId ? 'Kamera/mikrofon tidak ditemukan' : 'Camera/microphone not found';
  String get btnOpenSettings =>
      isId ? 'Buka Pengaturan' : 'Open Settings';
  String get btnTryAgain => isId ? 'Coba lagi' : 'Try again';
  String get btnReconnect => isId ? 'Sambung ulang' : 'Reconnect';
  String get msgCallRegisterOnly => isId
      ? 'Hanya akun terdaftar yang bisa melakukan panggilan.'
      : 'Only registered accounts can make calls.';
  String get msgCallInProgress =>
      isId ? 'Kamu sedang dalam panggilan lain.' : 'You are in another call.';
  String get errCallNetwork =>
      isId ? 'Tidak ada koneksi — periksa internet lalu coba lagi' : 'No connection — check internet and retry';
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
  String get privateRoomsStopBroadcast =>
      isId ? 'Hentikan broadcast' : 'Stop broadcast';
  String get roomBroadcastConnecting => isId ? 'Menyiapkan…' : 'Starting…';
  String get broadcastLiveNotif => isId
      ? 'Broadcast aktif — ketuk untuk kembali'
      : 'Broadcast live — tap to return';
  String get broadcastWatchingNotif => isId
      ? 'Menonton broadcast — ketuk untuk kembali'
      : 'Watching broadcast — tap to return';
  String get privateRoomsStartBroadcast =>
      isId ? 'Mulai broadcast' : 'Start broadcast';
  String get privateRoomsLiveNow => isId ? 'LIVE' : 'LIVE';

  String get roomActionHandRaise => isId ? 'Angkat tangan' : 'Raise hand';

  String get roomHandRaised => isId
      ? 'Tangan diangkat — tunggu admin mengizinkan'
      : 'Hand raised — waiting for admin approval';

  String get privateRoomsLiveConnecting =>
      isId ? 'Menyambungkan...' : 'Connecting...';

  String get privateRoomsMembersTitle => isId ? 'Anggota' : 'Members';

  String get privateRoomsPendingQueue =>
      isId ? 'Menunggu Persetujuan' : 'Pending Approvals';

  String get privateRoomsTitle => isId ? 'Room Privat' : 'Private Rooms';
  String get privateRoomNeedApproval => isId
      ? 'Menunggu persetujuan admin untuk mengirim pesan'
      : 'Waiting for admin approval to send messages';
  String get roomBroadcastFull =>
      isId ? 'Sudah 4 broadcaster (maksimal)' : 'Broadcast full (4/4)';
  String get roomBroadcastCapHint => isId
      ? 'Tunggu giliran atau angkat tangan'
      : 'Wait your turn or raise hand';

  String get labelAccountDeleted =>
      isId ? 'Akun dihapus' : 'Deleted account';
  String get msgAccountDeleted => isId
      ? 'Akun ini sudah dihapus'
      : 'This account has been deleted';

  // ── Voice stage global room (audio-only, max 6 mic) ──
}
