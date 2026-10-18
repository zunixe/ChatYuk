import 'package:flutter/material.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';

/// Pilihan ikon grup (desain 2026-10-18). Ditampilkan sebagai ikon Material,
/// tetapi DISIMPAN sebagai emoji ([emoji]) karena `rooms.icon` & `RoomIcon`
/// di seluruh app memakai emoji — kunci mentah ('chat') akan tampil sebagai
/// teks di daftar grup.
class GroupIconOption {
  final String key;
  final IconData icon;
  final String emoji;
  const GroupIconOption(this.key, this.icon, this.emoji);
}

const List<GroupIconOption> kGroupIcons = [
  GroupIconOption('chat', Icons.chat_bubble_outline_rounded, '💬'),
  GroupIconOption('users', Icons.groups_2_outlined, '👥'),
  GroupIconOption('sparkle', Icons.auto_awesome_outlined, '🎉'),
  GroupIconOption('game', Icons.sports_esports_outlined, '🎮'),
  GroupIconOption('music', Icons.music_note_rounded, '🎵'),
  GroupIconOption('heart', Icons.favorite_border_rounded, '💘'),
  GroupIconOption('flame', Icons.local_fire_department_outlined, '🔥'),
  GroupIconOption('star', Icons.star_outline_rounded, '⭐'),
  GroupIconOption('moon', Icons.nightlight_round, '🌙'),
  GroupIconOption('crown', Icons.workspace_premium_outlined, '👑'),
  GroupIconOption('coffee', Icons.coffee_outlined, '☕'),
  GroupIconOption('lock', Icons.lock_outline_rounded, '🔒'),
];

/// Aturan validasi form (UI). Server hanya mensyaratkan password tidak kosong
/// & nama 3–30; UI lebih ketat untuk password (6–20).
class GroupFormRules {
  static const int nameMin = 3;
  static const int nameMax = 30;
  static const int passMin = 6;
  static const int passMax = 20;
}

/// Isian form yang dikirim ke [CreateGroupSheet.onCreate].
class GroupDraft {
  final String name;
  final String iconKey;
  final String? password;
  const GroupDraft({required this.name, required this.iconKey, this.password});

  bool get withPassword => password != null;

  /// Emoji yang disimpan ke `rooms.icon`.
  String get iconEmoji =>
      kGroupIcons.firstWhere((e) => e.key == iconKey).emoji;
}

/// Gagal buat grup dengan pesan yang ditampilkan DI form (isian tetap ada).
class CreateGroupFailure implements Exception {
  final String message;
  const CreateGroupFailure(this.message);
}

/// Buka sheet "Buat grup". [onCreate] menjalankan pembuatan grup yang sudah
/// ada; kembalikan hasil (mis. map respons) → sheet tertutup dengan hasil itu.
/// Kembalikan null → sheet tertutup tanpa hasil (mis. pemanggil akan
/// menampilkan dialog koin kurang). Lempar [CreateGroupFailure] → pesan
/// tampil di form. [costLabel] (opsional) = info biaya koin per jenis akses.
Future<T?> showCreateGroupSheet<T>(
  BuildContext context, {
  required S s,
  required Future<T?> Function(GroupDraft draft) onCreate,
  String Function(bool withPassword)? costLabel,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        CreateGroupSheet<T>(s: s, onCreate: onCreate, costLabel: costLabel),
  );
}

class CreateGroupSheet<T> extends StatefulWidget {
  final S s;
  final Future<T?> Function(GroupDraft draft) onCreate;
  final String Function(bool withPassword)? costLabel;
  const CreateGroupSheet({
    super.key,
    required this.s,
    required this.onCreate,
    this.costLabel,
  });

  @override
  State<CreateGroupSheet<T>> createState() => _CreateGroupSheetState<T>();
}

class _CreateGroupSheetState<T> extends State<CreateGroupSheet<T>> {
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _iconKey = 'chat';
  bool _withPw = false;
  bool _submitting = false;
  String? _error;

  S get s => widget.s;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_refresh);
    _passCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  String get _name => _nameCtrl.text.trim();
  bool get _nameOk => _name.length >= GroupFormRules.nameMin;
  bool get _passOk =>
      !_withPw || _passCtrl.text.trim().length >= GroupFormRules.passMin;
  bool get _canSubmit => _nameOk && _passOk && !_submitting;

  GroupIconOption get _icon => kGroupIcons.firstWhere((e) => e.key == _iconKey);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final draft = GroupDraft(
      name: _name,
      iconKey: _iconKey,
      password: _withPw ? _passCtrl.text.trim() : null,
    );
    try {
      final res = await widget.onCreate(draft);
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } on CreateGroupFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = s.errCreateGroupRetry;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final len = _nameCtrl.text.length;
    return Container(
      height: media.size.height - 56 - media.padding.top,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _header(),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                16 + media.viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(
                    s.groupNameLabel,
                    trailing: Text(
                      '$len/${GroupFormRules.nameMax}',
                      style: AppText.label.copyWith(
                        color: len >= GroupFormRules.nameMax - 3
                            ? AppTheme.danger
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _nameField(),
                  const SizedBox(height: 6),
                  Text(
                    s.groupNameHelper,
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(
                    s.groupIconTitle,
                    trailing: Text(
                      s.groupIconLabel(_iconKey),
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _iconGrid(),
                  const SizedBox(height: 20),
                  _sectionLabel(s.groupAccessLabel),
                  const SizedBox(height: 10),
                  _accessCard(
                    withPw: false,
                    icon: Icons.all_inclusive_rounded,
                    title: s.groupNoPwTitle,
                    subtitle: s.groupNoPwSubtitle,
                  ),
                  _accessCard(
                    withPw: true,
                    icon: Icons.lock_outline_rounded,
                    title: s.groupPwTitle,
                    subtitle: s.groupPwSubtitle,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _withPw
                        ? _passwordPanel()
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.group_add_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.createGroupTitle,
                  style: AppText.title.copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  s.createGroupSubtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('group_sheet_close'),
            tooltip: s.btnClose,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.bgInput,
              foregroundColor: AppTheme.textSecondary,
              fixedSize: const Size(36, 36),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, {Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            text,
            style: AppText.label.copyWith(color: AppTheme.textPrimary),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _nameField() {
    final empty = _nameCtrl.text.isEmpty;
    final borderColor = empty
        ? AppTheme.bgInput
        : (_nameOk
              ? AppTheme.primary
              : AppTheme.textSecondary.withValues(alpha: 0.35));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 56,
      padding: const EdgeInsets.only(left: 8, right: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon.icon, size: 20, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('group_name'),
              controller: _nameCtrl,
              maxLength: GroupFormRules.nameMax,
              textCapitalization: TextCapitalization.words,
              style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                counterText: '',
                hintText: s.groupNameExample,
                hintStyle: AppText.body.copyWith(
                  color: AppTheme.textSecondary,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                // Tema global memberi contentPadding 16 horizontal — nolkan
                // agar teks rapat 10dp dari kotak ikon (sesuai desain).
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: kGroupIcons.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final opt = kGroupIcons[i];
        final on = opt.key == _iconKey;
        return Semantics(
          button: true,
          selected: on,
          label: s.groupIconLabel(opt.key),
          child: GestureDetector(
            key: ValueKey('group_icon_${opt.key}'),
            onTap: () => setState(() => _iconKey = opt.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: on
                    ? AppTheme.primary.withValues(alpha: 0.16)
                    : AppTheme.bgInput,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on ? AppTheme.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                opt.icon,
                size: 22,
                color: on ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _accessCard({
    required bool withPw,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final on = _withPw == withPw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: ValueKey(withPw ? 'group_access_pw' : 'group_access_open'),
        onTap: () => setState(() {
          _withPw = withPw;
          if (!withPw) _passCtrl.clear();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on
                ? AppTheme.primary.withValues(alpha: 0.10)
                : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: on
                  ? AppTheme.primary
                  : AppTheme.textSecondary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: on
                      ? AppTheme.primary.withValues(alpha: 0.16)
                      : AppTheme.bgInput,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: on ? AppTheme.primary : AppTheme.textSecondary,
                ),
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
                      subtitle,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppTheme.primary : Colors.transparent,
                  border: Border.all(
                    color: on
                        ? AppTheme.primary
                        : AppTheme.textSecondary.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: on
                    ? const Center(
                        child: CircleAvatar(
                          radius: 4,
                          backgroundColor: Colors.white,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.groupPasswordLabel,
            style: AppText.label.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('group_password'),
                    controller: _passCtrl,
                    obscureText: true,
                    maxLength: GroupFormRules.passMax,
                    style: AppText.body.copyWith(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: s.groupPasswordHint,
                      hintStyle: AppText.body.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.groupPasswordHelper,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final cost = widget.costLabel?.call(_withPw);
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.textSecondary.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cost != null) ...[
            Row(
              children: [
                Text('🪙', style: TextStyle(fontSize: AppGlyph.sm)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cost,
                    style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: AppTheme.danger),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const ValueKey('group_submit'),
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.bgInput,
                disabledForegroundColor: AppTheme.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(s.btnCreateGroup),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: TextButton(
              key: const ValueKey('group_cancel'),
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
              ),
              child: Text(s.btnCancel),
            ),
          ),
        ],
      ),
    );
  }
}
