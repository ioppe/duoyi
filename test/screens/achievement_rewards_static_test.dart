import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('成就保留徽章和分享且不自动发币、不展示币或币派生等级', () {
    final provider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/achievements_screen.dart',
    ).readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final cloudSync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains('static const _rewardStorageKey'));
    expect(provider, contains('coinBalance'));
    expect(provider, contains('rewardLedger'));
    expect(provider, isNot(contains('VirtualRewardRules.forEvent')));
    expect(provider, isNot(contains('VirtualRewardRules.forAchievement')));
    expect(provider, isNot(contains('_coinBalance +=')));
    expect(provider, contains('notifyAchievementUnlocked(achievement)'));
    expect(screen, contains('snapshotFor(a.id)'));
    for (final hidden in [
      '时光币',
      'coinBalance',
      'lifetimeCoins',
      'growthLevel',
      '_RewardLedgerCard',
      '_LevelCoinPanel',
    ]) {
      expect(screen, isNot(contains(hidden)), reason: hidden);
    }
    expect(screen, contains("tooltip: '成就分享图'"));
    expect(screen, contains('_AchievementShareDialog'));
    expect(screen, contains('_AchievementShareCard'));
    expect(screen, contains('_achievementShareMarkdown'));
    expect(screen, contains('RenderRepaintBoundary'));
    expect(screen, contains('ui.ImageByteFormat.png'));
    expect(screen, contains("package:share_plus/share_plus.dart"));
    expect(screen, contains('SharePlus.instance.share'));
    expect(screen, contains('ShareParams('));
    expect(screen, contains('XFile(file.path)'));
    expect(screen, contains('duoyi_achievement_'));
    expect(screen, contains('成就分享图已保存并打开系统分享面板'));
    expect(backup, contains("'duoyi_virtual_rewards'"));
    expect(cloudSync, contains("'duoyi_virtual_rewards': 'virtual_rewards'"));
    expect(main, contains('String _achievementPersistedSignature'));
    expect(main, contains('void markAchievementDirtyOnPersistedChange()'));
    expect(
      main,
      contains(
        'achievementProvider.addListener(markAchievementDirtyOnPersistedChange)',
      ),
    );
  });
}
