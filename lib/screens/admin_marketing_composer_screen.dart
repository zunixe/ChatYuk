import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../providers/riverpod/admin_provider.dart';

/// Composer email marketing — editor WYSIWYG (flutter_quill).
/// Hasil editor (Delta) dikonversi ke HTML via vsc_quill_delta_to_html,
/// lalu disimpan ke campaign.
class AdminMarketingComposerScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? campaign;
  const AdminMarketingComposerScreen({super.key, this.campaign});

  @override
  ConsumerState<AdminMarketingComposerScreen> createState() =>
      _AdminMarketingComposerScreenState();
}

class _AdminMarketingComposerScreenState
    extends ConsumerState<AdminMarketingComposerScreen> {
  late final quill.QuillController _ctrl;
  final _nameCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();
  String _segmentType = 'all_registered';
  bool _busy = false;

  bool get _isEdit => widget.campaign != null;

  @override
  void initState() {
    super.initState();
    final c = widget.campaign;
    _nameCtrl.text = '${c?['name'] ?? ''}';
    _subjectCtrl.text = '${c?['subject'] ?? ''}';
    final seg = (c?['segment'] as Map?)?.cast<String, dynamic>();
    _segmentType = '${seg?['type'] ?? 'all_registered'}';

    // Isi dokumen dari html_body kalau ada (plain text; MVP: HTML → teks).
    final body = '${c?['html_body'] ?? ''}';
    quill.Document doc;
    if (body.isEmpty) {
      doc = quill.Document();
    } else {
      // MVP: html_body disimpan sebagai HTML; kita muat sebagai teks biasa
      // (strip tag) agar editor tidak crash. Untuk edit lanjutan, admin
      // menyusun ulang — cukup untuk revisi subjek/nama/segmen.
      doc = quill.Document()..insert(0, _stripHtml(body));
    }
    _ctrl = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _subjectCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  /// Delta → HTML (untuk email). Bungkus bila kosong.
  String _deltaToHtml() {
    final ops = _ctrl.document.toDelta().toJson();
    try {
      final converter = QuillDeltaToHtmlConverter(
        List<Map<String, dynamic>>.from(ops),
        ConverterOptions.forEmail(),
      );
      return converter.convert().trim();
    } catch (_) {
      // Fallback: teks polos.
      return '<p>${_ctrl.document.toPlainText().trim()}</p>';
    }
  }

  Future<void> _save({required bool thenSend}) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    if (_subjectCtrl.text.trim().isEmpty || _deltaToHtml().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminMktSaveFail)),
      );
      return;
    }
    setState(() => _busy = true);
    final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    try {
      final id = await a.saveCampaign(
        id: (widget.campaign?['id'] as num?)?.toInt(),
        name: _nameCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        html: _deltaToHtml(),
        segment: {'type': _segmentType},
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (thenSend && id > 0) {
        final res = await a.sendCampaign(id);
        if (!mounted) return;
        final msg = res.startsWith('ok:')
            ? s.adminMktSentQueue
            : '${s.adminMktSendFail}: $res';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.adminMktSaved)));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminMktSaveFail)),
      );
    }
  }

  void _preview() {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final html = _deltaToHtml();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.adminMktPreview, style: AppText.titleEmphasis),
              const SizedBox(height: 8),
              Text(_subjectCtrl.text,
                  style: AppText.bodyStrong),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: SelectableText(
                    _stripHtml(html),
                    style: AppText.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;

    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: Builder(
        builder: (context) => _buildScaffold(context, s),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, S s) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? s.adminMktNewCampaign : s.adminMktNewCampaign),
        actions: [
          IconButton(
            tooltip: s.adminMktPreview,
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _preview,
          ),
          TextButton(
            onPressed: _busy ? null : () => _save(thenSend: false),
            child: Text(s.adminMktSaveDraft),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy ? null : () => _save(thenSend: true),
              child: Text(s.adminMktSend),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: s.adminMktCampaignName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectCtrl,
                  decoration: InputDecoration(
                    labelText: s.adminMktSubject,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _segmentType,
                  decoration: InputDecoration(
                    labelText: s.adminMktSegment,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'all_registered',
                      child: Text(s.adminMktSegmentAll),
                    ),
                    DropdownMenuItem(
                      value: 'active_days',
                      child: Text(s.adminMktSegmentActive30),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _segmentType = v ?? 'all_registered'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Toolbar WYSIWYG.
          Container(
            color: AppTheme.bgCard,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: quill.QuillSimpleToolbar(
              controller: _ctrl,
              config: const quill.QuillSimpleToolbarConfig(
                multiRowsDisplay: false,
                showFontFamily: false,
                showFontSize: false,
                showBackgroundColorButton: false,
                showColorButton: false,
                showCodeBlock: false,
                showInlineCode: false,
                showIndent: false,
                showListCheck: false,
                showQuote: false,
                showStrikeThrough: false,
                showSubscript: false,
                showSuperscript: false,
                showSearchButton: false,
                showClearFormat: false,
                showAlignmentButtons: false,
              ),
            ),
          ),
          const Divider(height: 1),
          // Editor.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: quill.QuillEditor.basic(
                controller: _ctrl,
                focusNode: _focusNode,
                scrollController: _scrollCtrl,
                config: quill.QuillEditorConfig(
                  placeholder: s.adminMktBody,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
