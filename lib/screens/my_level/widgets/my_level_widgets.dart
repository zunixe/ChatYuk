import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../profile/widgets/profile_widgets.dart' show formatPoints;

/// Seksi Privileges My Level: chip tab Lv.0–Lv.10 (horizontal) + daftar
/// privilege level terpilih (badge level + bonus koin naik level).
class MyLevelPrivileges extends StatelessWidget {
  final List<Map<String, dynamic>> ladder;
  final int selected;
  final ValueChanged<int> onSelect;
  final S s;

  const MyLevelPrivileges({
    super.key,
    required this.ladder,
    required this.selected,
    required this.onSelect,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final row = ladder
        .map((e) => (level: (e['level'] as num?)?.toInt() ?? 0,
            reward: (e['reward_coins'] as num?)?.toInt() ?? 0))
        .toList();
    final sel = row.where((e) => e.level == selected).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            s.myLevelPrivileges,
            style: AppText.label.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: row.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = row[i];
              final active = e.level == selected;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelect(e.level),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.primary
                        : AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active ? AppTheme.primary : AppTheme.divider,
                    ),
                  ),
                  child: Text(
                    s.levelShort(e.level),
                    style: AppText.label.copyWith(
                      color: active ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _PrivilegeCard(
          children: sel == null || (sel.level == 0 && sel.reward == 0)
              ? [
                  _PrivilegeEmpty(text: s.myLevelPrivNone),
                ]
              : [
                  _PrivilegeTile(
                    icon: Icons.workspace_premium,
                    titleKey: _PrivTitle.badge,
                    s: s,
                  ),
                  if (sel.reward > 0)
                    _PrivilegeTile(
                      icon: Icons.savings_outlined,
                      titleKey: _PrivTitle.reward,
                      rewardCoins: sel.reward,
                      s: s,
                    ),
                ],
        ),
      ],
    );
  }
}

/// Kartu Aturan Level: tabel Level | Top Up 🪙 | Bonus, baris level aktif
/// disorot.
class MyLevelRuleTable extends StatelessWidget {
  final List<Map<String, dynamic>> ladder;
  final int current;
  final S s;

  const MyLevelRuleTable({
    super.key,
    required this.ladder,
    required this.current,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 2),
          child: Text(
            s.myLevelRule,
            style: AppText.label.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            s.myLevelRuleDesc,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              _RuleRow.header(s),
              for (final e in ladder)
                _RuleRow(
                  level: (e['level'] as num?)?.toInt() ?? 0,
                  topup: (e['topup_coins'] as num?)?.toInt() ?? 0,
                  reward: (e['reward_coins'] as num?)?.toInt() ?? 0,
                  current: (e['level'] as num?)?.toInt() == current,
                  s: s,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _PrivTitle { badge, reward }

class _PrivilegeCard extends StatelessWidget {
  final List<Widget> children;
  const _PrivilegeCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: AppTheme.divider.withValues(alpha: 0.6)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PrivilegeTile extends StatelessWidget {
  final IconData icon;
  final _PrivTitle titleKey;
  final int rewardCoins;
  final S s;
  const _PrivilegeTile({
    required this.icon,
    required this.titleKey,
    required this.s,
    this.rewardCoins = 0,
  });

  @override
  Widget build(BuildContext context) {
    final title = titleKey == _PrivTitle.badge
        ? s.myLevelPrivBadge
        : s.myLevelPrivReward;
    final desc = titleKey == _PrivTitle.badge
        ? s.myLevelPrivBadgeDesc
        : s.myLevelPrivRewardDesc(rewardCoins);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.bodyStrong.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivilegeEmpty extends StatelessWidget {
  final String text;
  const _PrivilegeEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(
            child: Text(
              text,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final int level;
  final int topup;
  final int reward;
  final bool current;
  final S s;

  const _RuleRow({
    required this.level,
    required this.topup,
    required this.reward,
    required this.s,
    this.current = false,
  });

  const _RuleRow.header(this.s)
    : level = -1,
      topup = -1,
      reward = -1,
      current = false;

  @override
  Widget build(BuildContext context) {
    final isHeader = level < 0;
    final bg = current
        ? AppTheme.primary.withValues(alpha: 0.10)
        : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isHeader ? AppTheme.bgScreen.withValues(alpha: 0.5) : bg,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              isHeader ? s.myLevelColLevel : s.levelShort(level),
              style: AppText.bodyStrong.copyWith(
                color: isHeader
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              isHeader ? s.myLevelColTopup : formatPoints(topup),
              textAlign: TextAlign.right,
              style: AppText.bodyStrong.copyWith(
                color: isHeader
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isHeader
                  ? s.myLevelColReward
                  : reward > 0
                  ? '+${formatPoints(reward)}'
                  : '—',
              textAlign: TextAlign.right,
              style: AppText.bodyStrong.copyWith(
                color: isHeader
                    ? AppTheme.textSecondary
                    : reward > 0
                    ? Colors.amber.shade700
                    : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
