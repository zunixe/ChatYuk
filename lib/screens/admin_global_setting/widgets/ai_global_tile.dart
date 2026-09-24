import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';
import 'provider_section.dart';

/// AI Bot global: master switch semua balasan AI dummy + rate limit
/// (maks balasan per chat per jam & jeda minimal antar balasan).
class AiGlobalTile extends StatefulWidget {
  const AiGlobalTile({super.key});

  @override
  State<AiGlobalTile> createState() => _AiGlobalTileState();
}

class _AiGlobalTileState extends State<AiGlobalTile> {
  AdminProvider get _svc => context.read<AdminProvider>();
  bool _loading = true;
  bool _globalEnabled = true;
  int _maxReplies = 20;
  int _minInterval = 2;
  bool _guardEnabled = true;
  bool _aiAiEnabled = true;
  String _activeLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await _svc.getAiSettings();
      List<Map<String, dynamic>> providers = const [];
      try {
        providers = await _svc.getAiProviders();
      } catch (_) {}
      if (!mounted) return;
      String activeLabel = '';
      for (final p in providers) {
        if (p['is_active'] == true) {
          activeLabel = '${p['label'] ?? p['id'] ?? ''}';
          break;
        }
      }
      setState(() {
        _globalEnabled = st['ai_global_enabled'] != false;
        _maxReplies = (st['ai_max_replies_per_hour'] as num?)?.toInt() ?? 20;
        _minInterval = (st['ai_min_interval_sec'] as num?)?.toInt() ?? 2;
        _guardEnabled = st['ai_guard_enabled'] != false;
        _aiAiEnabled = st['ai_ai_chat_enabled'] != false;
        _activeLabel = activeLabel;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool v) async {
    if (guardOfflineCtx(context, context.read<LocaleProvider>().s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
    setState(() => _globalEnabled = v);
    try {
      await _svc.setAiSettings(globalEnabled: v);
    } catch (_) {
      if (mounted) setState(() => _globalEnabled = !v);
    }
  }

  Future<void> _openAiBotSheet() async {
    final maxCtrl = TextEditingController(text: '$_maxReplies');
    final minCtrl = TextEditingController(text: '$_minInterval');
    bool guardTmp = _guardEnabled;
    bool aiAiTmp = _aiAiEnabled;
    final s = context.read<LocaleProvider>().s;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom:
                20 +
                MediaQuery.viewInsetsOf(ctx).bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.aiGlobalTitle,
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: maxCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppText.body,
                  decoration: InputDecoration(labelText: s.aiGlobalMaxReplies),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppText.body,
                  decoration: InputDecoration(labelText: s.aiGlobalMinInterval),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.aiGlobalGuardTitle, style: AppText.body),
                          Text(
                            s.aiGlobalGuardDesc,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: guardTmp,
                      onChanged: (v) => setSheetState(() => guardTmp = v),
                      activeThumbColor: AppTheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.aiAiChatTitle, style: AppText.body),
                          Text(
                            s.aiAiChatDesc,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: aiAiTmp,
                      onChanged: (v) => setSheetState(() => aiAiTmp = v),
                      activeThumbColor: AppTheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final max =
                        int.tryParse(maxCtrl.text.trim()) ?? _maxReplies;
                    final min =
                        int.tryParse(minCtrl.text.trim()) ?? _minInterval;
                    try {
                      await _svc.setAiSettings(
                        maxReplies: max,
                        minInterval: min,
                        guardEnabled: guardTmp,
                        aiAiEnabled: aiAiTmp,
                      );
                      if (!mounted) return;
                      setState(() {
                        _maxReplies = max;
                        _minInterval = min;
                        _guardEnabled = guardTmp;
                        _aiAiEnabled = aiAiTmp;
                      });
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(content: Text(s.aiGlobalSaved)),
                          );
                      }
                    } catch (_) {}
                  },
                  child: Text(s.btnSave),
                ),
                const SizedBox(height: 16),
                Text(s.aiProviderListTitle, style: AppText.bodyStrong),
                const ProviderListSection(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    maxCtrl.dispose();
    minCtrl.dispose();
    // Refresh label provider aktif setelah sheet ditutup.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              color: AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.aiGlobalTitle,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.aiGlobalDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${s.aiGlobalMaxReplies}: $_maxReplies · ${s.aiGlobalMinInterval}: $_minInterval · ${s.aiGlobalGuardTitle}: ${_guardEnabled ? 'ON' : 'OFF'} · ${s.aiAiChatTitle}: ${_aiAiEnabled ? 'ON' : 'OFF'}${_activeLabel.isNotEmpty ? ' · $_activeLabel' : ''}',
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            color: AppTheme.primary,
            tooltip: s.aiGlobalTitle,
            onPressed: _loading ? null : _openAiBotSheet,
          ),
          _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: _globalEnabled,
                  onChanged: _toggle,
                  activeThumbColor: AppTheme.primary,
                ),
        ],
      ),
    );
  }
}
