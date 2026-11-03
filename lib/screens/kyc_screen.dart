import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/kyc_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';

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
    final XFile? picked;
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
    if (picked == null || !mounted) return;

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

        // 4. Foto selfie — untuk face-match manual admin.
        _PhotoCard(
          title: s.kycPhotoSelfie,
          hint: s.kycPhotoSelfieHint,
          dataUrl: _selfiePhoto,
          busy: _processingPhoto,
          tapLabel: s.kycTapToAdd,
          retakeLabel: s.kycRetake,
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
class _PhotoCard extends StatelessWidget {
  final String title;
  final String hint;
  final String? dataUrl;
  final bool busy;
  final String tapLabel;
  final String retakeLabel;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.title,
    required this.hint,
    required this.dataUrl,
    required this.busy,
    required this.tapLabel,
    required this.retakeLabel,
    required this.onTap,
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
                  : has
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              base64Decode(
                                dataUrl!.substring(dataUrl!.indexOf(',') + 1),
                              ),
                              fit: BoxFit.contain,
                              // MEMORY: thumbnail saja — bytes asli tetap
                              // di field (yang dikirim ke server).
                              cacheWidth: 600,
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: _chipLabel(retakeLabel),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                size: 32,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tapLabel,
                                style: AppText.caption.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
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
