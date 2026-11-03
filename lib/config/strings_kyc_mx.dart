part of 'strings.dart';

/// String KYC (verifikasi identitas untuk withdraw).
mixin SKycMx {
  bool get isId;

  String get kycTitle => isId ? 'Verifikasi Identitas' : 'Identity Verification';
  String get kycIntroTitle => isId
      ? 'Verifikasi identitas untuk bisa withdraw'
      : 'Verify your identity to enable withdrawals';
  String get kycIntroBody => isId
      ? 'Siapkan KTP asli (bukan fotokopi/foto layar). Ada 3 langkah: foto KTP, verifikasi wajah, lalu cek data. Foto hanya dilihat admin untuk verifikasi dan TIDAK dibagikan ke pengguna lain.'
      : 'Have your original KTP ready (no photocopy/screen photo). 3 steps: photo of your KTP, face verification, then confirm your data. Photos are only seen by admins and are NEVER shared with other users.';
  String kycStep(int i) => isId ? 'Langkah $i' : 'Step $i';
  String get kycPhotoId => isId ? 'Foto KTP' : 'KTP Photo';
  String get kycPhotoIdHint => isId
      ? 'Kamera membaca KTP otomatis. Pastikan keempat sudut masuk bingkai, teks jelas, dan tanpa pantulan cahaya.'
      : 'The camera reads your KTP automatically. Keep all four corners inside the frame, text sharp, and no glare.';
  String get kycPhotoSelfie => isId ? 'Verifikasi Wajah' : 'Face Verification';
  String get kycPhotoSelfieHint => isId
      ? 'Ikuti instruksi di layar (kedip & toleh) untuk membuktikan ini kamu secara langsung. Lepas masker/kacamata hitam.'
      : 'Follow the on-screen prompts (blink & turn) to prove it is really you, live. Remove masks/sunglasses.';
  String get kycTapToAdd => isId ? 'Ketuk untuk mulai' : 'Tap to start';
  String get kycRetake => isId ? 'Ulangi' : 'Retake';
  String get kycDataTitle => isId ? 'Data Diri' : 'Personal Data';
  String get kycDataHint => isId
      ? 'Terisi otomatis dari KTP. Periksa dan perbaiki bila salah baca.'
      : 'Filled automatically from your KTP. Check and correct any misreads.';
  String get kycFullName => isId ? 'Nama Lengkap (sesuai KTP)' : 'Full Name (as on KTP)';
  String get kycIdNumber => isId ? 'NIK (16 digit)' : 'NIK (16 digits)';
  String get kycBirthDate => isId ? 'Tanggal Lahir' : 'Date of Birth';
  String get kycPickDate => isId ? 'Pilih tanggal' : 'Pick date';
  String get kycSubmit => isId ? 'Kirim Verifikasi' : 'Submit Verification';
  String get kycSubmitting => isId ? 'Mengirim…' : 'Submitting…';
  String get kycSecureNote => isId
      ? 'Dokumen hanya bisa diakses admin verifikasi.'
      : 'Documents are only accessible to verification admins.';

  // Status hasil baca / verifikasi.
  String get kycKtpRead => isId ? 'KTP terbaca otomatis' : 'KTP read automatically';
  String get kycKtpNotRead => isId
      ? 'KTP tidak terbaca otomatis — isi data manual, admin akan memeriksa lebih teliti.'
      : 'KTP could not be read automatically — enter your data manually; an admin will check more closely.';
  String get kycLiveVerified => isId ? 'Wajah terverifikasi langsung' : 'Live face verified';
  String get kycWarnNikMismatch => isId
      ? 'NIK berbeda dengan yang terbaca di KTP'
      : 'NIK differs from the one read on the KTP';
  String get kycWarnNameMismatch => isId
      ? 'Nama berbeda dengan yang terbaca di KTP'
      : 'Name differs from the one read on the KTP';
  String get kycWarnGenderMismatch => isId
      ? 'Jenis kelamin di NIK berbeda dengan profil'
      : 'Gender in the NIK differs from your profile';

  // Error validasi.
  String get kycErrPhotos => isId
      ? 'Foto KTP & verifikasi wajah wajib diselesaikan'
      : 'KTP photo & face verification are required';
  String get kycErrName =>
      isId ? 'Nama lengkap minimal 3 huruf' : 'Full name must be 3+ characters';
  String get kycErrNumber => isId
      ? 'NIK tidak valid — periksa 16 digit sesuai KTP'
      : 'Invalid NIK — check the 16 digits on your KTP';
  String get kycErrBirth =>
      isId ? 'Pilih tanggal lahir dulu' : 'Pick your date of birth first';
  String get kycErrBirthMismatch => isId
      ? 'Tanggal lahir tidak sesuai dengan NIK'
      : 'Date of birth does not match the NIK';
  String get kycErrUnderage =>
      isId ? 'Usia minimal 17 tahun' : 'You must be at least 17 years old';
  String get kycErrNikUsed => isId
      ? 'NIK ini sudah dipakai akun lain'
      : 'This NIK is already used by another account';
  String get kycErrTooMany => isId
      ? 'Terlalu banyak pengajuan. Coba lagi besok.'
      : 'Too many submissions. Please try again tomorrow.';
  String get kycErrGeneric => isId
      ? 'Gagal mengirim verifikasi. Coba lagi.'
      : 'Failed to submit verification. Please try again.';
  String get kycErrDuplicate => isId
      ? 'Verifikasi sudah pernah dikirim'
      : 'Verification was already submitted';
  String get kycErrNoFace => isId
      ? 'Wajah tidak terdeteksi. Posisikan wajah di dalam oval lalu ulangi.'
      : 'No face detected. Place your face inside the oval and retry.';

  // Kamera KTP.
  String get kycDocAlign => isId
      ? 'Posisikan KTP di dalam bingkai'
      : 'Place your KTP inside the frame';
  String get kycDocBlurry => isId
      ? 'Buram — tahan HP lebih stabil'
      : 'Blurry — hold your phone steady';
  String get kycDocGlare => isId
      ? 'Ada pantulan cahaya — miringkan sedikit KTP'
      : 'Glare detected — tilt your KTP slightly';
  String get kycDocDark => isId
      ? 'Terlalu gelap — pindah ke tempat lebih terang'
      : 'Too dark — move somewhere brighter';
  String get kycDocNotKtp => isId
      ? 'KTP belum terbaca — dekatkan & pastikan teks jelas'
      : 'KTP not read yet — move closer and keep text clear';
  String get kycDocHold => isId
      ? 'KTP terbaca — tahan sebentar…'
      : 'KTP detected — hold still…';
  String get kycDocManual => isId
      ? 'Tidak terbaca otomatis? Ketuk tombol untuk memotret.'
      : 'Not detected? Tap the button to capture.';

  // Kamera wajah (liveness).
  String get kycFaceGuide => isId
      ? 'Posisikan wajah di dalam oval'
      : 'Place your face inside the oval';
  String get kycCamMulti => isId
      ? 'Terdeteksi lebih dari satu wajah'
      : 'More than one face detected';
  String get kycCamLookStraight => isId
      ? 'Hadapkan wajah lurus & dekatkan ke kamera'
      : 'Face the camera straight & move closer';
  String get kycLiveBlink => isId ? 'Kedipkan mata' : 'Blink your eyes';
  String get kycLiveTurn => isId
      ? 'Toleh kepala perlahan ke kiri lalu ke kanan'
      : 'Slowly turn your head left, then right';
  String get kycLiveStraight => isId
      ? 'Bagus! Hadap lurus ke kamera'
      : 'Great! Look straight at the camera';
  String get kycLiveRestart => isId
      ? 'Wajah berganti/hilang — ulangi dari awal'
      : 'Face lost or changed — starting over';
  String kycLiveProgress(int done, int total) =>
      isId ? 'Langkah $done dari $total' : 'Step $done of $total';
  String get kycCamPermTitle =>
      isId ? 'Izin kamera dibutuhkan' : 'Camera permission needed';
  String get kycCamPermBody => isId
      ? 'Verifikasi identitas wajib memakai kamera langsung. Izinkan kamera di pengaturan.'
      : 'Identity verification requires the live camera. Allow camera access in settings.';
  String get kycOpenSettings => isId ? 'Buka Pengaturan' : 'Open Settings';

  // Status pengajuan.
  String get kycPendingTitle => isId ? 'Sedang Ditinjau' : 'Under Review';
  String get kycPendingBody => isId
      ? 'Verifikasi kamu sedang ditinjau admin. Withdraw terbuka otomatis setelah disetujui.'
      : 'Your verification is being reviewed by an admin. Withdrawals unlock automatically once approved.';
  String get kycApprovedTitle => isId ? 'Terverifikasi' : 'Verified';
  String get kycApprovedBody => isId
      ? 'Identitas kamu sudah terverifikasi. Kamu bisa withdraw kapan saja.'
      : 'Your identity is verified. You can withdraw anytime.';
  String get kycRejectedTitle => isId ? 'Verifikasi Ditolak' : 'Verification Rejected';
  String kycRejectedReason(String reason) =>
      isId ? 'Alasan: $reason' : 'Reason: $reason';
  String get kycResubmit => isId ? 'Kirim Ulang' : 'Resubmit';
  String get kycBannerWithdraw => isId
      ? 'Verifikasi identitas dulu untuk bisa withdraw'
      : 'Verify your identity first to enable withdrawals';
  String get kycVerifyNow => isId ? 'Verifikasi Sekarang' : 'Verify Now';
}
