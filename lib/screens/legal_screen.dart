import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/legal_section.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

enum LegalKind { privacy, terms }

class LegalScreen extends StatelessWidget {
  final LegalKind kind;
  const LegalScreen({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          kind == LegalKind.privacy ? s.legalPrivacyTitle : s.legalTermsTitle,
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: kind == LegalKind.privacy
            ? _LegalDocBody(
                docTitle: s.legalPrivacyDocTitle,
                effective: s.legalPrivacyEffective,
                version: s.legalPrivacyVersion,
                noticeTitle: s.legalNoticeTitle,
                noticeText: s.legalNoticeText,
                sections: s.legalPrivacySections,
              )
            : _LegalDocBody(
                docTitle: s.legalTermsDocTitle,
                effective: s.legalTermsEffective,
                version: s.legalTermsVersion,
                noticeTitle: s.legalTermsNoticeTitle,
                noticeText: s.legalTermsNoticeText,
                sections: s.legalTermsSections,
              ),
      ),
    );
  }
}

class _LegalDocBody extends StatelessWidget {
  final String docTitle;
  final String effective;
  final String version;
  final String noticeTitle;
  final String noticeText;
  final List<LegalSection> sections;
  const _LegalDocBody({
    required this.docTitle,
    required this.effective,
    required this.version,
    required this.noticeTitle,
    required this.noticeText,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          docTitle,
          style: AppText.titleEmphasis.copyWith(color: AppTheme.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          effective,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          version,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _NoticeBox(title: noticeTitle, text: noticeText),
        const SizedBox(height: 8),
        for (final section in sections) ...[
          if (section.chapter != null) ...[
            const SizedBox(height: 24),
            Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 12),
            Text(
              section.chapter!,
              style: AppText.titleEmphasis.copyWith(color: AppTheme.primary),
            ),
            const SizedBox(height: 8),
          ],
          if (section.article != null) ...[
            Text(
              section.article!,
              style: AppText.label.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
          ],
          for (final item in section.items) ...[
            if (item.table != null)
              _LegalTable(rows: item.table!)
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (item.bullet) const TextSpan(text: '•  '),
                      ..._rich(item.text),
                    ],
                  ),
                  style: AppText.body,
                  textAlign: TextAlign.justify,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _NoticeBox extends StatelessWidget {
  final String title;
  final String text;
  const _NoticeBox({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label.copyWith(color: AppTheme.primary)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: _rich(text)),
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LegalTable extends StatelessWidget {
  final List<List<String>> rows;
  const _LegalTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final header = rows.first;
    final data = rows.skip(1).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.divider, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: AppTheme.primary.withValues(alpha: 0.08),
            child: Text(
              header.join('  ·  '),
              style: AppText.label.copyWith(color: AppTheme.primary),
            ),
          ),
          for (var i = 0; i < data.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppTheme.divider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data[i].first, style: AppText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(
                    data[i].skip(1).join(' — '),
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<InlineSpan> _rich(String text) {
  final spans = <InlineSpan>[];
  final boldParts = text.split('**');
  for (var i = 0; i < boldParts.length; i++) {
    if (boldParts[i].isEmpty) continue;
    if (i.isOdd) {
      spans.add(
        TextSpan(
          text: boldParts[i],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      final italicParts = boldParts[i].split('*');
      for (var j = 0; j < italicParts.length; j++) {
        if (italicParts[j].isEmpty) continue;
        spans.add(
          TextSpan(
            text: italicParts[j],
            style: j.isOdd
                ? const TextStyle(fontStyle: FontStyle.italic)
                : null,
          ),
        );
      }
    }
  }
  return spans;
}
