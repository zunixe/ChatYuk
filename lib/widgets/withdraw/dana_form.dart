import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';

/// Form input akun DANA (nomor + nama pemilik) dengan validasi client.
class DanaForm extends StatefulWidget {
  final String initialNumber;
  final String initialName;
  final bool saving;
  final Future<bool> Function(String number, String name) onSave;

  const DanaForm({
    super.key,
    this.initialNumber = '',
    this.initialName = '',
    this.saving = false,
    required this.onSave,
  });

  @override
  State<DanaForm> createState() => _DanaFormState();
}

class _DanaFormState extends State<DanaForm> {
  late final TextEditingController _number;
  late final TextEditingController _name;
  final _formKey = GlobalKey<FormState>();
  String? _numberError;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.initialNumber);
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Normalisasi + validasi nomor DANA. Mengembalikan nomor bersih atau null.
  String? _validateNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (!RegExp(r'^(08|62)[0-9]{8,13}$').hasMatch(digits)) return null;
    return digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
  }

  Future<void> _submit() async {
    final s = S(isId: Localizations.localeOf(context).languageCode == 'id');
    final clean = _validateNumber(_number.text);
    final name = _name.text.trim();

    setState(() {
      _numberError = clean == null ? s.wdInvalidNumber : null;
      _nameError = name.length < 3 ? s.wdInvalidName : null;
    });

    if (clean == null || name.length < 3) return;

    final ok = await widget.onSave(clean, name);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.wdDanaSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S(isId: Localizations.localeOf(context).languageCode == 'id');

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 17, color: Color(0xFF2196F3)),
              const SizedBox(width: 6),
              Text(
                s.wdDanaTitle,
                style: AppText.label.copyWith(color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _number,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
              LengthLimitingTextInputFormatter(18),
            ],
            style: AppText.body.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: s.wdDanaNumber,
              hintText: s.wdDanaNumberHint,
              errorText: _numberError,
              prefixIcon: const Icon(Icons.phone_android, size: 18),
            ),
            onChanged: (_) {
              if (_numberError != null) {
                setState(() => _numberError = null);
              }
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            style: AppText.body.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: s.wdDanaName,
              hintText: s.wdDanaNameHint,
              errorText: _nameError,
              prefixIcon: const Icon(Icons.person_outline, size: 18),
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: widget.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(s.wdDanaSave, style: AppText.button),
            ),
          ),
        ],
      ),
    );
  }
}
