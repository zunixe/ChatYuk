/// Visibilitas privacy — 5 pilihan:
/// - [everyone]       : semua orang
/// - [everyoneExcept] : semua orang KECUALI daftar (teman & anon bisa dipilih)
/// - [friends]        : hanya teman
/// - [friendsExcept]  : teman, kecuali daftar
/// - [nobody]         : tidak ada
enum PrivacyVisibility {
  everyone,
  everyoneExcept,
  friends,
  friendsExcept,
  nobody;

  /// Key yang dikirim/dibaca server (snake_case).
  String get wireKey => switch (this) {
    PrivacyVisibility.everyone => 'everyone',
    PrivacyVisibility.everyoneExcept => 'everyone_except',
    PrivacyVisibility.friends => 'friends',
    PrivacyVisibility.friendsExcept => 'friends_except',
    PrivacyVisibility.nobody => 'nobody',
  };

  /// True bila opsi ini memakai daftar pengecualian.
  bool get usesExclusions =>
      this == PrivacyVisibility.everyoneExcept ||
      this == PrivacyVisibility.friendsExcept;

  /// True bila opsi ini hanya untuk teman.
  bool get friendsOnly =>
      this == PrivacyVisibility.friends ||
      this == PrivacyVisibility.friendsExcept;

  static PrivacyVisibility fromWire(dynamic value) {
    // 'except' = nilai lama (pra-migrasi) → dianggap friendsExcept.
    if (value == 'except') return PrivacyVisibility.friendsExcept;
    return PrivacyVisibility.values.firstWhere(
      (v) => v.wireKey == value,
      orElse: () => PrivacyVisibility.everyone,
    );
  }
}

class PrivacySettings {
  final PrivacyVisibility presence;
  final PrivacyVisibility lastSeen;
  final PrivacyVisibility profilePhoto;
  final PrivacyVisibility about;
  final PrivacyVisibility story;
  final bool readReceipts;
  final Map<String, Set<String>> exclusions;

  const PrivacySettings({
    this.presence = PrivacyVisibility.everyone,
    this.lastSeen = PrivacyVisibility.everyone,
    this.profilePhoto = PrivacyVisibility.everyone,
    this.about = PrivacyVisibility.everyone,
    this.story = PrivacyVisibility.everyone,
    this.readReceipts = true,
    this.exclusions = const {},
  });

  factory PrivacySettings.fromMap(Map<String, dynamic> map) {
    final raw = (map['exclusions'] as Map?)?.cast<String, dynamic>() ?? {};
    return PrivacySettings(
      presence: PrivacyVisibility.fromWire(map['presence']),
      lastSeen: PrivacyVisibility.fromWire(map['last_seen']),
      profilePhoto: PrivacyVisibility.fromWire(map['profile_photo']),
      about: PrivacyVisibility.fromWire(map['about']),
      story: PrivacyVisibility.fromWire(map['story']),
      readReceipts: map['read_receipts'] != false,
      exclusions: {
        for (final entry in raw.entries)
          entry.key: ((entry.value as List?) ?? const [])
              .map((e) => '$e')
              .toSet(),
      },
    );
  }

  PrivacySettings copyWith({
    PrivacyVisibility? presence,
    PrivacyVisibility? lastSeen,
    PrivacyVisibility? profilePhoto,
    PrivacyVisibility? about,
    PrivacyVisibility? story,
    bool? readReceipts,
    Map<String, Set<String>>? exclusions,
  }) {
    return PrivacySettings(
      presence: presence ?? this.presence,
      lastSeen: lastSeen ?? this.lastSeen,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      about: about ?? this.about,
      story: story ?? this.story,
      readReceipts: readReceipts ?? this.readReceipts,
      exclusions: exclusions ?? this.exclusions,
    );
  }
}
