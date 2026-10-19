import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

void main() {
  group('Android 小组件资源', () {
    final legacyWidget = _WidgetResource(
      title: '历史兼容主小组件',
      providerXml: 'duoyi_widget_info.xml',
      layoutXml: 'duoyi_widget.xml',
      previewPng: 'widget_preview.png',
      receiver: 'DuoyiWidgetProvider',
      previewDrawable: 'widget_preview',
      layoutName: 'duoyi_widget',
      ids: [
        '@+id/widget_bottom_nav',
        '@+id/widget_nav_todo',
        '@+id/widget_nav_habit',
        '@+id/widget_nav_calendar',
        '@+id/widget_nav_focus',
        '@+id/widget_goal_summary',
        '@+id/widget_anniversary_summary',
        '@+id/widget_course_summary',
      ],
      compact: true,
    );
    final widgets = <_WidgetResource>[
      _WidgetResource(
        title: '今日待办',
        providerXml: 'duoyi_todo_widget_info.xml',
        layoutXml: 'duoyi_todo_widget.xml',
        previewPng: 'widget_todo_preview.png',
        receiver: 'DuoyiTodoWidgetProvider',
        previewDrawable: 'widget_todo_preview',
        layoutName: 'duoyi_todo_widget',
        ids: [
          '@+id/widget_todo_bottom_nav',
          '@+id/widget_todo_title',
          '@+id/widget_todo_count',
          '@+id/widget_todo_nav_todo',
          '@+id/widget_todo_nav_habit',
          '@+id/widget_todo_nav_calendar',
          '@+id/widget_todo_nav_focus',
          '@+id/widget_todo_row_1',
          '@+id/widget_todo_row_2',
          '@+id/widget_todo_row_3',
          '@+id/widget_todo_today_summary',
          '@+id/widget_todo_quick_add',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '专注',
        providerXml: 'duoyi_focus_habit_widget_info.xml',
        layoutXml: 'duoyi_focus_habit_widget.xml',
        previewPng: 'widget_focus_habit_preview.png',
        receiver: 'DuoyiFocusHabitWidgetProvider',
        previewDrawable: 'widget_focus_habit_preview',
        layoutName: 'duoyi_focus_habit_widget',
        ids: [
          '@+id/widget_focus_habit_bottom_nav',
          '@+id/widget_focus_habit_title',
          '@+id/widget_focus_habit_date',
          '@+id/widget_focus_nav_todo',
          '@+id/widget_focus_nav_habit',
          '@+id/widget_focus_nav_calendar',
          '@+id/widget_focus_nav_focus',
          '@+id/widget_focus_streak_count',
          '@+id/widget_focus_quick_start',
          '@+id/widget_focus_habit_summary',
          '@+id/widget_focus_streak_summary',
          '@+id/widget_focus_timer_caption',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '习惯',
        providerXml: 'duoyi_habit_widget_info.xml',
        layoutXml: 'duoyi_habit_widget.xml',
        previewPng: 'widget_habit_preview.png',
        receiver: 'DuoyiHabitWidgetProvider',
        previewDrawable: 'widget_habit_preview',
        layoutName: 'duoyi_habit_widget',
        ids: [
          '@+id/widget_habit_bottom_nav',
          '@+id/widget_habit_title',
          '@+id/widget_habit_subtitle',
          '@+id/widget_habit_nav_todo',
          '@+id/widget_habit_nav_habit',
          '@+id/widget_habit_nav_calendar',
          '@+id/widget_habit_nav_focus',
          '@+id/widget_habit_summary',
          '@+id/widget_habit_streak',
          '@+id/widget_habit_hint',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '月历',
        providerXml: 'duoyi_calendar_widget_info.xml',
        layoutXml: 'duoyi_calendar_widget.xml',
        previewPng: 'widget_calendar_preview.png',
        receiver: 'DuoyiCalendarWidgetProvider',
        previewDrawable: 'widget_calendar_preview',
        layoutName: 'duoyi_calendar_widget',
        ids: [
          '@+id/widget_calendar_bottom_nav',
          '@+id/widget_calendar_title',
          '@+id/widget_calendar_month',
          '@+id/widget_calendar_nav_todo',
          '@+id/widget_calendar_nav_habit',
          '@+id/widget_calendar_nav_calendar',
          '@+id/widget_calendar_nav_focus',
          '@+id/widget_calendar_grid',
          '@+id/widget_calendar_summary',
          '@+id/widget_calendar_today_button',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '今日日程',
        providerXml: 'duoyi_schedule_widget_info.xml',
        layoutXml: 'duoyi_schedule_widget.xml',
        previewPng: 'widget_schedule_preview.png',
        receiver: 'DuoyiScheduleWidgetProvider',
        previewDrawable: 'widget_schedule_preview',
        layoutName: 'duoyi_schedule_widget',
        ids: [
          '@+id/widget_schedule_bottom_nav',
          '@+id/widget_schedule_title',
          '@+id/widget_schedule_subtitle',
          '@+id/widget_schedule_nav_todo',
          '@+id/widget_schedule_nav_habit',
          '@+id/widget_schedule_nav_calendar',
          '@+id/widget_schedule_nav_focus',
          '@+id/widget_schedule_1',
          '@+id/widget_schedule_2',
          '@+id/widget_schedule_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '目标',
        providerXml: 'duoyi_goal_widget_info.xml',
        layoutXml: 'duoyi_goal_widget.xml',
        previewPng: 'widget_goal_preview.png',
        receiver: 'DuoyiGoalWidgetProvider',
        previewDrawable: 'widget_goal_preview',
        layoutName: 'duoyi_goal_widget',
        ids: [
          '@+id/widget_goal_bottom_nav',
          '@+id/widget_goal_title',
          '@+id/widget_goal_subtitle',
          '@+id/widget_goal_nav_todo',
          '@+id/widget_goal_nav_habit',
          '@+id/widget_goal_nav_calendar',
          '@+id/widget_goal_nav_focus',
          '@+id/widget_goal_1',
          '@+id/widget_goal_2',
          '@+id/widget_goal_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '课程表',
        providerXml: 'duoyi_course_widget_info.xml',
        layoutXml: 'duoyi_course_widget.xml',
        previewPng: 'widget_course_preview.png',
        receiver: 'DuoyiCourseWidgetProvider',
        previewDrawable: 'widget_course_preview',
        layoutName: 'duoyi_course_widget',
        ids: [
          '@+id/widget_course_bottom_nav',
          '@+id/widget_course_title',
          '@+id/widget_course_subtitle',
          '@+id/widget_course_nav_todo',
          '@+id/widget_course_nav_habit',
          '@+id/widget_course_nav_calendar',
          '@+id/widget_course_nav_focus',
          '@+id/widget_course_1',
          '@+id/widget_course_2',
          '@+id/widget_course_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '随手记',
        providerXml: 'duoyi_note_widget_info.xml',
        layoutXml: 'duoyi_note_widget.xml',
        previewPng: 'widget_note_preview.png',
        receiver: 'DuoyiNoteWidgetProvider',
        previewDrawable: 'widget_note_preview',
        layoutName: 'duoyi_note_widget',
        ids: [
          '@+id/widget_note_bottom_nav',
          '@+id/widget_note_title',
          '@+id/widget_note_subtitle',
          '@+id/widget_note_nav_todo',
          '@+id/widget_note_nav_habit',
          '@+id/widget_note_nav_calendar',
          '@+id/widget_note_nav_focus',
          '@+id/widget_note_1',
          '@+id/widget_note_2',
          '@+id/widget_note_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '纪念日',
        providerXml: 'duoyi_anniversary_widget_info.xml',
        layoutXml: 'duoyi_anniversary_widget.xml',
        previewPng: 'widget_anniversary_preview.png',
        receiver: 'DuoyiAnniversaryWidgetProvider',
        previewDrawable: 'widget_anniversary_preview',
        layoutName: 'duoyi_anniversary_widget',
        ids: [
          '@+id/widget_anniversary_bottom_nav',
          '@+id/widget_anniversary_title',
          '@+id/widget_anniversary_subtitle',
          '@+id/widget_anniversary_nav_todo',
          '@+id/widget_anniversary_nav_habit',
          '@+id/widget_anniversary_nav_calendar',
          '@+id/widget_anniversary_nav_focus',
          '@+id/widget_anniversary_1',
          '@+id/widget_anniversary_2',
          '@+id/widget_anniversary_3',
        ],
        compact: false,
      ),
    ];

    for (final widget in widgets) {
      test('${widget.title}小组件声明底部导航和 PNG 预览', () {
        _assertWidgetResource(widget);
      });
    }

    test('所有桌面小组件单行文本都声明截断边界', () {
      final layoutFiles =
          Directory(
              'android/app/src/main/res/layout',
            ).listSync().whereType<File>().where((file) {
              final name = file.uri.pathSegments.last;
              return name.startsWith('duoyi_') &&
                  name.contains('widget') &&
                  name.endsWith('.xml');
            }).toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(layoutFiles, isNotEmpty);

      for (final file in layoutFiles) {
        final layout = file.readAsStringSync();
        for (final block in _textViewBlocks(layout)) {
          final id = _textViewId(block);
          if (id == 'widget_calendar_grid') continue;
          expect(
            block,
            contains('android:maxLines='),
            reason: '${file.path} ${id ?? '<anonymous>'} must not grow rows',
          );
          expect(
            block,
            contains('android:ellipsize="end"'),
            reason:
                '${file.path} ${id ?? '<anonymous>'} must clip long widget text',
          );
        }
      }
    });

    test('桌面小组件动态短文本使用 wrap_content 时声明最大宽度', () {
      const constrainedDynamicTextIds = {
        'widget_todo_count',
        'widget_focus_habit_date',
        'widget_calendar_month',
        'widget_habit_percent',
        'widget_date',
      };
      final layoutFiles =
          Directory(
              'android/app/src/main/res/layout',
            ).listSync().whereType<File>().where((file) {
              final name = file.uri.pathSegments.last;
              return name.startsWith('duoyi_') &&
                  name.contains('widget') &&
                  name.endsWith('.xml');
            }).toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in layoutFiles) {
        final layout = file.readAsStringSync();
        for (final block in _textViewBlocks(layout)) {
          final id = _textViewId(block);
          if (!constrainedDynamicTextIds.contains(id)) continue;
          expect(block, contains('android:layout_width="wrap_content"'));
          expect(
            block,
            contains('android:maxWidth='),
            reason:
                '${file.path} $id must cap short dynamic text width in widget headers',
          );
        }
      }
    });

    test('桌面小组件圆角背景和按钮跟随主题且不被纯色背景覆盖', () {
      final theme = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetTheme.kt',
      ).readAsStringSync();
      final rootBg = File(
        'android/app/src/main/res/drawable/widget_bg.xml',
      ).readAsStringSync();
      final navBg = File(
        'android/app/src/main/res/drawable/widget_nav_bg.xml',
      ).readAsStringSync();
      final primaryButton = File(
        'android/app/src/main/res/drawable/widget_btn_primary.xml',
      ).readAsStringSync();
      final secondaryButton = File(
        'android/app/src/main/res/drawable/widget_btn_secondary.xml',
      ).readAsStringSync();
      final legacyProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetProvider.kt',
      ).readAsStringSync();
      final todoProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
      ).readAsStringSync();
      final focusProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();

      expect(theme, contains('setBackgroundTintList'));
      expect(theme, contains('fun applyButtonSurfaces('));
      expect(
        theme,
        isNot(contains('views.setInt(rootId, "setBackgroundColor"')),
      );
      expect(theme, contains('backgroundAssetKey'));
      expect(
        theme,
        contains('backgroundImageResource(theme.backgroundAssetKey)'),
      );
      expect(theme, contains('applyImageBackedSurface('));
      expect(theme, contains('views.setImageViewResource('));
      expect(theme, contains('views.setImageViewBitmap('));
      expect(theme, contains('roundedBackgroundBitmap('));
      expect(theme, contains('backgroundBitmapCache'));
      expect(theme, contains('maxBackgroundBitmapCacheEntries'));
      expect(theme, contains('renderRoundedBackgroundBitmap('));
      expect(theme, contains('source.recycle()'));
      expect(theme, contains('centerCropRect('));
      expect(theme, contains('R.id.widget_theme_background'));
      expect(theme, contains('R.id.widget_theme_overlay'));
      expect(theme, contains('imageOverlayColor(theme)'));
      expect(
        theme,
        contains(
          'views.setViewVisibility(R.id.widget_theme_overlay, View.VISIBLE)',
        ),
      );
      expect(theme, contains('"starrail",'));
      expect(
        theme,
        contains(
          '"assets/backgrounds/star_rail.png" -> R.drawable.widget_theme_star_rail',
        ),
      );
      expect(
        theme,
        contains('"assets/backgrounds/re0.png" -> R.drawable.widget_theme_re0'),
      );
      expect(theme, contains('"starrail",'));
      expect(theme, contains('"wutheringwaves",'));
      for (final key in [
        're0',
        'genshin',
        'star_rail',
        'wuthering',
        'zzz',
        'yanyun',
        'botw',
      ]) {
        expect(theme, contains('R.drawable.widget_theme_$key'));
        expect(
          File(
            'android/app/src/main/res/drawable-nodpi/widget_theme_$key.png',
          ).existsSync(),
          isTrue,
        );
      }
      expect(service, contains('backgroundAssetKey: _backgroundAssetKey'));
      expect(service, contains("'widget_theme_background_asset_key'"));
      expect(service, contains("'assets/backgrounds/re0.png' => 're0'"));
      expect(
        service,
        contains('Future<bool> updateTheme(HomeWidgetThemePayload theme)'),
      );
      expect(service, contains('[HomeWidget] updateTheme failed:'));
      expect(rootBg, contains('<corners android:radius="16dp" />'));
      expect(navBg, contains('<corners android:radius="9dp" />'));
      expect(primaryButton, contains('<corners android:radius="8dp" />'));
      expect(secondaryButton, contains('<corners android:radius="8dp" />'));
      final layoutFiles =
          Directory('android/app/src/main/res/layout')
              .listSync()
              .whereType<File>()
              .where(
                (file) =>
                    file.uri.pathSegments.last.startsWith('duoyi') &&
                    file.uri.pathSegments.last.endsWith('_widget.xml') &&
                    !file.uri.pathSegments.last.contains('preview'),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(
        layoutFiles.map((file) => file.path).toSet(),
        hasLength(layoutFiles.length),
      );
      for (final file in layoutFiles) {
        final xml = file.readAsStringSync();
        expect(xml, contains('<FrameLayout'));
        expect(xml, contains('android:clipToOutline="true"'));
        expect(xml, contains('@+id/widget_theme_background'));
        expect(xml, contains('android:scaleType="centerCrop"'));
        expect(xml, contains('@+id/widget_theme_overlay'));
        expect(
          xml,
          isNot(contains('<View')),
          reason:
              'Launcher RemoteViews hosts do not reliably support plain android.view.View; overlay must use a supported widget class.',
        );
      }
      expect(legacyProvider, contains('DuoyiWidgetTheme.applyButtonSurfaces('));
      expect(legacyProvider, contains('R.id.widget_quick_pomodoro'));
      expect(legacyProvider, contains('R.id.widget_quick_open'));
      expect(todoProvider, contains('DuoyiWidgetTheme.applyButtonSurfaces('));
      expect(todoProvider, contains('R.id.widget_todo_quick_add'));
      expect(focusProvider, contains('DuoyiWidgetTheme.applyButtonSurfaces('));
      expect(focusProvider, contains('R.id.widget_focus_quick_start'));
    });

    test('历史兼容主小组件保留注册用于升级前旧实例刷新', () {
      _assertWidgetResource(legacyWidget);
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final strings = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final configActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
      ).readAsStringSync();
      final legacyProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetProvider.kt',
      ).readAsStringSync();

      final legacyReceiver = _receiverBlock(manifest, 'DuoyiWidgetProvider');
      expect(legacyReceiver, contains('android:name=".DuoyiWidgetProvider"'));
      expect(
        legacyReceiver,
        contains('android.intent.action.MY_PACKAGE_REPLACED'),
      );
      expect(
        legacyReceiver,
        contains('android:resource="@xml/duoyi_widget_info"'),
      );
      expect(strings, isNot(contains('今日待办 / 习惯')));
      expect(strings, contains('历史兼容小组件'));
      final legacyInfo = File(
        'android/app/src/main/res/xml/duoyi_widget_info.xml',
      ).readAsStringSync();
      expect(legacyInfo, contains('android:targetCellWidth="3"'));
      expect(legacyInfo, contains('android:targetCellHeight="2"'));
      expect(legacyInfo, isNot(contains('android:targetCellHeight="3"')));
      expect(service, isNot(contains('_androidProviderName')));
      expect(
        service,
        isNot(contains("_androidLegacyProviderName = 'DuoyiWidgetProvider'")),
        reason:
            'Android legacy provider refresh should be covered by one native all-provider refresh.',
      );
      expect(
        configActivity,
        isNot(contains('DuoyiWidgetProvider.requestUpdate')),
      );
      expect(
        legacyProvider,
        contains(
          'DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(context)',
        ),
      );
    });

    test('升级或重启后恢复旧桌面小组件并延后启动期恢复任务', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final restoreReceiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetRestoreReceiver.kt',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();

      final receiverBlock = _receiverBlock(
        manifest,
        'DuoyiWidgetRestoreReceiver',
      );
      expect(
        receiverBlock,
        contains('android:name=".DuoyiWidgetRestoreReceiver"'),
      );
      expect(receiverBlock, contains('android:exported="true"'));
      expect(receiverBlock, contains('android.intent.action.BOOT_COMPLETED'));
      expect(
        receiverBlock,
        contains('android.intent.action.MY_PACKAGE_REPLACED'),
      );
      expect(
        receiverBlock,
        contains('android.intent.action.QUICKBOOT_POWERON'),
      );
      expect(restoreReceiver, contains('class DuoyiWidgetRestoreReceiver'));
      expect(
        restoreReceiver,
        contains('restoreEnabledProvidersForExistingWidgets(appContext)'),
      );
      expect(
        restoreReceiver,
        contains('requestUpdateForAllWidgets(appContext)'),
      );
      expect(variants, contains('active_variant_providers'));
      expect(variants, contains('markVariantProviderActive'));
      expect(variants, contains('restoreEnabledProvidersForExistingWidgets'));
      expect(
        variants,
        isNot(contains('widgetFamilies.flatMap { it.variantProviderClasses }')),
        reason:
            'Restore must not enable every compact/detailed provider on each app resume; only existing or active instances should be restored.',
      );
      expect(variants, contains('ensureProviderEnabled(context, component)'));
      expect(mainActivity, contains('scheduleWidgetRestoreAfterResume()'));
      expect(mainActivity, contains('widgetRestoreHandler.postDelayed'));
      expect(
        mainActivity,
        contains('}, 4_500L)'),
        reason: '启动和杀后台重进时小组件 provider 扫描应延后，不能压住首屏。',
      );
      expect(mainActivity, contains('lastWidgetRestoreAtMillis < 60_000L'));
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(appContext)',
        ),
        reason:
            'The delayed resume restore should repaint all registered widget providers after enabling variants.',
      );
      expect(
        mainActivity,
        contains(
          '"refreshAllWidgets" -> {\n                        DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(this)',
        ),
        reason:
            'Flutter-triggered widget refresh must restore disabled providers before repainting existing widgets.',
      );
      expect(
        mainActivity,
        isNot(
          contains(
            'override fun onResume() {\n        super.onResume()\n        DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(this)',
          ),
        ),
      );
    });

    test('专注、习惯、月历、今日日程、目标保持独立，不再暴露组合入口', () {
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final focusLayout = File(
        'android/app/src/main/res/layout/duoyi_focus_habit_widget.xml',
      ).readAsStringSync();
      final calendarLayout = File(
        'android/app/src/main/res/layout/duoyi_calendar_widget.xml',
      ).readAsStringSync();
      final calendarProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt',
      ).readAsStringSync();
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      expect(widgetScreen, isNot(contains('专注与习惯预览')));
      expect(widgetScreen, isNot(contains('月历日程预览')));
      expect(widgetScreen, contains('专注预览'));
      expect(widgetScreen, contains('习惯预览'));
      expect(widgetScreen, contains('月历预览'));
      expect(widgetScreen, contains('今日日程预览'));
      expect(widgetScreen, contains('目标预览'));
      expect(widgetScreen, contains('WidgetPreviewCard.focus'));
      expect(widgetScreen, contains('WidgetPreviewCard.habit'));
      expect(widgetScreen, contains('WidgetPreviewCard.schedule'));
      expect(widgetScreen, contains('WidgetPreviewCard.goal'));
      expect(focusLayout, isNot(contains('专注与习惯')));
      expect(focusLayout, isNot(contains('习惯完成')));
      expect(calendarLayout, contains('widget_calendar_today_button'));
      expect(calendarProvider, isNot(contains('calendar_day_summary_')));
      expect(manager, contains('DuoyiWidgetKind.focus'));
      expect(manager, contains('DuoyiWidgetKind.habit'));
      expect(manager, contains('DuoyiWidgetKind.schedule'));
      expect(manager, contains('DuoyiWidgetKind.goal'));
      expect(manager, isNot(contains('DuoyiWidgetKind.focusHabit')));
      expect(manager, isNot(contains("'focus_habit'")));
      expect(mainActivity, isNot(contains('"focus_habit"')));
    });

    test('应用内添加失败提示区分 launcher、权限、弹窗拦截和迟到回执', () {
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();

      expect(manager, contains('confirmationBlocked'));
      expect(manager, contains("'confirmation_blocked'"));
      expect(manager, contains("'canOpenWidgetSettings'"));
      expect(mainActivity, contains('"canOpenWidgetSettings"'));
      expect(mainActivity, contains('"confirmation_blocked"'));
      expect(mainActivity, contains('catch (e: SecurityException)'));
      expect(mainActivity, contains('"permission_denied"'));
      expect(
        mainActivity,
        contains('appWidgetSettingsIntent() ?: return false'),
      );
      expect(mainActivity, contains('resolveActivity(packageManager)'));

      expect(widgetScreen, contains('当前桌面启动器不支持应用内直接添加小组件'));
      expect(widgetScreen, contains('系统拒绝了本次添加请求'));
      expect(widgetScreen, contains('桌面没有展示或接受系统确认弹窗'));
      expect(widgetScreen, contains('已发起添加请求，但桌面暂未返回确认结果'));
      expect(widgetScreen, contains('if (widget.canOpenWidgetSettings)'));
      expect(widgetScreen, contains('if (canOpenSettings)'));
      expect(widgetScreen, contains('打开权限设置'));
      expect(mainActivity, contains('miui.intent.action.APP_PERM_EDITOR'));
      expect(
        mainActivity,
        contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'),
      );
    });

    test('底部导航每个入口都绑定到对应深链', () {
      final providerSources = {
        'todo': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
        ).readAsStringSync(),
        'focus': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt',
        ).readAsStringSync(),
        'habit': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiHabitWidgetProvider.kt',
        ).readAsStringSync(),
        'calendar': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt',
        ).readAsStringSync(),
        'schedule': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt',
        ).readAsStringSync(),
        'goal': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt',
        ).readAsStringSync(),
        'course': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt',
        ).readAsStringSync(),
        'note': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt',
        ).readAsStringSync(),
        'anniversary': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt',
        ).readAsStringSync(),
        'diary': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt',
        ).readAsStringSync(),
      };

      for (final source in providerSources.values) {
        expect(source, contains('Uri.parse("duoyi://tab/todo")'));
        expect(source, contains('Uri.parse("duoyi://tab/habit")'));
        expect(source, contains('Uri.parse("duoyi://tab/calendar")'));
        expect(source, contains('Uri.parse("duoyi://tab/focus")'));
        expect(source, contains('HomeWidgetLaunchIntent.getActivity'));
      }
      expect(providerSources['todo'], contains('duoyi://action/quick_todo'));
      expect(
        providerSources['todo'],
        contains('val encodedTodoId = Uri.encode(todoId)'),
      );
      expect(providerSources['todo'], contains(r'duoyi://todo/$encodedTodoId'));
      expect(
        providerSources['todo'],
        contains(r'duoyi://action/complete_todo?id=$encodedTodoId'),
      );
      expect(providerSources['todo'], isNot(contains(r'duoyi://todo/$todoId')));
      expect(
        providerSources['todo'],
        isNot(contains(r'duoyi://action/complete_todo?id=$todoId')),
      );
      expect(
        providerSources['todo'],
        contains('R.id.widget_todo_quick_add, quickAdd'),
      );
      expect(providerSources['todo'], contains('R.id.widget_todo_title, open'));
      expect(providerSources['todo'], contains('R.id.widget_todo_count, open'));
      expect(
        providerSources['todo'],
        contains('R.id.widget_todo_today_summary, open'),
      );
      expect(
        providerSources['todo'],
        contains(
          'if (todoId.isBlank()) {\n'
          '            views.setViewVisibility(doneViewId, View.GONE)\n'
          '            views.setOnClickPendingIntent(\n'
          '                itemViewId,',
        ),
      );
      expect(providerSources['todo'], contains('R.id.widget_todo_item_1'));
      expect(
        providerSources['todo'],
        contains('Uri.parse("duoyi://tab/todo")'),
        reason: '空待办行文本也要能打开待办页，不能只依赖父行点击',
      );
      expect(
        providerSources['focus'],
        contains('duoyi://action/start_pomodoro'),
      );
      expect(
        providerSources['focus'],
        contains('R.id.widget_focus_habit_title, openFocus'),
      );
      expect(
        providerSources['focus'],
        contains('R.id.widget_focus_streak_count, openFocus'),
      );
      expect(
        providerSources['focus'],
        contains('R.id.widget_focus_streak_summary, openFocus'),
      );
      expect(providerSources['focus'], contains('focus_timer_running'));
      expect(
        providerSources['focus'],
        contains('focus_timer_remaining_seconds'),
      );
      expect(providerSources['focus'], contains('focus_timer_ends_at_millis'));
      expect(providerSources['focus'], contains('formatTimer'));
      expect(providerSources['focus'], contains('查看倒计时'));
      expect(
        providerSources['habit'],
        contains('duoyi://action/checkin_habit?id='),
      );
      expect(
        providerSources['habit'],
        contains('Uri.encode(habitQuickCheckId)'),
      );
      expect(
        providerSources['habit'],
        contains('R.id.widget_habit_hint, quickCheckHabit'),
      );
      final headerBindings = <String, ({String title, String subtitle})>{
        'habit': (
          title: 'R.id.widget_habit_title, openHabit',
          subtitle: 'R.id.widget_habit_subtitle, openHabit',
        ),
        'schedule': (
          title: 'R.id.widget_schedule_title, openCalendar',
          subtitle: 'R.id.widget_schedule_subtitle, openCalendar',
        ),
        'goal': (
          title: 'R.id.widget_goal_title, openGoal',
          subtitle: 'R.id.widget_goal_subtitle, openGoal',
        ),
        'course': (
          title: 'R.id.widget_course_title, openCourse',
          subtitle: 'R.id.widget_course_subtitle, openCourse',
        ),
        'note': (
          title: 'R.id.widget_note_title, openNote',
          subtitle: 'R.id.widget_note_subtitle, openNote',
        ),
        'anniversary': (
          title: 'R.id.widget_anniversary_title, openAnniversary',
          subtitle: 'R.id.widget_anniversary_subtitle, openAnniversary',
        ),
        'diary': (
          title: 'R.id.widget_diary_title, openDiary',
          subtitle: 'R.id.widget_diary_subtitle, openDiary',
        ),
      };
      for (final entry in headerBindings.entries) {
        final source = providerSources[entry.key]!;
        expect(source, contains(entry.value.title));
        expect(source, contains(entry.value.subtitle));
      }
      expect(
        providerSources['calendar'],
        contains('R.id.widget_calendar_title, openCalendar'),
      );
      expect(
        providerSources['calendar'],
        contains('R.id.widget_calendar_month, openCalendar'),
      );
      expect(providerSources['goal'], contains('duoyi://goal'));
      expect(providerSources['goal'], isNot(contains('duoyi://tab/today')));
      expect(providerSources['goal'], contains('goal_highlight_1_id'));
      expect(providerSources['goal'], contains('goal_highlight_2_id'));
      expect(providerSources['goal'], contains('goal_highlight_3_id'));
      expect(
        providerSources['goal'],
        contains('if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)'),
        reason:
            'Flutter already stores full duoyi:// detail links for widget rows; Android must not encode the full URI as an id.',
      );
      expect(
        providerSources['goal'],
        contains(r'Uri.parse("$fallback/${Uri.encode(rawId)}")'),
        reason:
            'Legacy raw ids still need to be converted into a duoyi:// detail deep link before launching Flutter.',
      );
      expect(
        providerSources['goal'],
        isNot(
          contains(
            'Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })',
          ),
        ),
      );
      expect(providerSources['course'], contains('course_highlight_1_id'));
      expect(providerSources['course'], contains('course_highlight_2_id'));
      expect(providerSources['course'], contains('course_highlight_3_id'));
      expect(providerSources['course'], contains('duoyi://course'));
      expect(
        providerSources['course'],
        contains('R.id.widget_course_root, openCourse'),
      );
      expect(providerSources['schedule'], contains('schedule_highlight_1_id'));
      expect(providerSources['schedule'], contains('schedule_highlight_2_id'));
      expect(providerSources['schedule'], contains('schedule_highlight_3_id'));
      expect(providerSources['note'], contains('Uri.parse("duoyi://note")'));
      expect(providerSources['note'], contains('note_highlight_1_id'));
      expect(providerSources['note'], contains('note_highlight_2_id'));
      expect(providerSources['note'], contains('note_highlight_3_id'));
      expect(
        providerSources['anniversary'],
        contains('Uri.parse("duoyi://anniversary")'),
      );
      expect(
        providerSources['anniversary'],
        contains('anniversary_highlight_1_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('anniversary_highlight_2_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_1_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_2_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_3_id'),
      );
      expect(providerSources['diary'], contains('Uri.parse("duoyi://diary")'));
      expect(providerSources['diary'], contains('diary_highlight_1_id'));
      expect(providerSources['diary'], contains('diary_highlight_2_id'));
      expect(providerSources['diary'], contains('diary_highlight_3_id'));
      expect(providerSources['focus'], contains('focus_minutes_today'));
      final homeWidgetService = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      expect(homeWidgetService, contains('HomeWidget.saveWidgetData<int>('));
      expect(homeWidgetService, contains("'focus_minutes_today'"));
      expect(
        providerSources['focus'],
        isNot(contains('HomeWidgetBackgroundIntent')),
      );
    });

    test('待办小组件未完成任务使用 o 圆圈并保留交互按钮', () {
      final layout = File(
        'android/app/src/main/res/layout/duoyi_todo_widget.xml',
      ).readAsStringSync();
      final provider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();

      for (final index in [1, 2, 3]) {
        final doneView = _xmlTextViewWithId(layout, 'widget_todo_done_$index');
        expect(
          doneView,
          contains('android:text="o"'),
          reason: '待办小组件展示的是未完成任务，右侧操作符号应是 o/圆圈，不应误导成已完成勾选。',
        );
        expect(doneView, isNot(contains('android:text="✓"')));
      }

      expect(provider, contains('private fun bindTodoRow('));
      expect(provider, contains('val encodedTodoId = Uri.encode(todoId)'));
      expect(provider, contains(r'Uri.parse("duoyi://todo/$encodedTodoId")'));
      expect(
        provider,
        contains(
          r'Uri.parse("duoyi://action/complete_todo?id=$encodedTodoId")',
        ),
      );
      expect(provider, contains('R.id.widget_todo_quick_add, quickAdd'));
      expect(provider, contains('Uri.parse("duoyi://action/quick_todo")'));

      final todoBody = widgetScreen.substring(
        widgetScreen.indexOf('class _WidgetPreviewTodoBody'),
        widgetScreen.indexOf('class _WidgetPreviewFocusBody'),
      );
      expect(todoBody, contains("const _WidgetPreviewTodoRow(text: '整理今日计划')"));
      expect(
        todoBody,
        contains("const _WidgetPreviewTodoRow(text: '项目复盘 · 3 个子任务')"),
      );
      expect(
        todoBody,
        contains("const _WidgetPreviewTodoRow(text: '晚间运动 30 分钟')"),
      );
      expect(
        todoBody,
        contains("const _WidgetPreviewQuickAdd(label: '+ 添加待办')"),
      );

      final previewRow = widgetScreen.substring(
        widgetScreen.indexOf('class _WidgetPreviewTodoRow'),
        widgetScreen.indexOf('class _WidgetPreviewMetric'),
      );
      expect(previewRow, contains("child: const Text(\n            'o',"));
      expect(previewRow, isNot(contains('Icons.check_circle')));
    });

    test('月历小组件按尺寸裁剪网格并提供今天交互按钮', () {
      final layout = File(
        'android/app/src/main/res/layout/duoyi_calendar_widget.xml',
      ).readAsStringSync();
      final provider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();

      expect(layout, contains('@+id/widget_calendar_today_button'));
      expect(layout, contains('android:text="今天"'));
      expect(provider, contains('R.id.widget_calendar_today_button'));
      expect(provider, contains('DuoyiWidgetTheme.applyButtonSurfaces'));
      expect(provider, contains('DuoyiWidgetDisplayMode.isCompact(prefs, id)'));
      expect(
        provider,
        contains('DuoyiWidgetDisplayMode.isDetailed(prefs, id)'),
      );
      expect(provider, contains('buildMonthGrid(now, compact, detailed)'));
      expect(provider, contains('views.setTextViewTextSize('));
      expect(provider, contains('TypedValue.COMPLEX_UNIT_SP'));
      expect(provider, contains('if (compact) "M月" else "yyyy年M月"'));
      expect(provider, contains('if (compact) View.GONE else View.VISIBLE'));
      expect(
        provider,
        contains(
          'views.setOnClickPendingIntent(R.id.widget_calendar_today_button, openCalendar)',
        ),
      );
      expect(provider, contains('compact -> currentWeek..currentWeek'));
      expect(provider, contains('detailed -> 0..5'));
      expect(provider, contains('currentWeek - 1'));
      expect(widgetScreen, contains('class _WidgetPreviewCalendarGrid'));
      expect(widgetScreen, contains('class _WidgetPreviewCalendarCell'));
      expect(
        widgetScreen,
        contains("child: const Text(\n                '今天',"),
      );
    });

    test('小组件样式密度设置同步预览、新增固定请求和系统添加默认值', () {
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final helper = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDisplayMode.kt',
      ).readAsStringSync();

      expect(service, contains('setDisplayMode'));
      expect(service, contains('widget_display_mode'));
      expect(widgetScreen, contains('小组件样式已设为'));
      expect(widgetScreen, contains('final homeWidgetSynced'));
      expect(
        widgetScreen,
        contains('final nativeSynced = appliedCount != null'),
      );
      expect(widgetScreen, contains('桌面小组件同步失败'));
      expect(widgetScreen, contains(r'已同步 $appliedCount 个桌面实例'));
      expect(widgetScreen, contains('当前未检测到已添加的桌面实例'));
      expect(widgetScreen, contains(r'新添加时会请求 ${mode.launcherRequestLabel}'));
      expect(widgetScreen, contains('桌面格子大小仍由启动器控制'));
      expect(widgetScreen, contains('新添加实例的请求尺寸'));
      expect(widgetScreen, contains('SegmentedButton<WidgetDisplayMode>'));
      expect(
        widgetScreen,
        contains('HomeWidgetService.setDisplayMode(mode.id)'),
        reason:
            'The style selector must update the native default used before new widget instances receive a per-widget style.',
      );
      expect(
        widgetScreen,
        contains("prefs.setString(_displayModeKey, mode.id)"),
      );
      expect(
        widgetScreen,
        contains('AndroidWidgetManager.applyDisplayModeToExistingWidgets'),
      );
      expect(widgetScreen, contains('style: widget.displayMode.androidStyle'));
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();
      expect(manager, contains('applyDisplayModeToExistingWidgets'));
      expect(
        manager,
        contains('Future<int?> applyDisplayModeToExistingWidgets'),
      );
      expect(manager, contains('return null;'));
      expect(manager, contains("'applyWidgetDisplayMode'"));
      expect(mainActivity, contains('"applyWidgetDisplayMode"'));
      expect(variants, contains('applyDisplayModeToExistingWidgets'));
      expect(
        variants,
        contains('manager.updateAppWidgetOptions(id, style.toOptions())'),
      );
      expect(
        variants,
        contains('DuoyiWidgetDisplayMode.saveForWidget(prefs, id, style.id)'),
      );
      expect(
        widgetScreen,
        contains('WidgetPreviewCard.todo(displayMode: _displayMode)'),
      );
      expect(widgetScreen, contains('class _WidgetPreviewDensity'));
      expect(widgetScreen, contains('class _WidgetPreviewDensityScope'));
      expect(widgetScreen, contains('class _WidgetPreviewLineList'));
      expect(
        widgetScreen,
        contains('for (final line in lines.take(maxLines))'),
      );
      expect(widgetScreen, contains('class _WidgetPreviewContentFrame'));
      expect(widgetScreen, contains('FittedBox('));
      expect(widgetScreen, contains('BoxFit.scaleDown'));
      expect(
        widgetScreen,
        isNot(contains('NeverScrollableScrollPhysics')),
        reason:
            'Preview cards should scale their fixed widget content instead of hiding overflow in a disabled scroll view.',
      );
      expect(widgetScreen, contains('final visibleWeeks = switch (maxLines)'));
      expect(widgetScreen, contains('currentWeekIndex - 1'));
      expect(widgetScreen, contains('_ => [0, 1, 2, 3, 4, 5]'));
      expect(widgetScreen, contains('class _WidgetPreviewCalendarGrid'));
      expect(widgetScreen, contains('class _WidgetPreviewCalendarCell'));
      expect(
        widgetScreen,
        contains('displayMode != WidgetDisplayMode.compact'),
      );
      expect(widgetScreen, contains('if (maxLines >= 2)'));
      expect(widgetScreen, contains('if (maxLines >= 3)'));
      expect(helper, contains('PER_WIDGET_KEY_PREFIX'));
      expect(helper, contains('saveForWidget'));
      expect(helper, contains('saveForWidgetIfMissing'));
      expect(helper, contains('clearForWidget'));
      expect(helper, contains('modeFor'));
      expect(
        helper,
        contains('val globalMode = normalize(prefs.getString(KEY, null))'),
      );
      expect(
        helper,
        contains('return normalize(instanceMode)\n            ?: globalMode'),
        reason:
            'Pinned/configured widget instance style must win over the global default so existing instances are not rewritten when the in-app selector changes.',
      );
      expect(helper, contains('standardOrDetailedVisibility'));
      expect(helper, contains('bottomNavVisibility'));
      expect(helper, contains('detailedVisibility'));
      final pinStyle = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinStyle.kt',
      ).readAsStringSync();
      final resultReceiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinResultReceiver.kt',
      ).readAsStringSync();
      expect(pinStyle, contains('targetCellWidth = 2'));
      expect(pinStyle, contains('targetCellHeight = 2'));
      expect(pinStyle, contains('targetCellWidth = 3'));
      expect(pinStyle, contains('targetCellHeight = 2'));
      expect(
        pinStyle,
        contains(
          'id = "standard",\n'
          '            minWidth = 180,\n'
          '            minHeight = 110,\n'
          '            maxWidth = 180,\n'
          '            maxHeight = 110,',
        ),
        reason:
            'Standard in-app pin requests must stay at 3x2 instead of sharing the detailed 4x3 max size.',
      );
      expect(pinStyle, contains('targetCellWidth = 4'));
      expect(pinStyle, contains('targetCellHeight = 3'));
      expect(
        pinStyle,
        contains('when (options.getString("duoyi_widget_style"))'),
        reason:
            'An explicit app-selected widget style must win over launcher-quantized size options.',
      );
      expect(mainActivity, contains('DuoyiWidgetPinStyle.fromId(styleId)'));
      expect(
        mainActivity,
        contains('DuoyiWidgetProviderRegistry.componentFor'),
      );
      expect(mainActivity, contains('pinStyle.toOptions()'));
      expect(pinStyle, contains('fun toDisplayModeOptions(): Bundle'));
      expect(resultReceiver, contains('DuoyiWidgetDisplayMode.saveForWidget'));
      expect(resultReceiver, contains('manager.updateAppWidgetOptions('));
      expect(
        resultReceiver,
        contains('widgetId,\n            pinStyle.toOptions(),'),
      );
      expect(resultReceiver, contains('pinStyle.toOptions()'));
      expect(resultReceiver, contains('getAppWidgetInfo(widgetId)?.provider'));
      expect(
        resultReceiver,
        contains('kindForProvider(actualProvider?.className)'),
      );
      expect(
        resultReceiver,
        contains('markVariantProviderActive(context, provider)'),
      );
      expect(
        resultReceiver,
        contains('requestUpdateForComponent(context, provider)'),
        reason:
            'Pin confirmation should refresh the actual provider only, not the whole kind family.',
      );
      expect(manager, contains("'applyWidgetDisplayMode'"));
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.applyDisplayModeToExistingWidgets(this, style)',
        ),
        reason:
            'Display mode changes are applied and refreshed natively so Dart does not issue a second broad widget refresh.',
      );
      final todoLayout = File(
        'android/app/src/main/res/layout/duoyi_todo_widget.xml',
      ).readAsStringSync();
      final todoProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
      ).readAsStringSync();
      expect(todoLayout, contains('@+id/widget_todo_row_2'));
      expect(todoLayout, contains('@+id/widget_todo_row_3'));
      expect(
        todoProvider,
        contains('views.setViewVisibility(R.id.widget_todo_row_2'),
      );
      expect(
        todoProvider,
        contains('views.setViewVisibility(R.id.widget_todo_row_3'),
      );
      for (final widget in widgets) {
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        final bottomNav = widget.ids.firstWhere(
          (id) => id.contains('bottom_nav'),
        );
        final bottomNavName = bottomNav.replaceFirst('@+id/', '');
        expect(source, contains('DuoyiWidgetDisplayMode'));
        expect(source, contains('R.id.$bottomNavName'));
        expect(source, contains('DuoyiWidgetDisplayMode.bottomNavVisibility'));
        expect(source, contains('override fun onDeleted'));
        expect(source, contains('DuoyiWidgetDisplayMode.clearForWidget'));
      }
    });

    test('小组件数据和样式刷新覆盖紧凑、标准和详细 provider', () {
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();

      expect(service, contains('Future<bool> init()'));
      expect(service, contains('Future<bool> setDisplayMode(String mode)'));
      expect(
        service,
        contains('Future<bool> updateTheme(HomeWidgetThemePayload theme)'),
      );
      expect(service, contains('Future<bool> push({'));
      expect(service, contains('Future<bool> _updateAllWidgets()'));
      expect(service, contains("debugPrint('[HomeWidget]"));
      expect(service, isNot(contains('catch (_) {}')));
      expect(service, contains('AndroidWidgetManager.refreshAllWidgets()'));
      expect(service, contains('await Future.wait(theme.saveOperations())'));
      expect(
        service,
        isNot(contains('_androidVariantProviderNames(androidName)')),
        reason:
            'Android updates should not fan out through repeated Dart updateWidget calls.',
      );
      expect(service, isNot(contains('await updateOne(variantName)')));
      expect(service, isNot(contains('_androidLegacyProviderName')));
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('Future<bool> pushHomeWidgetNow()'));
      expect(main, contains('runQueuedHomeWidgetPush'));
      expect(main, contains('queued push completed with failures'));

      for (final widget in widgets) {
        final provider = widget.receiver;
        expect(
          service,
          contains("'$provider'"),
          reason: '$provider 标准 provider 必须进入刷新入口。',
        );
        final compact = provider.replaceFirst(
          'WidgetProvider',
          'CompactWidgetProvider',
        );
        final detailed = provider.replaceFirst(
          'WidgetProvider',
          'DetailedWidgetProvider',
        );
        expect(
          service,
          isNot(contains("'$compact'")),
          reason: '变体 provider 名应派生生成，避免 30 个常量漏改。',
        );
        expect(
          service,
          isNot(contains("'$detailed'")),
          reason: '变体 provider 名应派生生成，避免 30 个常量漏改。',
        );
      }
    });

    test('桌面快捷创建失败会返回明确原因并接入成功回调', () {
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final callbackReceiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinResultReceiver.kt',
      ).readAsStringSync();
      final styledProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiStyledWidgetProvider.kt',
      ).readAsStringSync();

      expect(manager, contains('enum AndroidWidgetPinResult'));
      expect(manager, contains('enum AndroidWidgetPinFinalStatus'));
      expect(manager, contains('invalidWidgetId'));
      expect(manager, contains('class AndroidWidgetPinRequest'));
      expect(manager, contains('class AndroidWidgetPinConfirmation'));
      expect(manager, contains("raw['status']?.toString()"));
      expect(manager, contains("'confirmed_unverified'"));
      expect(manager, contains("'invalid_widget_id'"));
      expect(manager, contains('requestPinWidgetDetailed'));
      expect(manager, contains('waitForPinResult'));
      expect(
        manager,
        contains('Duration timeout = const Duration(minutes: 2)'),
      );
      expect(
        manager,
        isNot(contains('cancelPinRequest(requestId)')),
        reason:
            'A launcher may deliver the pin callback after the in-app wait timeout; keep the pending provider alive for that late callback.',
      );
      expect(manager, contains('keep pending request'));
      expect(manager, contains("'lastPinResult'"));
      expect(manager, contains("'clearPinResult'"));
      expect(manager, contains("'cancelPinRequest'"));
      expect(manager, contains('openWidgetSettings'));
      expect(manager, contains("'openWidgetSettings'"));
      expect(manager, contains('unsupportedPlatform'));
      expect(manager, contains('unsupportedLauncher'));
      expect(manager, contains('checkPinSupport()'));
      expect(manager, contains('permissionDenied'));
      expect(manager, contains('invalidKind'));
      expect(manager, contains('enum AndroidWidgetStyle'));
      expect(manager, contains("'style': style.id"));
      expect(manager, contains('invokeMethod<String>'));
      expect(manager, contains("'requestPinWidget'"));
      expect(widgetScreen, contains('AndroidWidgetPinResult.unsupported'));
      expect(
        widgetScreen,
        contains('AndroidWidgetPinResult.unsupportedPlatform'),
      );
      expect(
        widgetScreen,
        contains('AndroidWidgetPinResult.unsupportedLauncher'),
      );
      expect(widgetScreen, contains('AndroidWidgetPinResult.permissionDenied'));
      expect(widgetScreen, contains('可打开完成流程或快速添加'));
      expect(widgetScreen, isNot(contains('可直接完成或快速添加')));
      expect(widgetScreen, contains('_WidgetPinSupportBanner'));
      expect(widgetScreen, contains('正在检查桌面小组件支持'));
      expect(widgetScreen, contains('当前桌面支持应用内添加'));
      expect(widgetScreen, contains('等待桌面确认'));
      expect(widgetScreen, isNot(contains('添加未确认')));
      expect(widgetScreen, contains('添加未完成'));
      expect(widgetScreen, contains('桌面返回了无效的小组件实例'));
      expect(
        widgetScreen,
        contains('AndroidWidgetPinFinalStatus.invalidWidgetId'),
      );
      expect(widgetScreen, contains('_showPinWidgetConfirmationFailureHelp'));
      expect(widgetScreen, contains('当前桌面可能不支持应用内添加'));
      expect(widgetScreen, contains('重新检测'));
      expect(widgetScreen, contains('打开应用设置'));
      expect(widgetScreen, contains('WidgetsBindingObserver'));
      expect(widgetScreen, contains('didChangeAppLifecycleState'));
      expect(widgetScreen, contains('AppLifecycleState.resumed'));
      expect(widgetScreen, contains('onPinSupportChanged'));
      expect(widgetScreen, contains('当前桌面不支持应用内直接添加小组件'));
      expect(widgetScreen, contains('当前平台不支持直接添加 Android 桌面小组件'));
      expect(widgetScreen, contains('系统拒绝了本次添加请求'));
      expect(widgetScreen, contains('桌面没有展示或接受系统确认弹窗'));
      expect(widgetScreen, contains('仅 Android 支持应用内添加'));
      expect(widgetScreen, contains('请从系统小组件列表添加'));
      expect(widgetScreen, contains('紧凑 2×2、标准 3×2 或详细 4×3'));
      expect(widgetScreen, isNot(contains('系统列表只能添加标准尺寸')));
      expect(widgetScreen, contains('桌面小组件权限'));
      expect(widgetScreen, contains('后台弹窗'));
      expect(widgetScreen, contains('launcherRequestLabel'));
      expect(
        widgetScreen,
        contains('class _AddWidgetButton extends StatefulWidget'),
      );
      expect(widgetScreen, contains('bool _requesting = false'));
      expect(
        widgetScreen,
        contains('onPressed: _requesting || widget.checkingPinSupport'),
      );
      expect(
        widgetScreen,
        contains('? () => _showPinWidgetHelp(context, support)'),
      );
      expect(widgetScreen, contains('BoxConstraints(maxWidth: maxWidth)'));
      expect(widgetScreen, contains('softWrap: false'));
      expect(widgetScreen, contains('Icons.help_outline'));
      expect(widgetScreen, contains('if (_requesting) return'));
      expect(widgetScreen, contains('CircularProgressIndicator'));
      expect(widgetScreen, contains('正在请求添加'));
      expect(widgetScreen, contains('新添加实例的请求尺寸'));
      expect(widgetScreen, contains('不会修改已添加实例'));
      expect(widgetScreen, contains('style: widget.displayMode.androidStyle'));
      expect(widgetScreen, contains('请在桌面确认'));
      expect(widgetScreen, isNot(contains('_showBeforePinPrompt')));
      expect(widgetScreen, contains('openWidgetSettings'));
      expect(widgetScreen, contains('允许多仪'));
      expect(widgetScreen, isNot(contains('长按空白处')));
      expect(mainActivity, contains('call.argument<String>("style")'));
      expect(mainActivity, contains('"openWidgetSettings"'));
      expect(mainActivity, contains('private fun openWidgetSettings'));
      expect(
        mainActivity,
        contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'),
      );
      expect(mainActivity, contains('"unsupported_launcher"'));
      expect(mainActivity, contains('return "unsupported_platform"'));
      expect(manager, isNot(contains("import 'dart:io'")));
      expect(manager, contains("import '../core/platform_info.dart';"));
      expect(manager, contains('return PlatformInfo.isAndroid;'));
      expect(mainActivity, contains('DuoyiWidgetPinStyle.fromId(styleId)'));
      expect(
        mainActivity,
        contains('val provider = widgetProviderFor(kind, pinStyle.id)'),
      );
      expect(
        mainActivity,
        contains('DuoyiWidgetProviderRegistry.componentFor(this, kind, style)'),
      );
      expect(mainActivity, isNot(contains('updateAppWidgetProviderInfo')));
      expect(
        mainActivity,
        isNot(contains('restoreStandardWidgetProviderInfo')),
      );
      expect(mainActivity, contains('override fun onResume()'));
      expect(
        mainActivity,
        isNot(contains('restoreStalePendingWidgetProviderInfo()')),
      );
      expect(mainActivity, isNot(contains(r'pending_started_at_$kind')));
      expect(mainActivity, isNot(contains('widgetPinRestoreDelayMillis')));
      expect(mainActivity, isNot(contains('savePendingWidgetPinStyle')));
      expect(
        mainActivity,
        isNot(contains('schedulePendingWidgetProviderRestore')),
      );
      final pinStyle = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinStyle.kt',
      ).readAsStringSync();
      expect(pinStyle, contains('AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH'));
      expect(
        pinStyle,
        contains('AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT'),
      );
      expect(pinStyle, contains('AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH'));
      expect(
        pinStyle,
        contains('AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT'),
      );
      expect(pinStyle, contains('putString("duoyi_widget_style", id)'));
      expect(mainActivity, isNot(contains('clearPendingWidgetPinStyle')));
      expect(
        pinStyle,
        contains('putInt("duoyi_widget_target_cell_width", targetCellWidth)'),
      );
      expect(
        pinStyle,
        contains('putInt("duoyi_widget_target_cell_height", targetCellHeight)'),
      );
      expect(pinStyle, contains('OPTION_APPWIDGET_SIZES'));
      expect(pinStyle, contains('putParcelableArrayList('));
      expect(
        pinStyle,
        contains('SizeF(minWidth.toFloat(), minHeight.toFloat())'),
      );
      expect(mainActivity, isNot(contains('putSerializable(')));
      expect(mainActivity, contains('PendingIntent.getBroadcast'));
      expect(mainActivity, contains('UUID.randomUUID().toString()'));
      expect(mainActivity, contains('requestId.hashCode()'));
      expect(
        mainActivity,
        isNot(contains(r'"${kind}_${pinStyle.id}".hashCode()')),
      );
      expect(mainActivity, contains('PendingIntent.FLAG_MUTABLE'));
      expect(
        mainActivity,
        isNot(contains('PendingIntent.FLAG_IMMUTABLE')),
        reason:
            'requestPinAppWidget callback must be mutable so Android can attach EXTRA_APPWIDGET_ID.',
      );
      expect(
        mainActivity,
        isNot(contains('restoreStalePendingWidgetProviderInfo')),
      );
      expect(callbackReceiver, contains('const val extraStyle'));
      expect(
        callbackReceiver,
        contains('DuoyiWidgetDisplayMode.saveForWidget'),
      );
      expect(callbackReceiver, contains('val providerStyle ='));
      expect(
        callbackReceiver,
        contains('intent.getStringExtra(extraStyle) ?: providerStyle'),
      );
      expect(
        callbackReceiver,
        contains('kindForProvider(actualProvider?.className)'),
      );
      expect(callbackReceiver, contains('updateAppWidgetOptions('));
      expect(styledProvider, contains('onAppWidgetOptionsChanged'));
      expect(
        styledProvider,
        contains(
          'val rawOptionStyle = newOptions.getString("duoyi_widget_style")',
        ),
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetPinStyle.fromWidgetOptions(newOptions)'),
      );
      expect(
        styledProvider,
        contains(
          'DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)',
        ),
      );
      expect(
        styledProvider,
        contains('"compact", "standard", "detailed" -> rawOptionStyle'),
        reason:
            'Only valid option style ids should override receiver-derived style.',
      );
      expect(
        styledProvider,
        contains('val normalizedStyle = optionStyle'),
        reason:
            'Explicit pin/config style should not be overwritten by launcher-quantized dimensions.',
      );
      expect(
        styledProvider,
        contains('val lockedVariantStyle = when (receiverStyle)'),
        reason:
            'Only compact/detailed variant receivers should lock density; standard widgets must react to launcher resize.',
      );
      expect(
        styledProvider,
        contains('?: lockedVariantStyle'),
        reason:
            'Compact/detailed variants should keep selected density even when launcher options are coarse.',
      );
      expect(
        styledProvider,
        contains('?: resizedStyle'),
        reason:
            'Size rebucketing is only a fallback when no explicit style exists.',
      );
      expect(
        styledProvider,
        isNot(contains('val normalizedStyle = resizedStyle ?: optionStyle')),
        reason:
            'Launcher options are often normalized by OEM launchers and must not override the selected style.',
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetDisplayMode.saveForWidget'),
        reason:
            'Options changes must persist the actual per-instance style before update.',
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetProviderRegistry.requestUpdateForProvider'),
        reason:
            'Options changes should repaint the provider family after style persistence.',
      );
      expect(
        styledProvider,
        contains('override fun onDeleted'),
        reason:
            'Deleting a launcher instance still clears per-widget density and lets the registry reclaim unused variant providers.',
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused'),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        contains(
          'updateAppWidgetOptions(widgetId, normalizedStyle.toDisplayModeOptions())',
        ),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        contains('requestedStyleFromIntent()'),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        contains('AppWidgetManager.EXTRA_APPWIDGET_OPTIONS'),
      );
      expect(
        callbackReceiver,
        isNot(contains('restoreStandardWidgetProviderInfo(context, kind)')),
      );
      expect(callbackReceiver, isNot(contains('updateAppWidgetProviderInfo(')));
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        isNot(contains('setTitle("选择小组件样式")')),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        isNot(contains('.setOnCancelListener { finish() }')),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        contains('finishWithStyle(widgetId, "standard")'),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        contains(
          'DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(applicationContext)',
        ),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
        ).readAsStringSync(),
        isNot(contains('peekPendingStyle(providerClassName)')),
      );
      expect(callbackReceiver, contains('AppWidgetManager.EXTRA_APPWIDGET_ID'));
      expect(
        callbackReceiver,
        isNot(
          contains(
            'if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return',
          ),
        ),
        reason:
            'Invalid pin callbacks must still be handled and recorded instead of disappearing silently.',
      );
      expect(callbackReceiver, contains('confirmed_unverified'));
      expect(callbackReceiver, contains('Log.w('));
      expect(callbackReceiver, contains('requestId='));
      expect(callbackReceiver, contains('kind='));
      expect(callbackReceiver, contains('style='));
      expect(callbackReceiver, contains('provider='));
      expect(
        callbackReceiver,
        contains(
          'recordResult(context, requestId, kind, pinStyle.id, widgetId, "confirmed_unverified")',
        ),
        reason:
            'Some launchers confirm pinning without returning EXTRA_APPWIDGET_ID; keep that path successful and let pending-provider TTL reconcile later.',
      );
      expect(callbackReceiver, contains('const val keyStatus = "status"'));
      expect(callbackReceiver, contains('putString(keyStatus, status)'));
      expect(callbackReceiver, contains('recordResult('));
      expect(callbackReceiver, contains('"confirmed"'));
      expect(
        mainActivity,
        contains(
          '"status" to prefs.getString(DuoyiWidgetPinResultReceiver.keyStatus, "")',
        ),
      );
      expect(
        mainActivity,
        contains('DuoyiWidgetPinResultReceiver::class.java'),
      );
      expect(
        mainActivity,
        contains('requestPinAppWidget(provider, options, callback)'),
      );
      expect(mainActivity, contains('return "unsupported_launcher"'));
      expect(mainActivity, contains('"permission_denied"'));
      expect(mainActivity, contains('return "invalid_kind"'));
      expect(mainActivity, contains('"unavailable"'));
      expect(mainActivity, contains('Log.i('));
      expect(mainActivity, contains('Log.w('));
      expect(mainActivity, contains(r'requestId=$requestId'));
      expect(mainActivity, contains(r'kind=$kind'));
      expect(mainActivity, contains(r'style=${pinStyle.id}'));
      expect(mainActivity, contains(r'provider=${provider.className}'));
      expect(
        RegExp(
          r'return try \{\s+enableWidgetProvider\(provider\)',
          multiLine: true,
        ).hasMatch(mainActivity),
        isTrue,
        reason:
            'Provider enabling can throw on some ROMs; it must be inside the try block so callers get permission_denied/unavailable instead of a platform crash.',
      );
      expect(
        manifest,
        contains('android:name=".DuoyiWidgetPinResultReceiver"'),
      );
      expect(callbackReceiver, contains('class DuoyiWidgetPinResultReceiver'));
      expect(
        callbackReceiver,
        contains(
          'DuoyiWidgetProviderRegistry.requestUpdateForKind(context, kind)',
        ),
      );
      expect(
        callbackReceiver,
        contains('DuoyiWidgetProviderRegistry.clearPendingVariantProvider'),
        reason:
            'A successful pin callback must clear pending temporary enable state.',
      );
      expect(
        callbackReceiver,
        contains('requestId.orEmpty()'),
        reason:
            'Pending variant cleanup should be scoped to the exact pin request.',
      );
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.cleanupPendingVariantProvider(this, requestId)',
        ),
      );
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.rememberPendingVariantProvider(this, requestId, provider)',
        ),
      );
      expect(
        callbackReceiver,
        contains(
          'DuoyiWidgetProviderRegistry.scheduleDisableVariantProviderIfUnused',
        ),
        reason:
            'A successful callback should delay cleanup until the launcher has registered the new widget id.',
      );
      expect(callbackReceiver, contains('extraRequestId'));
      expect(callbackReceiver, contains('keyConfirmedAt'));
      expect(callbackReceiver, contains('putInt(keyWidgetId, widgetId)'));
      expect(mainActivity, contains(r'"requested:$requestId"'));
      expect(mainActivity, contains('"lastPinResult"'));
      expect(mainActivity, contains('"clearPinResult"'));
      expect(mainActivity, contains('lastWidgetPinResult(requestId)'));
      expect(
        callbackReceiver,
        isNot(contains('.requestUpdate(context)')),
        reason:
            'Pin callbacks should refresh the full compact/standard/detailed provider family.',
      );
    });

    test('应用内固定小组件按样式请求尺寸并按需保持 variant provider 可用', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final pinStyle = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinStyle.kt',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();

      expect(pinStyle, isNot(contains('metaDataKey')));
      expect(pinStyle, contains('id = "compact"'));
      expect(pinStyle, contains('id = "standard"'));
      expect(pinStyle, contains('id = "detailed"'));
      expect(pinStyle, contains('targetCellWidth: Int'));
      expect(pinStyle, contains('targetCellHeight: Int'));
      expect(pinStyle, contains('maxWidth = 250'));
      expect(pinStyle, contains('maxHeight = 180'));
      expect(pinStyle, contains('minWidth = 110'));
      expect(pinStyle, contains('minWidth = 180'));
      expect(pinStyle, contains('minWidth = 250'));
      expect(pinStyle, contains('minHeight = 110'));
      expect(pinStyle, contains('minHeight = 180'));
      expect(pinStyle, contains('maxWidth = 110'));
      expect(pinStyle, contains('maxWidth = 250'));
      expect(pinStyle, contains('maxHeight = 110'));
      expect(pinStyle, contains('maxHeight = 180'));
      expect(pinStyle, contains('targetCellWidth = 2'));
      expect(pinStyle, contains('targetCellWidth = 3'));
      expect(pinStyle, contains('targetCellWidth = 4'));
      expect(pinStyle, contains('targetCellHeight = 2'));
      expect(pinStyle, contains('targetCellHeight = 3'));
      expect(widgetScreen, contains('previewCellLabel'));
      expect(widgetScreen, contains('桌面小组件权限未允许'));
      expect(widgetScreen, contains('previewAspectRatio'));
      expect(widgetScreen, contains('previewMaxWidth'));
      expect(widgetScreen, contains("'2x2'"));
      expect(widgetScreen, contains("'3x2'"));
      expect(widgetScreen, contains("'4x3'"));
      expect(widgetScreen, contains('小组件样式已设为'));
      expect(widgetScreen, contains('桌面格子大小仍由启动器控制'));
      expect(widgetScreen, contains('新添加实例的请求尺寸'));
      expect(widgetScreen, contains('label: Text('));
      expect(widgetScreen, contains("'添加\${widget.displayMode.label} "));
      expect(
        widgetScreen,
        contains("\${widget.displayMode.launcherRequestLabel}'"),
      );
      expect(widgetScreen, contains('AspectRatio('));
      expect(widgetScreen, contains('displayMode.previewAspectRatio'));
      expect(widgetScreen, contains('displayMode.previewCellLabel'));
      expect(
        mainActivity,
        isNot(
          contains(
            'if (manager.requestPinAppWidget(provider, options, callback)) {\n                restoreStandardWidgetProviderInfo',
          ),
        ),
      );
      expect(
        mainActivity,
        contains('val provider = widgetProviderFor(kind, pinStyle.id)'),
      );
      expect(mainActivity, contains('enableWidgetProvider(provider)'));
      expect(
        mainActivity,
        contains('PackageManager.COMPONENT_ENABLED_STATE_ENABLED'),
      );
      expect(
        mainActivity,
        contains('DuoyiWidgetProviderRegistry.rememberPendingVariantProvider'),
        reason:
            'Pending compact/detailed providers must be tracked so launcher late callbacks can still be reconciled.',
      );
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.cleanupPendingVariantProviders(appContext)',
        ),
        reason:
            'Returning from launcher must only clean expired temporary variant providers, not the in-flight launcher confirmation request.',
      );
      expect(
        mainActivity,
        contains(
          'DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(this, provider)',
        ),
        reason:
            'Failed pin requests still reconcile provider state so temporary variant providers are not left exposed.',
      );
      expect(variants, contains('fun rememberPendingVariantProvider'));
      expect(variants, contains('fun clearPendingVariantProvider'));
      expect(variants, contains('fun cleanupPendingVariantProviders'));
      expect(variants, contains('fun cleanupExpiredPendingVariantProviders'));
      expect(variants, contains('pendingVariantProviderTtlMillis'));
      expect(variants, contains('System.currentTimeMillis()'));
      expect(
        variants,
        contains('now - createdAt < pendingVariantProviderTtlMillis'),
        reason:
            'A normal onResume during launcher confirmation should not disable the just-enabled compact/detailed provider.',
      );
      expect(
        variants,
        contains('scheduleExpiredPendingVariantProviderCleanup(context)'),
      );
      expect(variants, contains('pendingVariantProviderTtlMillis + 5_000L'));
      expect(variants, contains('fun disableVariantProviderIfUnused'));
      expect(variants, contains('fun scheduleDisableVariantProviderIfUnused'));
      expect(variants, contains('Handler(Looper.getMainLooper()).postDelayed'));
      expect(
        variants,
        contains('keep_system_visible_variant_provider'),
        reason:
            'Compact/detailed receivers are now system picker entries and must stay visible after failed or deleted pin attempts.',
      );
      expect(
        variants,
        isNot(contains('PackageManager.COMPONENT_ENABLED_STATE_DISABLED')),
      );
      expect(variants, isNot(contains('disable_unused_variant_provider')));
      expect(variants, contains('"compact" -> family.compact'));
      expect(
        variants,
        contains('"detailed" -> family.detailed'),
        reason: '应用内 pin 必须选中真实变体 provider，否则桌面可能继续按标准尺寸添加。',
      );
      expect(variants, contains('else -> family.standard'));

      for (final widget in widgets) {
        final providerSource = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        final baseName = widget.providerXml.replaceFirst('.xml', '');
        final compact = File(
          'android/app/src/main/res/xml/${baseName}_compact.xml',
        ).readAsStringSync();
        final standard = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        final detailed = File(
          'android/app/src/main/res/xml/${baseName}_detailed.xml',
        ).readAsStringSync();
        final receiverBlock = _receiverBlock(manifest, widget.receiver);

        expect(
          receiverBlock,
          contains('android:resource="@xml/$baseName"'),
          reason: '${widget.title} 标准 provider 是唯一可见系统入口。',
        );
        expect(
          receiverBlock,
          contains('android:name="duoyi.appwidget.provider.compact"'),
        );
        expect(
          receiverBlock,
          contains('android:resource="@xml/${baseName}_compact"'),
        );
        expect(
          receiverBlock,
          contains('android:name="duoyi.appwidget.provider.detailed"'),
        );
        expect(
          receiverBlock,
          contains('android:resource="@xml/${baseName}_detailed"'),
        );
        expect(
          receiverBlock,
          contains('android:label="@string/${widget.labelResource}"'),
          reason: '${widget.title} 标准 provider 应注册为标准 3x2 系统入口标签',
        );
        final compactBlock = _receiverBlock(manifest, widget.compactReceiver);
        final detailedBlock = _receiverBlock(manifest, widget.detailedReceiver);
        expect(compactBlock, isNot(contains('android:enabled="false"')));
        expect(detailedBlock, isNot(contains('android:enabled="false"')));
        expect(
          compactBlock,
          contains('android:label="@string/${widget.labelResource}_compact"'),
          reason:
              '${widget.title} compact receiver should surface compact size in launcher confirmation.',
        );
        expect(
          detailedBlock,
          contains('android:label="@string/${widget.labelResource}_detailed"'),
          reason:
              '${widget.title} detailed receiver should surface detailed size in launcher confirmation.',
        );
        expect(
          compactBlock,
          contains('android:resource="@xml/${baseName}_compact"'),
        );
        expect(
          detailedBlock,
          contains('android:resource="@xml/${baseName}_detailed"'),
        );
        expect(
          providerSource,
          contains(
            'DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)',
          ),
          reason: '${widget.title} provider should infer style from receiver.',
        );
        expect(
          providerSource,
          contains(
            'DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)',
          ),
          reason:
              '${widget.title} provider should persist receiver style before first render.',
        );
        expect(compact, contains('android:minWidth="110dp"'));
        expect(compact, contains('android:minHeight="110dp"'));
        expect(compact, contains('android:minResizeWidth="110dp"'));
        expect(compact, contains('android:minResizeHeight="110dp"'));
        expect(compact, contains('android:maxResizeWidth="110dp"'));
        expect(compact, contains('android:maxResizeHeight="110dp"'));
        expect(compact, contains('android:targetCellWidth="2"'));
        expect(compact, contains('android:targetCellHeight="2"'));
        expect(
          compact,
          contains(
            'android:description="@string/widget_style_compact_description"',
          ),
        );
        expect(
          compact,
          contains('android:resizeMode="none"'),
          reason:
              '${widget.title} compact provider should keep its requested 2x2 footprint instead of being stretched to the standard launcher size.',
        );
        expect(
          standard,
          contains('android:initialLayout="@layout/${widget.layoutName}"'),
        );
        expect(standard, contains('android:minWidth="180dp"'));
        expect(standard, contains('android:minHeight="110dp"'));
        expect(standard, contains('android:minResizeWidth="110dp"'));
        expect(standard, contains('android:minResizeHeight="110dp"'));
        expect(standard, contains('android:maxResizeWidth="250dp"'));
        expect(standard, contains('android:maxResizeHeight="180dp"'));
        expect(standard, contains('android:targetCellWidth="3"'));
        expect(standard, contains('android:targetCellHeight="2"'));
        expect(
          standard,
          contains(
            'android:description="@string/widget_style_standard_description"',
          ),
        );
        expect(
          standard,
          contains('android:resizeMode="horizontal|vertical"'),
          reason:
              '${widget.title} standard provider remains user-resizable after placement.',
        );
        expect(detailed, contains('android:minWidth="250dp"'));
        expect(detailed, contains('android:minHeight="180dp"'));
        expect(detailed, contains('android:minResizeWidth="250dp"'));
        expect(detailed, contains('android:minResizeHeight="180dp"'));
        expect(detailed, contains('android:maxResizeWidth="250dp"'));
        expect(detailed, contains('android:maxResizeHeight="180dp"'));
        expect(detailed, contains('android:targetCellWidth="4"'));
        expect(detailed, contains('android:targetCellHeight="3"'));
        expect(
          detailed,
          contains(
            'android:description="@string/widget_style_detailed_description"',
          ),
        );
        expect(
          detailed,
          contains('android:resizeMode="none"'),
          reason:
              '${widget.title} detailed provider should keep its requested 4x3 footprint instead of being collapsed to the standard launcher size.',
        );
        expect(
          compact,
          contains('android:initialLayout="@layout/${widget.layoutName}"'),
        );
        expect(
          detailed,
          contains('android:initialLayout="@layout/${widget.layoutName}"'),
        );
        expect(
          compact,
          contains(
            'android:previewLayout="@layout/duoyi_widget_preview_compact"',
          ),
        );
        expect(
          standard,
          contains(
            'android:previewLayout="@layout/duoyi_widget_preview_standard"',
          ),
        );
        expect(
          detailed,
          contains(
            'android:previewLayout="@layout/duoyi_widget_preview_detailed"',
          ),
        );
        expect(
          compact,
          contains(
            'android:previewImage="@drawable/${widget.previewDrawable}"',
          ),
        );
        expect(
          standard,
          contains(
            'android:previewImage="@drawable/${widget.previewDrawable}"',
          ),
        );
        expect(
          detailed,
          contains(
            'android:previewImage="@drawable/${widget.previewDrawable}"',
          ),
        );
      }
    });

    test('每个小组件三种样式声明为不同桌面尺寸', () {
      final strings = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      expect(strings, contains('widget_style_compact_description'));
      expect(strings, contains('紧凑 2x2'));
      expect(strings, contains('widget_style_standard_description'));
      expect(strings, contains('标准 3x2'));
      expect(strings, contains('widget_style_detailed_description'));
      expect(strings, contains('详细 4x3'));

      for (final widget in widgets) {
        expect(
          RegExp(
            '<string name="${widget.labelResource}">[^<]*（标准 3x2）</string>',
          ).hasMatch(strings),
          isTrue,
          reason: '${widget.title} 可见系统入口应标明标准默认 3x2 尺寸',
        );
        expect(
          RegExp(
            '<string name="${widget.labelResource}_compact">[^<]*（紧凑 2x2）</string>',
          ).hasMatch(strings),
          isTrue,
          reason: '${widget.title} 紧凑尺寸文案仍要与应用内请求尺寸一致',
        );
        expect(
          RegExp(
            '<string name="${widget.labelResource}_detailed">[^<]*（详细 4x3）</string>',
          ).hasMatch(strings),
          isTrue,
          reason: '${widget.title} 详细尺寸文案仍要与应用内请求尺寸一致',
        );
        final baseName = widget.providerXml.replaceFirst('.xml', '');
        final compact = _widgetInfoSize(
          File('android/app/src/main/res/xml/${baseName}_compact.xml'),
        );
        final standard = _widgetInfoSize(
          File('android/app/src/main/res/xml/${widget.providerXml}'),
        );
        final detailed = _widgetInfoSize(
          File('android/app/src/main/res/xml/${baseName}_detailed.xml'),
        );
        final compactSource = File(
          'android/app/src/main/res/xml/${baseName}_compact.xml',
        ).readAsStringSync();
        final standardSource = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        final detailedSource = File(
          'android/app/src/main/res/xml/${baseName}_detailed.xml',
        ).readAsStringSync();

        expect(compact.cell, (width: 2, height: 2), reason: widget.title);
        expect(standard.cell, (width: 3, height: 2), reason: widget.title);
        expect(detailed.cell, (width: 4, height: 3), reason: widget.title);
        expect(
          {compact.cell, standard.cell, detailed.cell}.length,
          3,
          reason: '${widget.title} 紧凑/标准/详细不能退化成同一种格子',
        );
        expect(compact.minWidth, lessThan(standard.minWidth));
        expect(standard.minWidth, lessThan(detailed.minWidth));
        expect(compact.minHeight, standard.minHeight);
        expect(standard.minHeight, lessThan(detailed.minHeight));
        final stylePreviews = {
          compactSource: 'duoyi_widget_preview_compact',
          standardSource: 'duoyi_widget_preview_standard',
          detailedSource: 'duoyi_widget_preview_detailed',
        };
        for (final entry in stylePreviews.entries) {
          final source = entry.key;
          expect(
            source,
            contains('android:previewLayout="@layout/${entry.value}"'),
            reason: '${widget.title} 每个样式都要有不同的 launcher 预览布局',
          );
          expect(
            source,
            contains(
              'android:previewImage="@drawable/${widget.previewDrawable}"',
            ),
            reason: '${widget.title} 每个样式都要有 launcher 预览图',
          );
        }
      }
    });

    test('应用内小组件添加按样式选择真实 provider，标准入口仍独立', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();

      expect(
        service,
        isNot(
          contains(
            "return <String>['\${prefix}Compact\$suffix', '\${prefix}Detailed\$suffix'];",
          ),
        ),
        reason:
            'Android style variants are refreshed by native provider registry, not Dart fan-out.',
      );
      expect(variants, contains('fun componentFor('));
      expect(variants, contains('fun styleForProvider('));
      expect(variants, contains('fun requestUpdateForKind('));
      expect(variants, contains('listOf(standard, compact, detailed)'));
      expect(variants, contains('private const val tag = "DuoyiWidgetPin"'));
      expect(variants, contains('remember_pending requestId='));
      expect(variants, contains('clear_pending requestId='));
      expect(variants, contains('cleanup_pending requestId='));
      expect(variants, contains('cleanup_expired_pending requestId='));
      expect(variants, contains('schedule_disable_variant_provider provider='));
      expect(variants, contains('disable_variant_provider provider='));
      expect(variants, contains('keep_variant_provider provider='));
      expect(variants, contains('widgetCount='));
      expect(variants, contains('pendingCount='));
      expect(
        variants,
        contains('"compact" -> family.compact'),
        reason: '紧凑样式必须 pin 到真实 compact provider。',
      );
      expect(
        variants,
        contains('"detailed" -> family.detailed'),
        reason: '详细样式必须 pin 到真实 detailed provider。',
      );

      for (final widget in widgets) {
        final baseName = widget.providerXml.replaceFirst('.xml', '');
        final standardSource = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        final standardBlock = _receiverBlock(manifest, widget.receiver);

        expect(
          RegExp('android:name="\\.${widget.receiver}"').allMatches(manifest),
          hasLength(1),
          reason: '${widget.receiver} should be registered once',
        );
        final compactBlock = _receiverBlock(manifest, widget.compactReceiver);
        final detailedBlock = _receiverBlock(manifest, widget.detailedReceiver);
        expect(
          RegExp(
            'android:name="\\.${widget.compactReceiver}"',
          ).allMatches(manifest),
          hasLength(1),
          reason: '${widget.compactReceiver} should be registered once',
        );
        expect(
          RegExp(
            'android:name="\\.${widget.detailedReceiver}"',
          ).allMatches(manifest),
          hasLength(1),
          reason: '${widget.detailedReceiver} should be registered once',
        );
        expect(compactBlock, isNot(contains('android:enabled="false"')));
        expect(detailedBlock, isNot(contains('android:enabled="false"')));
        expect(
          compactBlock,
          contains('android:resource="@xml/${baseName}_compact"'),
        );
        expect(
          detailedBlock,
          contains('android:resource="@xml/${baseName}_detailed"'),
        );
        expect(
          standardSource,
          contains(
            'open class ${widget.receiver} : DuoyiStyledWidgetProvider()',
          ),
        );
        expect(
          variants,
          contains('class ${widget.compactReceiver} : ${widget.receiver}()'),
        );
        expect(
          variants,
          contains('class ${widget.detailedReceiver} : ${widget.receiver}()'),
        );
        expect(variants, contains('${widget.receiver}::class.java'));
        expect(variants, contains('${widget.compactReceiver}::class.java'));
        expect(variants, contains('${widget.detailedReceiver}::class.java'));
        expect(
          standardBlock,
          contains('android:resource="@xml/${baseName}_compact"'),
        );
        expect(standardBlock, contains('android:resource="@xml/$baseName"'));
        expect(
          standardBlock,
          contains('android:resource="@xml/${baseName}_detailed"'),
        );
        expect(
          standardBlock,
          contains('android.appwidget.action.APPWIDGET_UPDATE'),
        );
        expect(
          standardBlock,
          contains('android.intent.action.MY_PACKAGE_REPLACED'),
        );
      }
    });

    test('9 个标准 provider 统一继承、清理实例样式且三样式映射一致', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();

      expect(widgets, hasLength(9));
      for (final widget in widgets) {
        final baseName = widget.providerXml.replaceFirst('.xml', '');
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        final standardBlock = _receiverBlock(manifest, widget.receiver);

        expect(
          source,
          contains(
            'open class ${widget.receiver} : DuoyiStyledWidgetProvider()',
          ),
          reason: '${widget.receiver} must inherit shared style handling.',
        );
        expect(source, contains('override fun onDeleted'));
        expect(
          source,
          contains(
            'appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }',
          ),
          reason:
              '${widget.receiver} must clear per-widget style when launcher deletes an instance.',
        );
        expect(
          variants,
          contains('class ${widget.compactReceiver} : ${widget.receiver}()'),
        );
        expect(
          variants,
          contains('class ${widget.detailedReceiver} : ${widget.receiver}()'),
        );
        expect(
          standardBlock,
          contains('android:resource="@xml/$baseName"'),
          reason: '${widget.receiver} standard receiver must use standard XML.',
        );
        expect(
          standardBlock,
          contains('android:resource="@xml/${baseName}_compact"'),
          reason:
              '${widget.receiver} should keep compact XML metadata for app-side size mapping.',
        );
        expect(
          standardBlock,
          contains('android:resource="@xml/${baseName}_detailed"'),
          reason:
              '${widget.receiver} should keep detailed XML metadata for app-side size mapping.',
        );
      }
    });

    test('小组件 Android iOS 和 Flutter 清单保持 9 类 exact set 对齐', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final iosWidgets = File(
        'ios/DuoyiWidgets/DuoyiWidgets.swift',
      ).readAsStringSync();

      final expectedStandardProviders = _sorted(
        widgets.map((widget) => widget.receiver),
      );
      final expectedAllProviders = _sorted(
        widgets.expand(
          (widget) => [
            widget.receiver,
            widget.compactReceiver,
            widget.detailedReceiver,
          ],
        ),
      );
      final expectedManifestProviders = _sorted([
        legacyWidget.receiver,
        ...expectedAllProviders,
      ]);
      final expectedKindIds = _sorted(widgets.map((widget) => widget.kindId));
      final expectedIosKinds = _sorted(widgets.map((widget) => widget.iosKind));

      final manifestProviders = _sorted(
        RegExp(
          r'<receiver\b[\s\S]*?android:name="\.([^"]*WidgetProvider)"',
        ).allMatches(manifest).map((match) => match.group(1)!),
      );
      expect(manifestProviders, expectedManifestProviders);
      expect(manifestProviders, hasLength(28));
      expect(manifest, isNot(contains('DuoyiDiary')));

      final variantProviders = _sorted(
        RegExp(
          r'\b(Duoyi\w+WidgetProvider)::class\.java',
        ).allMatches(variants).map((match) => match.group(1)!),
      );
      expect(variantProviders, expectedAllProviders);

      final managerKindBlock = RegExp(
        r'enum DuoyiWidgetKind\s*\{([\s\S]*?)\}',
      ).firstMatch(manager);
      expect(managerKindBlock, isNotNull);
      final managerKinds = _sorted(
        managerKindBlock!
            .group(1)!
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
      expect(managerKinds, expectedKindIds);
      for (final kind in expectedKindIds) {
        expect(manager, contains("DuoyiWidgetKind.$kind => '$kind'"));
        expect(variants, contains('"$kind"'));
      }

      final androidServiceProviders = _sorted(
        RegExp(
          r"_android\w+ProviderName\s*=\s*'([^']+)'",
        ).allMatches(service).map((match) => match.group(1)!),
      );
      expect(
        service,
        isNot(contains("_androidLegacyProviderName = 'DuoyiWidgetProvider'")),
      );
      final iosServiceKinds = _sorted(
        RegExp(
          r"_ios\w+WidgetName\s*=\s*'([^']+)'",
        ).allMatches(service).map((match) => match.group(1)!),
      );
      expect(androidServiceProviders, expectedStandardProviders);
      expect(iosServiceKinds, expectedIosKinds);

      final updateTargets = service.substring(
        service.indexOf(
          'const List<_HomeWidgetUpdateTarget> _widgetUpdateTargets',
        ),
      );
      expect(
        RegExp(
          r'androidName: HomeWidgetService\._android\w+ProviderName',
        ).allMatches(updateTargets),
        hasLength(9),
      );
      expect(
        RegExp(
          r'iOSName: HomeWidgetService\._ios\w+WidgetName',
        ).allMatches(updateTargets),
        hasLength(9),
      );

      final iosKinds = _sorted(
        RegExp(
          r'kind:\s*"([^"]+Widget)"',
        ).allMatches(iosWidgets).map((match) => match.group(1)!),
      );
      expect(iosKinds, expectedIosKinds);
      expect(
        RegExp(r'DuoyiAnyWidget\(config: \w+Config\)').allMatches(iosWidgets),
        hasLength(9),
      );
    });

    test('全部小组件 provider XML 只引用对应三档 preview layout', () {
      final previewLayoutFiles = {
        'compact': File(
          'android/app/src/main/res/layout/duoyi_widget_preview_compact.xml',
        ),
        'standard': File(
          'android/app/src/main/res/layout/duoyi_widget_preview_standard.xml',
        ),
        'detailed': File(
          'android/app/src/main/res/layout/duoyi_widget_preview_detailed.xml',
        ),
      };
      final previewSources = <String, String>{};
      for (final entry in previewLayoutFiles.entries) {
        expect(entry.value.existsSync(), isTrue, reason: entry.value.path);
        previewSources[entry.key] = entry.value.readAsStringSync();
      }
      expect(previewSources.values.toSet(), hasLength(3));

      final providerFiles =
          Directory(
              'android/app/src/main/res/xml',
            ).listSync().whereType<File>().where((file) {
              final name = file.uri.pathSegments.last;
              return name.startsWith('duoyi_') &&
                  name.contains('widget_info') &&
                  name.endsWith('.xml');
            }).toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      expect(providerFiles, hasLength(31));
      for (final file in providerFiles) {
        final name = file.uri.pathSegments.last;
        final style = name.endsWith('_compact.xml')
            ? 'compact'
            : name.endsWith('_detailed.xml')
            ? 'detailed'
            : 'standard';
        final source = file.readAsStringSync();
        final previewRefs = RegExp(
          r'android:previewLayout="@layout/([^"]+)"',
        ).allMatches(source).map((match) => match.group(1)!).toList();

        expect(previewRefs, hasLength(1), reason: file.path);
        expect(
          previewRefs.single,
          'duoyi_widget_preview_$style',
          reason: '$name should use the $style preview layout',
        );
      }
    });

    test('options changed 只保存样式并触发 update 广播，避免递归修改 options/provider', () {
      final styledProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiStyledWidgetProvider.kt',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();

      expect(
        styledProvider,
        contains('override fun onAppWidgetOptionsChanged'),
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetPinStyle.fromWidgetOptions(newOptions)'),
      );
      expect(styledProvider, contains('val normalizedStyle = optionStyle'));
      expect(styledProvider, contains('Log.i('));
      expect(styledProvider, contains('"DuoyiWidgetPin"'));
      expect(styledProvider, contains('options_changed widgetId='));
      expect(styledProvider, contains(r'provider=${this::class.java.name}'));
      expect(styledProvider, contains('rawOptionStyle='));
      expect(styledProvider, contains('resizedStyle='));
      expect(styledProvider, contains('receiverStyle='));
      expect(styledProvider, contains('normalizedStyle='));
      expect(
        styledProvider,
        contains('val lockedVariantStyle = when (receiverStyle)'),
      );
      expect(styledProvider, contains('?: lockedVariantStyle'));
      expect(styledProvider, contains('?: receiverStyle'));
      expect(styledProvider, contains('?: resizedStyle'));
      expect(
        styledProvider,
        isNot(contains('val normalizedStyle = resizedStyle ?: optionStyle')),
      );
      expect(styledProvider, contains('DuoyiWidgetDisplayMode.saveForWidget'));
      expect(
        styledProvider,
        contains('DuoyiWidgetProviderRegistry.requestUpdateForProvider'),
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetProviderRegistry.markVariantProviderActive'),
      );
      expect(
        styledProvider,
        contains('DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused'),
      );
      expect(
        styledProvider,
        isNot(contains('updateAppWidgetOptions')),
        reason:
            'Writing options from onAppWidgetOptionsChanged can re-enter the callback.',
      );
      expect(
        styledProvider,
        isNot(contains('updateAppWidgetProviderInfo')),
        reason:
            'Provider switching from onAppWidgetOptionsChanged can recursively recreate option changes.',
      );
      expect(
        variants,
        contains('Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)'),
      );
      expect(variants, contains('setComponent(component)'));
      expect(variants, contains('context.sendBroadcast(intent)'));
      final requestUpdateBody = variants.substring(
        variants.indexOf(
          'fun requestUpdate(context: Context, providerClasses: List<Class<out AppWidgetProvider>>)',
        ),
        variants.indexOf('fun applyDisplayModeToExistingWidgets'),
      );
      expect(requestUpdateBody, isNot(contains('updateAppWidgetOptions')));
      expect(variants, contains('fun applyDisplayModeToExistingWidgets'));
      expect(variants, contains('apply_display_mode widgetId='));
      expect(variants, contains(r'normalizedStyle=${style.id}'));
      expect(variants, contains('activeVariantProvidersKey'));
      expect(variants, contains('"active_variant_providers"'));
      expect(variants, contains('fun markVariantProviderActive'));
      expect(variants, contains('activeVariantProviderComponents(context)'));
      expect(
        variants,
        isNot(contains('clearActiveVariantProvider(context, component)')),
        reason:
            'Active variant providers are retained across upgrades and launcher refreshes.',
      );
      expect(variants, contains('keep_active_variant_provider'));
      expect(
        variants,
        contains('manager.updateAppWidgetOptions(id, style.toOptions())'),
      );
      expect(variants, isNot(contains('updateAppWidgetProviderInfo')));
    });

    test('升级后刷新已有小组件，避免旧布局继续留在桌面', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      for (final widget in widgets) {
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        expect(
          RegExp(
            'android:name="\\.${widget.receiver}"[\\s\\S]*?android\\.intent\\.action\\.MY_PACKAGE_REPLACED',
          ).hasMatch(manifest),
          isTrue,
          reason: '${widget.receiver} should refresh on package replace',
        );
        expect(source, contains('Intent.ACTION_MY_PACKAGE_REPLACED'));
        expect(source, contains('fun requestUpdate(context: Context)'));
        expect(
          source,
          contains('DuoyiWidgetProviderRegistry.requestUpdateForKind'),
        );
      }
    });

    test('应用内小组件页展示 9 个可见独立预览并接入底部导航', () {
      final main = File('lib/main.dart').readAsStringSync();
      final deepLinkService = File(
        'lib/services/deep_link_service.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();

      expect(main, contains('WidgetScreen(key: widgetKey)'));
      expect(main, contains('final Set<int> _builtTabs = <int>{0}'));
      expect(main, contains('_LazyTabPlaceholder'));
      expect(main, contains('_buildTab(tab, safeVisibleTabs)'));
      expect(main, contains('var homeWidgetPushInFlight = false'));
      expect(main, contains('homeWidgetPushQueued = true'));
      expect(
        main,
        contains('Timer(const Duration(milliseconds: 2200)'),
        reason: '小组件推送会重建日程摘要，启动和连续数据变化时必须合并，不能 800ms 高频抢 UI。',
      );
      // 底导航文案已迁移到 BrandStrings（主题换文案对导航生效），
      // 见 test/core/brand_navigation_strings_test.dart 的静态锚点。
      expect(main, contains('label: brand.navWidget'));
      expect(main, contains("action == 'quick_todo'"));
      expect(main, contains("action == 'checkin_habit'"));
      expect(main, contains('_homeWidgetEventsForToday'));
      expect(main, contains('_homeWidgetEventDeepLink'));
      expect(main, contains("'duoyi://goal/\${Uri.encodeComponent(goal.id)}'"));
      expect(
        main,
        contains("'duoyi://course/\${Uri.encodeComponent(course.id)}'"),
      );
      expect(main, contains("'duoyi://note/\${Uri.encodeComponent(note.id)}'"));
      expect(service, isNot(contains('_androidDiaryProviderName')));
      expect(
        main,
        contains(
          'TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id)',
        ),
      );
      expect(
        main,
        contains('TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id)'),
      );
      expect(widgetScreen, isNot(contains('WidgetPreviewKind.diary')));
      expect(
        main,
        isNot(contains("todayEventSummary: top3.isEmpty ? '今日没有日程'")),
      );
      expect(main, contains('habits.incrementHabit(id)'));
      expect(main, contains('_showQuickTodoDialog'));
      expect(main, contains('DeepLinkService.takeInitialLink()'));
      expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
      expect(mainActivity, contains('duoyiDeepLinkFrom(intent)'));
      expect(mainActivity, contains('pendingInitialDeepLink'));
      expect(service, contains('habit_quick_check_id'));
      expect(service, contains('habit_quick_check_label'));
      expect(service, contains('_updateWidgetFamily'));
      expect(service, isNot(contains('_androidVariantProviderNames')));
      expect(widgetScreen, contains('WidgetPreviewCard'));
      expect(widgetScreen, contains('_WidgetPreviewNav'));
      for (final title in [
        '今日待办预览',
        '专注预览',
        '习惯预览',
        '月历预览',
        '今日日程预览',
        '目标预览',
        '课程表预览',
        '随手记预览',
        '纪念日预览',
      ]) {
        expect(widgetScreen, contains(title));
      }
      expect(widgetScreen, isNot(contains('多仪概览')));
      expect(widgetScreen, isNot(contains('WidgetPreviewCard.overview')));
      expect(widgetScreen, isNot(contains('WidgetPreviewKind.overview')));
      expect(widgetScreen, isNot(contains('_WidgetPreviewOverviewBody')));
      expect(widgetScreen, contains("'待办', '习惯', '日历', '专注'"));
      expect(widgetScreen, contains('展示进行中目标和进度'));
      expect(widgetScreen, contains('发版准备 · 68%'));
      expect(widgetScreen, contains('今日优先处理'));
      expect(widgetScreen, contains('+ 添加待办'));
      expect(widgetScreen, contains('开始 25 分钟专注'));
    });

    test('桌面小组件 deep link 跳转隐藏底部页时允许打开隐藏 tab', () {
      final main = File('lib/main.dart').readAsStringSync();
      final countdown = File(
        'lib/screens/countdown_screen.dart',
      ).readAsStringSync();
      final timeAudit = File(
        'lib/screens/time_audit_screen.dart',
      ).readAsStringSync();
      final anniversary = File(
        'lib/screens/anniversary_screen.dart',
      ).readAsStringSync();
      final todayRouter = File(
        'lib/screens/today_detail_router.dart',
      ).readAsStringSync();

      for (final host in ['goal', 'course', 'anniversary', 'note']) {
        final branch = _widgetUriBranch(main, host);
        expect(
          branch,
          contains('state.navigateTo(0, allowHidden: true)'),
          reason:
              'duoyi://$host should keep hidden Today/detail routes reachable',
        );
      }
      for (final tab in ['todo', 'habit', 'calendar', 'focus', 'widget']) {
        expect(
          main,
          contains("'$tab' => "),
          reason: 'duoyi://tab/$tab should be routed through tab branch',
        );
      }
      expect(main, contains('state.navigateTo(idx, allowHidden: true);'));
      expect(main, contains('_builtTabs.add(target)'));
      expect(main, contains('_builtTabs.add(safeIndex)'));
      expect(main, contains('bool _hasExplicitNavigation = false'));
      expect(main, contains('_hasExplicitNavigation = true'));
      expect(main, contains('if (_hasExplicitNavigation) return;'));
      expect(main, contains('final showingHiddenTab'));
      expect(main, contains('bottomNavigationBar: showingHiddenTab'));
      expect(main, contains('? _HiddenTabReturnBar('));
      expect(main, contains("const Text('返回我的')"));
      final noteBranch = _widgetUriBranch(main, 'note');
      expect(
        noteBranch,
        contains('_pushHiddenWidgetFallbackRoute(ctx, const NoteScreen())'),
        reason:
            'duoyi://note without an id should not push a black-backed route',
      );
      expect(
        main,
        contains('builder: (_) => BrandRouteSurface(child: child)'),
        reason: 'hidden widget fallback routes should keep the brand surface',
      );
      final startPomodoroBranch = _widgetActionBranch(main, 'start_pomodoro');
      expect(
        startPomodoroBranch,
        contains('state.navigateTo(4, allowHidden: true)'),
        reason: '桌面专注动作应能进入隐藏的专注页',
      );
      expect(startPomodoroBranch, contains('pomodoro.startIfIdle()'));
      expect(startPomodoroBranch, contains('已开始专注'));
      expect(startPomodoroBranch, contains('专注计时正在进行'));
      final quickTodoBranch = _widgetActionBranch(main, 'quick_todo');
      expect(
        quickTodoBranch,
        contains('state.navigateTo(1, allowHidden: true)'),
        reason: '桌面快捷待办动作应能进入隐藏的待办页',
      );
      expect(quickTodoBranch, contains('_createQuickTodoFromAction'));
      expect(main, contains('_showWidgetActionFeedbackFromShell'));
      expect(main, contains('String _quickTodoCreatedMessage(TodoItem todo)'));
      expect(main, contains('已创建待办'));
      final completeTodoBranch = _widgetActionBranch(main, 'complete_todo');
      expect(
        completeTodoBranch,
        contains('state.navigateTo(1, allowHidden: true)'),
        reason: '桌面待办完成动作应先进入待办页，并直接完成后反馈',
      );
      expect(completeTodoBranch, contains('_completeTodoFromWidgetAction'));
      expect(main, contains('todos.completeTodos([target.id])'));
      expect(main, contains('已完成：'));
      expect(
        completeTodoBranch,
        isNot(contains('completeTodoWithOptionalTimeRecord')),
      );
      expect(completeTodoBranch, contains('_showWidgetActionFeedback'));
      expect(completeTodoBranch, contains('这个任务不存在或已被删除'));
      expect(completeTodoBranch, contains('已经完成'));
      final checkinHabitBranch = _widgetActionBranch(main, 'checkin_habit');
      expect(
        checkinHabitBranch,
        contains('state.navigateTo(2, allowHidden: true)'),
        reason: '桌面习惯打卡动作应先进入习惯页',
      );
      expect(checkinHabitBranch, contains('_showWidgetActionFeedback'));
      expect(checkinHabitBranch, contains('这个习惯不存在或已被删除'));
      expect(checkinHabitBranch, contains('不支持快捷打卡'));
      expect(checkinHabitBranch, contains('今天不需要打卡'));
      expect(checkinHabitBranch, contains('今天已经完成'));
      expect(checkinHabitBranch, contains('已打卡：'));
      expect(main, contains("uri.host == 'countdown'"));
      expect(main, contains('CountdownScreen(initialCountdownId: id)'));
      expect(main, contains("uri.host == 'time-entry'"));
      expect(main, contains('TimeAuditScreen(initialEntryId: id)'));
      expect(countdown, contains('final String? initialCountdownId'));
      expect(countdown, contains('_openInitialCountdownIfNeeded'));
      expect(timeAudit, contains('final String? initialEntryId'));
      expect(timeAudit, contains('_openInitialEntryIfNeeded'));
      expect(anniversary, contains('final String? initialAnniversaryId'));
      expect(anniversary, contains('_openInitialAnniversaryIfNeeded'));
      expect(todayRouter, contains('initialAnniversaryId: id'));
    });

    test('隐藏页小组件内容行都绑定详情 deep link，空 id 回退到对应页面', () {
      final providers = <String, _DetailWidgetBinding>{
        'goal': _DetailWidgetBinding(
          fileName: 'DuoyiGoalWidgetProvider.kt',
          rowPrefix: 'widget_goal_',
          keyPrefix: 'goal_highlight_',
          fallback: 'duoyi://goal',
        ),
        'course': _DetailWidgetBinding(
          fileName: 'DuoyiCourseWidgetProvider.kt',
          rowPrefix: 'widget_course_',
          keyPrefix: 'course_highlight_',
          fallback: 'duoyi://course',
        ),
        'schedule': _DetailWidgetBinding(
          fileName: 'DuoyiScheduleWidgetProvider.kt',
          rowPrefix: 'widget_schedule_',
          keyPrefix: 'schedule_highlight_',
          fallback: 'duoyi://calendar',
        ),
        'note': _DetailWidgetBinding(
          fileName: 'DuoyiNoteWidgetProvider.kt',
          rowPrefix: 'widget_note_',
          keyPrefix: 'note_highlight_',
          fallback: 'duoyi://note',
        ),
        'anniversary': _DetailWidgetBinding(
          fileName: 'DuoyiAnniversaryWidgetProvider.kt',
          rowPrefix: 'widget_anniversary_',
          keyPrefix: 'memorial_highlight_',
          fallback: 'duoyi://anniversary',
        ),
        'diary': _DetailWidgetBinding(
          fileName: 'DuoyiDiaryWidgetProvider.kt',
          rowPrefix: 'widget_diary_',
          keyPrefix: 'diary_highlight_',
          fallback: 'duoyi://diary',
        ),
      };

      for (final entry in providers.entries) {
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${entry.value.fileName}',
        ).readAsStringSync();
        expect(source, contains('HomeWidgetLaunchIntent.getActivity'));
        if (entry.key == 'anniversary') {
          expect(
            source,
            contains('detailUri(prefs, primaryKey, fallbackKey, fallback)'),
            reason:
                'anniversary should prefer ordinary anniversary ids and fall back to memorial ids.',
          );
          expect(source, contains('prefs.getString(primaryKey, null)'));
          expect(source, contains('?: prefs.getString(fallbackKey, "")'));
          for (var index = 1; index <= 3; index++) {
            expect(source, contains('R.id.${entry.value.rowPrefix}$index,'));
            expect(source, contains('anniversary_highlight_${index}_id'));
            expect(source, contains('memorial_highlight_${index}_id'));
          }
          expect(
            source,
            contains(
              'if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)',
            ),
          );
          expect(
            source,
            contains(r'Uri.parse("$fallback/${Uri.encode(rawId)}")'),
          );
          continue;
        }
        expect(
          source,
          contains('detailUri(prefs, key, fallback)'),
          reason:
              '${entry.key} should route raw saved ids through a deep-link builder.',
        );
        expect(
          source,
          contains('val rawId = prefs.getString(key, "")?.trim().orEmpty()'),
        );
        expect(
          source,
          contains('if (rawId.isBlank()) return Uri.parse(fallback)'),
        );
        expect(
          source,
          contains('if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)'),
          reason:
              '${entry.key} should open full duoyi:// row links saved by Flutter without double-encoding them.',
        );
        expect(
          source,
          contains(r'Uri.parse("$fallback/${Uri.encode(rawId)}")'),
        );
        expect(
          source,
          isNot(
            contains(
              'Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })',
            ),
          ),
          reason: '${entry.key} must not parse the raw id directly as a Uri.',
        );
        for (var index = 1; index <= 3; index++) {
          expect(
            source,
            contains('R.id.${entry.value.rowPrefix}$index,'),
            reason: '${entry.key} row $index should be clickable',
          );
          expect(
            source,
            contains(
              'itemIntent(context, prefs, "${entry.value.keyPrefix}${index}_id", "${entry.value.fallback}")',
            ),
            reason:
                '${entry.key} row $index should open detail or fallback page',
          );
        }
      }
    });

    test('桌面快捷创建只支持 10 种可见独立小组件', () {
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final variants = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
      ).readAsStringSync();

      for (final kind in [
        'todo',
        'focus',
        'habit',
        'calendar',
        'schedule',
        'goal',
        'course',
        'note',
        'anniversary',
      ]) {
        expect(manager, contains('DuoyiWidgetKind.$kind'));
        expect(manager, contains("'$kind'"));
        expect(variants, contains('"$kind"'));
      }
      expect(manager, isNot(contains('DuoyiWidgetKind.diary')));
      expect(variants, isNot(contains('"diary"')));
      expect(manager, isNot(contains('DuoyiWidgetKind.overview')));
      expect(manager, isNot(contains("'overview'")));
      expect(mainActivity, isNot(contains('"overview"')));
      expect(variants, isNot(contains('"overview"')));
      expect(
        mainActivity,
        isNot(contains('else -> ComponentName(this, DuoyiWidgetProvider')),
      );
      for (final receiver in widgets.map((w) => w.receiver)) {
        expect(variants, contains('$receiver::class.java'));
      }
    });

    test('10 种可见独立小组件都通过配置入口初始化对应 provider', () {
      final configActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
      ).readAsStringSync();

      expect(configActivity, contains('getAppWidgetInfo(widgetId)'));
      expect(
        configActivity,
        contains(
          'requestUpdateForProvider(applicationContext, providerClassName)',
        ),
      );
      expect(configActivity, contains('styleForProvider(providerClassName)'));
      for (final widget in widgets) {
        final provider = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        expect(
          provider,
          contains(
            'android:configure="com.duoyi.duoyi.DuoyiWidgetConfigActivity"',
          ),
          reason:
              '${widget.providerXml} should initialize through config activity',
        );
        expect(
          configActivity,
          contains('DuoyiWidgetProviderRegistry.requestUpdateForProvider'),
          reason: '${widget.receiver} should be refreshed after placement',
        );
      }
    });

    test('10 种可见独立小组件标准入口默认 3x2 且可调整到 2x2-4x3', () {
      for (final widget in widgets) {
        final provider = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        expect(provider, contains('android:resizeMode="horizontal|vertical"'));
        expect(provider, contains('android:minWidth="180dp"'));
        expect(provider, contains('android:minHeight="110dp"'));
        expect(provider, contains('android:targetCellWidth="3"'));
        expect(provider, contains('android:targetCellHeight="2"'));
        expect(provider, contains('android:minResizeWidth="110dp"'));
        expect(provider, contains('android:minResizeHeight="110dp"'));
        expect(provider, contains('android:maxResizeWidth="250dp"'));
        expect(provider, contains('android:maxResizeHeight="180dp"'));
      }
    });
  });
}

void _assertWidgetResource(_WidgetResource widget, {bool registered = true}) {
  final provider = File(
    'android/app/src/main/res/xml/${widget.providerXml}',
  ).readAsStringSync();
  final layout = File(
    'android/app/src/main/res/layout/${widget.layoutXml}',
  ).readAsStringSync();
  final preview = File(
    'android/app/src/main/res/drawable-nodpi/${widget.previewPng}',
  );

  expect(
    provider,
    contains('android:previewImage="@drawable/${widget.previewDrawable}"'),
  );
  expect(
    provider,
    contains('android:previewLayout="@layout/duoyi_widget_preview_standard"'),
  );
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  if (registered) {
    expect(
      _receiverBlock(manifest, widget.receiver),
      contains('android:resource="@drawable/${widget.previewDrawable}"'),
    );
  } else {
    expect(
      manifest,
      isNot(contains('android:name=".${widget.receiver}"')),
      reason: '${widget.receiver} should not be visible in widget picker',
    );
  }
  expect(preview.existsSync(), isTrue);
  expect(preview.lengthSync(), greaterThan(1024));
  expect(_pngSize(preview), const _PngSize(720, 480));
  expect(_pngContainsTextLikeContent(preview), isTrue);
  for (final id in widget.ids) {
    expect(
      layout,
      contains(id),
      reason: '${widget.layoutXml} should contain $id',
    );
  }
  expect(
    File(
      'android/app/src/main/res/drawable/${widget.previewDrawable}.xml',
    ).existsSync(),
    isFalse,
  );
}

String _receiverBlock(String manifest, String receiverName) {
  final match = RegExp(
    '<receiver[\\s\\S]*?android:name="\\.$receiverName"[\\s\\S]*?</receiver>',
  ).firstMatch(manifest);
  expect(match, isNotNull, reason: '$receiverName receiver not found');
  return match!.group(0)!;
}

String _xmlTextViewWithId(String source, String id) {
  final match = RegExp(
    '<TextView[\\s\\S]*?android:id="@\\+id/$id"[\\s\\S]*?/>',
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$id TextView not found');
  return match!.group(0)!;
}

String _widgetUriBranch(String source, String host) {
  final start = source.indexOf("} else if (uri.host == '$host'");
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $host branch');
  final next = source.indexOf('} else if (uri.host == ', start + 1);
  expect(next, greaterThan(start), reason: 'Missing branch after $host');
  return source.substring(start, next);
}

String _widgetActionBranch(String source, String action) {
  final start = source.indexOf("action == '$action'");
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $action action');
  final nextElse = source.indexOf("} else if (action == '", start + 1);
  final end = nextElse >= 0 ? nextElse : source.indexOf('\n    }', start + 1);
  expect(end, greaterThan(start), reason: 'Missing end for $action action');
  return source.substring(start, end);
}

Iterable<String> _textViewBlocks(String layout) {
  return RegExp(
    r'<TextView\b[\s\S]*?(?:/>|</TextView>)',
  ).allMatches(layout).map((match) => match.group(0)!);
}

String? _textViewId(String block) {
  final match = RegExp(r'android:id="@\+id/([^"]+)"').firstMatch(block);
  return match?.group(1);
}

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

bool _pngContainsTextLikeContent(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  // The real preview is a rendered screenshot-style PNG with many colors and
  // dark text pixels. A blank/abstract placeholder typically lacks this range.
  final unique = <int>{};
  var darkPixels = 0;
  for (var i = 0; i < bytes.length - 2; i += 97) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    unique.add((r << 16) | (g << 8) | b);
    if (r < 80 && g < 80 && b < 80) darkPixels++;
  }
  return width == 720 && height == 480 && unique.length > 24 && darkPixels > 5;
}

_PngSize _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  expect(bytes.take(signature.length).toList(), signature);
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return _PngSize(data.getUint32(16), data.getUint32(20));
}

_WidgetInfoSize _widgetInfoSize(File file) {
  expect(file.existsSync(), isTrue, reason: '${file.path} should exist');
  final source = file.readAsStringSync();
  int attr(String name) {
    final match = RegExp('android:$name="([0-9]+)(?:dp)?"').firstMatch(source);
    expect(match, isNotNull, reason: '${file.path} missing $name');
    return int.parse(match!.group(1)!);
  }

  return _WidgetInfoSize(
    minWidth: attr('minWidth'),
    minHeight: attr('minHeight'),
    targetCellWidth: attr('targetCellWidth'),
    targetCellHeight: attr('targetCellHeight'),
  );
}

class _WidgetResource {
  final String title;
  final String providerXml;
  final String layoutXml;
  final String previewPng;
  final String receiver;
  final String previewDrawable;
  final String layoutName;
  final List<String> ids;
  final bool compact;

  const _WidgetResource({
    required this.title,
    required this.providerXml,
    required this.layoutXml,
    required this.previewPng,
    required this.receiver,
    required this.previewDrawable,
    required this.layoutName,
    required this.ids,
    required this.compact,
  });

  String get compactReceiver =>
      receiver.replaceFirst('WidgetProvider', 'CompactWidgetProvider');

  String get detailedReceiver =>
      receiver.replaceFirst('WidgetProvider', 'DetailedWidgetProvider');

  String get kindId {
    final withoutPrefix = providerXml
        .replaceFirst('duoyi_', '')
        .replaceFirst('_widget_info.xml', '');
    return withoutPrefix == 'focus_habit' ? 'focus' : withoutPrefix;
  }

  String get iosKind {
    return switch (kindId) {
      'todo' => 'DuoyiTodoWidget',
      'focus' => 'DuoyiFocusWidget',
      'habit' => 'DuoyiHabitWidget',
      'calendar' => 'DuoyiCalendarWidget',
      'schedule' => 'DuoyiScheduleWidget',
      'goal' => 'DuoyiGoalWidget',
      'course' => 'DuoyiCourseWidget',
      'note' => 'DuoyiNoteWidget',
      'anniversary' => 'DuoyiAnniversaryWidget',
      'diary' => 'DuoyiDiaryWidget',
      _ => throw StateError('Unknown widget kind: $kindId'),
    };
  }

  String get labelResource {
    final base = providerXml.replaceFirst('.xml', '');
    return base
        .replaceFirst('duoyi_', 'widget_')
        .replaceFirst('_widget_info', '_label');
  }
}

class _PngSize {
  final int width;
  final int height;

  const _PngSize(this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is _PngSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

class _WidgetInfoSize {
  final int minWidth;
  final int minHeight;
  final int targetCellWidth;
  final int targetCellHeight;

  const _WidgetInfoSize({
    required this.minWidth,
    required this.minHeight,
    required this.targetCellWidth,
    required this.targetCellHeight,
  });

  ({int width, int height}) get cell =>
      (width: targetCellWidth, height: targetCellHeight);
}

class _DetailWidgetBinding {
  final String fileName;
  final String rowPrefix;
  final String keyPrefix;
  final String fallback;

  const _DetailWidgetBinding({
    required this.fileName,
    required this.rowPrefix,
    required this.keyPrefix,
    required this.fallback,
  });
}
