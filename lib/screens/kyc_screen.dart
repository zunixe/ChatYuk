import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/kyc_service.dart';
import '../providers/theme_provider.dart';

String? _kycProcessImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final w = decoded.width, h = decoded.height;
  const maxSide = 1200;
  if (w > maxSide || h > maxSide) {
    final scale = maxSide / (w > h ? w : h);
    final img2 = img.copyResize(decoded, width: (w * scale).round(), height: (h * scale).round());
    return base64Encode(img.encodeJpg(img2, quality: 80));
  }
  return base64Encode(img.encodeJpg(decoded, quality: 80));
}

/// Screen verifikasi identitas (KYC) untuk pencairan (Fase 5).
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  String _idType = 'ktp';
  DateTime? _birthDate;
  String? _idPhoto;
  String? _selfiePhoto;
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic> _status = {'status': 'none'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await KycService.instance.myStatus();
    if (!mounted) return;
    setState(() {
      _status = st;
      _loading = false;
    });
  }

  Future<void> _pickId() async {
    final p = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (p == null) return;
    final b = await p.readAsBytes();
    final base64 = await compute(_kycProcessImage, b);
    if (base64 != null && mounted) setState(() => _idPhoto = base64);
  }

  Future<void> _pickSelfie() async {
    final p = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600);
    if (p == null) return;
    final b = await p.readAsBytes();
    final base64 = await compute(_kycProcessImage, b);
    if (base64 != null && mounted) setState(() => _selfiePhoto = base64);
  }

  Future<void> _submit() async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameCtrl.text.trim();
    final idNumber = _idNumberCtrl.text.trim();
    if (name.length < 3) { messenger.showSnackBar(SnackBar(content: Text(s.kycErrName))); return; }
    if (idNumber.length < 8) { messenger.showSnackBar(SnackBar(content: Text(s.kycErrIdNumber))); return; }
    if (_idPhoto == null || _selfiePhoto == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.kycErrPhotos))); return;
    }
    setState(() => _submitting = true);
    try {
      await KycService.instance.submit(
        fullName: name,
        idType: _idType,
        idNumber: idNumber,
        idPhoto: _idPhoto!,
        selfiePhoto: _selfiePhoto!,
        birthDate: _birthDate?.toIso8601String().split('T').first,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.kycSubmitted)));
      await _load();
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('already') ? s.kycAlreadySubmitted : s.kycSubmitFailed;
      messenger.showSnackBar(SnackBar(content: Text(show)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final st = _status['status'] ?? 'none';
    final approved = st == 'approved';
    final pending = st == 'pending';

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.kycTitle), backgroundColor: AppTheme.bgScreen),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
              children: [
                _statusBanner(s, st),
                SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  enabled: !approved && !pending,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.kycFullName,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    hintText: 'contoh: Budi Santoso',
                    hintStyle: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
                SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _idType,
                      dropdownColor: AppTheme.bgCard,
                      style: AppText.body,
                      decoration: InputDecoration(
                        labelText: s.kycIdType,
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                      ),
                      items: [
                        DropdownMenuItem(value: 'ktp', child: Text(s.kycIdTypeKtp)),
                        DropdownMenuItem(value: 'passport', child: Text(s.kycIdTypePassport)),
                      ],
                      onChanged: approved || pending ? null : (v) => setState(() => _idType = v ?? 'ktp'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: approved || pending ? null : () => _pickBirthDate(),
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: s.kycBirthDate,
                          labelStyle: TextStyle(color: AppTheme.textSecondary),
                        ),
                        child: Text(
                          _birthDate == null ? s.kycOptional : _birthDate!.toIso8601String().split('T').first,
                          style: AppText.body,
                        ),
                      ),
                    ),
                  ),
                ]),
                SizedBox(height: 14),
                TextField(
                  controller: _idNumberCtrl,
                  enabled: !approved && !pending,
                  style: TextStyle(color: AppTheme.textPrimary),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.kycIdNumber,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                SizedBox(height: 24),
                Row(children: [
                  Expanded(child: _photoBox(s, label: s.kycIdPhoto, data: _idPhoto, onTap: _pickId)),
                  SizedBox(width: 14),
                  Expanded(child: _photoBox(s, label: s.kycSelfie, data: _selfiePhoto, onTap: _pickSelfie)),
                ]),
                SizedBox(height: 8),
                Text(s.kycHint, style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
                SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: AppTheme.bgInput,
                  ),
                  onPressed: (approved || pending || _submitting) ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(approved || pending ? s.kycSubmitted : s.kycSubmit,
                            style: AppText.bodyStrong.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }

  Future<void> _pickBirthDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) setState(() => _birthDate = d);
  }

  Widget _statusBanner(S s, String st) {
    final (color, icon, text) = switch (st) {
      'approved' => (const Color(0xFF2E7D32), Icons.verified_user, s.kycStatusApproved),
      'pending' => (const Color(0xFFF9A825), Icons.hourglass_top, s.kycStatusPending),
      'rejected' => (AppTheme.danger, Icons.cancel, s.kycStatusRejected),
      _ => (AppTheme.primary, Icons.info_outline, s.kycStatusNone),
    };
    final reason = st == 'rejected' && _status['reject_reason'] != null
        ? ' ${_status['reject_reason']}' : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(text + reason, style: AppText.bodySmall)),
      ]),
    );
  }

  Widget _photoBox(S s, {required String label, String? data, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(0xFFE0E0E0)),
        ),
        child: data == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_a_photo_outlined, color: AppTheme.textSecondary, size: 28),
                SizedBox(height: 6),
                Text(label, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
              ])
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(base64Decode(data), fit: BoxFit.cover),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                        child: Text(label, style: AppText.caption.copyWith(color: Colors.white)),
                      ),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }
}
