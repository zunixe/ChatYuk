import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/mission.dart';
import 'package:chatyuk/providers/riverpod/missions_provider.dart';

void main() {
  group('Mission Model', () {
    test('Mission.fromJson parses correctly', () {
      final json = {
        'id': 1,
        'mission_key': 'test_mission',
        'title': 'Test Mission',
        'description': 'Test description',
        'category': 'daily',
        'target_value': 5,
        'target_unit': 'calls',
        'reward_coins': 10,
        'is_daily': true,
        'is_locked': false,
        'progress': 2,
        'is_completed': false,
        'claimed': false,
      };

      final mission = Mission.fromJson(json);
      expect(mission.missionKey, 'test_mission');
      expect(mission.title, 'Test Mission');
      expect(mission.targetValue, 5);
      expect(mission.rewardCoins, 10);
      expect(mission.isDaily, true);
      expect(mission.isLocked, false);
      expect(mission.progress, 2);
      expect(mission.isCompleted, false);
      expect(mission.claimed, false);
      expect(mission.canClaim, false);
    });

    test('Mission copyWith updates fields', () {
      final mission = Mission(
        id: 1,
        missionKey: 'test',
        title: 'Test',
        description: '',
        category: 'daily',
        targetValue: 5,
        targetUnit: 'calls',
      );

      final updated = mission.copyWith(progress: 5, isCompleted: true);
      expect(updated.progress, 5);
      expect(updated.isCompleted, true);
      expect(updated.missionKey, 'test');
    });

    test('Mission canClaim works correctly', () {
      final incomplete = Mission(
        id: 1, missionKey: '', title: '', description: '',
        category: '', targetValue: 0, targetUnit: '',
      );
      final complete = incomplete.copyWith(isCompleted: true);
      final claimed = complete.copyWith(claimed: true);

      expect(incomplete.canClaim, false);
      expect(complete.canClaim, true);
      expect(claimed.canClaim, false);
    });

    test('UnlockCondition parses correctly', () {
      const condition = UnlockCondition(type: 'total_coins', value: 1200);
      expect(condition.type, 'total_coins');
      expect(condition.value, 1200);
    });
  });

  group('MissionsState', () {
    test('completedCount sums main + daily', () {
      final state = MissionsState(
        mainMissions: [
          Mission(id: 1, missionKey: '', title: '', description: '',
              category: '', targetValue: 1, targetUnit: '',
              isCompleted: true),
          Mission(id: 2, missionKey: '', title: '', description: '',
              category: '', targetValue: 1, targetUnit: ''),
        ],
        dailyMissions: [
          Mission(id: 3, missionKey: '', title: '', description: '',
              category: '', targetValue: 1, targetUnit: '',
              isCompleted: true),
          Mission(id: 4, missionKey: '', title: '', description: '',
              category: '', targetValue: 1, targetUnit: '',
              isCompleted: false),
          Mission(id: 5, missionKey: '', title: '', description: '',
              category: '', targetValue: 1, targetUnit: ''),
        ],
      );
      expect(state.completedCount, 2);
      expect(state.claimableCount, 2);
      expect(state.totalRewardPotential, 0);
    });

    test('copyWith returns new state', () {
      const state = MissionsState(loading: true);
      final copied = state.copyWith(loading: false);
      expect(copied.loading, false);
      expect(state.loading, true);
    });
  });
}