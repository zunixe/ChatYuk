import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';
import '../../../utils.dart';

/// Daftar provider AI: tap = expand (model, base URL, API key),
/// radio = provider yang dipakai edge function. Bisa tambah baru.
class ProviderListSection extends StatefulWidget {
  const ProviderListSection({super.key});

  @override
  State<ProviderListSection> createState() => _ProviderListSectionState();
}

class _ProviderListSectionState extends State<ProviderListSection> {
  AdminProvider get _svc => context.read<AdminProvider>();
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _items = const [];
  String? _expandedId;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _svc.getAiProviders();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.aiProviderLoadFail,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            TextButton(onPressed: _reload, child: Text(s.btnRetry)),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in _items)
          ProviderCard(
            key: ValueKey('prov-${p['id']}'),
            data: p,
            expanded: _expandedId == '${p['id']}',
            onToggleExpand: () {
              setState(() {
                _expandedId = _expandedId == '${p['id']}' ? null : '${p['id']}';
              });
            },
            onChanged: _reload,
          ),
        if (_adding)
          ProviderCard(
            key: const ValueKey('prov-new'),
            data: const {},
            expanded: true,
            isNew: true,
            onToggleExpand: () => setState(() => _adding = false),
            onChanged: () {
              setState(() => _adding = false);
              _reload();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _adding
                ? null
                : () => setState(() {
                    _adding = true;
                    _expandedId = null;
                  }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(s.aiProviderAdd),
          ),
        ),
      ],
    );
  }
}

/// Satu kartu provider: radio + label + model; expand = edit 4 field.
class ProviderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool expanded;
  final bool isNew;
  final VoidCallback onToggleExpand;
  final VoidCallback onChanged;

  const ProviderCard({
    super.key,
    required this.data,
    required this.expanded,
    this.isNew = false,
    required this.onToggleExpand,
    required this.onChanged,
  });

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  AdminProvider get _svc => context.read<AdminProvider>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _storyModelCtrl;
  late final TextEditingController _fallbackModelCtrl;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _keyCtrl;
  bool _busy = false;
  bool _activating = false;

  /// Model gratis + terbukti jalan & patuh, per provider (host).
  /// Dropdown model di tiap kartu (termasuk form tambah) difilter otomatis
  /// dari base URL kartu itu — tanpa dropdown provider terpisah.
  static const _modelsByBase = {
    'integrate.api.nvidia.com': ['nim/nvidia/nemotron-3-ultra-550b-a55b'],
    'tokenharbor.ai': ['th/deepseek-v4.1-flash:free'],
    'openrouter.ai': [
      'nvidia/nemotron-3.5-lightning:free',
      'nvidia/nemotron-3-super-120b-a12b:free',
      'nvidia/nemotron-3-ultra-550b-a55b:free',
      'inclusionai/ling-3.0-flash-fin:free',
    ],
    'api.b.ai': ['mimo-v2.5', 'qwen3.8-flash'],
  };

  /// Model terpilih (null = ketikan manual).
  String? _modelSel;

  /// Pilihan model sesuai base URL kartu ini (semua bila tak dikenal).
  List<String> _modelChoices() {
    final b = _baseCtrl.text.trim().toLowerCase();
    for (final entry in _modelsByBase.entries) {
      if (b.contains(entry.key)) return entry.value;
    }
    return [for (final v in _modelsByBase.values) ...v];
  }

  /// Model terpilih: pilihan user, atau yang cocok dengan isi field.
  String? _matchedModelId() {
    if (_modelSel != null) return _modelSel;
    final m = _modelCtrl.text.trim();
    if (m.isEmpty) return null;
    final ids = _modelChoices();
    return ids.contains(m) ? m : null;
  }

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: '${widget.data['label'] ?? ''}');
    _modelCtrl = TextEditingController(
      text: '${widget.data['default_model'] ?? ''}',
    );
    _storyModelCtrl = TextEditingController(
      text: '${widget.data['story_model'] ?? ''}',
    );
    _fallbackModelCtrl = TextEditingController(
      text: '${widget.data['fallback_model'] ?? ''}',
    );
    _baseCtrl = TextEditingController(text: '${widget.data['api_base'] ?? ''}');
    _keyCtrl = TextEditingController(text: '${widget.data['api_key'] ?? ''}');
    _modelCtrl.addListener(_onModelTextChanged);
  }

  void _onModelTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _modelCtrl.removeListener(_onModelTextChanged);
    _labelCtrl.dispose();
    _modelCtrl.dispose();
    _storyModelCtrl.dispose();
    _fallbackModelCtrl.dispose();
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (guardOfflineCtx(context, context.read<LocaleProvider>().s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
    final s = context.read<LocaleProvider>().s;
    setState(() => _busy = true);
    try {
      await _svc.saveAiProvider(
        id: widget.isNew ? null : '${widget.data['id']}',
        label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        apiBase: _baseCtrl.text.trim().isEmpty ? null : _baseCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim().isEmpty ? null : _keyCtrl.text.trim(),
        defaultModel: _modelCtrl.text.trim().isEmpty
            ? null
            : _modelCtrl.text.trim(),
        storyModel: _storyModelCtrl.text.trim().isEmpty
            ? null
            : _storyModelCtrl.text.trim(),
        fallbackModel: _fallbackModelCtrl.text.trim().isEmpty
            ? null
            : _fallbackModelCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderSaved)));
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  Future<void> _activate() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _activating = true);
    try {
      await _svc.activateAiProvider('${widget.data['id']}');
      if (!mounted) return;
      setState(() => _activating = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderActivated)));
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _activating = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  Future<void> _delete() async {
    final s = context.read<LocaleProvider>().s;
    // Tangkap messenger + callback SEBELUM await: card bisa ter-unmount
    // saat RPC berjalan (rebuild parent) — feedback + refresh list harus
    // tetap jalan walau card sudah tidak mounted (bug "hapus tapi muncul lagi").
    final messenger = ScaffoldMessenger.of(context);
    final notifyChanged = widget.onChanged;
    dlog('[DELPROV] open confirm id=${widget.data['id']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.aiProviderDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDelete,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      dlog('[DELPROV] abort ok=$ok mounted=$mounted');
      return;
    }
    dlog('[DELPROV] confirmed, starting');
    setState(() => _busy = true);
    try {
      final id = '${widget.data['id']}';
      final isActive = widget.data['is_active'] == true && !widget.isNew;
      dlog('[DELPROV] id=$id isActive=$isActive isNew=${widget.isNew}');
      if (isActive) {
        // Hapus provider AKTIF: pindahkan status aktif ke provider lain
        // dulu (failover) supaya RPC tidak menolak. Kalau ini satu-satunya
        // provider → tolak dengan pesan jelas (jangan hapus diam-diam).
        final all = await _svc.getAiProviders();
        Map<String, dynamic>? next;
        for (final p in all) {
          if ('${p['id']}' == id) continue;
          next ??= p;
          if ((p['api_key'] as String? ?? '').isNotEmpty) {
            next = p;
            break;
          }
        }
        if (next == null) {
          dlog('[DELPROV] last provider, blocked');
          messenger
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(s.aiProviderDeleteLast)));
          return;
        }
        dlog('[DELPROV] failover to ${next['id']}');
        await _svc.activateAiProvider('${next['id']}');
        dlog('[DELPROV] failover ok');
      }
      dlog('[DELPROV] calling delete RPC (mounted=$mounted)');
      await _svc.deleteAiProvider('${widget.data['id']}');
      dlog('[DELPROV] delete RPC ok (mounted=$mounted)');
      // Sengaja TANPA cek mounted: messenger + onChanged milik ancestor
      // yang tetap hidup — user wajib dapat feedback + list refresh
      // meski card ini sudah ter-unmount.
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderDeleted)));
      notifyChanged();
    } catch (e) {
      dlog('[DELPROV] ERROR: $e (mounted=$mounted)');
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$e'.contains('PROVIDER_LAST_ACTIVE')
                  ? s.aiProviderDeleteLast
                  : s.aiProviderDeleteActive,
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final active = widget.data['is_active'] == true && !widget.isNew;
    final model = '${widget.data['default_model'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppTheme.primary
              : AppTheme.textSecondary.withValues(alpha: 0.25),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  widget.isNew
                      ? const Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppTheme.primary,
                          size: 22,
                        )
                      : _activating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Radio<bool>(
                          value: true,
                          groupValue: active ? true : null,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) {
                            if (!active) _activate();
                          },
                        ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isNew
                              ? s.aiProviderAdd
                              : '${widget.data['label'] ?? widget.data['id'] ?? ''}',
                          style: AppText.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!widget.isNew && model.isNotEmpty)
                          Text(
                            model,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.aiProviderActive,
                        style: AppText.label.copyWith(color: AppTheme.primary),
                      ),
                    ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _labelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(labelText: s.aiProviderLabel),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.aiProviderModelPreset,
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _matchedModelId(),
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiProviderModelPreset,
                    ),
                    items: [
                      for (final id in _modelChoices())
                        DropdownMenuItem(
                          value: id,
                          child: Text(
                            id,
                            style: AppText.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _modelSel = id;
                        _modelCtrl.text = id;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(labelText: s.aiGlobalModel),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _storyModelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiProviderStoryModel,
                      helperText: s.aiProviderStoryModelHint,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fallbackModelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiProviderFallbackModel,
                      helperText: s.aiProviderFallbackModelHint,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiGlobalBaseUrl,
                      helperText: s.aiGlobalProviderHint,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: true,
                    style: AppText.body,
                    decoration: InputDecoration(labelText: s.aiGlobalApiKey),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!widget.isNew)
                        TextButton.icon(
                          onPressed: _busy ? null : _delete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.danger,
                          ),
                          label: Text(
                            s.btnDelete,
                            style: const TextStyle(color: AppTheme.danger),
                          ),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          widget.isNew ? s.aiProviderAdd : s.aiProviderSave,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
