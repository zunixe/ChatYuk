import 'package:flutter/material.dart';

import '../config/country_codes.dart';
import '../config/strings.dart';
import '../config/theme.dart';

Future<CountryDial?> showCountryCodePicker(
  BuildContext context,
  S s, {
  required CountryDial selected,
}) {
  return showModalBottomSheet<CountryDial>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _CountryCodeSheet(s: s, selected: selected),
  );
}

class _CountryCodeSheet extends StatefulWidget {
  final S s;
  final CountryDial selected;
  const _CountryCodeSheet({required this.s, required this.selected});

  @override
  State<_CountryCodeSheet> createState() => _CountryCodeSheetState();
}

class _CountryCodeSheetState extends State<_CountryCodeSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? countryDials
        : countryDials.where((c) {
            return c.name.toLowerCase().contains(q) ||
                c.dial.contains(q) ||
                ('+${c.dial}').contains(q) ||
                c.iso.toLowerCase().contains(q);
          }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.s.titleChooseCountryCode,
                style: AppText.title,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                style: AppText.body.copyWith(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.s.hintSearchCountryCode,
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.s.hintSearchCountryCode,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final isSel = c.iso == widget.selected.iso &&
                              c.dial == widget.selected.dial;
                          return ListTile(
                            dense: true,
                            leading: Text(
                              countryFlag(c.iso),
                              style: AppText.body,
                            ),
                            title: Text(
                              c.name,
                              style: AppText.bodyStrong.copyWith(
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '+${c.dial}',
                                  style: AppText.bodyStrong.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                if (isSel) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check,
                                    size: 20,
                                    color: AppTheme.primary,
                                  ),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
