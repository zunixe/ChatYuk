import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../core/media/native_image.dart';
import '../widgets/room_icon.dart';
import 'group_media_screen.dart';
import 'room_members_sheet.dart';
import '../config/theme.dart';

/// Layar info grup ala WA: ikon, nama, deskripsi, pemilik, anggota,
/// dibuat, expiry + token undangan (owner). Dibuka dari menu ⋮ grup.
class GroupInfoScreen extends ConsumerStatefulWidget {
  final RoomModel room;
  final String myRole; // owner | admin | member
  const GroupInfoScreen({super.key, required this.room, required this.myRole});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  List<Map<String, dynamic>> _members = [];
  String? _joinToken;
  bool _loading = true;

  /// Ikon terkini (bisa berubah setelah ganti avatar). Mulai dari room.icon.
  late String _icon = widget.room.icon;
  bool _changingIcon = false;

  bool get _isOwner => widget.myRole == 'owner';
  bool get _canEditIcon =>
      widget.myRole == 'owner' || widget.myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // PARALEL: listMembers & fetchRoomById independen — jangan berurutan
      // (dulu 2 RTT). Satu RTT.
      final rp = ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier);
      final membersF = rp.listMembers(widget.room.id);
      final roomF = _isOwner ? rp.fetchRoomById(widget.room.id) : null;
      final members = await membersF;
      final row = roomF != null ? await roomF : null;
      final token = row == null ? '' : '${row['join_token'] ?? ''}';
      if (!mounted) return;
      setState(() {
        _members = members;
        _joinToken = token.isNotEmpty ? token : null;
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

  /// Ganti ikon/avatar grup: pilih sumber → crop 1:1 → proses → upload
  /// `room-icons/<uid>/...` → RPC update_room_icon → update tampilan.
  Future<void> _changeIcon() async {
    if (_changingIcon || !_canEditIcon) return;
    final s = ref.read(localeProvider).s;
    final uid = ref.read(authProvider.notifier).uid;
    if (uid == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.groupIconCamera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.groupIconGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errPhotoPermission)),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    // Crop interaktif 1:1 — ikon grup bulat/persegi, jadi area dipilih jelas.
    final CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1024,
        maxHeight: 1024,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: s.groupChangeIcon,
            toolbarColor: AppTheme.bgScreen,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppTheme.primary,
            lockAspectRatio: true,
            statusBarLight: !AppTheme.isDark,
          ),
          IOSUiSettings(
              title: s.groupChangeIcon, aspectRatioLockEnabled: true),
        ],
      );
    } catch (_) {
      return;
    }
    if (cropped == null || !mounted) return;

    setState(() => _changingIcon = true);
    try {
      final bytes = await cropped.readAsBytes();
      if (!mounted) return;
      // 512px square + q85 cukup untuk ikon grup (sama pola avatar).
      final b64 = await NativeImage.processSquare(bytes, size: 512, quality: 85);
      if (b64 == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errPhotoProcess)),
          );
        }
        return;
      }
      final path = await ref
          .read(storageProvider)
          .uploadRoomIcon(uid: uid, base64: b64);
      if (path == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errPhotoUpload)),
          );
        }
        return;
      }
      final res = await ref
          .read(roomProvider.notifier)
          .updateRoomIcon(widget.room.id, path);
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() => _icon = path);
        // Segarkan daftar grupku agar ikon baru tampil di tab Grup.
        unawaited(
            ref.read(roomProvider.notifier).loadMyGroups(refresh: true));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.groupIconUpdated)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.groupIconFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.groupIconFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _changingIcon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
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
              // Insets bawah (nav bar) — edge-to-edge Android 15.
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                Center(
                  child: Semantics(
                    button: _canEditIcon,
                    label: _canEditIcon ? s.groupChangeIcon : null,
                    child: GestureDetector(
                    onTap: _canEditIcon ? _changeIcon : null,
                    child: Stack(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Center(
                            child: _changingIcon
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4),
                                  )
                                : RoomIcon(
                                    category: room.category,
                                    emoji: _icon,
                                    size: 88,
                                    roomId: room.id,
                                  ),
                          ),
                        ),
                        // Badge kamera kecil: penanda bisa diganti (owner/admin).
                        if (_canEditIcon)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppTheme.bgScreen, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
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
