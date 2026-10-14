part of 'strings.dart';

mixin SAuthMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
  String get roomVoiceJoin => isId ? 'Ikut voice' : 'Join voice';
  String get roomVoiceConnecting => isId ? 'Menyambungkan…' : 'Connecting…';
  String get roomVoiceGoStage => isId ? 'Nyalakan mic' : 'Turn on mic';
  String get roomVoiceMute => isId ? 'Matikan mic' : 'Mute mic';
  String get roomVoiceUnmute => isId ? 'Nyalakan mic' : 'Unmute mic';
  String get roomVoiceLeave => isId ? 'Keluar voice' : 'Leave voice';
  String get roomVoiceStageFull => isId
      ? 'Panggung penuh (6/6) — tunggu giliran'
      : 'Stage full (6/6) — wait your turn';
  String get roomVoiceMutedByAdmin => isId
      ? 'Mic dimatikan admin'
      : 'Mic muted by admin';
  String get roomVoiceConnectFail => isId
      ? 'Gagal menyambungkan mic — coba lagi'
      : 'Failed to connect mic — try again';
  String get roomVoiceDiagTitle =>
      isId ? 'Diagnostik voice' : 'Voice diagnostics';
  String get roomVoiceDiagHint => isId
      ? 'Kirim foto layar ini ke dev bila suara bermasalah'
      : 'Send a screenshot of this to dev if audio fails';
  String get roomVoiceMuted => isId ? 'Dimute' : 'Muted';
  String get roomVoiceSpeaking => isId ? 'Bicara' : 'Speaking';
  String roomVoiceListeners(int n) =>
      isId ? '$n pendengar' : '$n listening';
  String get roomVoiceNoSpeakers => isId
      ? 'Belum ada yang bicara — jadilah yang pertama'
      : 'No one speaking yet — be the first';

  String get btnClose => isId ? 'Tutup' : 'Close';
  String get btnZoomIn => isId ? 'Perbesar' : 'Zoom in';
  String get btnZoomOut => isId ? 'Perkecil' : 'Zoom out';
  String get btnZoomReset => isId ? 'Atur ulang zoom' : 'Reset zoom';
  String get viewerZoomHint => isId
      ? 'Cubit 2 jari / ketuk 2x untuk zoom'
      : 'Pinch or double-tap to zoom';
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
  String get btnComplete => isId ? 'LENGKAPI' : 'COMPLETE';
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
  // ── Tanggal lahir & Nomor HP (Pengaturan › Akun) ──
  String get labelBirthDate => isId ? 'Tanggal Lahir' : 'Date of Birth';
  String get descBirthDate =>
      isId ? 'Tanggal lahir asli kamu' : 'Your real date of birth';
  String get hintBirthDateNotSet => isId ? 'Belum diisi' : 'Not set';
  String get titlePickBirthDate =>
      isId ? 'Pilih Tanggal Lahir' : 'Select Date of Birth';
  String get msgBirthDateSaved =>
      isId ? 'Tanggal lahir tersimpan' : 'Date of birth saved';
  String get labelPhone => isId ? 'Nomor HP' : 'Phone Number';
  String get descPhone =>
      isId ? 'Nomor HP aktif kamu' : 'Your active phone number';
  String get hintPhoneNotSet => isId ? 'Belum diisi' : 'Not set';
  String get hintPhoneInput => isId ? 'Contoh: +6281234567890' : 'e.g. +6281234567890';
  String get msgPhoneSaved => isId ? 'Nomor HP tersimpan' : 'Phone number saved';
  String get errPhoneInvalid => isId
      ? 'Nomor HP tidak valid (6–20 digit, boleh diawali +)'
      : 'Invalid phone number (6–20 digits, may start with +)';
  String get labelCountryCode => isId ? 'Kode negara' : 'Country code';
  String get titleChooseCountryCode =>
      isId ? 'Pilih kode negara' : 'Choose country code';
  String get hintSearchCountryCode =>
      isId ? 'Cari negara / kode...' : 'Search country / code...';
  String get hintPhoneNumber =>
      isId ? 'Nomor HP tanpa 0 depan' : 'Number without leading 0';
  String get labelPhoneFull =>
      isId ? 'Nomor lengkap' : 'Full number';
  // ── Verifikasi nomor HP via Telegram ──
  String get phoneVerifyTitle =>
      isId ? 'Verifikasi via Telegram' : 'Verify via Telegram';
  String get phoneVerifyDesc => isId
      ? 'Buka bot Telegram kami untuk memverifikasi nomor HP. Setelah terverifikasi, akunmu dapat badge emas.'
      : 'Open our Telegram bot to verify your phone number. Once verified, your account gets a gold badge.';
  String get phoneVerifyBtn =>
      isId ? 'Verifikasi Sekarang' : 'Verify Now';
  String get phoneVerifyLater => isId ? 'Nanti saja' : 'Later';
  String get phoneVerifyWaiting => isId
      ? 'Menunggu verifikasi… buka Telegram & tekan tombol Verifikasi Nomor Saya.'
      : 'Waiting for verification… open Telegram & tap Verify My Number.';
  String get phoneVerifyOpened => isId
      ? 'Telegram terbuka. Tekan "Verifikasi Nomor Saya" di bot.'
      : 'Telegram opened. Tap "Verify My Number" in the bot.';
  String get phoneVerifySuccess =>
      isId ? 'Nomor HP terverifikasi!' : 'Phone number verified!';
  String get phoneVerifyFailed =>
      isId ? 'Verifikasi gagal. Coba lagi.' : 'Verification failed. Try again.';
  String get phoneVerifyRateLimited => isId
      ? 'Terlalu banyak percobaan. Coba lagi nanti.'
      : 'Too many attempts. Try again later.';
  String get phoneVerifyPhoneEmpty =>
      isId ? 'Isi nomor HP dulu.' : 'Enter your phone number first.';
  String get phoneVerifyRetry => isId ? 'Coba lagi' : 'Try again';
  String get phoneVerifiedBadge =>
      isId ? 'Terverifikasi' : 'Verified';
  String get phoneVerifiedAt =>
      isId ? 'Terverifikasi' : 'Verified';

  String get errBirthDateFuture =>
      isId ? 'Tanggal lahir tidak boleh di masa depan' : 'Date of birth cannot be in the future';
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
  String get msgAnonRetention7d => isId
      ? 'Tidak login 7 hari? Akun anonim ini dan username-nya akan dihapus otomatis. Daftarkan email agar username kamu tidak hilang.'
      : 'Inactive for 7 days? This anonymous account and its username will be deleted automatically. Register your email to keep your username.';
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
  String get errNicknameBanned => isId
      ? 'Nickname ini tidak diizinkan, pilih yang lain'
      : 'This nickname is not allowed, choose another';
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
  String get errOtpExpired => isId
      ? 'Kode sudah kedaluwarsa. Kirim ulang kode.'
      : 'Code expired. Resend a new one.';
  String get errOtpUsed => isId
      ? 'Kode sudah dipakai. Kirim ulang kode.'
      : 'Code already used. Resend a new one.';
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
  String get codeCopy => isId ? 'Salin kode' : 'Copy code';
  String get codeCopied => isId ? 'Kode disalin' : 'Code copied';
  String codeShowAll(int n) =>
      isId ? 'Tampilkan $n baris lagi' : 'Show $n more lines';
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
      ? 'Sembunyikan "Mulai Chat" + akun anon tidak bisa chat/post (tetap bisa lihat-lihat). Akun dummy & admin tetap bebas.'
      : 'Hide "Start Chatting" + anon accounts cannot chat/post (still can browse). Dummy & admin accounts unaffected.';

  // ── Soft gate anon (fitur anon dinonaktifkan) ──
  String get anonGateBanner => isId
      ? 'Fitur akun anon sedang dinonaktifkan — daftar untuk lanjut chat & posting'
      : 'Anonymous accounts are temporarily disabled — register to continue chatting & posting';
  String get anonGateBannerCta => isId ? 'Daftar' : 'Register';
  String get anonGateBlocked => isId
      ? 'Akun anon sedang dinonaktifkan. Daftar dengan email atau Google untuk lanjut chat — data kamu tetap tersimpan.'
      : 'Anonymous accounts are currently disabled. Register with email or Google to continue chatting — your data stays intact.';

  // ── Notifikasi pengingat harian (admin) ──
  String get labelReengageNotif => isId ? 'Pengingat Harian' : 'Daily Reminder';
  String get descReengageNotif => isId
      ? 'Push pengingat tiap 19:00 ke user offline 1-8 hari (stop setelah 7 hari)'
      : 'Push daily reminder at 19:00 to users offline 1-8 days (stops after 7 days)';

  // ── Points ──
}
