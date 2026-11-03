import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/kyc/kyc_capture.dart';
import '../core/kyc/kyc_form_check.dart';
import '../core/kyc/ktp_ocr.dart';
import '../core/kyc/nik.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/kyc_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';
import 'kyc/kyc_document_camera_screen.dart';
import 'kyc/kyc_selfie_camera_screen.dart';
import 'kyc/widgets/kyc_camera_widgets.dart';
import 'kyc/widgets/kyc_form_widgets.dart';

/// Halaman verifikasi identitas (KYC) — syarat withdraw perempuan.
///
/// 3 langkah, semuanya kamera LANGSUNG (tanpa galeri):
///  1. KTP — kamera membaca KTP (OCR) + cek tajam/silau, auto-jepret.
///  2. Wajah — liveness (kedip + toleh) dengan wajah yang sama.
///  3. Data — terisi otomatis dari KTP; NIK divalidasi strukturnya dan
///     dicocokkan dengan tgl lahir; beda dengan hasil baca KTP ditandai.
/// Hasil cek dikirim sebagai `checks` untuk admin; server memvalidasi
/// ulang NIK/tgl lahir/NIK unik (klien bisa dimodifikasi).
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  /// Hitung wajah pada file — injectable untuk test (ML Kit native tidak
  /// ada di unit test). -1 = detektor gagal (jangan blokir).
  @visibleForTesting
  static Future<int> Function(String path) faceChecker = _faceCount;

  /// Baca teks KTP dari file (fallback kamera sistem) — injectable test.
  @visibleForTesting
  static Future<List<String>> Function(String path) ocrReader = _ocrLines;

  static Future<int> _faceCount(String path) async {
    final d = FaceDetector(options: FaceDetectorOptions());
    try {
      return (await d.processImage(InputImage.fromFilePath(path))).length;
    } catch (e) {
      dlog('[KYC] face detect error: $e');
      return -1;
    } finally {
      d.close();
    }
  }

  static Future<List<String>> _ocrLines(String path) async {
    final r = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final t = await r.processImage(InputImage.fromFilePath(path));
      return [for (final b in t.blocks) for (final l in b.lines) l.text];
    } catch (e) {
      dlog('[KYC] ocr error: $e');
      return const [];
    } finally {
      r.close();
    }
  }

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final _nameCtrl = TextEditingController();
  final _nikCtrl = TextEditingController();
  final _picker = ImagePicker();

  DateTime? _birthDate;
  KycDocCapture? _doc;
  KycSelfieCapture? _selfie;
  Uint8List? _docBytes; // JPEG terproses (dikirim) — didecode SEKALI
  Uint8List? _selfieBytes;
  String? _docB64;
  String? _selfieB64;
  bool _busyDoc = false;
  bool _busySelfie = false;

  @override
  void initState() {
    super.initState();
    _nikCtrl.addListener(_onNikChanged);
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nikCtrl.dispose();
    super.dispose();
  }

  void _onNikChanged() {
    final info = Nik.parse(_nikCtrl.text);
    // NIK valid & tgl lahir belum diisi → isi dari NIK.
    if (info != null && _birthDate == null) _birthDate = info.birthDate;
    setState(() {});
  }

  void _snack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ));
  }

  /// JPEG 1200px q82 → (bytes untuk pratinjau, base64 untuk server).
  Future<(Uint8List, String)?> _process(String path) async {
    final raw = await XFile(path).readAsBytes();
    final b64 = await NativeImage.processJpeg(raw, maxPx: 1200, quality: 82);
    if (b64 == null) return null;
    return (base64Decode(b64), b64);
  }

  Future<void> _captureDoc(S s) async {
    KycDocumentCameraScreen.lastInitFailed = false;
    var cap = await Navigator.push<KycDocCapture?>(
      context,
      MaterialPageRoute(builder: (_) => const KycDocumentCameraScreen()),
    );
    if (!mounted) return;
    if (cap == null && KycDocumentCameraScreen.lastInitFailed) {
      // Kamera kustom gagal (mis. MIUI) → kamera sistem, tetap tanpa galeri.
      final x = await _pickCamera(CameraDevice.rear);
      if (x == null || !mounted) return;
      setState(() => _busyDoc = true);
      cap = KycDocCapture(
        path: x.path,
        ocr: KtpOcr.parse(await KycScreen.ocrReader(x.path)),
      );
    }
    if (cap == null) return;
    setState(() => _busyDoc = true);
    try {
      final p = await _process(cap.path);
      if (!mounted) return;
      if (p == null) return _snack(s.kycErrGeneric);
      final ocr = cap.ocr;
      setState(() {
        _doc = cap;
        _docBytes = p.$1;
        _docB64 = p.$2;
        // Isi otomatis dari KTP (user tetap bisa mengoreksi).
        if (ocr.nik != null) _nikCtrl.text = ocr.nik!;
        if (ocr.name != null) _nameCtrl.text = ocr.name!;
        final info = Nik.parse(_nikCtrl.text);
        _birthDate = ocr.birthDate ?? info?.birthDate ?? _birthDate;
      });
    } finally {
      if (mounted) setState(() => _busyDoc = false);
    }
  }

  Future<void> _captureSelfie(S s) async {
    KycSelfieCameraScreen.lastInitFailed = false;
    var cap = await Navigator.push<KycSelfieCapture?>(
      context,
      MaterialPageRoute(builder: (_) => const KycSelfieCameraScreen()),
    );
    if (!mounted) return;
    if (cap == null && KycSelfieCameraScreen.lastInitFailed) {
      final x = await _pickCamera(CameraDevice.front);
      if (x == null || !mounted) return;
      cap = KycSelfieCapture(path: x.path, live: false);
    }
    if (cap == null) return;
    setState(() => _busySelfie = true);
    try {
      final faces = await KycScreen.faceChecker(cap.path);
      if (!mounted) return;
      if (faces == 0) return _snack(s.kycErrNoFace);
      if (faces > 1) return _snack(s.kycCamMulti);
      final p = await _process(cap.path);
      if (!mounted) return;
      if (p == null) return _snack(s.kycErrGeneric);
      setState(() {
        _selfie = cap;
        _selfieBytes = p.$1;
        _selfieB64 = p.$2;
      });
    } finally {
      if (mounted) setState(() => _busySelfie = false);
    }
  }

  Future<XFile?> _pickCamera(CameraDevice device) async {
    try {
      return await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: device,
      );
    } catch (e) {
      dlog('[KYC] system camera error: $e');
      return null;
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  /// Gender profil — dibaca sekali (null bila auth belum siap, mis. test).
  String? _gender;
  bool _genderRead = false;
  String? get _profileGender {
    if (!_genderRead) {
      _genderRead = true;
      try {
        _gender = ref.read(authProvider).profile?.gender;
      } catch (_) {}
    }
    return _gender;
  }

  KycFormCheck _check() => KycFormCheck.evaluate(
        nik: _nikCtrl.text.trim(),
        name: _nameCtrl.text,
        birth: _birthDate,
        doc: _doc,
        selfie: _selfie,
        profileGender: _profileGender,
      );

  String _errorText(S s, KycFormError e) => switch (e) {
        KycFormError.photos => s.kycErrPhotos,
        KycFormError.name => s.kycErrName,
        KycFormError.nik => s.kycErrNumber,
        KycFormError.birth => s.kycErrBirth,
        KycFormError.birthMismatch => s.kycErrBirthMismatch,
        KycFormError.underage => s.kycErrUnderage,
      };

  Future<void> _submit(S s) async {
    final c = _check();
    if (c.error != null) return _snack(_errorText(s, c.error!));
    final res = await ref.read(kycProvider.notifier).submit(
          fullName: _nameCtrl.text.trim(),
          idType: 'ktp',
          idNumber: _nikCtrl.text.trim(),
          idPhoto: 'data:image/jpeg;base64,$_docB64',
          selfiePhoto: 'data:image/jpeg;base64,$_selfieB64',
          birthDate: _birthDate,
          checks: c.checks,
        );
    if (!mounted || res == null) return;
    _snack(switch (res) {
      KycSubmitError.duplicate => s.kycErrDuplicate,
      KycSubmitError.nikUsed => s.kycErrNikUsed,
      KycSubmitError.nikInvalid => s.kycErrNumber,
      KycSubmitError.birthMismatch => s.kycErrBirthMismatch,
      KycSubmitError.underage => s.kycErrUnderage,
      KycSubmitError.name => s.kycErrName,
      KycSubmitError.tooMany => s.kycErrTooMany,
      KycSubmitError.photos => s.kycErrPhotos,
      KycSubmitError.busy || KycSubmitError.generic => s.kycErrGeneric,
    });
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
              'pending' => KycStatusView(
                  icon: Icons.hourglass_top_outlined,
                  color: kKycWarn,
                  title: s.kycPendingTitle,
                  body: s.kycPendingBody,
                ),
              'approved' => KycStatusView(
                  icon: Icons.verified_outlined,
                  color: kKycOk,
                  title: s.kycApprovedTitle,
                  body: s.kycApprovedBody,
                ),
              _ => _buildForm(s, kyc),
            },
    );
  }

  Widget _buildForm(S s, KycState kyc) {
    final check = _check();
    final ocr = _doc?.ocr;
    final nik = _nikCtrl.text.trim();
    final nikError = nik.length == 16 && Nik.parse(nik) == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (kyc.isRejected) ...[
          KycCard(
            color: AppTheme.danger.withValues(alpha: 0.12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.error_outline, size: 20, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.kycRejectedTitle,
                      style: AppText.bodyStrong.copyWith(color: AppTheme.danger),
                    ),
                  ),
                ]),
                if ((kyc.rejectReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.kycRejectedReason(kyc.rejectReason!),
                    style: AppText.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        KycCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.kycIntroTitle, style: AppText.bodyStrong),
              const SizedBox(height: 6),
              Text(
                s.kycIntroBody,
                style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KycStepCard(
          number: 1,
          title: s.kycPhotoId,
          hint: s.kycPhotoIdHint,
          done: _doc != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KycPhotoTile(
                bytes: _docBytes,
                emptyIcon: Icons.badge_outlined,
                tapLabel: s.kycTapToAdd,
                retakeLabel: s.kycRetake,
                busy: _busyDoc,
                onTap: () => _captureDoc(s),
              ),
              if (ocr != null)
                ocr.looksLikeKtp
                    ? KycNote(
                        icon: Icons.check_circle_outline,
                        color: kKycOk,
                        text: s.kycKtpRead,
                      )
                    : KycNote(
                        icon: Icons.info_outline,
                        color: kKycWarn,
                        text: s.kycKtpNotRead,
                      ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KycStepCard(
          number: 2,
          title: s.kycPhotoSelfie,
          hint: s.kycPhotoSelfieHint,
          done: _selfie != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox(
                  width: 180,
                  child: KycPhotoTile(
                    bytes: _selfieBytes,
                    emptyIcon: Icons.face_retouching_natural,
                    tapLabel: s.kycTapToAdd,
                    retakeLabel: s.kycRetake,
                    busy: _busySelfie,
                    aspect: 0.78,
                    onTap: () => _captureSelfie(s),
                  ),
                ),
              ),
              if (_selfie?.live == true)
                KycNote(
                  icon: Icons.verified_user_outlined,
                  color: kKycOk,
                  text: s.kycLiveVerified,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KycStepCard(
          number: 3,
          title: s.kycDataTitle,
          hint: s.kycDataHint,
          done: check.error == null,
          child: Column(
            children: [
              TextField(
                controller: _nikCtrl,
                decoration: InputDecoration(
                  labelText: s.kycIdNumber,
                  errorText: nikError ? s.kycErrNumber : null,
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 16,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: s.kycFullName),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickBirthDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: s.kycBirthDate,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                    errorText: check.error == KycFormError.birthMismatch
                        ? s.kycErrBirthMismatch
                        : null,
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
              for (final w in check.warnings)
                KycNote(
                  icon: Icons.warning_amber_rounded,
                  color: kKycWarn,
                  text: switch (w) {
                    KycFormWarning.nikMismatch => s.kycWarnNikMismatch,
                    KycFormWarning.nameMismatch => s.kycWarnNameMismatch,
                    KycFormWarning.genderMismatch => s.kycWarnGenderMismatch,
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: kyc.submitting || _busyDoc || _busySelfie
              ? null
              : () => _submit(s),
          child: Text(kyc.submitting ? s.kycSubmitting : s.kycSubmit),
        ),
        const SizedBox(height: 10),
        KycNote(
          icon: Icons.lock_outline,
          color: AppTheme.textSecondary,
          text: s.kycSecureNote,
        ),
      ],
    );
  }
}
