import 'package:flutter/material.dart';

import '../config/country_codes.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import 'country_code_picker.dart';

Future<String?> showPhoneEditDialog(
  BuildContext context,
  S s, {
  required String currentPhone,
  String? countryName,
}) async {
  CountryDial dial;
  String national;
  final existing = currentPhone.trim();
  if (existing.startsWith('+') && existing.length > 2) {
    dial = findDialForPhone(existing);
    national = splitNationalNumber(existing, dial.dial);
  } else if (existing.isNotEmpty) {
    dial = findDialForCountryName(countryName);
    final digits = existing.replaceAll(RegExp(r'[^0-9]'), '');
    national = digits.startsWith('0') ? digits.substring(1) : digits;
  } else {
    dial = findDialForCountryName(countryName);
    national = '';
  }
  final ctrl = TextEditingController(text: national);
  String? errorText;
  var saving = false;

  try {
    return await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final preview = combineDialAndNumber(dial.dial, ctrl.text);
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: Text(s.labelPhone, style: AppText.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.descPhone,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: saving
                          ? null
                          : () async {
                              final picked = await showCountryCodePicker(
                                ctx,
                                s,
                                selected: dial,
                              );
                              if (picked != null && ctx.mounted) {
                                setDlg(() => dial = picked);
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              countryFlag(dial.iso),
                              style: AppText.body,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '+${dial.dial}',
                              style: AppText.bodyStrong.copyWith(
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        style: AppText.body.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: s.hintPhoneNumber,
                          errorText: errorText,
                        ),
                        onChanged: (_) {
                          if (errorText != null) {
                            setDlg(() => errorText = null);
                          } else {
                            setDlg(() {});
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${s.labelPhoneFull}: ${preview.isEmpty ? '-' : preview}',
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(s.btnCancel),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final full =
                            combineDialAndNumber(dial.dial, ctrl.text);
                        if (ctrl.text.trim().isNotEmpty &&
                            (full.isEmpty ||
                                full.length < 7 ||
                                full.replaceAll('+', '').length < 6)) {
                          setDlg(() => errorText = s.errPhoneInvalid);
                          return;
                        }
                        setDlg(() {
                          saving = true;
                          errorText = null;
                        });
                        if (ctx.mounted) Navigator.pop(ctx, full);
                      },
                child: Text(s.btnSave),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    ctrl.dispose();
  }
}
