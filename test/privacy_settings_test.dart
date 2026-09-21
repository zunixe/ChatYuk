import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/models/privacy_settings.dart';

void main() {
  test('privacy settings parses visibility and exclusions', () {
    final settings = PrivacySettings.fromMap({
      'presence': 'friends',
      'last_seen': 'friends_except',
      'profile_photo': 'nobody',
      'about': 'everyone',
      'story': 'friends',
      'read_receipts': false,
      'exclusions': {
        'last_seen': ['u1', 'u2'],
      },
    });

    expect(settings.presence, PrivacyVisibility.friends);
    expect(settings.lastSeen, PrivacyVisibility.friendsExcept);
    expect(settings.profilePhoto, PrivacyVisibility.nobody);
    expect(settings.readReceipts, isFalse);
    expect(settings.exclusions['last_seen'], {'u1', 'u2'});
  });

  test('invalid visibility falls back to everyone', () {
    final settings = PrivacySettings.fromMap({'presence': 'invalid'});
    expect(settings.presence, PrivacyVisibility.everyone);
    expect(settings.readReceipts, isTrue);
  });

  test('copyWith keeps unrelated privacy values', () {
    const original = PrivacySettings(
      presence: PrivacyVisibility.friends,
      readReceipts: false,
    );
    final changed = original.copyWith(lastSeen: PrivacyVisibility.nobody);
    expect(changed.presence, PrivacyVisibility.friends);
    expect(changed.lastSeen, PrivacyVisibility.nobody);
    expect(changed.readReceipts, isFalse);
  });

  test('wireKey/fromWire roundtrip 5 nilai', () {
    for (final v in PrivacyVisibility.values) {
      expect(PrivacyVisibility.fromWire(v.wireKey), v);
    }
  });

  test("nilai lama 'except' dibaca sebagai friendsExcept (kompatibel)", () {
    expect(
      PrivacyVisibility.fromWire('except'),
      PrivacyVisibility.friendsExcept,
    );
  });

  test('usesExclusions & friendsOnly benar per opsi', () {
    expect(PrivacyVisibility.everyone.usesExclusions, isFalse);
    expect(PrivacyVisibility.everyoneExcept.usesExclusions, isTrue);
    expect(PrivacyVisibility.friends.usesExclusions, isFalse);
    expect(PrivacyVisibility.friendsExcept.usesExclusions, isTrue);
    expect(PrivacyVisibility.nobody.usesExclusions, isFalse);

    expect(PrivacyVisibility.friends.friendsOnly, isTrue);
    expect(PrivacyVisibility.friendsExcept.friendsOnly, isTrue);
    expect(PrivacyVisibility.everyoneExcept.friendsOnly, isFalse);
  });
}
