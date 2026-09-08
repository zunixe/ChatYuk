import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../providers/locale_provider.dart';
import '../services/private_room_service.dart';
import '../services/room_service.dart';
import 'group_media_screen.dart';
import 'room_members_sheet.dart';

/// Layar info grup ala WA: ikon, nama, deskripsi, pemilik, anggota,
/// dibuat, expiry + token undangan (owner). Dibuka dari menu ⋮ grup.
class GroupInfoScreen extends StatefulWidget {
  final RoomModel room;
  final String myRole; // owner | admin | member
  const GroupInfoScreen({super.key, required this.room, required this.myRole});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<Map<String, dynamic>> _members = [];
  String? _joinToken;
  bool _loading = true;

  bool get _isOwner => widget.myRole == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members =
          await PrivateRoomService.instance.listMembers(widget.room.id);
      String? token;
      if (_isOwner) {
        final row = await RoomService().fetchRoomById(widget.room.id);
        token = '${row?['join_token'] ?? ''}';
      }
      if (!mounted) return;
      setState(() {
        _members = members;
        _joinToken = (token != null && token.isNotEmpty) ? token : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateStr(DateTime? d, S s) {
    if (d == null) return '-';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final m = d.month >= 1 && d.month <= 12 ? months[d.month] : '';
    return '${d.day} $m ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final room = widget.room;
    final expired = room.expiresAt != null &&
        room.expiresAt!.isBefore(DateTime.now());
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.menuGroupInfo, style: AppText.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(room.icon,
                          style: const TextStyle(fontSize: 44)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(room.name,
                      style: AppText.title
                          .copyWith(color: AppTheme.textPrimary)),
                ),
                if (room.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(room.description,
                        textAlign: TextAlign.center,
                        style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary)),
                  ),
                ],
                const SizedBox(height: 16),
                _row(s.groupInfoOwner,
                    room.ownerName.isNotEmpty ? room.ownerName : '-'),
                _row(
                    '${s.groupInfoMembers} (${_members.length})',
                    _members
                        .take(5)
                        .map((m) => '${m['nickname'] ?? '?'}')
                        .join(', ')),
                _row(s.groupInfoExpiry,
                    room.expiresAt == null
                        ? s.groupInfoPermanent
                        : expired
                            ? s.groupInfoExpired
                            : _dateStr(room.expiresAt, s)),
                if (_isOwner && _joinToken != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: _joinToken!));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(s.groupInfoTokenCopied)));
                    },
                    child: _row(
                        s.groupInfoToken, _joinToken!,
                        trailing: const Icon(Icons.copy_rounded,
                            size: 16, color: AppTheme.primary)),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GroupMediaScreen(room: room),
                            ),
                          );
                        },
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18),
                        label: Text(s.menuGroupMedia),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.85,
                              builder: (_, __) => ClipRRect(
                                borderRadius:
                                    const BorderRadius.vertical(
                                        top: Radius.circular(16)),
                                child: RoomMembersSheet(
                                  roomId: room.id,
                                  myRole: widget.myRole,
                                  onChanged: () =>
                                      setState(() => _load()),
                                ),
                              ),
                            ),
                          ).then((_) {
                            if (mounted) _load();
                          });
                        },
                        icon: const Icon(Icons.group_outlined, size: 18),
                        label: Text(
                            '${s.groupInfoMembers} (${_members.length})'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppText.bodySmall
                    .copyWith(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppText.bodyStrong
                    .copyWith(color: AppTheme.textPrimary)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
