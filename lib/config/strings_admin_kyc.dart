// String ADMIN tab KYC — JANGAN di-import dari kode build rilis (lihat
// strings_admin.dart).
import 'strings.dart';

extension SAdminKycX on S {
  String get adminKycTitle => isId ? 'Verifikasi Identitas' : 'Identity Verifications';
  String get adminKycEmpty => isId
      ? 'Tidak ada pengajuan verifikasi'
      : 'No verification requests';
  String get adminKycPending => isId ? 'Menunggu' : 'Pending';
  String get adminKycApproved => isId ? 'Disetujui' : 'Approved';
  String get adminKycRejected => isId ? 'Ditolak' : 'Rejected';
  String get adminKycAll => isId ? 'Semua' : 'All';
  String get adminKycApprove => isId ? 'Setujui' : 'Approve';
  String get adminKycReject => isId ? 'Tolak' : 'Reject';
  String get adminKycRejectTitle => isId ? 'Tolak Verifikasi' : 'Reject Verification';
  String get adminKycRejectHint => isId
      ? 'Alasan penolakan (ditampilkan ke user)'
      : 'Rejection reason (shown to the user)';
  String get adminKycDocPhoto => isId ? 'Foto KTP' : 'KTP Photo';
  String get adminKycSelfiePhoto => isId ? 'Foto Selfie' : 'Selfie Photo';
  String get adminKycApprovedSnack =>
      isId ? 'Verifikasi disetujui' : 'Verification approved';
  String get adminKycRejectedSnack =>
      isId ? 'Verifikasi ditolak' : 'Verification rejected';
  String get adminKycRejectNeedReason =>
      isId ? 'Isi alasan penolakan dulu' : 'Enter a rejection reason first';
  String adminKycReviewedAt(String date) =>
      isId ? 'Ditinjau $date' : 'Reviewed $date';
  String get adminKycAlreadyProcessed => isId
      ? 'Pengajuan ini sudah diproses admin lain'
      : 'This request was already processed';
  String get adminKycLoadPhotos => isId ? 'Memuat foto…' : 'Loading photos…';

  // Hasil cek otomatis (ditampilkan sebagai chip ✓/✗ untuk admin).
  String get adminKycChecks => isId ? 'Cek otomatis' : 'Automatic checks';
  String get adminKycChkNik => isId ? 'Struktur NIK' : 'NIK structure';
  String get adminKycChkOcr => isId ? 'KTP terbaca' : 'KTP read';
  String get adminKycChkNikOcr => isId ? 'NIK = KTP' : 'NIK = KTP';
  String get adminKycChkName => isId ? 'Nama = KTP' : 'Name = KTP';
  String get adminKycChkBirth => isId ? 'Tgl lahir = NIK' : 'DOB = NIK';
  String get adminKycChkGender => isId ? 'Gender = profil' : 'Gender = profile';
  String get adminKycChkLive => isId ? 'Liveness' : 'Liveness';
  String get adminKycChkQuality => isId ? 'Foto tajam' : 'Sharp photo';
  String adminKycOcrRead(String v) => isId ? 'Terbaca: $v' : 'Read: $v';
}
