import '../core/app_clock.dart';
import 'dart:io' show Directory, File;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../core/app_version.dart';
import '../core/brand_strings.dart';
import '../core/desktop_tokens.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_service.dart';
import '../providers/auth_provider.dart';
import '../services/ai_service.dart';
import '../services/app_update_installer.dart';
import '../services/app_update_service.dart';
import '../widgets/brand_background.dart';
import '../widgets/cached_avatar_image.dart';
import '../widgets/stats_overview_cards.dart';
import '../widgets/surface_components.dart';
import '../widgets/sync_status_card.dart';
import '../widgets/weekly_productivity_card.dart';
import 'theme_picker_screen.dart';
import 'announcements_screen.dart';
import 'feedback_screen.dart';
import 'note_screen.dart';
import 'statistics_screen.dart';
import 'time_audit_screen.dart';
import 'pomodoro_screen.dart';
import 'countdown_screen.dart';
import 'anniversary_screen.dart' as anniversary;
import 'goal_screen.dart';
import 'course_schedule_screen.dart';
import 'almanac_screen.dart';
import 'admin_screen.dart';
import 'achievements_screen.dart';
import 'backup_screen.dart';
import 'lock_settings_screen.dart';
import 'export_screen.dart';
import 'search_screen.dart';
import 'ai_history_screen.dart';
import 'preferences_screen.dart';
import 'integrations_screen.dart';
import 'share_screen.dart';
import 'sync_conflict_log_screen.dart';
import 'profile_screen.dart';
import 'more_apps_screen.dart';
import 'widget_screen.dart';
import 'notification_history_screen.dart';

const double _mineHeaderCompactHeight = 96;
const double _mineHeaderRegularHeight = 84;

typedef _MineThemeSlice = ({
  BrandStrings strings,
  String brandName,
  AvatarFrameReward avatarFrame,
});

typedef _MineAuthSlice = ({
  String? userId,
  String? username,
  String? displayName,
  String? avatar,
  bool isLoggedIn,
  bool isAdmin,
});

typedef _MineProfileSlice = ({
  String username,
  String displayName,
  String avatarUrl,
  String avatarInitials,
  int currentStreak,
  int productivityScore,
});

enum _MineMenu { apps, settings, support }

class MineScreen extends StatelessWidget {
  final List<int>? visibleBottomNavTabs;
  final bool useShellBackground;
  final _MineMenu? _menu;

  const MineScreen({
    super.key,
    this.visibleBottomNavTabs,
    this.useShellBackground = false,
  }) : _menu = null;

  const MineScreen._secondary(_MineMenu menu, {this.visibleBottomNavTabs})
    : _menu = menu,
      useShellBackground = false;

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = context.select<ThemeProvider, _MineThemeSlice>(
      (provider) => (
        strings: provider.brand.strings,
        brandName: provider.brand.name,
        avatarFrame: provider.activeAvatarFrame,
      ),
    );
    final s = theme.strings;
    final todoCompletionRate = context.select<TodoProvider, int>(_todoRate);
    final todoProvider = context.read<TodoProvider>();
    final habitProvider = context.read<HabitProvider>();
    final weeklyFocus = context.select<PomodoroProvider, int>(_weeklyFocus);
    final pomodoroProvider = context.read<PomodoroProvider>();
    final profile = context.select<UserProvider, _MineProfileSlice>((provider) {
      final p = provider.profile;
      return (
        username: p.username,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        avatarInitials: p.avatarInitials,
        currentStreak: p.currentStreak,
        productivityScore: p.productivityScore,
      );
    });
    final notificationHistoryCount = context.select<NotificationService, int>(
      (service) => service.historyCount,
    );
    final hasUnreadNotificationHistory = context
        .select<NotificationService, bool>(
          (service) => service.hasUnreadHistory,
        );
    final auth = context.select<AuthProvider, _MineAuthSlice>((provider) {
      final state = provider.state;
      return (
        userId: state.userId,
        username: state.username,
        displayName: state.displayName,
        avatar: state.avatar,
        isLoggedIn: state.isLoggedIn,
        isAdmin: state.isAdmin,
      );
    });
    final aiEnabled = context.select<AiService, bool>((ai) => ai.enabled);
    final aiReviewHistoryCount = context.select<AiService, int>(
      (ai) => ai.reviewHistory.length,
    );
    final updater = context.read<AppUpdateService>();
    final updateChecking = context.select<AppUpdateService, bool>(
      (service) => service.checking,
    );
    final updateHasUpdate = context.select<AppUpdateService, bool>(
      (service) => service.hasUpdate,
    );
    final updateLatestVersion = context.select<AppUpdateService, String?>(
      (service) => service.latestVersion,
    );
    final cs = Theme.of(context).colorScheme;
    final avatarFrame = theme.avatarFrame;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final scaffoldBackground = useShellBackground
        ? Colors.transparent
        : routeBackground;
    final toolbarBackground = useShellBackground
        ? Colors.transparent
        : routeBackground.withValues(alpha: 0.96);

    final localDisplayName = _firstNonEmpty([
      profile.displayName,
      profile.username,
      I18n.tr('profile.default_user'),
    ]);
    final displayName = auth.isLoggedIn
        ? _firstNonEmpty([
            auth.displayName,
            auth.username,
            profile.displayName,
            localDisplayName,
          ])
        : localDisplayName;
    final avatarValue = auth.isLoggedIn
        ? _firstNonEmpty([
            auth.avatar,
            profile.avatarUrl,
            profile.avatarInitials,
          ])
        : _firstNonEmpty([profile.avatarUrl, profile.avatarInitials]);
    final mineHeader = AppSurfaceCard(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final avatarSize = compact ? 50.0 : 56.0;
          final headerHeight = compact
              ? _mineHeaderCompactHeight
              : _mineHeaderRegularHeight;
          final avatar = SizedBox(
            width: avatarSize + 6,
            height: avatarSize + 6,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Tooltip(
                    message: I18n.tr('mine.avatar.view'),
                    child: Semantics(
                      button: true,
                      label: I18n.tr('mine.avatar.view'),
                      child: InkWell(
                        key: const ValueKey('mine_avatar_preview_button'),
                        customBorder: const CircleBorder(),
                        onTap: () => _showAvatarPreview(context),
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          padding:
                              avatarFrame.id ==
                                  ThemeProvider.defaultAvatarFrameId
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(3),
                          decoration:
                              avatarFrame.id ==
                                  ThemeProvider.defaultAvatarFrameId
                              ? null
                              : BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: avatarFrame.colors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: avatarFrame.colors.first
                                          .withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                          child: Hero(
                            tag: 'mine-avatar-preview',
                            child: _ProfileAvatar(
                              avatar: avatarValue,
                              displayName: displayName,
                              radius: compact ? 26 : 30,
                              cacheKey: _avatarCacheKey(
                                avatarValue,
                                auth.userId,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: SizedBox.square(
                    key: const ValueKey('mine_avatar_edit_button'),
                    dimension: 44,
                    child: Tooltip(
                      message: I18n.tr('mine.avatar.edit'),
                      child: Semantics(
                        button: true,
                        label: I18n.tr('mine.avatar.edit'),
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _pickAndSaveAvatar(context),
                            child: Center(
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Color.alphaBlend(
                                    cs.primary.withValues(alpha: 0.90),
                                    cs.surface,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.surface.withValues(alpha: 0.92),
                                    width: 0.45,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          final username = auth.isLoggedIn
              ? _firstNonEmpty([auth.username, profile.username])
              : profile.username;
          final accountAction = auth.isLoggedIn
              ? Tooltip(
                  message: I18n.tr('auth.logout'),
                  child: IconButton.filledTonal(
                    key: const ValueKey('mine_top_logout_button'),
                    onPressed: () => _confirmLogout(context),
                    icon: const Icon(
                      Icons.logout,
                      size: DesignTokens.controlIconSize,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(
                        DesignTokens.controlMinHeight,
                      ),
                      backgroundColor: cs.errorContainer.withValues(
                        alpha: 0.58,
                      ),
                      foregroundColor: cs.onErrorContainer,
                    ),
                  ),
                )
              : const SizedBox.shrink();
          final nameText = displayName.trim().isEmpty
              ? I18n.tr('profile.default_user')
              : displayName.trim();
          final usernameText = username.trim();
          final identityChip = usernameText.isEmpty
              ? null
              : _MineUserLineChip(
                  label: '@$usernameText',
                  icon: Icons.badge_outlined,
                  color: cs.primary,
                );
          final rewardChips = <Widget>[
            if (auth.isLoggedIn && auth.isAdmin)
              _MineUserLineChip(
                label: I18n.tr('mine.badge.admin'),
                color: cs.primary,
              ),
          ];
          return SizedBox(
            key: const ValueKey('mine_header_stable_box'),
            height: headerHeight,
            child: Row(
              key: const ValueKey('mine_user_info_row'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(key: const ValueKey('mine_avatar_row'), child: avatar),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: SizedBox(
                    height: headerHeight,
                    child: Semantics(
                      button: true,
                      label: I18n.tr('mine.view_profile_semantics'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                        onTap: () => _openProfileEditor(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontSize: DesignTokens.fontSizeMd,
                                      color: cs.onSurface,
                                      height: 1.18,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              _MineHeaderMetadata(
                                compact: compact,
                                identityChip: identityChip,
                                rewardChips: rewardChips,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: headerHeight,
                  child: Center(child: accountAction),
                ),
              ],
            ),
          );
        },
      ),
    );

    final mineStats = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _MineStatsGrid(
        cards: [
          StatsOverviewCard(
            title: I18n.tr('mine.stats.todos'),
            value: '$todoCompletionRate',
            unit: '%',
            icon: Icons.check_circle_outline,
            color: cs.primary,
          ),
          StatsOverviewCard(
            title: I18n.tr('mine.stats.streak'),
            value: '${profile.currentStreak}',
            unit: I18n.tr('unit.day'),
            icon: Icons.repeat,
            color: cs.tertiary,
          ),
          StatsOverviewCard(
            title: I18n.tr('mine.stats.focus'),
            value: '$weeklyFocus',
            unit: I18n.tr('unit.minute'),
            icon: Icons.timer,
            color: DesignTokens.defaultError,
          ),
          StatsOverviewCard(
            title: I18n.tr('mine.stats.productivity'),
            value: '${profile.productivityScore}',
            icon: Icons.auto_awesome,
            color: DesignTokens.defaultWarning,
          ),
        ],
      ),
    );

    final aiAssistant = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: aiEnabled
          ? _AiWeeklyReviewCard(
              todoProvider: todoProvider,
              pomodoroProvider: pomodoroProvider,
              habitProvider: habitProvider,
            )
          : AppInfoBanner(
              icon: Icons.auto_awesome,
              title: I18n.tr('mine.ai_assistant'),
              message: I18n.tr('mine.ai_assistant.disabled_message'),
              color: Colors.purple,
              onTap: auth.isAdmin
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const BrandRouteSurface(child: AdminScreen()),
                      ),
                    )
                  : null,
            ),
    );

    // 宽屏桌面档（与 today 桌面仪表盘同款纯宽度判定）：条目限宽居中 +
    // 分组瓦片两列，消除限宽壳内仍通栏拉伸的"手机感"；窄屏路径原样不动，
    // 顶部栏仍全宽固定、内容整体滚动。
    final isWidescreen =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn;
    final tileColumns = isWidescreen ? 2 : 1;
    Widget capped(Widget child) => isWidescreen
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesktopTokens.secondaryMaxContentWidth,
              ),
              child: child,
            ),
          )
        : child;

    final appSections = <Widget>[
      if (aiEnabled) capped(aiAssistant),
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.action_plan'),
          children: [
            _Tile(
              icon: Icons.flag_circle_outlined,
              label: I18n.tr('goal.title'),
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(child: GoalScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.timer,
              label: I18n.tr('mine.tile.pomodoro'),
              color: Colors.red,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: PomodoroScreen(useShellBackground: true),
                  ),
                ),
              ),
            ),
            _Tile(
              icon: Icons.apps_outlined,
              label: I18n.tr('mine.tile.more_apps'),
              subtitle: I18n.tr('mine.tile.more_apps.subtitle'),
              color: Colors.blueGrey,
              onTap: () => _openMoreApplications(context),
            ),
          ],
        ),
      ),
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.review'),
          children: [
            _Tile(
              icon: Icons.access_time,
              label: I18n.tr('time_audit.title'),
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: TimeAuditScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.pie_chart_outline,
              label: I18n.tr('mine.tile.statistics'),
              color: Colors.indigo,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: StatisticsScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.edit_note,
              label: I18n.tr('note.title'),
              color: Colors.amber.shade700,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(child: NoteScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.emoji_events_outlined,
              label: I18n.tr('mine.tile.achievements'),
              color: Colors.amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: AchievementsScreen()),
                ),
              ),
            ),
            if (aiEnabled)
              _Tile(
                icon: Icons.history,
                label: I18n.tr('ai_history.title'),
                color: Colors.purple,
                trailing: aiReviewHistoryCount == 0
                    ? null
                    : Text(
                        '$aiReviewHistoryCount',
                        style: const TextStyle(fontSize: 11),
                      ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: AiHistoryScreen()),
                  ),
                ),
              ),
          ],
        ),
      ),
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.tools'),
          children: [
            _Tile(
              icon: Icons.school_outlined,
              label: I18n.tr('mine.tile.courses'),
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: CourseScheduleScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.calendar_month_outlined,
              label: I18n.tr('today.almanac.title'),
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: AlmanacScreen(
                      initialMode: AlmanacEntryMode.calendar,
                    ),
                  ),
                ),
              ),
            ),
            _Tile(
              icon: Icons.hourglass_bottom_outlined,
              label: I18n.tr('countdown.title'),
              color: Colors.deepOrange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: CountdownScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.event_available_outlined,
              label: I18n.tr('anniversary.title'),
              color: Colors.pink,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: anniversary.MemorialAnniversaryScreen(),
                  ),
                ),
              ),
            ),
            _Tile(
              icon: Icons.cake_outlined,
              label: I18n.tr('anniversary.birthday'),
              color: Colors.purple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: anniversary.BirthdayScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
    final settingsSections = <Widget>[
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.personal'),
          children: [
            _Tile(
              icon: Icons.tune,
              label: I18n.tr('preferences.title'),
              color: Colors.indigo,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: PreferencesScreen()),
                ),
              ),
            ),
            _Tile(
              key: const ValueKey('mine_widget_settings_entry'),
              icon: Icons.widgets_outlined,
              label: I18n.tr('mine.tile.widget_settings'),
              subtitle: I18n.tr('mine.tile.widget_settings.subtitle'),
              color: Colors.teal,
              onTap: () => _openBrandedRoute(
                context,
                const WidgetScreen(asSettings: true),
              ),
            ),
            _Tile(
              icon: Icons.lock_outline,
              label: I18n.tr('app_lock.title'),
              color: Colors.red.shade400,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: LockSettingsScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
      // 云同步状态卡：上次同步时间 / 进行中 / 未同步角标 / 失败原因
      // 与自动重试提示，紧贴"数据协作"分组（含同步冲突记录入口）上方。
      capped(const SyncStatusCard()),
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.data'),
          children: [
            _Tile(
              icon: Icons.groups_2_outlined,
              label: I18n.tr('share.title'),
              color: Colors.cyan,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(child: ShareScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.extension_outlined,
              label: I18n.tr('mine.tile.integrations'),
              color: Colors.deepPurple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: IntegrationsScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.sync_problem_outlined,
              label: I18n.tr('sync_conflict.title'),
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: SyncConflictLogScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.event_note_outlined,
              label: I18n.tr('export.title'),
              color: Colors.lightBlue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: ExportScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.backup_outlined,
              label: I18n.tr('mine.tile.backup'),
              color: Colors.brown,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: BackupScreen(initialMode: BackupEntryMode.backup),
                  ),
                ),
              ),
            ),
            _Tile(
              icon: Icons.restore_outlined,
              label: I18n.tr('mine.tile.restore'),
              color: Colors.blueGrey,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrandRouteSurface(
                    child: BackupScreen(initialMode: BackupEntryMode.restore),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.group.notifications'),
          children: [
            _Tile(
              key: const ValueKey('mine_notification_history_entry'),
              icon: Icons.history_toggle_off_outlined,
              label: I18n.tr('mine.tile.notification_history'),
              subtitle: notificationHistoryCount == 0
                  ? I18n.tr('mine.tile.notification_history.empty')
                  : '$notificationHistoryCount${I18n.tr('mine.tile.notification_history.count_suffix')}',
              color: Colors.blueGrey,
              trailing: notificationHistoryCount == 0
                  ? null
                  : hasUnreadNotificationHistory
                  ? const _UnreadDot()
                  : null,
              onTap: () => _openNotificationHistory(context),
            ),
            _Tile(
              icon: Icons.notifications_outlined,
              label: I18n.tr('mine.tile.notification_settings'),
              subtitle: I18n.tr('mine.tile.notification_settings.subtitle'),
              color: Colors.orange,
              onTap: () => _openNotificationSettings(context),
            ),
            if (auth.isLoggedIn && auth.isAdmin)
              _Tile(
                icon: Icons.admin_panel_settings_outlined,
                label: I18n.tr('mine.tile.admin'),
                color: Colors.deepOrange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: AdminScreen()),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
    final supportSections = <Widget>[
      capped(
        _TileGroup(
          columns: tileColumns,
          title: I18n.tr('mine.menu.support'),
          children: [
            _Tile(
              icon: Icons.campaign_outlined,
              label: I18n.tr('announcement.title'),
              color: Colors.cyan,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const BrandRouteSurface(child: AnnouncementsScreen()),
                ),
              ),
            ),
            _Tile(
              icon: Icons.forum_outlined,
              label: I18n.tr('mine.tile.feedback'),
              subtitle: I18n.tr('mine.tile.feedback.subtitle'),
              color: Colors.indigo,
              onTap: () => _openFeedback(context, 'feature'),
            ),
            _Tile(
              icon: Icons.system_update,
              label: I18n.tr('mine.tile.check_updates'),
              color: Colors.teal,
              trailing: updateChecking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : (updateHasUpdate
                        ? _UpdateAvailableBadge(version: updateLatestVersion)
                        : null),
              onTap: () => _showUpdateDialog(context, updater),
            ),
            _Tile(
              icon: Icons.info_outline,
              label: s.mineAboutLabel,
              color: Colors.grey,
              onTap: () => _aboutDialog(context),
            ),
          ],
        ),
      ),
    ];

    // 二级路由继续通过本组件的 selectors 读取最新状态，避免保存菜单快照。
    final menu = _menu;
    if (menu != null) {
      return _MineMenuScreen(
        title: I18n.tr(switch (menu) {
          _MineMenu.apps => 'mine.menu.apps',
          _MineMenu.settings => 'mine.menu.settings',
          _MineMenu.support => 'mine.menu.support',
        }),
        sections: switch (menu) {
          _MineMenu.apps => appSections,
          _MineMenu.settings => settingsSections,
          _MineMenu.support => supportSections,
        },
      );
    }

    return Scaffold(
      backgroundColor: scaffoldBackground,
      appBar: AppBar(
        title: Text(s.mineTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: toolbarBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: I18n.tr('quick.menu.search'),
            icon: const Icon(Icons.search),
            onPressed: () => _openBrandedRoute(context, const SearchScreen()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const PageStorageKey<String>('mine_screen_list'),
          restorationId: 'mine_screen_list',
          padding: const EdgeInsets.only(bottom: DesignTokens.spaceXxl),
          children: [
            capped(mineHeader),
            capped(
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceMd,
                  0,
                  DesignTokens.spaceMd,
                  DesignTokens.spaceMd,
                ),
                child: WeeklyProductivityCard(
                  key: const ValueKey('mine_weekly_productivity'),
                  onTap: () =>
                      _openBrandedRoute(context, const StatisticsScreen()),
                ),
              ),
            ),
            capped(mineStats),
            const SizedBox(height: DesignTokens.spaceLg),
            capped(
              _TileGroup(
                columns: tileColumns,
                title: I18n.tr('mine.menu.title'),
                children: [
                  _Tile(
                    key: const ValueKey('mine_apps_entry'),
                    icon: Icons.apps_outlined,
                    label: I18n.tr('mine.menu.apps'),
                    subtitle: I18n.tr('mine.menu.apps.subtitle'),
                    color: cs.primary,
                    onTap: () => _openMenuPage(context, _MineMenu.apps),
                  ),
                  _Tile(
                    key: const ValueKey('mine_appearance_entry'),
                    icon: Icons.palette_outlined,
                    label: I18n.tr('mine.menu.appearance'),
                    subtitle: I18n.tr('mine.menu.appearance.subtitle'),
                    color: cs.secondary,
                    trailing: Text(
                      theme.brandName,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: DesignTokens.fontSizeSecondary,
                      ),
                    ),
                    onTap: () =>
                        _openBrandedRoute(context, const ThemePickerScreen()),
                  ),
                  _Tile(
                    key: const ValueKey('mine_settings_entry'),
                    icon: Icons.settings_outlined,
                    label: I18n.tr('mine.menu.settings'),
                    subtitle: I18n.tr('mine.menu.settings.subtitle'),
                    color: cs.primary,
                    trailing: hasUnreadNotificationHistory
                        ? const _UnreadDot()
                        : null,
                    onTap: () => _openMenuPage(context, _MineMenu.settings),
                  ),
                  _Tile(
                    key: const ValueKey('mine_support_entry'),
                    icon: Icons.help_outline,
                    label: I18n.tr('mine.menu.support'),
                    subtitle: I18n.tr('mine.menu.support.subtitle'),
                    color: cs.secondary,
                    trailing: updateHasUpdate
                        ? _UpdateAvailableBadge(version: updateLatestVersion)
                        : null,
                    onTap: () => _openMenuPage(context, _MineMenu.support),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMenuPage(BuildContext context, _MineMenu menu) {
    _openBrandedRoute(
      context,
      MineScreen._secondary(menu, visibleBottomNavTabs: visibleBottomNavTabs),
    );
  }

  int _todoRate(TodoProvider t) {
    if (t.todos.isEmpty) return 0;
    return (t.completedTodos.length / t.todos.length * 100).round();
  }

  int _weeklyFocus(PomodoroProvider p) {
    final now = AppClock.now();
    final weekAgo = AppClock.date(now.year, now.month, now.day - 7);
    return p.sessions
            .where(
              (s) => s.type.name == 'focus' && s.startTime.isAfter(weekAgo),
            )
            .fold(0, (sum, s) => sum + s.durationSeconds) ~/
        60;
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  void _openProfileEditor(BuildContext context, {bool avatarOnly = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandRouteSurface(
          child: ProfileScreen(openAvatarSheetOnStart: avatarOnly),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: const Icon(Icons.logout),
        title: Text(I18n.tr('mine.logout.confirm_title')),
        content: Text(I18n.tr('mine.logout.confirm_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: appSecondaryFilledButtonStyle(ctx),
            child: Text(I18n.tr('auth.logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    var cleanupFailed = false;
    try {
      await context.read<AuthProvider>().logout();
    } catch (_) {
      cleanupFailed = true;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleanupFailed
              ? I18n.tr('mine.logout.cleanup_failed')
              : I18n.tr('mine.logout.done'),
        ),
      ),
    );
  }

  Future<void> _pickAndSaveAvatar(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null || !context.mounted) return;
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      if (auth.state.isLoggedIn) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception(I18n.tr('profile.avatar.file_empty'));
        }
        if (bytes.length > 3 * 1024 * 1024) {
          throw Exception(I18n.tr('profile.avatar.too_large'));
        }
        await auth.uploadAvatarBytes(filename: file.name, bytes: bytes);
        final state = auth.state;
        await userProvider.updateProfile(
          username: _firstNonEmpty([
            state.username,
            userProvider.profile.username,
            I18n.tr('profile.default_user'),
          ]),
          displayName: state.displayName ?? '',
          email: state.email ?? '',
          emailVerified: state.emailVerified,
          avatarUrl: state.avatar ?? '',
          bio: state.bio ?? '',
        );
      } else {
        final storedPath = await _copyLocalAvatarFile(file);
        final profile = userProvider.profile;
        await userProvider.updateProfile(
          username: profile.username,
          avatarInitials: profile.avatarInitials,
          displayName: profile.displayName,
          email: profile.email,
          emailVerified: profile.emailVerified,
          avatarUrl: storedPath,
          bio: profile.bio,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('profile.avatar.saved'))));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${I18n.tr('profile.avatar.save_failed_prefix')}${_avatarErrorMessage(e)}',
          ),
        ),
      );
    }
  }

  void _showAvatarPreview(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final profile = userProvider.profile;
    final displayName = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.displayName,
            auth.state.username,
            profile.displayName,
            profile.username,
            I18n.tr('mine.me_fallback'),
          ])
        : _firstNonEmpty([
            profile.displayName,
            profile.username,
            I18n.tr('mine.me_fallback'),
          ]);
    final avatar = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.avatar,
            profile.avatarUrl,
            profile.avatarInitials,
          ])
        : _firstNonEmpty([profile.avatarUrl, profile.avatarInitials]);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AvatarPreviewScreen(
          avatar: avatar,
          displayName: displayName,
          cacheKey: _avatarCacheKey(avatar, auth.state.userId),
          onEdit: () => _pickAndSaveAvatar(context),
        ),
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, AppUpdateService u) async {
    if (!u.checking) await u.checkNow();
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !u.mustUpdate,
      builder: (ctx) => Consumer<AppUpdateService>(
        builder: (context, updater, _) {
          final notes = updater.latestNotesForDisplay;
          return PopScope(
            canPop: !updater.mustUpdate && !updater.busy,
            child: AppDialog(
              title: Text(
                I18n.tr(
                  updater.mustUpdate
                      ? 'mine.update.required_title'
                      : 'mine.update.check_title',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${I18n.tr('mine.update.current_version_prefix')}${updater.currentVersion}',
                  ),
                  Text(
                    "${I18n.tr('mine.update.remote_version_prefix')}${updater.latestVersion ?? '—'}",
                  ),
                  if (updater.minimumSupportedVersion != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      "${I18n.tr('mine.update.min_supported_prefix')}${updater.minimumSupportedVersion}",
                    ),
                  ],
                  if (updater.mustUpdate) ...[
                    const SizedBox(height: 12),
                    AppInfoBanner(
                      icon: Icons.system_update_alt_outlined,
                      title: I18n.tr('mine.update.force_banner_title'),
                      message: I18n.tr('mine.update.force_banner_message'),
                      color: Theme.of(context).colorScheme.error,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                  if (updater.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      updater.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  if (updater.hasUpdate) ...[
                    const SizedBox(height: 12),
                    Text(
                      I18n.tr('mine.update.available'),
                      style: const TextStyle(
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                  ] else if (updater.error == null && !updater.checking) ...[
                    const SizedBox(height: 12),
                    Text(I18n.tr('mine.update.up_to_date')),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      I18n.tr('mine.update.notes'),
                      style: const TextStyle(
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            notes,
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (updater.hasUpdate && updater.latestAssetName != null) ...[
                    const SizedBox(height: 8),
                    _UpdatePackageInfo(assetName: updater.latestAssetName!),
                  ],
                  if ((updater.mustUpdate || updater.hasUpdate) &&
                      updater.latestUrl == null &&
                      !updater.hasDownloadedInstaller) ...[
                    const SizedBox(height: 12),
                    AppInfoBanner(
                      icon: Icons.link_off_outlined,
                      title: I18n.tr('mine.update.package_missing_title'),
                      message: updater.forceUpdateBlockedReason == null
                          ? I18n.tr('mine.update.package_missing_message')
                          : "${I18n.tr('mine.update.package_broken_prefix')}${updater.forceUpdateBlockedReason}${I18n.tr('mine.update.package_broken_suffix')}",
                      color: Theme.of(context).colorScheme.error,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                  if (updater.hasUpdate && updater.downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: updater.downloadProgress),
                    const SizedBox(height: 6),
                    Text(
                      updater.downloadProgress == null
                          ? I18n.tr('mine.update.downloading')
                          : "${I18n.tr('mine.update.downloading_progress_prefix')}${(updater.downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ] else if (updater.hasUpdate && updater.installing) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(I18n.tr('mine.update.installing')),
                  ],
                ],
              ),
              actions: [
                if (!updater.mustUpdate)
                  TextButton(
                    onPressed: updater.busy ? null : () => Navigator.pop(ctx),
                    child: Text(I18n.tr('action.close')),
                  ),
                if (updater.hasUpdate &&
                    (updater.latestUrl != null ||
                        updater.hasDownloadedInstaller) &&
                    AppUpdateInstaller.supportsInstall)
                  FilledButton.icon(
                    onPressed: updater.busy
                        ? null
                        : () async {
                            await updater.downloadAndInstallLatest();
                            if (!context.mounted) return;
                            if (updater.error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(updater.error!)),
                              );
                            }
                          },
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      I18n.tr(
                        updater.hasDownloadedInstaller
                            ? 'mine.update.install_downloaded'
                            : 'mine.update.download_and_install',
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNotificationSettings(BuildContext context) async {
    _openBrandedRoute(context, const NotificationSettingsScreen());
  }

  void _openMoreApplications(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandRouteSurface(
          child: MoreApplicationsScreen(
            visibleBottomNavTabs: visibleBottomNavTabs,
          ),
        ),
      ),
    );
  }

  void _openNotificationHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(
          child: NotificationHistoryScreen(markReadOnOpen: true),
        ),
      ),
    );
  }

  void _openFeedback(BuildContext context, String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BrandRouteSurface(child: FeedbackScreen(initialCategory: category)),
      ),
    );
  }

  void _openBrandedRoute(BuildContext context, Widget child) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child)),
    );
  }

  void _aboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(I18n.tr('mine.about.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${I18n.tr('mine.about.version_prefix')}${AppVersion.display}",
            ),
            const SizedBox(height: 4),
            Text(I18n.tr('mine.about.tagline')),
            const SizedBox(height: 4),
            Text(I18n.tr('nav.todo')),
            Text(I18n.tr('nav.habit')),
            Text(I18n.tr('nav.calendar')),
            Text(I18n.tr('mine.tile.pomodoro')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('mine.about.ok')),
          ),
        ],
      ),
    );
  }
}

class _UpdatePackageInfo extends StatelessWidget {
  final String assetName;

  const _UpdatePackageInfo({required this.assetName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: DesignTokens.fontWeightStrong,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface,
      height: 1.35,
    );

    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            I18n.tr('mine.update.package_label'),
            style: labelStyle,
          );
          final value = Text(
            _breakableUpdateAssetName(assetName),
            softWrap: true,
            style: valueStyle,
          );
          if (constraints.maxWidth < 260) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 3), value],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 52, child: label),
              const SizedBox(width: 8),
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}

String _breakableUpdateAssetName(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 24) return trimmed;
  final buffer = StringBuffer();
  var runLength = 0;
  for (final codePoint in trimmed.runes) {
    final char = String.fromCharCode(codePoint);
    buffer.write(char);
    runLength += 1;
    if (_isUpdateAssetBreakPoint(char) || runLength >= 16) {
      buffer.write('\u{200B}');
      runLength = 0;
    }
  }
  return buffer.toString();
}

bool _isUpdateAssetBreakPoint(String char) {
  return switch (char) {
    '-' || '_' || '.' || '/' || '+' => true,
    _ => false,
  };
}

class _ProfileAvatar extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final double radius;
  final Object? cacheKey;

  const _ProfileAvatar({
    required this.avatar,
    required this.displayName,
    required this.radius,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty
        ? fallback.characters.first
        : I18n.tr('mine.me_fallback');

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: networkUrl != null
          ? ClipOval(
              child: CachedAvatarImage(
                url: networkUrl,
                cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
                width: radius * 2,
                height: radius * 2,
                fallbackBuilder: (_) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : localPath != null
          ? ClipOval(
              child: Image.file(
                File(localPath),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : Text(
              letter,
              style: TextStyle(
                fontSize: radius * 0.62,
                color: cs.onPrimary,
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
    );
  }
}

class _MineUserLineChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _MineUserLineChip({
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 20, maxWidth: 160),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Color.alphaBlend(
                  color.withValues(alpha: 0.48),
                  cs.onSurface,
                ),
                fontWeight: DesignTokens.fontWeightStrong,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MineHeaderMetadata extends StatelessWidget {
  final bool compact;
  final Widget? identityChip;
  final List<Widget> rewardChips;

  const _MineHeaderMetadata({
    required this.compact,
    required this.identityChip,
    required this.rewardChips,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? 8.0 : 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final identityMaxWidth = maxWidth.clamp(0.0, compact ? 112.0 : 170.0);
        final metadata = <Widget>[
          if (identityChip != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: identityMaxWidth),
              child: identityChip!,
            ),
          ...rewardChips,
        ];
        final rewards = Wrap(
          spacing: spacing,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: rewardChips,
        );

        if (compact) {
          return Column(
            key: const ValueKey('mine_header_metadata_compact'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (identityChip != null) ...[
                metadata.first,
                const SizedBox(height: 2),
              ],
              rewards,
            ],
          );
        }

        return Wrap(
          key: const ValueKey('mine_header_metadata_regular'),
          spacing: spacing,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: metadata,
        );
      },
    );
  }
}

class _AvatarPreviewScreen extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;
  final VoidCallback? onEdit;

  const _AvatarPreviewScreen({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: appSecondaryRouteTitleTextStyle(
          context,
        ).copyWith(color: Colors.white),
        title: Text(I18n.tr('mine.avatar.title')),
        actions: [
          if (onEdit != null)
            IconButton(
              tooltip: I18n.tr('mine.avatar.edit'),
              onPressed: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) => onEdit!());
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: 'mine-avatar-preview',
          child: _ProfileAvatarFullImage(
            avatar: avatar,
            displayName: displayName,
            cacheKey: cacheKey,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarFullImage extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;

  const _ProfileAvatarFullImage({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final image = networkUrl != null
        ? CachedAvatarImage(
            url: networkUrl,
            cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            fallbackBuilder: _fallbackAvatar,
          )
        : localPath != null
        ? Image.file(
            File(localPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallbackAvatar(context),
          )
        : null;

    return SizedBox.expand(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(child: image ?? _fallbackAvatar(context)),
      ),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final radius = (size.shortestSide * 0.28).clamp(84.0, 150.0);
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty
        ? fallback.characters.first
        : I18n.tr('mine.me_fallback');
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: _ProfileAvatarLetter(
        letter: letter,
        radius: radius,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _ProfileAvatarLetter extends StatelessWidget {
  final String letter;
  final double radius;
  final Color color;

  const _ProfileAvatarLetter({
    required this.letter,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.62,
        color: color,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
    );
  }
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_networkAvatarUrl(trimmed) != null) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

String? _networkAvatarUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return trimmed;
  }
  final pathSegments = Uri.tryParse(trimmed)?.pathSegments ?? const <String>[];
  if (pathSegments.isNotEmpty &&
      (pathSegments.first == 'api' || pathSegments.first == 'uploads')) {
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.resolve(trimmed).toString();
    }
    return trimmed;
  }
  return null;
}

/// 头像缓存键。
///
/// 仅由 `userId` 与头像值（服务端 URL / 本地带微秒时间戳的文件名）决定：
/// 这两者都会在用户真正更换头像时变化，足以失效旧缓存。
/// 注意**不要**混入 `profile.updatedAt` —— 它会随每次统计重算（待办完成数、
/// 专注分钟、连续打卡）而刷新，登录后云同步回写数据时会频繁变动，导致头像被
/// 反复重新解码/读盘，滑动“我的”页面时产生明显卡顿。
String _avatarCacheKey(String? avatarUrl, String? userId) {
  return '${userId ?? ''}|${avatarUrl?.trim() ?? ''}';
}

Future<String> _copyLocalAvatarFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception(I18n.tr('profile.avatar.file_empty'));
  }
  if (bytes.length > 3 * 1024 * 1024) {
    throw Exception(I18n.tr('profile.avatar.too_large'));
  }
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/profile_avatars');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final filename =
      'avatar_${DateTime.now().microsecondsSinceEpoch}${_avatarExtensionFor(file.name)}';
  final target = File('${dir.path}/$filename');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

String _avatarExtensionFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpeg')) return '.jpg';
  for (final extension in ['.jpg', '.png', '.webp', '.gif']) {
    if (lower.endsWith(extension)) return extension;
  }
  return '.png';
}

String _avatarErrorMessage(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}

class _MineStatsGrid extends StatelessWidget {
  final List<Widget> cards;

  const _MineStatsGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final columns = compact ? 2 : 4;
          final baseHeight = compact ? 70.0 : 64.0;
          final fontGrowth =
              (MediaQuery.textScalerOf(
                        context,
                      ).scale(DesignTokens.fontSizeBody) -
                      DesignTokens.fontSizeBody)
                  .clamp(0.0, double.infinity);
          final rows = <Widget>[];

          for (var index = 0; index < cards.length; index += columns) {
            final rowCards = cards.skip(index).take(columns).toList();
            rows.add(
              SizedBox(
                height: baseHeight + fontGrowth * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rowCards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: RepaintBoundary(child: rowCards[i])),
                    ],
                    for (var i = rowCards.length; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            key: const ValueKey('mine_stats_stable_grid'),
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                rows[i],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AiWeeklyReviewCard extends StatefulWidget {
  final TodoProvider todoProvider;
  final PomodoroProvider pomodoroProvider;
  final HabitProvider habitProvider;
  const _AiWeeklyReviewCard({
    required this.todoProvider,
    required this.pomodoroProvider,
    required this.habitProvider,
  });

  @override
  State<_AiWeeklyReviewCard> createState() => _AiWeeklyReviewCardState();
}

class _AiWeeklyReviewCardState extends State<_AiWeeklyReviewCard> {
  bool _busy = false;
  String? _result;
  String? _summary;
  String? _error;
  bool _generatedToday = false;
  bool _reviewExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppClock.watch(context);
    final cached = context.read<AiService>().weeklyReviewForDay(AppClock.now());
    if (cached != null && _result == null) {
      _result = cached.content;
      _summary = cached.summary;
      _generatedToday = true;
      _reviewExpanded = false;
    }
  }

  Future<void> _run() async {
    final cached = context.read<AiService>().weeklyReviewForDay(AppClock.now());
    if (cached != null) {
      setState(() {
        _result = cached.content;
        _summary = cached.summary;
        _generatedToday = true;
        _reviewExpanded = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ai = context.read<AiService>();
      final now = AppClock.now();
      final range = _reviewRange(now);
      final completed = widget.todoProvider.completedTodos
          .where((t) => _inRange(t.completedAt ?? t.updatedAt, range))
          .length;
      final total = widget.todoProvider.todos
          .where((t) => _inRange(t.date, range))
          .length;
      final focus =
          widget.pomodoroProvider.sessions
              .where(
                (s) => s.type.name == 'focus' && _inRange(s.startTime, range),
              )
              .fold(0, (sum, s) => sum + s.durationSeconds) ~/
          60;
      final streak = widget.habitProvider.longestCurrentStreak;
      final label = _reviewRangeLabel(now);
      _result = await ai.weeklyReview(
        completedTodos: completed,
        totalTodos: total,
        weeklyFocusMinutes: focus,
        habitStreak: streak,
        periodLabel: label,
      );
      _summary =
          '$label${I18n.tr('mine.ai.summary.header_suffix')}$completed / $total${I18n.tr('mine.ai.summary.todos_suffix')}$focus${I18n.tr('mine.ai.summary.focus_suffix')}$streak${I18n.tr('mine.ai.summary.streak_suffix')}';
      _generatedToday = true;
      _reviewExpanded = true;
    } on AiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({DateTime start, DateTime end}) _reviewRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final start = now.weekday == DateTime.monday
        ? thisMonday.subtract(const Duration(days: 7))
        : thisMonday;
    return (
      start: AppClock.date(start.year, start.month, start.day),
      end: AppClock.date(start.year, start.month, start.day + 7),
    );
  }

  String _reviewRangeLabel(DateTime now) => I18n.tr(
    now.weekday == DateTime.monday
        ? 'mine.ai.range.last_week'
        : 'mine.ai.range.this_week',
  );

  bool _inRange(DateTime at, ({DateTime start, DateTime end}) range) {
    return !at.isBefore(range.start) && at.isBefore(range.end);
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final hasReview = _result != null;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: cs.primary, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                I18n.tr('mine.ai.review_title'),
                style: const TextStyle(
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const Spacer(),
              if (hasReview)
                IconButton(
                  key: const ValueKey('mine_ai_review_toggle'),
                  tooltip: I18n.tr(
                    _reviewExpanded ? 'mine.ai.collapse' : 'mine.ai.expand',
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      setState(() => _reviewExpanded = !_reviewExpanded),
                  icon: Icon(
                    _reviewExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
              TextButton(
                onPressed: _busy || _generatedToday ? null : _run,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        I18n.tr(
                          _generatedToday
                              ? 'mine.ai.generated_today'
                              : 'mine.ai.generate',
                        ),
                      ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_summary != null) ...[
                    Text(
                      _summary!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  ClipRect(
                    key: const ValueKey('mine_ai_review_content'),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: _reviewExpanded
                          ? Text(
                              _result!,
                              style: const TextStyle(fontSize: 13, height: 1.6),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (!_reviewExpanded)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _reviewExpanded = true),
                      icon: const Icon(Icons.unfold_more, size: 15),
                      label: Text(I18n.tr('mine.ai.expand_full')),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "${I18n.tr('mine.ai.hint_prefix')}${_reviewRangeLabel(AppClock.now())}${I18n.tr('mine.ai.hint_suffix')}",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

class _MineMenuScreen extends StatelessWidget {
  final String title;
  final List<Widget> sections;

  const _MineMenuScreen({required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final background = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: ValueKey('mine_menu_$title'),
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceLg),
          children: sections,
        ),
      ),
    );
  }
}

class _TileGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// 瓦片列数：1 = 原单列通栏（窄屏），2 = 宽屏两列网格。
  final int columns;

  const _TileGroup({
    required this.title,
    required this.children,
    this.columns = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.15,
                fontWeight: DesignTokens.fontWeightStrong,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          AppSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: columns > 1
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      // 宽屏两列瓦片网格：瓦片自带内边距，组内不再画通栏
                      // 分隔线；可读宽度不足时自动退回单列。
                      final gap = DesignTokens.spaceXs;
                      final cellWidth = (constraints.maxWidth - gap) / 2;
                      if (cellWidth < 240) {
                        return _singleColumn(cs);
                      }
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          for (final child in children)
                            SizedBox(width: cellWidth, child: child),
                        ],
                      );
                    },
                  )
                : _singleColumn(cs),
          ),
        ],
      ),
    );
  }

  Widget _singleColumn(ColorScheme cs) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 44,
              color: cs.outlineVariant.withValues(alpha: 0.14),
            ),
          children[i],
        ],
      ],
    );
  }
}

class _UpdateAvailableBadge extends StatelessWidget {
  final String? version;

  const _UpdateAvailableBadge({this.version});

  @override
  Widget build(BuildContext context) {
    final text = version == null || version!.trim().isEmpty
        ? I18n.tr('mine.update.badge')
        : "${I18n.tr('mine.update.badge_version_prefix')}$version";
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 96),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(context).copyWith(
                        fontSize: DesignTokens.fontSizeBody,
                        height: 1.4,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: DesignTokens.fontSizeSecondary,
                          height: 1.15,
                          color: cs.onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child:
                    trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.34),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
