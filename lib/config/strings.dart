// Semua string UI aplikasi dalam Bahasa Indonesia dan English.
// Untuk tambah bahasa baru: tambah getter baru di sini.
class S {
  final bool isId;
  // ignore: prefer_const_constructors_in_immutables
  S({required this.isId});

  // ── Entry Screen ──
  String get appTagline =>
      isId ? 'Chat Bebas, Dimana Saja' : 'Chat Freely, Anywhere';
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

  // ── KYC (verifikasi identitas) ──
  String get kycTitle =>
      isId ? 'Verifikasi Identitas' : 'Identity Verification';
  String get kycFullName => isId
      ? 'Nama Lengkap (sesuai KTP/Paspor)'
      : 'Full Name (as on ID/Passport)';
  String get kycIdType => isId ? 'Jenis Identitas' : 'ID Type';
  String get kycIdTypeKtp => isId ? 'KTP' : 'KTP';
  String get kycIdTypePassport => isId ? 'Paspor' : 'Passport';
  String get kycIdNumber => isId ? 'Nomor Identitas' : 'ID Number';
  String get kycBirthDate => isId ? 'Tanggal Lahir' : 'Birth Date';
  String get kycOptional => isId ? 'opsional' : 'optional';
  String get kycIdPhoto => isId ? 'Foto KTP/Identitas' : 'ID Photo';
  String get kycSelfie => isId ? 'Foto Selfie' : 'Selfie';
  String get kycHint => isId
      ? 'Selfie harus jelas memperlihatkan wajah & kartu identitas di tangan.'
      : 'Selfie must clearly show your face and hold your ID card.';
  String get kycSubmit => isId ? 'Kirim Permohonan' : 'Submit Request';
  String get kycSubmitted => isId ? 'Permohonan terkirim' : 'Request submitted';
  String get kycAlreadySubmitted => isId
      ? 'Permohonan sudah ada, tunggu review'
      : 'Request exists, waiting for review';
  String get kycSubmitFailed =>
      isId ? 'Gagal mengirim permohonan' : 'Failed to submit request';
  String get kycErrName => isId ? 'Nama terlalu pendek' : 'Name too short';
  String get kycErrIdNumber =>
      isId ? 'Nomor identitas tidak valid' : 'Invalid ID number';
  String get kycErrPhotos =>
      isId ? 'Foto KTP & selfie wajib diisi' : 'ID photo & selfie are required';
  String get kycStatusNone => isId
      ? 'Belum verifikasi. Lengkapi untuk bisa mencairkan koin.'
      : 'Not verified. Complete this to be able to cash out coins.';
  String get kycStatusPending =>
      isId ? 'Menunggu review admin.' : 'Pending admin review.';
  String get kycStatusApproved => isId ? 'Terverifikasi ✓' : 'Verified ✓';
  String get kycStatusRejected => isId ? 'Ditolak:' : 'Rejected:';
  String get menuKyc => isId ? 'Verifikasi (KYC)' : 'Verification (KYC)';
  // ── Admin KYC review ──
  String get adminKycTitle => isId ? 'Review KYC' : 'KYC Review';
  String get adminKycDesc => isId
      ? 'Tinjau & setujui verifikasi identitas user'
      : 'Review & approve user identity verification';
  String get kycRejectTitle => isId ? 'Tolak Permohonan' : 'Reject Request';
  String get kycRejectReason => isId ? 'Alasan penolakan' : 'Rejection reason';
  String get kycApprovedToast =>
      isId ? 'Permohonan disetujui' : 'Request approved';
  String get kycRejectedToast =>
      isId ? 'Permohonan ditolak' : 'Request rejected';
  String get kycNoRequests => isId ? 'Tidak ada permohonan' : 'No requests';
  String get btnApprove => isId ? 'Setujui' : 'Approve';
  String get btnReject => isId ? 'Tolak' : 'Reject';
  String get btnRefresh => isId ? 'Muat ulang' : 'Refresh';
  // ── Withdrawal (pencairan) ──
  String get withdrawTitle => isId ? 'Cairkan Koin' : 'Withdraw Coins';
  String get withdrawBalance =>
      isId ? 'Saldo bisa dicairkan' : 'Withdrawable balance';
  String get withdrawRate => isId ? 'Nilai tukar' : 'Exchange rate';
  String get withdrawOnlyEarned => isId
      ? 'Hanya koin earned (hasil gift/transfer uang) yang bisa dicairkan. Koin bonus & topup tidak.'
      : 'Only earned coins (from gifts/paid transfers) are withdrawable. Bonus & topup coins are not.';
  String get withdrawAmount => isId ? 'Jumlah koin' : 'Coin amount';
  String get withdrawMethod => isId ? 'Metode Pencairan' : 'Withdrawal Method';
  String get withdrawMethodQris => isId ? 'QRIS' : 'QRIS';
  String get withdrawMethodBank => isId ? 'Transfer Bank' : 'Bank Transfer';
  String get withdrawMethodEwallet => isId ? 'E-Wallet' : 'E-Wallet';
  String get withdrawQrisId =>
      isId ? 'ID QRIS / Nama tujuan' : 'QRIS ID / Destination name';
  String get withdrawAccountNo =>
      isId ? 'Nomor Rekening / ID' : 'Account Number / ID';
  String get withdrawHolder => isId ? 'Nama Pemilik' : 'Account Holder Name';
  String get withdrawSubmit => isId ? 'Ajukan Pencairan' : 'Request Withdrawal';
  String withdrawPreview(int rp) =>
      isId ? '💰 Kamu akan terima ±Rp$rp' : '💰 You will receive ~Rp$rp';
  String withdrawPreviewHint(int min) => isId
      ? 'Minimal $min koin ($min × 7) untuk mencairkan'
      : 'Minimum $min coins to withdraw';
  String withdrawBelowMin(int min) =>
      isId ? 'Minimal pencairan $min koin' : 'Minimum withdrawal is $min coins';
  String get withdrawInsufficient =>
      isId ? 'Saldo earned tidak cukup' : 'Insufficient earned balance';
  String get withdrawInvalidPayout =>
      isId ? 'Data metode pembayaran tidak valid' : 'Invalid payout details';
  String get withdrawConfirmTitle =>
      isId ? 'Konfirmasi Pencairan' : 'Confirm Withdrawal';
  String withdrawConfirmBody(int coin, int rp) => isId
      ? 'Tarik $coin koin dengan nilai ±Rp$rp? Koin akan ditahan sampai admin membayar.'
      : 'Withdraw $coin coins worth ~Rp$rp? Coins are held until admin pays.';
  String get btnConfirm => isId ? 'Konfirmasi' : 'Confirm';
  String get withdrawRequested =>
      isId ? 'Pencairan diajukan' : 'Withdrawal requested';
  String get withdrawKycRequired => isId
      ? 'Verifikasi identitas (KYC) wajib untuk mencairkan.'
      : 'Identity verification (KYC) is required to withdraw.';
  String get withdrawFailed =>
      isId ? 'Gagal mengajukan pencairan' : 'Failed to request withdrawal';
  String get withdrawHistory =>
      isId ? 'Riwayat Pencairan' : 'Withdrawal History';
  String get withdrawNoHistory =>
      isId ? 'Belum ada pencairan' : 'No withdrawals yet';
  String get withdrawStatusPending => isId ? 'Menunggu' : 'Pending';
  String get withdrawStatusPaid => isId ? 'Dibayar' : 'Paid';
  String get withdrawStatusRejected => isId ? 'Ditolak' : 'Rejected';
  String get withdrawTxId => isId ? 'Referensi' : 'Reference';
  String get withdrawNote => isId ? 'Catatan' : 'Note';
  String get errCoinDisabled => isId
      ? 'Sistem koin sedang dinonaktifkan'
      : 'Coin system is currently disabled';
  // ── Admin Withdrawal review ──
  String get adminWithdrawTitle =>
      isId ? 'Review Pencairan' : 'Withdrawal Review';
  String get adminWithdrawDesc => isId
      ? 'Tinjau & proses permintaan pencairan'
      : 'Review & process withdrawal requests';
  String get withdrawPay => isId ? 'Tandai Dibayar' : 'Mark as Paid';
  String get withdrawPayTxId =>
      isId ? 'ID transaksi (opsional)' : 'Transaction ID (optional)';
  String get withdrawPayConfirm => isId
      ? 'Yakin sudah membayar ke user?'
      : 'Confirm you have paid this user?';
  String get withdrawPaidToast => isId ? 'Ditandai dibayar' : 'Marked as paid';
  String get withdrawRejectedToast => isId
      ? 'Pencairan ditolak & dana dikembalikan'
      : 'Withdrawal rejected & funds returned';
  String get withdrawRejectTitle =>
      isId ? 'Tolak Pencairan' : 'Reject Withdrawal';
  String get withdrawNoRequests =>
      isId ? 'Tidak ada permintaan' : 'No requests';
  // ── Admin Revenue Dashboard ──
  String get adminRevenueTitle =>
      isId ? 'Pendapatan Platform' : 'Platform Revenue';
  String get adminRevenueDesc => isId
      ? 'Ringkasan pendapatan dari gift & pencairan'
      : 'Revenue summary from gifts & withdrawals';
  String get adminRevenueGift => isId ? 'Pendapatan Gift' : 'Gift Revenue';
  String get adminRevenueCutTotal =>
      isId ? 'Total potongan platform' : 'Total platform cut';
  String get adminRevenueCutToday => isId ? 'Potongan hari ini' : "Today's cut";
  String get adminRevenueGross =>
      isId ? 'Total nominal gift' : 'Total gift value';
  String get adminRevenueGiftCount => isId ? 'Gift terkirim' : 'Gifts sent';
  String get adminRevenueTopGifts => isId ? 'Gift Terpopuler' : 'Top Gifts';
  String get adminRevenueWithdraw =>
      isId ? 'Ringkasan Pencairan' : 'Withdrawal Summary';
  String get adminRevenuePending =>
      isId ? 'Menunggu dibayar' : 'Pending payout';
  String get adminRevenuePaid => isId ? 'Sudah dibayar' : 'Paid out';
  String get adminRevenueRejected => isId ? 'Ditolak' : 'Rejected';
  String get adminRevenueSettings =>
      isId ? 'Pengaturan Ekonomi' : 'Economy Settings';
  String get adminRevenueCutPct => isId ? 'Potongan gift' : 'Gift cut';
  String get adminRevenueRate =>
      isId ? 'Nilai tukar (Rp/koin)' : 'Exchange rate (Rp/coin)';
  String get adminRevenueNoData => isId ? 'Belum ada data' : 'No data yet';

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
  String get descTheme => isId ? 'Tampilan gelap untuk kenyamanan mata' : 'Dark appearance for comfort';
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
  String get notifFriendRequestBody => isId
      ? 'mengirim permintaan teman'
      : 'sent you a friend request';
  String get notifSubscribeBody =>
      isId ? 'berlangganan ke kamu' : 'subscribed to you';
  String get labelNotifications => isId ? 'Notifikasi' : 'Notifications';
  String get notifEnabledDesc => isId
      ? 'Terima notifikasi pesan baru'
      : 'Receive new message notifications';

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
  String get btnChangePassword =>
      isId ? 'Ganti Password' : 'Change Password';
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
  String get errCurrentPasswordWrong => isId
      ? 'Password saat ini salah'
      : 'Current password is incorrect';
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
  String get titleVerifyEmail =>
      isId ? 'Verifikasi Email' : 'Verify Email';
  String get msgVerifyCodeSent => isId
      ? 'Kode verifikasi dikirim ke email kamu. Masukkan kode 6 digit di bawah.'
      : 'A verification code was sent to your email. Enter the 6-digit code below.';
  String get hintVerifyCode =>
      isId ? 'Kode 6 digit' : '6-digit code';
  String get btnVerify => isId ? 'Verifikasi' : 'Verify';
  String get btnResendCode => isId ? 'Kirim Ulang Kode' : 'Resend Code';
  String get msgResendCodeSent => isId
      ? 'Kode baru dikirim ke email kamu.'
      : 'A new code was sent to your email.';
  String get errInvalidCode => isId
      ? 'Kode tidak valid. Coba lagi.'
      : 'Invalid code. Please try again.';
  String get msgEmailVerified => isId
      ? 'Email terverifikasi!' : 'Email verified!';
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

  // ── Screenshot admin ──
  String get labelScreenshotAllow =>
      isId ? 'Izinkan screenshot aplikasi' : 'Allow app screenshots';
  String get descScreenshotAdmin => isId
      ? 'Admin — kontrol screenshot untuk semua pengguna'
      : 'Admin — control screenshots for all users';

  // ── Watermark admin ──
  String get labelWatermarkAdmin =>
      isId ? 'Aktifkan watermark forensik' : 'Enable forensic watermark';
  String get descWatermarkAdmin => isId
      ? 'Admin — foto sekali lihat ditandai identitas penerima'
      : 'Admin — view-once photos tagged with receiver identity';

  // ── Invisible admin ──
  String get labelInvisibleAdmin => isId ? 'Mode invisible' : 'Invisible mode';
  String get descInvisibleAdmin => isId
      ? 'Admin — tidak muncul di daftar pengguna online'
      : 'Admin — hidden from online users list';

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
      ? 'Koin pro tidak cukup. Top up dulu untuk membuka foto.'
      : 'Not enough pro coins. Top up to unlock photos.';
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
  // ── Wallet (bucket saldo) ──
  String get walletBucketBonus => isId ? 'Koin bonus' : 'Bonus coins';
  String get walletBucketTopup => isId ? 'Koin pro' : 'Pro coins';
  String get walletBucketEarned =>
      isId ? 'Koin bisa dicairkan' : 'Withdrawable coins';
  String get walletTitle => isId ? 'Dompet Koin' : 'Coin Wallet';
  String get walletTotal => isId ? 'Total koin' : 'Total coins';
  String get walletWithdrawable => isId ? 'Bisa dicairkan' : 'Withdrawable';
  String get walletBonusHint => isId
      ? 'Hanya untuk chat & fitur, tidak bisa dicairkan'
      : 'For chat & features only, not withdrawable';
  String get walletTopupHint => isId
      ? 'Hasil pembelian, untuk belanja di app'
      : 'From purchases, for spending in-app';
  String get walletEarnedHint => isId
      ? 'Hasil kiriman koin pro, bisa dicairkan'
      : 'From pro-coin transfers, can be withdrawn';
  // ── Top-Up (iPaymu) ──
  String get topupTitle => isId ? 'Isi Koin' : 'Top Up Coins';
  String get topupPickPackage =>
      isId ? 'Pilih paket koin:' : 'Choose a coin package:';
  String get topupBuy => isId ? 'Beli' : 'Buy';
  String get topupInfo => isId
      ? 'Pembayaran diproses aman via iPaymu (VA, QRIS, e-wallet). Koin masuk otomatis setelah pembayaran terkonfirmasi.'
      : 'Payments processed securely via iPaymu (VA, QRIS, e-wallet). Coins are added automatically once confirmed.';
  String get topupWaitingTitle =>
      isId ? 'Menunggu pembayaran' : 'Waiting for payment';
  String get topupWaitingBody => isId
      ? 'Selesaikan pembayaran di halaman yang terbuka, lalu tekan Cek Status.'
      : 'Complete payment on the opened page, then tap Check Status.';
  String get topupCheckStatus => isId ? 'Cek Status' : 'Check Status';
  String get topupSuccess => isId
      ? 'Pembayaran berhasil! Koin sudah ditambahkan.'
      : 'Payment successful! Coins added.';
  String get topupStillPending => isId
      ? 'Pembayaran belum terkonfirmasi. Coba lagi sebentar.'
      : 'Payment not confirmed yet. Try again shortly.';
  String get topupFailed => isId
      ? 'Pembayaran gagal atau dibatalkan.'
      : 'Payment failed or cancelled.';
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
  String get tooltipResize => isId ? 'Geser untuk mengubah ukuran' : 'Drag to resize';
  String get tooltipPhoto => isId ? 'Foto' : 'Photo';
  String get labelGenderFilter => isId ? 'Gender' : 'Gender';
  String get btnDelete => isId ? 'Hapus' : 'Delete';
  String get confirmDeletePost => isId
      ? 'Yakin ingin menghapus postingan ini?'
      : 'Delete this post?';
  String get postDeleted => isId ? 'Postingan dihapus' : 'Post deleted';
  String get errDeletePost => isId ? 'Gagal menghapus postingan' : 'Failed to delete post';
  String get adminPanel => isId ? 'Admin Panel' : 'Admin Panel';
  String get statsUsers => isId ? 'Users' : 'Users';
  String get statsActive => isId ? 'Active' : 'Active';
  String get statsMsgs => isId ? 'Msgs' : 'Msgs';
  String get statsRooms => isId ? 'Rooms' : 'Rooms';
  String get statsReg => isId ? 'Reg.' : 'Reg.';
  String get statsAnon => isId ? 'Anon' : 'Anon';
  String get statsAvg => isId ? 'Avg' : 'Avg';
  String get statsTotal => isId ? 'Total' : 'Total';
  String get adminNoUsers => isId ? 'Tidak ada user' : 'No users';
  String get adminPointSettings =>
      isId ? 'Pengaturan Nilai Poin' : 'Point Value Settings';
  String get adminSavePointSettings =>
      isId ? 'Simpan Pengaturan' : 'Save Settings';
  String get adminViewOnMaps => isId ? 'Lihat di Maps' : 'View on Maps';
  String get roomPrivateLabel => isId ? 'Privat' : 'Private';
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
  String get btnSend => isId ? 'Kirim' : 'Send';
  String get adminStuckUsers =>
      isId ? 'user terjebak (0 poin)' : 'users stuck (0 points)';
  String get onlineActiveUsers => isId ? 'pengguna aktif' : 'active users';
  String get labelVerified => isId ? 'Terverifikasi' : 'Verified';
  String get lobbyCountryHint => isId ? 'Negara / Country' : 'Country / Negara';
  String get donateCopyAddress => isId ? 'Salin Alamat ' : 'Copy Address ';
  String get googleSignInFailed =>
      isId ? 'Google sign in gagal: ' : 'Google sign in failed: ';

  // ── Admin Chat Monitor ──
  String get adminOverview => isId ? 'Ringkasan' : 'Overview';
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
  String get adminSearchChat =>
      isId ? 'Cari percakapan...' : 'Search conversations...';
  String get adminUserSingular => isId ? 'user' : 'user';
  String get adminUsersPlural => isId ? 'user' : 'users';
  String get chatMsgCount => isId ? 'pesan' : 'messages';
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

  // ── Admin Dummy Accounts ──
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
  String get dummyBackToAdmin => isId ? 'Kembali ke Admin' : 'Back to Admin';
  String get dummyBackConfirmTitle =>
      isId ? 'Kembali ke Admin?' : 'Back to Admin?';
  String get dummyBackConfirmBody => isId
      ? 'Kembali ke akun admin. Akun dummy tetap login & statusnya tidak berubah.'
      : 'Return to the admin account. The dummy stays signed in and its status is unchanged.';
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
  String get dummyBackFailed => isId
      ? 'Sesi admin kedaluwarsa — silakan login manual'
      : 'Admin session expired — sign in manually';
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
  String get dummyBackDone =>
      isId ? 'Kembali ke akun admin' : 'Back to admin account';
  String get dummyBannerTitle =>
      isId ? 'Mode Akun Dummy' : 'Dummy Account Mode';
  String get dummyBannerSubtitle =>
      isId ? 'Kamu sedang tampil sebagai %s' : 'You are appearing as %s';

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
  String get friendRequestTitle => isId ? 'Permintaan Teman' : 'Friend Requests';
  String get friendRequestEmpty => isId
      ? 'Belum ada permintaan teman'
      : 'No friend requests yet';
  String get friendRequestSent => isId
      ? 'Permintaan teman terkirim'
      : 'Friend request sent';
  String get friendRequestAccepted => isId
      ? 'Permintaan teman diterima'
      : 'Friend request accepted';
  String get subscriptionsTitle => isId ? 'Langganan' : 'Subscriptions';
  String get subscriptionsEmpty => isId
      ? 'Belum ada langganan'
      : 'No subscriptions yet';
  String subscribePrice(int c) =>
      isId ? '$c koin / bulan' : '$c coins / month';
  String get subscribePriceSuffix =>
      isId ? '🪙 / bulan' : '🪙 / month';
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
  String get setSubPriceTitle => isId
      ? 'Harga Subscribe' : 'Subscription Price';
  String get setSubPriceHint => isId
      ? '0 = nonaktif (gratis diikuti)'
      : '0 = disabled (free to follow)';
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
  String get subscribeWhatIs => isId
      ? 'Apa itu Subscribe?'
      : 'What is Subscribe?';
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
  String get hintWritePost => isId ? 'Tulis sesuatu...' : "Share what's on your mind...";
  String get btnPost => isId ? 'Posting' : 'Post';
  String get btnAdd => isId ? 'Add' : 'Add';
  String get btnCamera => isId ? 'Kamera' : 'Camera';
  String get btnGallery => isId ? 'Galeri' : 'Gallery';
  String get postingAs => isId ? 'Posting sebagai' : 'Posting as';
  String get promptCompleteEmailTitle => isId
      ? 'Lengkapi email untuk posting'
      : 'Complete email to post';
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
  String get labelVisibility => isId ? 'Siapa yang bisa melihat' : 'Who can see this';
  String get visPublic => isId ? 'Publik' : 'Public';
  String get visFollowers => isId ? 'Pengikut' : 'Followers';
  String get visSubscribers => isId ? 'Subscriber' : 'Subscribers';
  String get visPublicDesc => isId ? 'Semua orang' : 'Everyone';
  String get visFollowersDesc => isId ? 'Pengikut, teman & subscriber' : 'Followers, friends & subscribers';
  String get visSubscribersDesc => isId ? 'Hanya subscriber aktif' : 'Active subscribers only';
  String get hintComment => isId ? 'Tulis komentar...' : 'Write a comment...';
  String hintReplyTo(String name) => isId ? 'Balas $name' : 'Reply to $name';
  String get emptyTimeline => isId ? 'Belum ada postingan' : 'No posts yet';
  String get emptyTimelineHint => isId
      ? 'Jadilah yang pertama posting di timeline!'
      : 'Be the first to post on the timeline!';
  String get emptyTimelineCta => isId
      ? 'Ketuk + untuk membuat postingan'
      : 'Tap + to create a post';
  String get emptyFollowing => isId
      ? 'Belum ada postingan dari yang kamu ikuti'
      : 'No posts from people you follow';
  String get emptyFollowingHint => isId
      ? 'Ikuti orang lain untuk melihat postingan mereka di sini.'
      : 'Follow others to see their posts here.';
  String get emptyMine => isId
      ? 'Belum ada postinganmu'
      : 'No posts from you yet';
  String get emptyMineHint => isId
      ? 'Buat postingan pertamamu, akan muncul di sini.'
      : 'Create your first post, it will appear here.';
  String get noMorePosts => isId ? 'Tidak ada postingan lagi' : 'No more posts';
  String get errPostEmpty => isId ? 'Tulis sesuatu atau pilih foto' : 'Write something or pick a photo';
  String get errPostTooLong => isId ? 'Postingan maksimal 2000 karakter' : 'Post must be at most 2000 characters';
  String get errPostLimit => isId
      ? 'Batas posting harian tercapai'
      : 'Daily post limit reached';
  String get boostPaidLabel => isId ? 'Boost (koin pro)' : 'Boost (pro coins)';
  String get boostBonusLabel => isId ? 'Boost (koin bonus)' : 'Boost (bonus coins)';
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


