import 'package:flutter/material.dart';

/// Unlock condition for a mission
class UnlockCondition {
  final String type; // 'total_coins', 'level', 'claim_welcome'
  final int value;

  const UnlockCondition({required this.type, required this.value});

  factory UnlockCondition.fromJson(Map<String, dynamic> json) {
    return UnlockCondition(
      type: json['type'] ?? 'total_coins',
      value: (json['value'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'value': value};
}

/// Mission model - represents a single mission definition
class Mission {
  final int id;
  final String missionKey;
  final String title;
  final String description;
  final String category;
  final int targetValue;
  final String targetUnit;
  final int rewardCoins;
  final bool isDaily;
  final bool isLocked;
  final UnlockCondition? unlockCondition;
  final TimeOfDay? scheduleStart;
  final TimeOfDay? scheduleEnd;
  final int displayOrder;

  // Progress tracking
  int progress;
  bool isCompleted;
  bool claimed;
  DateTime? completedAt;

  Mission({
    required this.id,
    required this.missionKey,
    required this.title,
    required this.description,
    required this.category,
    required this.targetValue,
    required this.targetUnit,
    this.rewardCoins = 0,
    this.isDaily = false,
    this.isLocked = false,
    this.unlockCondition,
    this.scheduleStart,
    this.scheduleEnd,
    this.displayOrder = 0,
    this.progress = 0,
    this.isCompleted = false,
    this.claimed = false,
    this.completedAt,
  });

  factory Mission.fromJson(Map<String, dynamic> json) {
    TimeOfDay? parseTime(String? t) {
      if (t == null || t.isEmpty) return null;
      final parts = t.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
      return null;
    }

    return Mission(
      id: (json['id'] as num?)?.toInt() ?? 0,
      missionKey: json['mission_key'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      targetValue: (json['target_value'] as num?)?.toInt() ?? 0,
      targetUnit: json['target_unit'] ?? '',
      rewardCoins: (json['reward_coins'] as num?)?.toInt() ?? 0,
      isDaily: json['is_daily'] == true,
      isLocked: json['is_locked'] == true,
      unlockCondition: json['unlock_condition'] != null
          ? UnlockCondition.fromJson(json['unlock_condition'])
          : null,
      scheduleStart: parseTime(json['schedule_start']),
      scheduleEnd: parseTime(json['schedule_end']),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      isCompleted: json['is_completed'] == true,
      claimed: json['claimed'] == true,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mission_key': missionKey,
    'title': title,
    'description': description,
    'category': category,
    'target_value': targetValue,
    'target_unit': targetUnit,
    'reward_coins': rewardCoins,
    'is_daily': isDaily,
    'is_locked': isLocked,
    'unlock_condition': unlockCondition?.toJson(),
    'display_order': displayOrder,
    'progress': progress,
    'is_completed': isCompleted,
    'claimed': claimed,
    'completed_at': completedAt?.toIso8601String(),
  };

  Mission copyWith({
    int? progress,
    bool? isCompleted,
    bool? claimed,
    DateTime? completedAt,
    bool? isLocked,
  }) =>
      Mission(
        id: id,
        missionKey: missionKey,
        title: title,
        description: description,
        category: category,
        targetValue: targetValue,
        targetUnit: targetUnit,
        rewardCoins: rewardCoins,
        isDaily: isDaily,
        isLocked: isLocked ?? this.isLocked,
        unlockCondition: unlockCondition,
        scheduleStart: scheduleStart,
        scheduleEnd: scheduleEnd,
        displayOrder: displayOrder,
        progress: progress ?? this.progress,
        isCompleted: isCompleted ?? this.isCompleted,
        claimed: claimed ?? this.claimed,
        completedAt: completedAt ?? this.completedAt,
      );

  bool get isUnlocked => !isLocked;
  bool get canClaim => isCompleted && !claimed;
}

/// Mission progress data for a user
class MissionProgress {
  final List<Mission> mainMissions;
  final List<Mission> dailyMissions;
  final int totalCoins;

  /// Sign-in streak (halaman Bonus): 0 = belum klaim hari ini, 1..7 =
  /// hari siklus berjalan. Grid 7 hari digambar dari nilai ini.
  final int loginStreak;

  /// Tanggal terakhir klaim (yyyy-mm-dd) — null = belum pernah.
  final String? lastLoginDate;

  /// Gender user — seksi sign-in hanya untuk male.
  final String? gender;

  const MissionProgress({
    this.mainMissions = const [],
    this.dailyMissions = const [],
    this.totalCoins = 0,
    this.loginStreak = 0,
    this.lastLoginDate,
    this.gender,
  });

  factory MissionProgress.fromJson(Map<String, dynamic> json) {
    // Toleran tipe: main/daily yang bukan List tidak boleh melempar.
    final main = json['main'] is List
        ? (json['main'] as List).map((m) => Mission.fromJson(m)).toList()
        : <Mission>[];
    final daily = json['daily'] is List
        ? (json['daily'] as List).map((m) => Mission.fromJson(m)).toList()
        : <Mission>[];

    return MissionProgress(
      mainMissions: main,
      dailyMissions: daily,
      totalCoins: (json['total_coins'] as num?)?.toInt() ?? 0,
      loginStreak: (json['login_streak'] as num?)?.toInt() ?? 0,
      lastLoginDate: json['last_login_date'] as String?,
      gender: json['gender'] as String?,
    );
  }
}