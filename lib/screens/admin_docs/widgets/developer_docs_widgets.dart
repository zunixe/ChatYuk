import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/theme_provider.dart';
import '../../admin_panel/widgets/panel_card.dart';
import 'flow_diagram.dart';
import '../../../config/strings_docs.dart' show SDocsX;

/// Daftar dokumentasi DEVELOPER — arsitektur & service ChatYuk.
/// Termasuk diagram alur (ASCII, scroll horizontal) di bagian atas.
class DeveloperDocsList extends ConsumerWidget {
  final String query;
  const DeveloperDocsList({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final q = query.trim().toLowerCase();

    // Diagram: judul + art + kata kunci pencarian.
    final diagrams = <_Diagram>[
      _Diagram(
        s.docsDevLayerDiagramTitle,
        s.docsDevLayerDiagram,
        'layer lapisan arsitektur architecture stack',
        Icons.layers_outlined,
        Colors.blue,
      ),
      _Diagram(
        s.docsDevMessageFlowTitle,
        s.docsDevMessageFlow,
        'pesan message chat send kirim composer outbox realtime',
        Icons.forum_outlined,
        Colors.green,
      ),
      _Diagram(
        s.docsDevNotifFlowTitle,
        s.docsDevNotifFlow,
        'notifikasi notification outbox worker fcm push fanout',
        Icons.notifications_active_outlined,
        Colors.orange,
      ),
      _Diagram(
        s.docsDevCallFlowTitle,
        s.docsDevCallFlow,
        'call panggilan webrtc turn signal ringing billing',
        Icons.call_outlined,
        Colors.teal,
      ),
      _Diagram(
        s.docsDevCoinFlowTitle,
        s.docsDevCoinFlow,
        'koin coin ekonomi economy topup charge gift ledger',
        Icons.monetization_on_outlined,
        Colors.amber,
      ),
    ];

    final sections = <_DocSection>[
      _DocSection(s.docsDevLayersTitle, s.docsDevLayersBody, Icons.layers_outlined, Colors.blue),
      _DocSection(s.docsDevBackendTitle, s.docsDevBackendBody, Icons.storage_outlined, Colors.teal),
      _DocSection(s.docsDevEdgeTitle, s.docsDevEdgeBody, Icons.bolt_outlined, Colors.orange),
      _DocSection(s.docsDevRealtimeTitle, s.docsDevRealtimeBody, Icons.sync_outlined, Colors.green),
      _DocSection(s.docsDevCacheTitle, s.docsDevCacheBody, Icons.sd_card_outlined, Colors.purple),
      _DocSection(s.docsDevServicesTitle, s.docsDevServicesBody, Icons.handyman_outlined, Colors.indigo),
      _DocSection(s.docsDevProvidersTitle, s.docsDevProvidersBody, Icons.folder_outlined, Colors.cyan),
      _DocSection(s.docsDevModelsTitle, s.docsDevModelsBody, Icons.widgets_outlined, Colors.blueGrey),
      _DocSection(s.docsDevEconomyTitle, s.docsDevEconomyBody, Icons.monetization_on_outlined, Colors.amber),
      _DocSection(s.docsDevErrorsTitle, s.docsDevErrorsBody, Icons.error_outline, Colors.deepOrange),
      _DocSection(s.docsDevTestsTitle, s.docsDevTestsBody, Icons.verified_outlined, Colors.lightGreen),
      _DocSection(s.docsDevAdminPanelTitle, s.docsDevAdminPanelBody, Icons.admin_panel_settings_outlined, Colors.cyan),
      _DocSection(s.docsDevBuildTitle, s.docsDevBuildBody, Icons.build_outlined, Colors.red),
    ];

    // Saat ada query, diagram cocok bila judul/art/keyword mengandungnya.
    final shownDiagrams = q.isEmpty
        ? diagrams
        : diagrams
            .where((d) =>
                d.title.toLowerCase().contains(q) ||
                d.art.toLowerCase().contains(q) ||
                d.keywords.contains(q))
            .toList();
    final shownSections = q.isEmpty
        ? sections
        : sections
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.body.toLowerCase().contains(q))
            .toList();

    if (shownDiagrams.isEmpty && shownSections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            s.adminDocsEmpty,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Bagian diagram ──
        if (shownDiagrams.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(s.docsDevDiagramsTitle, style: AppText.titleEmphasis),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.docsDevDiagramsIntro,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          for (final d in shownDiagrams)
            FlowDiagram(
              title: d.title,
              art: d.art,
              hint: s.docsDevDiagramNoWrap,
              icon: d.icon,
              color: d.color,
            ),
          const SizedBox(height: 6),
        ],
        // ── Bagian teks ──
        for (var i = 0; i < shownSections.length; i++) ...[
          PanelCard(
            shownSections[i].title,
            shownSections[i].icon,
            shownSections[i].color,
            [
              Text(
                shownSections[i].body,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          if (i < shownSections.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Diagram {
  final String title;
  final String art;
  final String keywords;
  final IconData icon;
  final Color color;
  const _Diagram(this.title, this.art, this.keywords, this.icon, this.color);
}

class _DocSection {
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  const _DocSection(this.title, this.body, this.icon, this.color);
}
