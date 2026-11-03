import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/kyc_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';
import 'kyc_selfie_camera_screen.dart';

/// Halaman verifikasi identitas (KYC) — syarat withdraw perempuan.
///
/// Flow (best practice KTP/paspor): consent → jenis dokumen → foto dokumen
/// → foto selfie → data (nama, nomor, tgl lahir) → kirim → status.
/// Status pending/approved/rejected menggantikan form (rejected → resubmit).
/// Foto diproses `NativeImage.processJpeg` (max 1200px q82) → data URL
/// base64 ke `submit_kyc` (kolom TEXT — bucket public tidak dipakai agar
/// dokumen tidak terekspos URL publik).
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  /// Deteksi wajah pada file foto — injectable untuk test (ML Kit native
  /// tak tersedia di unit test). Return jumlah wajah, -1 = detektor gagal
  /// di device (jangan blokir — admin tetap review manual).
  @visibleForTesting
  static Future<int> Function(String path) faceChecker = _faceCount;

  static Future<int> _faceCount(String path) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    try {
      final faces =
          await detector.processImage(InputImage.fromFilePath(path));
      return faces.length;
    } catch (e) {
      dlog('[KYC] face detect error: $e');
      return -1;
    } finally {
      detector.close();
    }
  }

  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _picker = ImagePicker();

  String _docType = 'ktp';
  DateTime? _birthDate;
  String? _idPhoto; // data:image/jpeg;base64,…
  String? _selfiePhoto;
  bool _processingPhoto = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  Future<ImageSource?> _pickSource(S s) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.kycCamera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.kycGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(S s, {required bool selfie}) async {
    final source = await _pickSource(s);
    if (source == null || !mounted) return;
    XFile? picked;
    if (selfie && source == ImageSource.camera) {
      // Kamera selfie KUSTOM: oval panduan DI DALAM viewfinder + deteksi
      // wajah live — shutter baru aktif saat wajah pas. Gagal init (mis.
      // MIUI) → lastInitFailed → fallback ke kamera sistem di bawah.
      KycSelfieCameraScreen.lastInitFailed = false;
      picked = await Navigator.push<XFile?>(
        context,
        MaterialPageRoute(builder: (_) => const KycSelfieCameraScreen()),
      );
      if (!mounted) return;
      // null & BUKAN init-gagal = user sengaja membatalkan → jangan
      // buka kamera lain, langsung keluar.
      if (picked == null && !KycSelfieCameraScreen.lastInitFailed) return;
    }
    if (picked == null) {
      try {
        picked = await _picker.pickImage(
          source: source,
          // Selfie idealnya kamera depan (best practice face-match).
          preferredCameraDevice:
              selfie ? CameraDevice.front : CameraDevice.rear,
        );
      } catch (e) {
        dlog('[KYC] pick error: $e');
        return;
      }
    }
    if (picked == null || !mounted) return;

    // Validasi selfie: harus ada wajah (anti foto asal/tembok/dokumen).
    // Dilakukan SEBELUM proses — hemat waktu user daripada ditolak admin.
    if (selfie) {
      final faces = await faceChecker(picked.path);
      if (!mounted) return;
      if (faces == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.kycErrNoFace),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
      // faces == -1 → detektor gagal di device ini → lanjut; admin
      // tetap mereview manual. faces ≥ 1 → lolos.
    }

    setState(() => _processingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      // 1200px q82: cukup tajam untuk membaca dokumen, ~150-300KB base64.
      final b64 = await NativeImage.processJpeg(
        bytes,
        maxPx: 1200,
        quality: 82,
      );
      if (!mounted) return;
      if (b64 == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.kycErrGeneric)),
        );
        return;
      }
      setState(() {
        final url = 'data:image/jpeg;base64,$b64';
        if (selfie) {
          _selfiePhoto = url;
        } else {
          _idPhoto = url;
        }
      });
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  Future<void> _pickBirthDate(S s) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 17),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppTheme.primary,
                surface: AppTheme.bgCard,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  String? _validate(S s) {
    if (_idPhoto == null || _selfiePhoto == null) return s.kycErrPhotos;
    if (_nameCtrl.text.trim().length < 3) return s.kycErrName;
    if (_numberCtrl.text.trim().length < 8) return s.kycErrNumber;
    if (_birthDate == null) return s.kycErrBirth;
    return null;
  }

  Future<void> _submit(S s) async {
    final err = _validate(s);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final res = await ref.read(kycProvider.notifier).submit(
          fullName: _nameCtrl.text.trim(),
          idType: _docType,
          idNumber: _numberCtrl.text.trim(),
          idPhoto: _idPhoto!,
          selfiePhoto: _selfiePhoto!,
          birthDate: _birthDate,
        );
    if (!mounted) return;
    if (res != null) {
      final msg = res == 'duplicate'
          ? s.kycErrDuplicate
          : res.startsWith('server:')
              ? res.substring(7)
              : s.kycErrGeneric;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final kyc = ref.watch(kycProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.kycTitle)),
      body: kyc.loading
          ? const Center(child: CircularProgressIndicator())
          : switch (kyc.status) {
              'pending' => _StatusView(
                  icon: Icons.hourglass_top_outlined,
                  color: Colors.orange,
                  title: s.kycPendingTitle,
                  body: s.kycPendingBody,
                ),
              'approved' => _StatusView(
                  icon: Icons.verified_outlined,
                  color: const Color(0xFF2ECC71),
                  title: s.kycApprovedTitle,
                  body: s.kycApprovedBody,
                ),
              _ => _buildForm(s, kyc),
            },
    );
  }

  Widget _buildForm(S s, KycState kyc) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Status rejected → tampilkan alasan di atas form resubmit.
        if (kyc.isRejected) ...[
          _Card(
            color: AppTheme.danger.withValues(alpha: 0.12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.error_outline, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.kycRejectedTitle,
                      style: AppText.bodyStrong.copyWith(
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                ]),
                if ((kyc.rejectReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.kycRejectedReason(kyc.rejectReason!),
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 1. Intro + consent (wajib legal: foto dokumen & wajah).
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.kycIntroTitle, style: AppText.bodyStrong),
              const SizedBox(height: 6),
              Text(
                s.kycIntroBody,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Jenis dokumen — KTP / Paspor / SIM (panduan capture
        // menyesuaikan tipe yang dipilih).
        _sectionLabel(s.kycDocType),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _docChip(s.kycDocKtp, 'ktp'),
            _docChip(s.kycDocPassport, 'passport'),
            _docChip(s.kycDocSim, 'sim'),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Foto dokumen — panduan kualitas (4 sudut, jelas, tanpa glare).
        _PhotoCard(
          title: s.kycPhotoId,
          hint: s.kycPhotoIdHint,
          dataUrl: _idPhoto,
          busy: _processingPhoto,
          tapLabel: s.kycTapToAdd,
          retakeLabel: s.kycRetake,
          onTap: () => _pickPhoto(s, selfie: false),
        ),
        const SizedBox(height: 12),

        // 4. Foto selfie — panduan oval posisi wajah + validasi ada wajah
        // (ML Kit) saat foto dipilih; admin cocokkan dengan foto dokumen.
        _PhotoCard(
          title: s.kycPhotoSelfie,
          hint: s.kycPhotoSelfieHint,
          dataUrl: _selfiePhoto,
          busy: _processingPhoto,
          tapLabel: s.kycTapToAdd,
          retakeLabel: s.kycRetake,
          faceGuide: true,
          guideText: s.kycFaceGuide,
          onTap: () => _pickPhoto(s, selfie: true),
        ),
        const SizedBox(height: 16),

        // 5. Data diri sesuai dokumen.
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(labelText: s.kycFullName),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _numberCtrl,
          decoration: InputDecoration(labelText: s.kycIdNumber),
          keyboardType: TextInputType.visiblePassword,
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _pickBirthDate(s),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: s.kycBirthDate,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            child: Text(
              _birthDate == null
                  ? s.kycPickDate
                  : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
              style: AppText.body.copyWith(
                color: _birthDate == null
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed:
              kyc.submitting || _processingPhoto ? null : () => _submit(s),
          child: Text(kyc.submitting ? s.kycSubmitting : s.kycSubmit),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: AppText.label.copyWith(color: AppTheme.textSecondary),
      );

  Widget _docChip(String label, String value) {
    final sel = _docType == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _docType = value),
      selectedColor: AppTheme.primary.withValues(alpha: 0.25),
    );
  }
}

/// Kartu dasar section (latar card + padding konsisten).
class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;
  const _Card({required this.child, this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

/// Kartu ambil/lihat foto KYC — tap membuka picker kamera/galeri.
/// [faceGuide] menggambar oval panduan posisi wajah (selfie).
class _PhotoCard extends StatelessWidget {
  final String title;
  final String hint;
  final String? dataUrl;
  final bool busy;
  final String tapLabel;
  final String retakeLabel;
  final bool faceGuide;
  final String? guideText;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.title,
    required this.hint,
    required this.dataUrl,
    required this.busy,
    required this.tapLabel,
    required this.retakeLabel,
    required this.onTap,
    this.faceGuide = false,
    this.guideText,
  });

  @override
  Widget build(BuildContext context) {
    final has = dataUrl != null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            hint,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: busy ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 170,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: has ? AppTheme.primary : AppTheme.divider,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Oval panduan posisi wajah — tetap terlihat di
                        // atas preview supaya user bisa cek posisi muka.
                        if (faceGuide)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _FaceGuidePainter(),
                            ),
                          ),
                        if (has)
                          Image.memory(
                            base64Decode(
                              dataUrl!.substring(dataUrl!.indexOf(',') + 1),
                            ),
                            fit: BoxFit.contain,
                            // MEMORY: thumbnail saja — bytes asli tetap
                            // di field (yang dikirim ke server).
                            cacheWidth: 600,
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!faceGuide) ...[
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 32,
                                    color: AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                Text(
                                  faceGuide && guideText != null
                                      ? guideText!
                                      : tapLabel,
                                  textAlign: TextAlign.center,
                                  style: AppText.caption.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (has)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: _chipLabel(retakeLabel),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: AppText.caption.copyWith(color: Colors.white)),
      );
}

/// Oval panduan posisi wajah di kartu selfie — outline putus-putus +
/// ikon wajah di tengah supaya jelas area targetnya.
class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Oval sedikit lebih tinggi dari lebar — bentuk umum wajah.
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.42,
      height: size.height * 0.72,
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Outline putus-putus: potong perimeter oval jadi segmen.
    final path = Path()..addOval(rect);
    const dashLen = 10.0;
    const gapLen = 7.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dashLen),
          paint,
        );
        dist += dashLen + gapLen;
      }
    }

    // Ikon wajah sederhana di tengah oval (mata + senyum).
    final c = rect.center;
    final eyePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final eyeY = c.dy - rect.height * 0.08;
    canvas.drawCircle(Offset(c.dx - rect.width * 0.14, eyeY), 3, eyePaint);
    canvas.drawCircle(Offset(c.dx + rect.width * 0.14, eyeY), 3, eyePaint);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + rect.height * 0.06),
        width: rect.width * 0.3,
        height: rect.height * 0.22,
      ),
      0.4,
      2.34,
      false,
      paint..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) => false;
}

/// Tampilan status (pending/approved) — ikon + judul + penjelasan.
class _StatusView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _StatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: 14),
              Text(title, style: AppText.titleEmphasis),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}
