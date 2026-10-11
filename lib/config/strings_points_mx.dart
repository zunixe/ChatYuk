part of 'strings.dart';

mixin SPointsMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
  String get pointsTitle => isId ? 'YukCoin' : 'YukCoin';
  String get pointsBalance => isId ? 'Poin' : 'Points';
  String onlineMilestone(int minutes) =>
      isId ? 'Online $minutes menit' : 'Online $minutes min';
  String get outOfPointsTitle => isId ? '😢 Poin Habis!' : '😢 Out of Points!';
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

  // ── Story (ala Instagram) ──
  String get storyAddTooltip => isId ? 'Buat Story' : 'Create Story';
  String get storyComposerTitle => isId ? 'Story Baru' : 'New Story';
  String get storyAddTextHint => isId ? 'Tulis sesuatu…' : 'Say something…';
  String get storyVisibilityLabel =>
      isId ? 'Siapa yang bisa melihat story ini?' : 'Who can see this story?';
  String get storyVisibilityEveryone => isId ? 'Semua orang' : 'Everyone';
  String get storyVisibilityEveryoneDesc =>
      isId ? 'Termasuk pengguna anonim' : 'Includes anonymous users';
  String get storyVisibilityFollowers => isId ? 'Pengikut' : 'Followers';
  String get storyVisibilityFollowersDesc =>
      isId ? 'Hanya yang mengikuti kamu' : 'Only people who follow you';
  String get storyVisibilityFriends => isId ? 'Teman' : 'Friends';
  String get storyVisibilityFriendsDesc =>
      isId ? 'Hanya teman dua arah' : 'Mutual friends only';
  /// Label slide private (dulu "dihapus") — hanya pembuat yang bisa lihat.
  String get storyVisibilityPrivate =>
      isId ? 'Private (hanya saya)' : 'Private (only me)';
  String get storyVisibilityPrivateDesc => isId
      ? 'Disembunyikan dari orang lain, hanya kamu yang bisa lihat'
      : 'Hidden from others, only you can see it';
  String get storyBtnPublish => isId ? 'Bagikan ke Story' : 'Share to Story';
  String get storyMine => isId ? 'Story Saya' : 'My Story';
  String get storyMicNeeded => isId
      ? 'Izin mikrofon dibutuhkan untuk merekam video'
      : 'Microphone permission is needed to record video';
  String get storyRecordFail => isId
      ? 'Gagal merekam video, coba lagi'
      : 'Failed to record video, try again';
  String get storyHoldToRecord =>
      isId ? 'Tahan untuk merekam video' : 'Hold to record video';
  String get storyVideoTooLong => isId
      ? 'Video maksimal 15 detik'
      : 'Video must be 15 seconds max';
  String get storyVideoTooShort => isId
      ? 'Video terlalu pendek (minimal 1 detik)'
      : 'Video too short (minimum 1 second)';
  String get storyVideoSplitInfo => isId
      ? 'Video panjang dipotong otomatis per 15 detik — maksimal 2 story.'
      : 'Long video is auto-split every 15 seconds — max 2 stories.';
  String get storyVideoTooBig => isId
      ? 'Video terlalu besar (maks 15 MB)'
      : 'Video too large (max 15 MB)';
  String get storyCompressFail => isId
      ? 'Gagal mengompres video, coba lagi'
      : 'Failed to compress video, try again';
  String get storyCompressing => isId
      ? 'Mengompres video…'
      : 'Compressing video…';
  String get storyMute => isId ? 'Benamkan story' : 'Mute story';
  String get storyUnmute => isId ? 'Tampilkan lagi' : 'Unmute story';
  String get storyMuted => isId
      ? 'Story dibenamkan — pindah paling belakang'
      : 'Story muted — moved to the back';
  String get storyUnmuted =>
      isId ? 'Story ditampilkan lagi' : 'Story unmuted';
  String get storyEmptyTray => isId ? 'Belum ada story' : 'No stories yet';
  String get storyAddToStory => isId ? 'Tambah' : 'Add';
  String get storyUploading => isId ? 'Mengunggah…' : 'Uploading…';
  String get storyPublishFail =>
      isId ? 'Gagal membagikan story' : 'Failed to share story';
  String get storyDeleted =>
      isId ? 'Story jadi privat (hanya kamu)' : 'Story set to private (only you)';
  String get storyVideoSoon =>
      isId ? 'Story video segera hadir' : 'Video stories coming soon';
  String get storyCamera => isId ? 'Kamera' : 'Camera';
  String get storyPartialTitle =>
      isId ? 'Akses foto terbatas' : 'Limited photo access';
  String get storyPartialDesc => isId
      ? 'Hanya sebagian foto yang terlihat. Pilih foto lain atau izinkan semua di Pengaturan.'
      : 'Only some photos are visible. Select more photos or allow all in Settings.';
  String get storyPartialAdd => isId ? 'Pilih foto' : 'Select photos';
  String get storyPartialAllowAll => isId ? 'Izinkan semua' : 'Allow all';
  String get storyDeleteFail =>
      isId ? 'Gagal menghapus story' : 'Failed to delete story';
  String get storyLoadFail =>
      isId ? 'Gagal memuat story' : 'Failed to load story';
  String get storyDeleteSlideTitle =>
      isId ? 'Sembunyikan slide ini?' : 'Hide this slide?';
  String get storyDeleteSlideMsg => isId
      ? 'Slide ini tidak akan terlihat orang lain, tapi tetap bisa kamu lihat sendiri (privat).'
      : 'This slide won\'t be visible to others, but you can still see it yourself (private).';
  String get storyViewersTitle => isId ? 'Penonton Story' : 'Story Viewers';
  String get storyViewersEmpty =>
      isId ? 'Belum ada yang melihat' : 'No views yet';
  String get storyViewersLoadFail => isId
      ? 'Gagal memuat daftar penonton'
      : 'Failed to load viewers';
  String get storyOwnBadge => isId ? 'Kamu' : 'You';
  String get storyTextPaletteTooltip => isId ? 'Warna teks' : 'Text color';
  String get storyTextSizeTooltip => isId ? 'Ukuran teks' : 'Text size';
  String get storyTextBgTooltip => isId ? 'Latar teks' : 'Text background';
  String get storyAnonBlocked => isId
      ? 'Story hanya untuk pengguna terdaftar'
      : 'Stories are for registered users only';
  String get storySlideLimit =>
      isId ? 'Batas 10 story per 24 jam' : 'Limit is 10 stories per 24 hours';
  String get storyTapLeftRightHint => isId
      ? 'Tap sisi kanan/kiri untuk pindah'
      : 'Tap right/left side to navigate';
  String storyReplyHint(String name) =>
      isId ? 'Balas $name...' : 'Reply to $name...';
  String get storyReplySent => isId ? 'Balasan terkirim' : 'Reply sent';
  String storyLikeCount(int n) =>
      isId ? '$n suka' : '$n like${n == 1 ? '' : 's'}';
  String storyShareMsg(String name) => isId
      ? 'Lihat story $name di ChatYuk!\nhttps://play.google.com/store/apps/details?id=com.chatyuk.chatyuk'
      : 'Check out $name\'s story on ChatYuk!\nhttps://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';
  String get storyDiscardTitle => isId ? 'Buang story?' : 'Discard story?';
  String get storyDiscardMsg => isId
      ? 'Foto dan teks yang belum dibagikan akan hilang.'
      : 'Unshared photo and text will be lost.';
  String get storyDiscardYes => isId ? 'Buang' : 'Discard';
  String get storyKeepEditing => isId ? 'Lanjut' : 'Keep editing';
  // ── Foto terkunci (paywall) ──
  String get photoLockedTitle => isId ? 'Foto Terkunci' : 'Locked Photo';
  String get photoLockedHint =>
      isId ? 'Buka foto ini untuk melihatnya' : 'Unlock this photo to view it';
  String photoUnlockOnce(int c) =>
      isId ? 'Lihat sekali · $c YukCoin' : 'View once · $c YukCoin';
  String photoUnlockPerm(int c) =>
      isId ? 'Buka permanen · $c YukCoin' : 'Unlock forever · $c YukCoin';
  String get photoUnlockNeedTopup => isId
      ? 'YukCoin tidak cukup. Dapatkan dari bonus harian & aktivitas.'
      : 'Not enough YukCoin. Earn from daily bonuses & activities.';
  String get photoUnlockFailed =>
      isId ? 'Gagal membuka foto' : 'Failed to unlock photo';
  String get photoUnlockedToast => isId ? 'Foto terbuka' : 'Photo unlocked';
  // ── History Poin ──
  String get pointHistoryTitle => isId ? 'History Poin' : 'Point History';
  String get pointHistoryEmpty =>
      isId ? 'Belum ada transaksi' : 'No transactions yet';
  String get pointHistoryCredit => isId ? 'Masuk' : 'In';
  String get pointHistoryDebit => isId ? 'Keluar' : 'Out';
  String get pointHistoryCoin => isId ? 'YukCoin' : 'YukCoin';
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
  String get pointHistoryCoinSent => isId ? 'Kirim YukCoin' : 'Send YukCoin';
  String get pointHistoryCoinReceived => isId ? 'Terima YukCoin' : 'Receive YukCoin';
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
  String get walletBucketBonus => isId ? 'YukCoin bonus' : 'Bonus YukCoin';
  String get walletBucketTopup => isId ? 'YukCoin' : 'YukCoin';
  String get walletBucketEarned => isId ? 'YukCoin hadiah' : 'Gift YukCoin';
  String get walletTitle => isId ? 'Dompet YukCoin' : 'YukCoin Wallet';
  String get walletTotal => isId ? 'Total YukCoin' : 'Total YukCoin';

  // ── YukCoin v2 (halaman & fitur berbayar) ──
  String get yukcoinTitle => isId ? 'YukCoin' : 'YukCoin';
  String get yukcoinMyBalance => isId ? 'Saldo kamu' : 'Your balance';
  String get yukcoinHowToEarn => isId ? 'Cara dapat YukCoin' : 'How to earn YukCoin';
  // Overhaul 2026-10: tidak ada bonus gratis — coin dari topup/welcome.
  String get yukcoinEarnTopup => isId ? 'Top-up (beli koin)' : 'Top-up (buy coins)';
  String get yukcoinEarnWelcome => isId ? 'Bonus pendaftaran' : 'Sign-up bonus';
  String get yukcoinEarnCallIncome =>
      isId ? 'Terima panggilan' : 'Receive calls';
  String get yukcoinFeatureCallAudio =>
      isId ? 'Panggilan audio' : 'Audio call';
  String get yukcoinFeatureCallVideo =>
      isId ? 'Panggilan video' : 'Video call';
  String get yukcoinFeatureFilterGender =>
      isId ? 'Filter gender' : 'Gender filter';
  String get yukcoinFeatureNearby =>
      isId ? 'Cari orang sekitar' : 'Find people nearby';
  String get yukcoinPerMin => isId ? 'koin/menit' : 'coins/min';
  String get yukcoinHowToSpend =>
      isId ? 'Cara pakai YukCoin' : 'How to spend YukCoin';
  String get yukcoinTopup => isId ? 'Isi YukCoin' : 'Top up YukCoin';
  String get yukcoinPickPackage =>
      isId ? 'Pilih paket koin' : 'Pick a coin package';
  // Overhaul coin (2026-10): tidak ada poin gratis — coin hanya dari topup.
  String get pointsOutOfCoinBody => isId
      ? 'Koinmu habis. Isi koin lewat top-up untuk lanjut menelepon & memakai fitur.'
      : 'You are out of coins. Top up to keep calling and using features.';
  String get pointsOnboardCoinTitle =>
      isId ? 'Koin untuk menelepon' : 'Coins for calling';
  String get pointsOnboardCoinBody => isId
      ? 'Isi koin lewat top-up. Pakai koin untuk menelepon (audio/video), filter, dan cari orang sekitar.'
      : 'Top up to get coins. Use them for calls (audio/video), filters, and finding people nearby.';
  String get pointsOnboardCallFree => isId
      ? 'Menelepon (audio/video) pakai koin'
      : 'Calling (audio/video) uses coins';
  String callCostPerMin(int coins) => isId
      ? '🪙 $coins koin/menit'
      : '🪙 $coins coins/min';
  String get callEndedNoCoin => isId
      ? 'Koin habis — panggilan diakhiri'
      : 'Out of coins — call ended';
  // Edukasi: coin dipakai untuk nelp (ditampilkan saat saldo tak cukup).
  String get callNeedCoinTitle => isId ? '🪙 Koin untuk menelepon' : '🪙 Coins for calling';
  String callNeedCoinBody(int need) => isId
      ? 'Untuk menelepon kamu butuh minimal $need koin (1 menit pertama). Isi koin lewat top-up untuk mulai menelepon.'
      : 'You need at least $need coins to call (first minute). Top up to start calling.';
  String get yukcoinTopupSoon =>
      isId ? 'Top-up segera hadir' : 'Top-up coming soon';
  String get yukcoinEarnLogin => isId ? 'Login harian' : 'Daily login';
  String get yukcoinEarnOnline => isId ? 'Online harian' : 'Daily online';
  String get yukcoinEarnRoomRead => isId ? 'Baca room' : 'Read rooms';
  String get yukcoinEarnNewChat => isId ? 'Chat orang baru' : 'Chat new people';
  String get yukcoinEarnReferral => isId ? 'Ajak teman' : 'Invite friends';
  String get yukcoinEarnQuest => isId ? 'Misi mingguan' : 'Weekly quests';
  String get yukcoinFeatureUndo =>
      isId ? 'Undo pesan' : 'Undo message';
  String get yukcoinFeatureEdit =>
      isId ? 'Edit pesan' : 'Edit message';
  String get yukcoinFeatureExtraPhoto =>
      isId ? 'Slot foto tambahan' : 'Extra photo slots';
  String get yukcoinFeatureGhost =>
      isId ? 'Mode hantu (invisible)' : 'Ghost mode (invisible)';
  String get yukcoinPerUse => isId ? 'sekali pakai' : 'per use';
  String get yukcoinPerDay => isId ? 'per hari' : 'per day';
  String get yukcoinOnce => isId ? 'sekali beli' : 'one-time';
  String get yukcoinNotEnough =>
      isId ? 'YukCoin tidak cukup' : 'Not enough YukCoin';
  String get yukcoinBought => isId ? 'Berhasil dibeli' : 'Purchased';
  String get yukcoinFailed =>
      isId ? 'Gagal, coba lagi' : 'Failed, try again';
  String get yukcoinUseConfirm =>
      isId ? 'Pakai YukCoin?' : 'Use YukCoin?';
  String yukcoinUseConfirmBody(int cost) => isId
      ? 'Aksi ini akan memakai $cost YukCoin.'
      : 'This action will cost $cost YukCoin.';
  String get yukcoinCancel => isId ? 'Batal' : 'Cancel';
  String get yukcoinConfirm => isId ? 'Pakai' : 'Use';
  String get ghostModeActive => isId ? 'Mode hantu aktif' : 'Ghost mode active';
  String get ghostModeBuy => isId ? 'Beli mode hantu' : 'Buy ghost mode';
  String get ghostModeDesc => isId
      ? 'Sembunyikan status online-mu. Kamu tetap bisa chat.'
      : 'Hide your online status. You can still chat.';
  String get undoMessageDone => isId ? 'Pesan dibatalkan' : 'Message undone';
  String get editMessageHint =>
      isId ? 'Tulis pesan baru...' : 'Write new message...';
  String get extraPhotoBuy => isId ? 'Beli +5 slot foto' : 'Buy +5 photo slots';

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
      ? 'YukCoin tidak cukup untuk hadiah ini'
      : 'Not enough YukCoin for this gift';
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
  // ── Top Aktif (leaderboard keaktifan: pesan + reaksi) ──
  String get topActiveTitle => isId ? 'Top Aktif' : 'Top Active';
  String get topActiveTooltip =>
      isId ? 'Top Aktif — paling sering chat' : 'Top Active — most chatty';
  String get topActiveTabWeekly => isId ? 'Mingguan' : 'Weekly';
  String get topActiveTabAllTime => isId ? 'Sepanjang Masa' : 'All-Time';
  String get topActiveHintWeekly => isId
      ? 'Peringkat keaktifan 7 hari terakhir'
      : 'Activity ranking — last 7 days';
  String get topActiveHintAllTime => isId
      ? 'Peringkat keaktifan sepanjang masa'
      : 'Activity ranking — all-time';
  String get topActiveEmpty =>
      isId ? 'Belum ada data keaktifan' : 'No activity data yet';
  String get topActiveUnranked =>
      isId ? 'Belum masuk peringkat' : 'Not ranked yet';
  String get topActiveYourRank => isId ? 'Peringkat kamu' : 'Your rank';
  String get topActiveMsgs => isId ? 'pesan' : 'messages';
  String get topActiveReactions => isId ? 'reaksi' : 'reactions';
  String get topActiveScore => isId ? 'Skor' : 'Score';
  String get topActivePosts => isId ? 'postingan' : 'posts';
  String get topActiveStories => isId ? 'story' : 'stories';
  String get topActiveTopLabelWeekly =>
      isId ? 'Paling aktif minggu ini' : 'Most active this week';
  String get topActiveTopLabelAllTime =>
      isId ? 'Paling aktif sepanjang masa' : 'Most active all-time';
  String get topActiveGuestLabel => isId ? 'Aktif berkontribusi' : 'Active member';
  String get topActiveSubHint => isId
      ? 'Peringkat berdasarkan keaktifan — tanpa angka'
      : 'Ranked by activity — no numbers';

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
  String get roomInviteTitle => isId ? 'Undang ke grup' : 'Invite to group';
  String get roomInviteHint => isId
      ? 'Pilih dari yang pernah chat denganmu (teman/bukan)'
      : 'Pick from people you have chatted with (friends or not)';
  String get roomInvitedOk =>
      isId ? 'Berhasil diundang ke grup' : 'Invited to group';
  String get roomInviteFull => isId ? 'Grup penuh' : 'Group is full';
  String get roomInviteSearchHint =>
      isId ? 'Cari nama...' : 'Search name...';
  String get roomInviteFriends => isId ? 'Teman' : 'Friends';
  String get roomInviteOthers => isId ? 'Lainnya' : 'Others';
  String get roomInviteAlready =>
      isId ? 'Sudah diundang' : 'Already invited';
  String get privateRoomsInviteMembers =>
      isId ? 'Undang Anggota' : 'Invite members';
  String privateRoomsInvitedCount(int n) =>
      isId ? 'Terundang ($n)' : 'Invited ($n)';
  String get btnSkip => isId ? 'Lewati' : 'Skip';
  String get btnDone => isId ? 'Selesai' : 'Done';
  String get mFirstPhoto => isId ? 'Kirim foto pertama' : 'Send first photo';
  String get mFirstRoomChat => isId ? 'Chat room pertama' : 'First room chat';
  String get btnRetry => isId ? 'Coba Lagi' : 'Retry';
  String get btnRefresh => isId ? 'Segarkan' : 'Refresh';
  String get msgServerError =>
      isId ? 'Gagal terhubung ke server' : 'Failed to connect to server';
  String get msgServerErrorHint => isId
      ? 'Periksa koneksi internet kamu, lalu coba lagi.'
      : 'Check your internet connection and try again.';
  String get msgFileTooLarge => isId
      ? 'File terlalu besar. Maksimal 10MB.'
      : 'File too large. Maximum 10MB.';

  // ── Kualitas foto HD (ala WhatsApp) ──
  String get photoHdLabel => 'HD';
  String get photoHdOn => isId ? 'HD aktif' : 'HD on';
  String get photoHdOff => isId ? 'HD mati' : 'HD off';
  String get photoQualityTitle =>
      isId ? 'Kualitas Foto' : 'Photo Quality';
  String get photoQualityStandard => isId ? 'Standar' : 'Standard';
  String get photoQualityStandardDesc => isId
      ? 'Kirim cepat & hemat kuota'
      : 'Fast sending & data saving';
  String get photoQualityHd => isId ? 'HD' : 'HD';
  String get photoQualityHdDesc => isId
      ? 'Resolusi tinggi (~1920px), file lebih besar'
      : 'High resolution (~1920px), larger files';

  // ── Bersihkan cache (penyimpanan) ──
  String get clearCacheTitle =>
      isId ? 'Bersihkan Cache' : 'Clear Cache';
  String get clearCacheDesc => isId
      ? 'Kosongkan cache sementara (pesan & foto tetap aman)'
      : 'Free up temporary cache (messages & photos stay safe)';
  String get clearCacheConfirmTitle =>
      isId ? 'Bersihkan cache?' : 'Clear cache?';
  String get clearCacheConfirmBody => isId
      ? 'Cache sementara (foto & pesan yang belum lama dibuka) akan dikosongkan '
          'untuk mempercepat aplikasi. Pesan & foto kamu TIDAK terhapus — '
          'hanya dimuat ulang saat dibuka lagi.'
      : 'Temporary cache (recently viewed photos & messages) will be cleared '
          'to speed up the app. Your messages & photos are NOT deleted — '
          'they are just reloaded when opened again.';
  String get clearCacheDone =>
      isId ? 'Cache dibersihkan' : 'Cache cleared';
  String get btnClear => isId ? 'Bersihkan' : 'Clear';

  // ── Popup update aplikasi ──
  String get updateTitle => isId ? 'Update Tersedia' : 'Update Available';
  String get updateRequiredTitle =>
      isId ? 'Update Wajib' : 'Update Required';
  String updateAvailableMsg(String v) => isId
      ? 'Versi $v sudah tersedia. Update sekarang untuk pengalaman terbaik.'
      : 'Version $v is available. Update now for the best experience.';
  String get updateRequiredMsg => isId
      ? 'Versi kamu sudah tidak didukung. Update dulu untuk lanjut memakai app.'
      : 'Your version is no longer supported. Please update to continue.';
  String get updateNotesLabel => isId ? 'Yang baru:' : "What's new:";
  String get btnUpdateNow => isId ? 'Update Sekarang' : 'Update Now';
  String get btnUpdateLater => isId ? 'Nanti' : 'Later';
  String updateDownloading(int pct) =>
      isId ? 'Mengunduh… $pct%' : 'Downloading… $pct%';
  String get updatePreparing =>
      isId ? 'Menyiapkan unduhan…' : 'Preparing download…';
  String get updateReadyTitle =>
      isId ? 'Update siap dipasang' : 'Update ready to install';
  String get updateReadyMsg => isId
      ? 'Update sudah diunduh. Mulai ulang app untuk menerapkannya.'
      : 'The update is downloaded. Restart the app to apply it.';
  String get btnUpdateRestart =>
      isId ? 'Mulai Ulang & Pasang' : 'Restart & Install';
  String get updateFailed => isId
      ? 'Gagal memulai update. Coba lagi atau update lewat Google Play.'
      : 'Failed to start the update. Try again or update via Google Play.';
  String get btnOpenStore => isId ? 'Buka Google Play' : 'Open Google Play';
  String get updateOpenStoreMsg => isId
      ? 'App ini tidak di-install dari Google Play. Buka halaman app di Play Store untuk update.'
      : 'This app was not installed from Google Play. Open the Play Store listing to update.';
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
  // Header menu Online: total user (agregat) — compact.
  String get onlineTotalRegistered => isId ? 'terdaftar' : 'registered';
  String get onlineTotalAnon => isId ? 'anon' : 'anon';
  String get labelVerified => isId ? 'Terverifikasi' : 'Verified';
  String get lobbyCountryHint => isId ? 'Negara / Country' : 'Country / Negara';
  String get donateCopyAddress => isId ? 'Salin Alamat ' : 'Copy Address ';
  String liveViewerCount(int count) => 'LIVE · $count';
  String get googleSignInFailed =>
      isId ? 'Google sign in gagal: ' : 'Google sign in failed: ';

  // ── Admin Chat Monitor ──
}
