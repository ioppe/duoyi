import 'package:test/test.dart';

import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/core/virtual_rewards.dart';

void main() {
  test('all business events leave historical rewards unchanged', () {
    for (final type in DomainEventType.values) {
      expect(
        VirtualRewardRules.forEvent(
          DomainEvent(
            type: type,
            objectId: 'work-1',
            metadata: const {
              'date': '2026-05-20',
              'count': 1,
              'durationSeconds': 1500,
            },
          ),
        ),
        isNull,
        reason: type.name,
      );
    }
  });

  test('achievement compatibility metadata no longer grants coins', () {
    final grant = VirtualRewardRules.forAchievement(
      id: 'first_todo',
      title: '启程',
      description: '完成第一个待办',
    );
    expect(grant.id, 'achievement:first_todo');
    expect(grant.title, '解锁成就：启程');
    expect(grant.coins, 0);
  });
}
