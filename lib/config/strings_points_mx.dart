part of 'strings.dart';

mixin SPointsMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
  String get pointsTitle => isId ? 'YukCoin' : 'YukCoin';
  String get pointsBalance => isId ? 'YukCoin' : 'YukCoin';
  String onlineMilestone(int minutes) =>
      isId ? 'Online $minutes menit' : 'Online $minutes min';
  String get outOfPointsTitle => isId ? '😢 YukCoin Habis!' : '😢 Out of YukCoin!';
  String get pointsSafe => isId ? '✅ Aman selamanya' : '✅ Safe forever';
  String get pointsAnonymousLose => isId
      ? 'YukCoin akan hilang kalau kamu logout atau ganti HP'
      : 'YukCoin will be lost if you logout or switch phones';
  // Netral (tanpa janji jumlah): bonus daftar hanya untuk male — female
  // ditolak server. User anonim yang melihat label ini belum memilih
  // gender, jadi menjanjikan "+100" akan menyesatkan.
  String get pointsRegisterBonusLabel =>
      isId ? 'Daftar pakai email' : 'Register with email';
  // Parameterized (Dart tak dukung %d — pakai fungsi)
  String pointsDeduct(int n) => isId ? '-$n YukCoin' : '-$n YukCoin';
  String pointsGain(int n, String reason) =>
      isId ? '+$n YukCoin — $reason' : '+$n YukCoin — $reason';
  String pointsStreakToast(int day, int n) => isId
      ? '🔥 Streak $day hari — +$n YukCoin'
      : '🔥 $day-day streak — +$n YukCoin';
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

  // ── Sticker (ala Telegram) ──
  String get stickerTabTitle => isId ? 'Stiker' : 'Stickers';
  String get stickerAddFromGallery =>
      isId ? 'Buat dari galeri' : 'Create from gallery';
  String get stickerEmpty => isId
      ? 'Belum ada stiker. Buat dari galeri (foto → stiker persegi).'
      : 'No stickers yet. Create one from your gallery.';
  String get stickerSendFail => isId ? 'Gagal kirim stiker' : 'Failed to send sticker';
  String get stickerEditTitle => isId ? 'Edit stiker' : 'Edit sticker';
  String get stickerEditSend => isId ? 'Kirim stiker' : 'Send sticker';
  String get stickerEditAddText => isId ? 'Teks' : 'Text';
  String get stickerEditTextTitle => isId ? 'Tulis teks' : 'Write text';
  String get stickerEditTextHint => isId ? 'Ketik di sini…' : 'Type here…';
  String get stickerEditBgOn => isId ? 'Latar: ada' : 'Background: on';
  String get stickerEditBgOff => isId ? 'Latar: hapus' : 'Background: off';
  String get stickerPackMine => isId ? 'Koleksiku' : 'My pack';
  String get stickerPackArt => isId ? 'Emoji Art' : 'Emoji Art';
  String get stickerPickVideo => isId ? 'Video pendek' : 'Short video';
  String get stickerPickFile =>
      isId ? 'Berkas .tgs/.gif' : '.tgs/.gif file';
  String get stickerTooBig =>
      isId ? 'Video maksimal 8 MB' : 'Video max 8 MB';
  String get stickerArtCredit =>
      isId ? 'Emoji Art oleh Twemoji (Twitter, CC-BY 4.0)' : 'Emoji Art by Twemoji (Twitter, CC-BY 4.0)';
  String get stickerDeleteTitle =>
      isId ? 'Hapus stiker?' : 'Delete sticker?';
  String get stickerDeleteBody => isId
      ? 'Stiker ini akan dihapus dari koleksimu.'
      : 'This sticker will be removed from your pack.';
  String get stickerDeleted => isId ? 'Stiker dihapus' : 'Sticker deleted';
  String get stickerDeleteFail =>
      isId ? 'Gagal hapus stiker' : 'Failed to delete sticker';
  String get stickerDeleteHint =>
      isId ? 'Tahan untuk hapus' : 'Long-press to delete';
  String get storyPublishFail =>
      isId ? 'Gagal membagikan story' : 'Failed to share story';
  String get storyDeleted =>
      isId ? 'Story jadi privat (hanya kamu)' : 'Story set to private (only you)';
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
  // ── History Poin ──
  String get pointHistoryTitle => isId ? 'Riwayat YukCoin' : 'YukCoin History';
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
  String get pointHistoryAdminReset => isId ? 'Reset YukCoin' : 'YukCoin reset';
  String get pointHistoryPostBoost => isId ? 'Promosi postingan' : 'Post boost';
  String get pointHistoryLevelReward => isId ? 'Hadiah level' : 'Level reward';
  String get pointHistoryCallAudio => isId ? 'Call audio' : 'Audio call';
  String get pointHistoryCallVideo => isId ? 'Call video' : 'Video call';
  String get pointHistoryCallIncome => isId ? 'Pendapatan call' : 'Call income';
  String get pointHistoryGiftSent => isId ? 'Kirim hadiah' : 'Gift sent';
  String get pointHistoryGiftReceived => isId ? 'Terima hadiah' : 'Gift received';
  String get pointHistoryMatchSearch =>
      isId ? 'Cari match' : 'Match search';
  String get pointHistoryTopup => isId ? 'Isi YukCoin' : 'Top up';
  String get pointHistoryMissionReward =>
      isId ? 'Hadiah misi' : 'Mission reward';
  String get pointHistoryWithdraw =>
      isId ? 'Tarik saldo' : 'Withdrawal';
  String get pointHistoryPhotoUnlock => isId ? 'Buka foto' : 'Unlock photo';
  String get pointHistoryPhotoIncome =>
      isId ? 'Pendapatan foto' : 'Photo income';
  String get pointHistorySubscribe => isId ? 'Subscribe' : 'Subscribe';
  String get pointHistorySubscribeIncome =>
      isId ? 'Pendapatan subscribe' : 'Subscribe income';
  String get pointHistoryWelcome => isId ? 'Bonus selamat datang' : 'Welcome bonus';
  String get pointHistorySignup => isId ? 'Bonus daftar' : 'Sign-up bonus';
  String get pointHistoryRefund => isId ? 'Refund' : 'Refund';
  String get pointHistoryOther =>
      isId ? 'Transaksi YukCoin' : 'YukCoin transaction';
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
  String get yukcoinEarnTopup => isId ? 'Top-up (beli YukCoin)' : 'Top-up (buy YukCoin)';
  String get yukcoinEarnWelcome => isId ? 'Bonus pendaftaran' : 'Sign-up bonus';
  String get yukcoinEarnCallAudio =>
      isId ? 'Terima panggilan audio' : 'Take audio calls';
  String get yukcoinEarnCallVideo =>
      isId ? 'Terima panggilan video' : 'Take video calls';
  String get yukcoinEarnCallNote =>
      isId ? 'Penelepon membayar per menit' : 'The caller pays per minute';
  String get yukcoinEarnMatch => isId ? 'Ikut match video' : 'Join video match';
  String get yukcoinEarnMatchNote =>
      isId ? 'Kamu tidak ditagih' : 'You are never charged';
  String get yukcoinEarnGift =>
      isId ? 'Terima hadiah di chat berdua' : 'Receive gifts in one-to-one chats';
  String get yukcoinFeatureCallAudio =>
      isId ? 'Panggilan audio' : 'Audio call';
  String get yukcoinFeatureCallVideo =>
      isId ? 'Panggilan video' : 'Video call';
  String get yukcoinFeatureFilterGender =>
      isId ? 'Filter gender' : 'Gender filter';
  String get yukcoinFeatureNearby =>
      isId ? 'Cari orang sekitar' : 'Find people nearby';
  String get yukcoinPerMin => isId ? 'YukCoin/menit' : 'YukCoin/min';
  String get yukcoinFeatureMatch =>
      isId ? 'Cari pasangan (match)' : 'Find a match';
  String get yukcoinFeatureGift =>
      isId ? 'Kirim hadiah di chat' : 'Send a gift in chat';
  String get yukcoinPerMatch => isId ? 'YukCoin/match' : 'YukCoin/match';
  String get yukcoinPerGift => isId ? 'YukCoin/hadiah' : 'YukCoin/gift';
  String get yukcoinMatchNote => isId
      ? 'Dipotong sekali saat dapat pasangan — bukan saat menekan Match.'
      : 'Charged once when you get a match — not when you tap Match.';
  // Match video juga ditagih tarif per menit setelah masa gratis.
  String yukcoinMatchPerMinNote(int perMin, int freeMin) => isId
      ? 'Lanjutannya $perMin YukCoin/menit setelah $freeMin menit gratis.'
      : 'Then $perMin YukCoin/min after the first $freeMin free minutes.';
  String get yukcoinGiftNote => isId
      ? 'Hanya untuk chat berdua. Sebagian nilai hadiah jadi milik penerima.'
      : 'One-to-one chats only. Part of the gift value goes to the receiver.';
  String get yukcoinHowToSpend =>
      isId ? 'Cara pakai YukCoin' : 'How to spend YukCoin';
  String get yukcoinTopup => isId ? 'Isi YukCoin' : 'Top up YukCoin';
  String get yukcoinPickPackage =>
      isId ? 'Pilih paket YukCoin' : 'Pick a YukCoin package';
  // Overhaul coin (2026-10): tidak ada poin gratis — coin hanya dari topup.
  String get pointsOutOfCoinBody => isId
      ? 'YukCoin kamu habis. Isi YukCoin lewat top-up untuk lanjut menelepon, match video, atau kirim hadiah.'
      : 'You are out of YukCoin. Top up to keep calling, video matching, or sending gifts.';
  // ── Onboarding MALE: apa saja yang memakai YukCoin ──
  String get pointsOnboardMaleTitle =>
      isId ? 'YukCoin kamu dipakai untuk ini' : 'What your YukCoin pays for';
  String get pointsOnboardMaleSub => isId
      ? 'Isi dulu lewat top-up, lalu pakai untuk:'
      : 'Top up first, then spend it on:';
  String pointsOnboardMaleCall(int audio, int video) => isId
      ? '🪙 $audio/menit audio · $video/menit video'
      : '🪙 $audio/min audio · $video/min video';
  String pointsOnboardMaleMatch(int fee) => isId
      ? '🪙 $fee YC per match — dipotong saat dapat pasangan'
      : '🪙 $fee YC per match — charged when you get a match';
  String pointsOnboardMaleGift(int min, int max) => isId
      ? '🪙 $min–$max YC per hadiah, hanya di chat berdua'
      : '🪙 $min–$max YC per gift, one-to-one chats only';
  String get pointsOnboardMaleFree => isId
      ? 'Gratis: chat teks, filter gender, cari orang sekitar'
      : 'Free: text chat, gender filter, find people nearby';

  // ── Onboarding FEMALE: cara MENDAPAT YukCoin ──
  String get pointsOnboardFemaleTitle =>
      isId ? 'Dapat YukCoin dari lawan bicara' : 'Earn YukCoin from your callers';
  String get pointsOnboardFemaleSub => isId
      ? 'Kamu tidak perlu top-up. YukCoin masuk saat mereka memakai fitur berbayar ke kamu:'
      : 'No top-up needed. YukCoin comes in when others pay to reach you:';
  String get pointsOnboardFemaleCall => isId
      ? '📞 Terima panggilan audio & video'
      : '📞 Take audio & video calls';
  String get pointsOnboardFemaleGift => isId
      ? '🎁 Terima hadiah di chat berdua'
      : '🎁 Receive gifts in one-to-one chats';
  String get pointsOnboardFemaleMatch => isId
      ? '👥 Ikut match video — kamu tidak ditagih'
      : '👥 Join video match — you are never charged';
  String pointsOnboardFemaleWithdraw(int min) => isId
      ? '💰 Tarik ke DANA lewat menu Saldo (min. $min YukCoin)'
      : '💰 Cash out to DANA from the Saldo menu (min. $min coins)';

  String get pointsOnboardCoinTitle =>
      isId ? 'YukCoin untuk menelepon' : 'YukCoin for calling';
  // 2026-10-31: koin HANYA untuk call/video/match/gift. Filter, cari orang
  // sekitar, undo, edit, slot foto, dan mode hantu GRATIS.
  String get pointsOnboardCoinBody => isId
      ? 'Isi YukCoin lewat top-up. YukCoin dipakai untuk menelepon (audio/video), match video, dan kirim hadiah. Fitur lain gratis.'
      : 'Top up to get YukCoin. YukCoin is used for calls (audio/video), video match, and sending gifts. Everything else is free.';
  String get pointsOnboardCallFree => isId
      ? 'Menelepon (audio/video) pakai YukCoin'
      : 'Calling (audio/video) uses YukCoin';
  String get callReconnecting =>
      isId ? 'Menyambungkan ulang…' : 'Reconnecting…';
  String callCostPerMin(int coins) => isId
      ? '🪙 $coins YukCoin/menit'
      : '🪙 $coins YukCoin/min';
  String get callEndedNoCoin => isId
      ? 'YukCoin habis — panggilan diakhiri'
      : 'Out of YukCoin — call ended';
  // Edukasi: coin dipakai untuk nelp (ditampilkan saat saldo tak cukup).
  String get callNeedCoinTitle => isId ? '🪙 YukCoin untuk menelepon' : '🪙 YukCoin for calling';
  String callNeedCoinBody(int need) => isId
      ? 'Untuk menelepon kamu butuh minimal $need YukCoin (1 menit pertama). Isi YukCoin lewat top-up untuk mulai menelepon.'
      : 'You need at least $need YukCoin to call (first minute). Top up to start calling.';
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
  // Slot foto = kapasitas galeri profil (default 4 foto).
  String get extraPhotoSlotsLabel =>
      isId ? 'Slot foto' : 'Photo slots';
  String get extraPhotoBuy => isId
      ? 'Tambah 5 slot foto (galeri profil)'
      : 'Add 5 photo slots (profile gallery)';
  // 2026-10-31: slot foto GRATIS (keputusan "poin hanya call & gift").
  String get extraPhotoFreeBody => isId
      ? 'Tambah 5 slot foto gratis?'
      : 'Add 5 photo slots for free?';

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
      isId ? 'YukCoin didapat 7 hari terakhir' : 'YukCoin earned in last 7 days';
  String get lbAllTimeHint =>
      isId ? 'Total saldo YukCoin' : 'Total YukCoin balance';
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

  // ── Misi (Missions) ──
  String get missionsTitle => isId ? 'Misi' : 'Missions';
  String get missionsMainTitle => isId ? 'Misi Utama' : 'Main Missions';
  String get missionsDailyTitle => isId ? 'Misi Harian' : 'Daily Missions';
  String get missionsLockedHint =>
      isId ? 'Kumpulkan 1200 YukCoin untuk membuka' : 'Collect 1200 YukCoin to unlock';
  String get missionsUnlockTitle =>
      isId ? 'Misi Harian Terkunci' : 'Daily Missions Locked';
  String missionsUnlockProgress(int n) =>
      isId ? '$n / 1200 YukCoin' : '$n / 1200 YukCoin';
  String missionsCompletedCount(int n, int total) =>
      isId ? '$n/$total selesai' : '$n/$total completed';
  String missionClaim(int n) => isId ? 'Klaim Hadiah $n' : 'Claim Reward $n';
  String missionCompleted(String status) =>
      isId ? 'Selesai!' : 'Complete!';
  String missionLocked(String status) =>
      isId ? 'Terkunci' : 'Locked';

  // ── Halaman Bonus (ala Vava, male) ──
  String get bonusTitle => isId ? 'Bonus' : 'Bonus';
  String get bonusSignInRewards =>
      isId ? 'Hadiah Masuk Harian' : 'Sign in rewards';
  String bonusDay(int n) => isId ? 'Hari $n' : 'Day $n';
  String get bonusSignIn => isId ? 'Masuk Harian' : 'Sign in';
  String get bonusSignInDone => isId ? 'Sudah klaim hari ini' : 'Claimed today';
  String bonusStreakToast(int coins) =>
      isId ? '+$coins YukCoin — masuk harian!' : '+$coins YukCoin — signed in!';
  String get bonusStreakToastZero =>
      isId ? 'Sudah klaim hari ini, kembali besok' : 'Already claimed, come back tomorrow';
  String get bonusBeginnerTasks =>
      isId ? 'Tugas Pemula' : 'Beginner Tasks';
  String get bonusDailyBonus => isId ? 'Bonus Harian' : 'Daily Bonus';
  String get bonusDailyNote => isId
      ? 'Tugas direset setiap hari. Klaim hadiahmu segera setelah tugas selesai.'
      : 'Tasks reset daily. Claim your rewards promptly after completing the tasks.';
  String bonusTaskProgress(int cur, int target) =>
      isId ? '($cur/$target)' : '($cur/$target)';
  String bonusCounterProgress(int cur, int target) =>
      isId ? '$cur/$target' : '$cur/$target';
  String bonusRewardCoins(int n) => isId ? '+$n' : '+$n';
  // 2026-11-01: reward misi male masuk bucket `bonus` — tidak bisa
  // dicairkan atau bayar fitur. Label eksplisit agar tidak salah kira.
  String bonusRewardCoinsNonWithdrawable(int n) => isId
      ? '+$n koin bonus (tidak bisa dicairkan)'
      : '+$n bonus coins (cannot be withdrawn)';
  String get bonusClaim => isId ? 'Klaim' : 'Claim';
  String get bonusClaimed => isId ? 'Diklaim' : 'Claimed';
  String get bonusGo => isId ? 'Mulai' : 'Go';
  String get bonusLocked => isId ? 'Terkunci' : 'Locked';

  // ── Saldo (layar penghasilan) ──
  String get saldoTitle => isId ? 'Saldo' : 'Balance';
  String get saldoMy => isId ? 'Saldo Saya' : 'My Balance';
  String get saldoAvailable => isId ? 'YukCoin tersedia' : 'Available YukCoin';
  String get saldoEarnings => isId ? 'Penghasilan' : 'Earnings';
  String get saldoTotal => isId ? 'Penghasilan Total' : 'Total Earnings';
  String get saldoTotalHint => isId
      ? 'Total yang pernah kamu terima (bukan saldo saat ini)'
      : 'Total you have ever earned (not current balance)';
  String get saldoWeekly => isId ? 'Minggu Ini' : 'This Week';
  String get saldoToday => isId ? 'Hari Ini' : 'Today';
  String get saldoBreakdown => isId ? 'Rincian Penghasilan' : 'Earnings Breakdown';
  String get saldoPrivateCall => isId ? 'Panggilan Privasi' : 'Private Calls';
  String get saldoMatchCall => isId ? 'Panggilan Match' : 'Match Calls';
  String get saldoMessage => isId ? 'Pesan' : 'Messages';
  String get saldoGift => isId ? 'Hadiah' : 'Gifts';
  String get saldoMission => isId ? 'Tugas' : 'Tasks';
  String get saldoBonus => isId ? 'Bonus' : 'Bonus';
  String get saldoOther => isId ? 'Lainnya' : 'Others';
  // Hint di bawah tombol withdraw non-aktif — kapan tombol hidup.
  String saldoWdLocked(int min, int need) => isId
      ? 'Aktif saat saldo withdrawable mencapai $min 🪙 (kurang $need lagi)'
      : 'Unlocks at $min 🪙 ($need to go)';
  String get saldoStats => isId ? 'Statistik Aktivitas' : 'Activity Stats';
  String get saldoVideoCallCount =>
      isId ? 'Jumlah Panggilan Video' : 'Video Calls';
  String get saldoVideoCallDuration =>
      isId ? 'Durasi Panggilan Video' : 'Video Call Duration';
  String get saldoAvgMatch =>
      isId ? 'Rata-rata Panggilan Match' : 'Avg Match Call';
  String get saldoAnswerRate =>
      isId ? 'Tingkat Menjawab Panggilan Pribadi' : 'Private Call Answer Rate';
  String get saldoMessageReply => isId ? 'Balasan Pesan' : 'Message Replies';
  String get saldoOnlineDuration => isId ? 'Durasi Daring' : 'Online Duration';
  String get saldoLoadFail =>
      isId ? 'Gagal memuat data saldo' : 'Failed to load balance data';
  String get saldoUnitTimes => isId ? 'kali' : 'times';
  String get saldoUnitMin => isId ? 'menit' : 'min';
  String get saldoUnitPct => '%';
  String saldoCoins(int n) => '$n YukCoin';

  // ── Withdraw (tarik saldo ke DANA) ──
  String get wdTitle => isId ? 'Withdraw' : 'Withdraw';
  String get wdWithdrawable => isId ? 'Saldo Bisa Ditarik' : 'Withdrawable Balance';
  // 2026-11-02: hanya koin PENGHASILAN (bucket earned) yang bisa ditarik.
  // Koin bonus (gratis) menaikkan saldo total tapi tidak bisa dicairkan.
  String get wdWithdrawableHint => isId
      ? 'Hanya YukCoin penghasilan yang bisa ditarik ke DANA'
      : 'Only earned YukCoin can be withdrawn to DANA';
  String get wdTotalBalance => isId ? 'Total Saldo' : 'Total Balance';
  String get wdNotWithdrawable =>
      isId ? 'Tidak bisa ditarik' : 'Not withdrawable';
  String get wdAmountLabel => isId ? 'Jumlah YukCoin' : 'YukCoin Amount';
  // Angka dari server (get_withdraw_config) supaya tidak basi kalau admin
  // mengubah withdraw_min_coins.
  String wdAmountHint(int min) => isId
      ? 'Min. $min YukCoin'
      : 'Minimum $min YukCoin';
  String get wdMaxAmount => isId ? 'Semua' : 'All';
  String get wdCalcTitle => isId ? 'Rincian' : 'Breakdown';
  String get wdCalcGross => isId ? 'Nilai YukCoin' : 'YukCoin value';
  String get wdCalcFee => isId ? 'Biaya withdraw' : 'Withdrawal fee';
  String get wdCalcNet => isId ? 'Diterima di DANA' : 'Received in DANA';
  String get wdRate => isId ? 'Rate' : 'Rate';
  String get wdDanaTitle => isId ? 'Akun DANA' : 'DANA Account';
  String get wdDanaNumber => isId ? 'Nomor DANA' : 'DANA number';
  String get wdDanaNumberHint => isId ? '08xx / 62xx' : '08xx / 62xx';
  String get wdDanaName => isId ? 'Nama Pemilik' : 'Account holder';
  String get wdDanaNameHint => isId ? 'Nama sesuai akun DANA' : 'Name on the DANA account';
  String get wdDanaSave => isId ? 'Simpan Akun' : 'Save Account';
  String get wdDanaSaved => isId ? 'Akun DANA tersimpan' : 'DANA account saved';
  String get wdSubmit => isId ? 'Ajukan Withdraw' : 'Request Withdraw';
  String get wdSubmitting => isId ? 'Mengirim…' : 'Submitting…';
  String get wdHistory => isId ? 'Riwayat Withdraw' : 'Withdraw History';
  String get wdHistoryEmpty =>
      isId ? 'Belum ada withdraw' : 'No withdrawals yet';
  String get wdStatusPending => isId ? 'Menunggu' : 'Pending';
  String get wdStatusPaid => isId ? 'Dibayar' : 'Paid';
  String get wdStatusRejected => isId ? 'Ditolak' : 'Rejected';
  String get wdFemaleOnly =>
      isId ? 'Withdraw hanya untuk akun perempuan' : 'Withdrawal is for female accounts only';
  // Angka diambil dari server (get_withdraw_config) supaya tidak basi
  // kalau admin mengubah withdraw_min_coins.
  String wdBelowMin(int min) => isId
      ? 'Minimal $min YukCoin untuk withdraw'
      : 'Minimum $min coins to withdraw';
  String get wdPointsDisabled => isId
      ? 'Sistem koin sedang dimatikan. Coba lagi nanti.'
      : 'The coin system is currently disabled. Try again later.';
  String get wdInsufficient => isId
      ? 'Saldo bisa ditarik tidak cukup'
      : 'Not enough withdrawable balance';
  String wdDailyLimit(int max) => isId
      ? 'Maksimal $max withdraw per hari'
      : 'Maximum $max withdrawals per day';
  String wdTooSoon(int hours) => isId
      ? 'Tunggu $hours jam antara withdraw'
      : 'Wait $hours hour(s) between withdrawals';
  String wdAccountTooNew(int hours) => isId
      ? 'Akun harus berumur minimal $hours jam'
      : 'Account must be at least $hours hours old';
  String get wdInvalidNumber =>
      isId ? 'Nomor DANA tidak valid' : 'Invalid DANA number';
  String get wdInvalidName =>
      isId ? 'Nama pemilik minimal 3 huruf' : 'Holder name must be 3+ characters';
  String get wdNoAccount =>
      isId ? 'Isi akun DANA dulu' : 'Fill in your DANA account first';
  String get wdSuccess => isId
      ? 'Withdraw diajukan! Menunggu persetujuan admin.'
      : 'Withdrawal requested! Awaiting admin approval.';
  String get wdReviewNote => isId ? 'Catatan admin' : 'Admin note';
  String get wdConfirmTitle => isId ? 'Ajukan Withdraw?' : 'Request Withdrawal?';
  String wdConfirmBody(int coins, int net) => isId
      ? 'Tarik $coins YukCoin dan terima Rp $net ke DANA?'
      : 'Withdraw $coins coins and receive Rp $net to DANA?';
  String get wdConfirmYes => isId ? 'Ya, Ajukan' : 'Yes, Request';
  String get wdLoadFail =>
      isId ? 'Gagal memuat data withdraw' : 'Failed to load withdrawal data';

  // ── Lock gender (dipilih sekali, tidak bisa diubah) ──
  String get genderLockTitle =>
      isId ? 'Pastikan Gender Sudah Benar' : 'Make Sure Your Gender Is Correct';
  String get genderLockWarning => isId
      ? 'Gender hanya bisa dipilih SEKALI dan TIDAK DAPAT diubah setelah disimpan.'
      : 'Gender can only be chosen ONCE and CANNOT be changed after saving.';
  String genderLockCurrent(String g) =>
      isId ? 'Pilihan kamu: $g' : 'Your choice: $g';
  String get genderLockConfirmYes => isId ? 'Ya, Simpan' : 'Yes, Save';
  String get genderLockConfirmRegister => isId ? 'Ya, Daftar' : 'Yes, Register';
  String get genderLockSaved => isId
      ? 'Gender tersimpan dan tidak dapat diubah lagi'
      : 'Gender saved and can no longer be changed';
  String get genderLockedNotice =>
      isId ? 'Gender tidak dapat diubah' : 'Gender cannot be changed';
  String get genderCancel => isId ? 'Batal' : 'Cancel';

  // ── My Level (male only — level dari kumulatif topup) ──
  String get myLevelTitle => isId ? 'My Level' : 'My Level';
  String get myLevelSubtitle =>
      isId ? 'Level & privilege kamu' : 'Your level & privileges';
  String get myLevelPrivileges => isId ? 'Privileges' : 'Privileges';
  String get myLevelRule => isId ? 'Aturan Level' : 'Level Rule';
  String get myLevelRuleDesc => isId
      ? 'Level naik sesuai total kumulatif top-up YukCoin'
      : 'Level up according to cumulative YukCoin top-up amount';
  String myLevelTopupMore(String coins, int level) => isId
      ? 'Top up $coins 🪙 lagi untuk naik ke Lv.$level'
      : 'Top up $coins 🪙 more to reach Lv.$level';
  String get myLevelMaxLevel =>
      isId ? 'Kamu di level tertinggi 🔥' : 'You reached the top level 🔥';
  String myLevelReward(int coins) =>
      isId ? 'Naik level dapat +$coins 🪙' : 'Level up grants +$coins 🪙';
  String get myLevelPrivBadge => isId ? 'Badge Level' : 'Level Badge';
  String get myLevelPrivBadgeDesc => isId
      ? 'Badge level tampil di profil kamu'
      : 'Your level badge shows on your profile';
  String get myLevelPrivReward => isId ? 'Bonus Koin' : 'Coin Bonus';
  String get myLevelPrivNone => isId
      ? 'Belum ada privilege di level ini — top up untuk mulai'
      : 'No privileges at this level yet — top up to get started';  String myLevelPrivRewardDesc(int coins) => isId
      ? 'Dapat +$coins 🪙 saat naik ke level ini'
      : 'Get +$coins 🪙 when reaching this level';
  String get myLevelColLevel => isId ? 'Level' : 'Level';
  String get myLevelColTopup => isId ? 'Top Up 🪙' : 'Top Up 🪙';
  String get myLevelColReward => isId ? 'Bonus' : 'Bonus';
  String get myLevelCtaTopup => isId ? 'Isi YukCoin' : 'Top Up YukCoin';
  String get myLevelLoadFail =>
      isId ? 'Gagal memuat level' : 'Failed to load level';
  String levelShort(int n) => 'Lv.$n';

  // ── Admin Chat Monitor ──
}
