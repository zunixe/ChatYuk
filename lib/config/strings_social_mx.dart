part of 'strings.dart';

mixin SSocialMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
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
  /// Baris statistik ringkas di kartu (gaya IG), mis. "1.2K Followers · 34 Friends".
  /// Angka sudah diringkas (compactCount) sebelum dipanggil.
  String socialCountsShort(String followers, String friends) =>
      isId ? '$followers Pengikut · $friends Teman' : '$followers Followers · $friends Friends';
  String get btnFollow => isId ? 'Ikuti' : 'Follow';
  String get btnUnfollow => isId ? 'Berhenti Ikuti' : 'Unfollow';
  // Snackbar konfirmasi follow (jelas + nama, bukan cuma kata tombol).
  String snackNowFollowing(String name) =>
      isId ? 'Mengikuti $name' : 'Following $name';
  String snackUnfollowed(String name) =>
      isId ? 'Berhenti mengikuti $name' : 'Unfollowed $name';
  String snackBlocked(String name) =>
      isId ? '$name diblokir' : '$name blocked';
  String snackNowFriends(String name) =>
      isId ? 'Sekarang berteman dengan $name' : 'Now friends with $name';
  String get btnChatNow => isId ? 'Chat' : 'Chat';
  // Tombol "Kirim Pesan" (profil orang lain) + tooltip tombol teman.
  String get btnSendMessage => isId ? 'Kirim Pesan' : 'Send Message';
  String get friendTooltipFriend => isId ? 'Berteman' : 'Friends';
  String get friendTooltipPending =>
      isId ? 'Menunggu konfirmasi' : 'Pending confirmation';
  String get friendTooltipAdd => isId ? 'Tambah teman' : 'Add friend';
  String get msgRegisterToFollow =>
      isId ? 'Daftar dulu untuk mengikuti' : 'Register to follow';
  String get msgTargetNotRegistered => isId
      ? 'Akun ini belum terdaftar, tidak bisa diikuti'
      : 'This account is not registered and cannot be followed';
  String get btnAddFriend => isId ? 'Tambah Teman' : 'Add Friend';
  String get btnFriendRequested => isId ? 'Terkirim' : 'Sent';
  String get btnFriendPending =>
      isId ? 'Terima Permintaan' : 'Accept Request';
  String get btnFriends => isId ? 'Teman' : 'Friends';
  String get btnSubscribe => isId ? 'Subscribe' : 'Subscribe';
  String get btnSubscribed => isId ? 'Berlangganan' : 'Subscribed';
  String get btnUnsubscribe => isId ? 'Berhenti Berlangganan' : 'Unsubscribe';
  String get friendRequestTitle =>
      isId ? 'Permintaan Teman' : 'Friend Requests';
  String get friendRequestEmpty =>
      isId ? 'Belum ada permintaan teman' : 'No friend requests yet';
  String get friendRequestInbox => isId ? 'Masuk' : 'Incoming';
  String get friendRequestSent =>
      isId ? 'Permintaan teman terkirim' : 'Friend request sent';
  String get friendRequestAccepted =>
      isId ? 'Permintaan teman diterima' : 'Friend request accepted';
  String get friendRequestCancelled =>
      isId ? 'Permintaan teman dibatalkan' : 'Friend request cancelled';
  String get friendRequestStatusAccepted =>
      isId ? 'Diterima' : 'Accepted';
  String get friendRequestStatusRejected =>
      isId ? 'Ditolak' : 'Rejected';

  // ── Sheet "Status kamu" (status + visibilitas diri sendiri) ──
  String get myStatusTitle => isId ? 'Status kamu' : 'Your status';
  String get myStatusStatusLabel => isId ? 'Status' : 'Status';
  String get myStatusVisibleTo =>
      isId ? 'Terlihat oleh' : 'Visible to';
  String get myStatusVisibleEveryone =>
      isId ? '🌍 Semua orang' : '🌍 Everyone';
  String get myStatusVisibleFriends => isId ? '👥 Hanya teman' : '👥 Friends only';
  String myStatusVisibleOnly(int n) =>
      isId ? '✋ Hanya $n orang' : '✋ Only $n people';
  String get myStatusVisibleNobody => isId ? '🚫 Tidak ada' : '🚫 Nobody';
  String myStatusExceptN(int n) =>
      isId ? 'kecuali $n orang' : 'except $n people';
  String myStatusExceptNAndOffline(int n) => isId
      ? 'kecuali $n orang · mereka melihatmu Offline'
      : 'except $n people · they see you Offline';
  String get myStatusTheySeeOffline =>
      isId ? 'kamu tampak Offline' : 'you appear Offline';
  String get myStatusGhostActive =>
      isId ? 'Mode hantu aktif' : 'Ghost mode active';
  String get myStatusPhotoLabel => isId ? 'Foto profil' : 'Profile photo';
  String get myStatusManageInPrivacy =>
      isId ? 'Kelola di Privasi' : 'Manage in Privacy';
  String get subscriptionsTitle => isId ? 'Langganan' : 'Subscriptions';
  String get subscriptionsEmpty =>
      isId ? 'Belum ada langganan' : 'No subscriptions yet';
  String subscribePrice(int c) => isId ? '$c YukCoin / bulan' : '$c YukCoin / month';
  String get subscribePriceSuffix => isId ? '🪙 / bulan' : '🪙 / month';
  String get subscribeConfirmTitle => isId ? 'Subscribe' : 'Subscribe';
  String subscribeConfirmBody(String name, int c, int periods) => isId
      ? 'Berlangganan ke $name selama $periods bulan seharga ${c * periods} YukCoin?'
      : 'Subscribe to $name for $periods months at ${c * periods} YukCoin?';
  String get subscribeSuccess => isId ? 'Berhasil berlangganan' : 'Subscribed';
  String get unsubscribeSuccess =>
      isId ? 'Berhenti berlangganan' : 'Unsubscribed';
  String get subscribeNeedPaid => isId
      ? 'YukCoin tidak cukup. Top up dulu.'
      : 'Not enough YukCoin. Top up first.';
  String get subscribeNeedRegister => isId
      ? 'Hanya akun terdaftar yang bisa subscribe'
      : 'Only registered accounts can subscribe';
  String get setSubPriceTitle =>
      isId ? 'Harga Subscribe' : 'Subscription Price';
  String get setSubPriceHint =>
      isId ? '0 = nonaktif (gratis diikuti)' : '0 = disabled (free to follow)';
  String get socialListEmpty => isId ? 'Belum ada data' : 'No data yet';
  String get paidBalanceLabel => isId ? 'YukCoin' : 'YukCoin';
  String get bonusBalanceLabel => isId ? 'YukCoin bonus' : 'Bonus YukCoin';
  String paidOrBonus(int paid, int bonus) => isId
      ? 'YukCoin $paid · atau bonus $bonus'
      : 'Pro $paid · or bonus $bonus';
  String get menuFollow => isId ? 'Ikuti' : 'Follow';
  String get menuUnfollow => isId ? 'Berhenti Ikuti' : 'Unfollow';
  String get menuAddFriend => isId ? 'Tambah Teman' : 'Add Friend';
  // ── Penjelasan beda Follow vs Teman ──
  String get hintFollowVsFriend => isId
      ? 'Ikuti = lihat postingan mereka. Tambah Teman = lihat status, foto & story (butuh persetujuan).'
      : 'Follow = see their posts. Add Friend = see status, photo & story (needs approval).';
  String get hintFriendMutual => isId
      ? 'Berteman otomatis saling mengikuti.'
      : 'Becoming friends means you follow each other automatically.';
  String get sheetFollowVsFriendTitle =>
      isId ? 'Ikuti atau Berteman?' : 'Follow or Add Friend?';
  String get sheetFollowLabel => isId ? 'Ikuti (Follow)' : 'Follow';
  String get sheetFollowDesc => isId
      ? 'Lihat postingan mereka di Feed "Mengikuti". Tanpa perlu persetujuan, cukup satu tap.'
      : 'See their posts in your "Following" feed. No approval needed, just one tap.';
  String get sheetFriendLabel => isId ? 'Tambah Teman (Friend)' : 'Add Friend';
  String get sheetFriendDesc => isId
      ? 'Lihat status online, foto profil, tentang, dan story mereka. Perlu disetujui. Berteman otomatis saling mengikuti.'
      : 'See their online status, profile photo, about, and story. Needs their approval. Becoming friends means you follow each other automatically.';
  String get friendRequestSentMutual => isId
      ? 'Permintaan teman terkirim — berteman otomatis saling mengikuti.'
      : 'Friend request sent — becoming friends means you follow each other.';
  // ── Putus teman / batalkan permintaan ──
  String get btnUnfriend => isId ? 'Putus Teman' : 'Unfriend';
  String get btnCancelRequest => isId ? 'Batalkan' : 'Cancel';
  String get unfriendConfirmTitle =>
      isId ? 'Putus pertemanan?' : 'Unfriend?';
  String unfriendConfirmBody(String name) => isId
      ? 'Kamu dan $name tidak akan saling mengikuti lagi, dan tidak akan bisa melihat status, foto, atau story masing-masing.'
      : 'You and $name will no longer follow each other, and will not be able to see each other\'s status, photos, or stories.';
  String get unfriendDone => isId ? 'Pertemanan diputus' : 'Unfriended';
  String get cancelRequestConfirmTitle =>
      isId ? 'Batalkan permintaan teman?' : 'Cancel friend request?';
  String cancelRequestConfirmBody(String name) => isId
      ? 'Permintaan teman ke $name akan ditarik.'
      : 'Your friend request to $name will be withdrawn.';
  String get cancelRequestDone =>
      isId ? 'Permintaan teman dibatalkan' : 'Friend request cancelled';
  String get needRegisteredForPaid => isId
      ? 'Fitur ini butuh akun terdaftar & YukCoin'
      : 'This feature needs a registered account & YukCoin';
  // ── Subscribe: penjelasan buat fans & creator ──
  String get subscribeWhatIs =>
      isId ? 'Apa itu Subscribe?' : 'What is Subscribe?';
  String get subscribeExplain => isId
      ? 'Dukung kreator favoritmu setiap bulan. YukCoin yang kamu bayar menjadi penghasilan kreator, dan platform mengambil potongan kecil untuk biaya operasional.'
      : 'Support your favorite creator monthly. Your YukCoin become the creator\'s income, and the platform takes a small cut for operating costs.';
  String get subscribeFansHint => isId
      ? 'Berlangganan untuk mendukung kreator ini. Dibayar pakai YukCoin.'
      : 'Subscribe to support this creator. Paid with YukCoin.';
  String get subscribeCreatorHint => isId
      ? 'Jadilah kreator: pasang harga langganan bulanan. Fans yang subscribe memberimu penghasilan.'
      : 'Become a creator: set a monthly subscription price. Fans who subscribe become your income.';
  String get subscriptionsEmptyHint => isId
      ? 'Kamu belum berlangganan ke kreator mana pun.\nTemukan kreator di daftar online lalu tap Subscribe.'
      : 'You haven\'t subscribed to any creator yet.\nFind creators in the online list and tap Subscribe.';
  String get setSubPriceExplain => isId
      ? 'Fans membayar harga ini setiap bulan untuk berlangganan. Kamu terima 70%, platform 30%.'
      : 'Fans pay this price monthly to subscribe. You receive 70%, the platform takes 30%.';

  // ── Menu cepat samping (halaman Online) ──
  String get quickMenuTimeline => isId ? 'Buka Timeline' : 'Open Timeline';
  String get quickMenuGlobalRoom => isId ? 'Buka Global Room' : 'Open Global Room';
  String get quickMenuCreateGroup => isId ? 'Buat Grup' : 'Create Group';

  // ── Timeline ──
  String get navTimeline => isId ? 'Timeline' : 'Timeline';
  String get tabAll => isId ? 'Semua' : 'All';
  String get tabFollowing => isId ? 'Mengikuti' : 'Following';
  String get tabMine => isId ? 'Postinganku' : 'My Posts';
  String get tabMessages => isId ? 'Pesan' : 'Messages';
  String get menuNewGroup => isId ? 'Grup Baru' : 'New group';
  String get menuReadAll => isId ? 'Tandai semua dibaca' : 'Mark all as read';
  String get tabGroups => isId ? 'Grup' : 'Groups';
  String get tabRooms => isId ? 'Global Room' : 'Global Room';
  String get titleTimeline => isId ? 'Timeline' : 'Timeline';
  String get titlePostDetail => isId ? 'Postingan' : 'Post';
  String get postDetailGone => isId
      ? 'Postingan sudah dihapus atau tidak bisa dilihat.'
      : 'This post was deleted or is unavailable.';
  String get hintWritePost =>
      isId ? 'Tulis sesuatu...' : "Share what's on your mind...";
  String get btnPost => isId ? 'Posting' : 'Post';
  // ── Composer (posting) — judul, tip, aksi ──
  String get composerTitle => isId ? 'Buat Postingan' : 'Create Post';
  String get composerIntroHeadline =>
      isId ? 'Apa yang ingin kamu bagikan?' : 'What do you want to share?';
  String get composerIntroSub => isId
      ? 'Bagikan momen, ide, atau cerita ke semua orang.'
      : 'Share moments, ideas, or stories with everyone.';
  String get composerActionGallery => isId ? 'Galeri' : 'Gallery';
  String get composerActionCamera => isId ? 'Kamera' : 'Camera';
  String get composerActionEmoji => isId ? 'Emoji' : 'Emoji';
  String get composerMediaHint =>
      isId ? 'Tambahkan foto biar makin menarik' : 'Add photos to stand out';
  String get composerTipsTitle =>
      isId ? 'Tips biar dilihat banyak orang' : 'Tips to get more views';
  String get composerTip1 =>
      isId ? 'Pakai foto yang jelas & menarik' : 'Use clear, engaging photos';
  String get composerTip2 => isId
      ? 'Tambahkan #hashtag biar mudah ditemukan'
      : 'Add #hashtags so people can find you';
  String get composerTip3 => isId
      ? 'Ceritakan singkat, jujur, dan menarik'
      : 'Keep it short, honest, and interesting';
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
  String get promptCompleteEmailNearbyTitle => isId
      ? 'Lengkapi email untuk mencari orang sekitar'
      : 'Complete email to find people nearby';
  String get promptCompleteEmailNearbyMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa mencari orang di sekitarmu.'
      : 'You have not completed your email. Complete your email on the Profile page to search for people nearby.';
  String get promptCompleteEmailChatTitle => isId
      ? 'Lengkapi email untuk mengirim pesan'
      : 'Complete email to send messages';
  String get promptCompleteEmailChatMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa mengirim pesan.'
      : 'You have not completed your email. Complete your email on the Profile page to send messages.';
  String get promptCompleteEmailGroupTitle => isId
      ? 'Lengkapi email untuk membuat grup'
      : 'Complete email to create groups';
  String get promptCompleteEmailGroupMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa membuat grup.'
      : 'You have not completed your email. Complete your email on the Profile page to create groups.';
  String get promptCompleteEmailCallTitle => isId
      ? 'Lengkapi email untuk menelepon'
      : 'Complete email to make calls';
  String get promptCompleteEmailCallMsg => isId
      ? 'Kamu belum melengkapi email. Lengkapi email di halaman Profil agar bisa menelepon.'
      : 'You have not completed your email. Complete your email on the Profile page to make calls.';
  String get btnGoProfile => isId ? 'Ke Profil' : 'Go to Profile';
  String get photoCountLabel => isId ? 'foto' : 'photos';
  String get btnBoost => isId ? 'Boost' : 'Boost';
  String get btnComment => isId ? 'Komentar' : 'Comments';
  String get commentEmpty =>
      isId ? 'Belum ada komentar' : 'No comments yet';
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
  String get postAddTooltip => isId ? 'Buat Postingan' : 'Create Post';
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
  String get boostPaidLabel => isId ? 'Boost (YukCoin)' : 'Boost (YukCoin)';
  String get boostBonusLabel =>
      isId ? 'Boost (bonus YukCoin)' : 'Boost (bonus YukCoin)';
  String get boostConfirm => isId
      ? 'Boost postingan ini supaya naik ke atas feed?'
      : 'Boost this post to the top of the feed?';
  String get msgBoosted => isId ? 'Postingan di-boost' : 'Post boosted';
  String get msgPosted => isId ? 'Berhasil diposting' : 'Posted';
  // ── Composer redesign (2026-10-17) ──
  String get composerTitleNew => isId ? 'Postingan baru' : 'New post';
  String get composerHintShare => isId
      ? 'Apa yang ingin kamu bagikan?'
      : 'What do you want to share?';
  String get titleWhoCanReply =>
      isId ? 'Siapa yang bisa membalas' : 'Who can reply';
  String get visPublicDescLong => isId
      ? 'Semua orang bisa membalas dan melihat'
      : 'Anyone can reply and see';
  String get visFollowersDescLong =>
      isId ? 'Hanya orang yang mengikutimu' : 'Only people who follow you';
  String get visSubscribersDescLong => isId
      ? 'Hanya subscriber yang bisa melihat'
      : 'Only subscribers can see';
  String get composerDiscardTitle =>
      isId ? 'Buang postingan?' : 'Discard post?';
  String get composerDiscardMsg => isId
      ? 'Teks dan foto yang belum dikirim akan hilang.'
      : 'Your text and photos will be lost.';
  String get btnDiscard => isId ? 'Buang' : 'Discard';
  String get tooltipAddPhoto =>
      isId ? 'Tambah foto atau video' : 'Add photo or video';
  String get tooltipAddEmoji => isId ? 'Tambah emoji' : 'Add emoji';
  String get tooltipHashtag => isId ? 'Hashtag' : 'Hashtag';
  String get tooltipRemovePhoto => isId ? 'Hapus foto' : 'Remove photo';
  String get msgPostSent => isId ? 'Postingan dikirim' : 'Post sent';
  String get errPreparePhoto => isId
      ? 'Sebagian foto gagal diproses'
      : 'Some photos failed to process';
  String get msgCommented => isId ? 'Komentar terkirim' : 'Comment posted';
  String get commentDeleteTitle =>
      isId ? 'Hapus komentar?' : 'Delete comment?';
  String get commentDeleteBody => isId
      ? 'Komentar yang dihapus tidak bisa dikembalikan.'
      : 'Deleted comments cannot be restored.';
  String get commentDeleted => isId ? 'Komentar dihapus' : 'Comment deleted';
  String get msgLiked => isId ? 'Disukai' : 'Liked';
  String get msgUnliked => isId ? 'Batal suka' : 'Unliked';
  String get msgShared => isId ? 'Dibagikan' : 'Shared';
  String get shareSearchUsers => isId ? 'Cari user...' : 'Search users...';
  String get shareViaApps =>
      isId ? 'Bagikan via aplikasi' : 'Share via apps';
  String get shareCopyLink => isId ? 'Salin Tautan' : 'Copy Link';
  String get shareCopied => isId ? 'Tautan disalin' : 'Link copied';
  String get shareMoreApps => isId ? 'Lainnya' : 'More';
  String shareSentTo(String name) =>
      isId ? 'Dibagikan ke $name' : 'Shared to $name';
  String postShareMsg(String author, String text) {
    const link =
        'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';
    if (text.isEmpty) {
      return isId
          ? 'Lihat postingan $author di ChatYuk!\n$link'
          : 'Check out $author\'s post on ChatYuk!\n$link';
    }
    return isId
        ? 'Lihat postingan $author di ChatYuk:\n$text\n$link'
        : 'Check out $author\'s post on ChatYuk:\n$text\n$link';
  }

  String commentShareMsg(String author, String text) {
    const link =
        'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';
    if (text.isEmpty) {
      return isId
          ? 'Lihat komentar $author di ChatYuk!\n$link'
          : 'Check out $author\'s comment on ChatYuk!\n$link';
    }
    return isId
        ? 'Lihat komentar $author di ChatYuk:\n$text\n$link'
        : 'Check out $author\'s comment on ChatYuk:\n$text\n$link';
  }
  String get badgeBoosted => isId ? 'Boost' : 'Boost';
  String get badgeFriend => isId ? 'Teman' : 'Friend';
  String get badgeSubscriber => isId ? 'Subscriber' : 'Subscriber';
  String get noResults =>
      isId ? 'Tidak ada hasil ditemukan' : 'No results found';

  // ── Long-press pesan ala WA (reaksi + toolbar seleksi) ──
  String get menuForward => isId ? 'Teruskan' : 'Forward';
  String get menuStar => isId ? 'Bintang' : 'Star';
  String get menuUnstar => isId ? 'Hapus bintang' : 'Unstar';
  String get menuCopy => isId ? 'Salin' : 'Copy';
  String get msgMessageCopied => isId ? 'Pesan disalin' : 'Message copied';
  String get msgStarred => isId ? 'Pesan dibintangi' : 'Message starred';
  String get msgUnstarred => isId ? 'Bintang dihapus' : 'Star removed';
  String get msgForwarded => isId ? 'Pesan diteruskan' : 'Message forwarded';
  String get forwardTitle => isId ? 'Teruskan ke' : 'Forward to';
  String get forwardSearchHint => isId ? 'Cari chat...' : 'Search chats...';
  String get msgForwardedLabel => isId ? 'Diteruskan' : 'Forwarded';
  String get msgReactionFailed =>
      isId ? 'Gagal memberi reaksi' : 'Failed to react';
  String get msgReactionRemoveFailed =>
      isId ? 'Gagal menghapus reaksi' : 'Failed to remove reaction';
  String get msgStarFailed =>
      isId ? 'Gagal mengubah bintang' : 'Failed to update star';
  String reactionsTitle(int n) =>
      isId ? '$n reaksi' : (n == 1 ? '1 reaction' : '$n reactions');
  String get msgTapToRemove => isId ? 'Ketuk untuk menghapus' : 'Tap to remove';
}
