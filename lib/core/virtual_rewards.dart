import 'domain_event_bus.dart';

// Historical reward structures remain readable by backup and sync clients.
class RewardGrant {
  final String id;
  final String title;
  final int coins;
  final String reason;

  const RewardGrant({
    required this.id,
    required this.title,
    required this.coins,
    required this.reason,
  });
}

class VirtualRewardRules {
  const VirtualRewardRules._();

  static RewardGrant? forEvent(DomainEvent event) => null;

  static RewardGrant forAchievement({
    required String id,
    required String title,
    required String description,
  }) => RewardGrant(
    id: 'achievement:$id',
    title: '解锁成就：$title',
    coins: 0,
    reason: description,
  );
}
