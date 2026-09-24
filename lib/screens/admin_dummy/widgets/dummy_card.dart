import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import 'section_card.dart';
import 'dummy_ai_sheet.dart' show parseAiHours;

/// Jam:menit WIB dari ISO string — netral bahasa (netral di semua locale).
String _wibClock(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final wib = dt.toUtc().add(const Duration(hours: 7));
  return '${wib.hour.toString().padLeft(2, '0')}:${wib.minute.toString().padLeft(2, '0')}';
}

int _sleepHash(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)).toSigned(32);
  }
  return h.abs();
}

({int sleepHour, int wakeHour}) _sleepSpec(String uid, String dateWib) {
  final h = _sleepHash('$uid|$dateWib|sleep');
  return (sleepHour: 20 + (h % 4), wakeHour: 4 + ((h ~/ 4) % 3));
}

/// True bila dummy sedang jam tidur menurut jadwal server (WIB).
bool _isAsleepNow(String uid, DateTime now) {
  final wib = now.toUtc().add(const Duration(hours: 7));
  final date =
      '${wib.year.toString().padLeft(4, '0')}-${wib.month.toString().padLeft(2, '0')}-${wib.day.toString().padLeft(2, '0')}';
  final spec = _sleepSpec(uid, date);
  return wib.hour >= spec.sleepHour || wib.hour < spec.wakeHour;
}

/// ai_wake_until masih berlaku → dibangunkan paksa (balasan + online).
bool _isWakeActive(Map<String, dynamic> item, DateTime now) {
  final raw = '${item['ai_wake_until'] ?? ''}';
  if (raw.isEmpty) return false;
  final until = DateTime.tryParse(raw);
  return until != null && until.isAfter(now);
}

// Warna status dgn tambahan 'invisible' (khas admin — bukan status app).
Color _statusColor(String status) =>
    status == 'invisible' ? const Color(0xFF7E57C2) : AppTheme.statusColor(status);

String _genderLabel(S s, String? gender) =>
    gender == 'female' ? s.labelGenderFemale : s.labelGenderMale;

/// Kartu satu dummy: identitas + chip tidur + unread + tombol jadwal/story
/// + baris aksi (dropdown status, chip AI, ikon wake/invisible/edit/chat/hapus).
/// Aksi diteruskan ke pemilik via callback (I/O tetap di screen).
class DummyCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final S s;
  final VoidCallback onSchedule;
  final VoidCallback onStories;
  final ValueChanged<String> onStatus;
  final VoidCallback onWake;
  final VoidCallback onToggleInvisible;
  final VoidCallback onEdit;
  final VoidCallback onChatAs;
  final VoidCallback onDelete;
  final VoidCallback onAiSheet;

  const DummyCard({
    super.key,
    required this.item,
    required this.s,
    required this.onSchedule,
    required this.onStories,
    required this.onStatus,
    required this.onWake,
    required this.onToggleInvisible,
    required this.onEdit,
    required this.onChatAs,
    required this.onDelete,
    required this.onAiSheet,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = item['nickname'] as String? ?? '';
    final status = item['status'] as String? ?? 'offline';
    final gender = item['gender'] as String? ?? 'male';
    final age = (item['age'] as num?)?.toInt();
    final city = item['city'] as String? ?? '';
    final unread = (item['unread'] as num?)?.toInt() ?? 0;
    final info = [
      _genderLabel(s, gender),
      if (age != null) '$age',
      if (city.isNotEmpty) city,
    ].join(' · ');
    // Profesi dari ai_persona (data, tampil apa adanya). Dipadatkan:
    // potong catatan kurung (RAHASIA/JADWAL) supaya muat satu baris.
    final rawProfession =
        ((item['ai_persona'] as Map?)?['profession'] as String?)?.trim() ?? '';
    final profession = rawProfession.split('(').first.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    nickname.isEmpty
                        ? '?'
                        : nickname.characters.first.toUpperCase(),
                    style: AppText.label.copyWith(color: AppTheme.primary),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodyStrong,
                            ),
                          ),
                          // Badge EXPERT: dari kolom `kind` (bukan nickname).
                          if ((item['kind'] as String? ?? 'regular') ==
                              'expert') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 11,
                                    color: AppTheme.accent,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    s.dummyKindExpert,
                                    style: AppText.caption.copyWith(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (info.isNotEmpty)
                        Text(
                          info,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      if (profession.isNotEmpty)
                        Text(
                          profession,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppTheme.accent,
                          ),
                        ),
                      _sleepChip(item, s),
                    ],
                  ),
                ),
                if (unread > 0) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mark_chat_unread,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '$unread',
                          style: AppText.label.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
                // Info jadwal AI (kapan online/offline dari cron) — klik.
                // (Tanpa Spacer: Expanded kolom teks sudah mendorong tombol
                // ini ke kanan; Spacer malah memakan setengah lebar teks.)
                IconButton(
                  icon: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: s.dummyAiScheduleTitle,
                  onPressed: onSchedule,
                ),
                // Story harian — HANYA dummy biasa (expert tak punya story).
                if ((item['kind'] as String? ?? 'regular') == 'regular')
                  IconButton(
                    icon: Icon(
                      Icons.auto_stories_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: s.dummyStoryList,
                    onPressed: onStories,
                  ),
              ],
            ),
            SizedBox(height: 8),
            // Baris aksi: dropdown status + chip AI (kiri), 4 tombol ikon
            // kanan mepet tanpa celah (InkWell padding 6 — bukan IconButton
            // yang memaksa min touch-target 48).
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _statusDropdown(item, status, s),
                ),
                const SizedBox(width: 6),
                _aiChip(item, s),
                _iconBtn(
                  tooltip: s.dummyWake,
                  icon: _isWakeActive(item, DateTime.now())
                      ? Icons.alarm_on
                      : Icons.alarm_add_outlined,
                  color: _isWakeActive(item, DateTime.now())
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  onTap: onWake,
                ),
                _iconBtn(
                  tooltip: s.statusInvisible,
                  icon: status == 'invisible'
                      ? Icons.visibility_off
                      : Icons.visibility_off_outlined,
                  color: status == 'invisible'
                      ? _statusColor('invisible')
                      : AppTheme.textSecondary,
                  onTap: onToggleInvisible,
                ),
                _iconBtn(
                  tooltip: s.dummyEdit,
                  icon: Icons.edit_outlined,
                  color: AppTheme.textSecondary,
                  onTap: onEdit,
                ),
                _iconBtn(
                  tooltip: s.dummyChatAs,
                  icon: Icons.chat_bubble_outline,
                  color: AppTheme.primary,
                  onTap: onChatAs,
                ),
                _iconBtn(
                  tooltip: s.dummyDelete,
                  icon: Icons.delete_outline,
                  color: AppTheme.danger,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dropdown status dummy (online/idle/offline/invisible) — nilai aktif
  /// langsung terlihat; ganti nilai = set status via RPC yang sama seperti
  /// chip dulu. Invisible = user lain lihat offline & tidak muncul di
  /// daftar online (cron AI tidak menimpa).
  Widget _statusDropdown(Map<String, dynamic> item, String current, S s) {
    const values = ['online', 'idle', 'offline', 'invisible'];
    final labels = [
      s.statusOnline,
      s.statusIdle,
      s.statusOffline,
      s.statusInvisible,
    ];
    final safeValue = values.contains(current) ? current : 'offline';
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      isDense: true,
      style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: [
        for (var i = 0; i < values.length; i++)
          DropdownMenuItem(
            value: values[i],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(values[i]),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(
                      color: _statusColor(values[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != current) onStatus(v);
      },
    );
  }

  /// Chip AI dummy: ON = aksen solid + ikon terisi putih, OFF = abu
  /// netral + ikon outline — beda tegas sekilas (bukan samar).
  /// Tap = buka sheet persona.
  Widget _aiChip(Map<String, dynamic> item, S s) {
    final aiOn = item['ai_enabled'] == true;
    final offColor = AppTheme.textSecondary;
    return InkWell(
      onTap: onAiSheet,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: aiOn ? AppTheme.accent : offColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: aiOn
              ? null
              : Border.all(color: offColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              aiOn ? Icons.smart_toy : Icons.smart_toy_outlined,
              size: 13,
              color: aiOn ? Colors.white : offColor,
            ),
            const SizedBox(width: 4),
            Text(
              s.dummyAiChip,
              style: AppText.label.copyWith(
                color: aiOn ? Colors.white : offColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chip Tidur/Bangun di kartu dummy — bedakan "AI error" vs "lagi tidur":
  /// Bangun paksa (wake aktif, teks + jam s/d) / Bangun (jam melek) / Tidur.
  /// Dihitung dari jam tidur server + ai_wake_until (konsisten dgn gate).
  /// Kalau ai_active_hours mencakup jam sekarang → paksa bangun (online 24j).
  Widget _sleepChip(Map<String, dynamic> item, S s) {
    final now = DateTime.now();
    final wakeActive = _isWakeActive(item, now);
    // Cek apakah jam sekarang ada di ai_active_hours → dummy bangun.
    final wib = now.toUtc().add(const Duration(hours: 7));
    final activeHours = parseAiHours(item['ai_active_hours']);
    final inActiveHours = activeHours.contains(wib.hour);
    final asleep =
        !wakeActive && !inActiveHours && _isAsleepNow('${item['uid'] ?? ''}', now);
    final label = wakeActive
        ? '${s.dummyAwake} • ${s.dummyWakeUntil.replaceFirst('%s', _wibClock('${item['ai_wake_until'] ?? ''}'))}'
        : asleep
            ? s.dummyAsleep
            : s.dummyAwake;
    final color = asleep ? AppTheme.textSecondary : AppTheme.online;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            asleep ? Icons.bedtime_outlined : Icons.alarm_on_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Tombol ikon kartu dummy yang mepet: InkWell padding 4 (total 28px),
  /// tanpa min touch-target 48 ala IconButton. Visual ikon 20, jarak
  /// antar-ikon = 8px.
  Widget _iconBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
