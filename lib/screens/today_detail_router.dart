import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../models/anniversary.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'anniversary_screen.dart';
import 'course_schedule_screen.dart';
import 'goal_edit_screen.dart';
import 'goal_screen.dart';
import 'habit_detail_screen.dart';
import 'habit_screen.dart';
import 'note_screen.dart';
import 'todo_detail_screen.dart';
import 'todo_screen.dart';

/// 今日页 / 其他聚合页调用的"详情跳转"所属 section 类型（Requirement 6.2）。
enum TodaySectionKind {
  todos,
  courses,
  anniversaries,
  goals,
  habits,
  notes,
  diary,
}

/// 今日页 / 聚合页"查看"按钮的统一路由入口（Requirement 6）。
///
/// - 按 section 类型跳转到对应详情页；
/// - 若具体 id 指向的条目已被删除 / id 为空，退化到列表页或 `EmptyState` 兜底，
///   而不是把用户直接扔进黑屏页面（R6.3）；
/// - 路由构建过程中抛出的任何异常被捕获 → `ErrorState` 页（R6.4）。
class TodayDetailRouter {
  TodayDetailRouter._();

  /// 统一入口。[id] 可选；未传时进入对应 section 的列表页。
  static Future<void> open(
    BuildContext context,
    TodaySectionKind kind, {
    String? id,
  }) async {
    try {
      final route = _routeFor(context, kind, id);
      await Navigator.push(context, route);
    } catch (e, st) {
      // 路由构建阶段失败（例如 Provider 不在上下文），跳到 ErrorState 兜底。
      debugPrint('[TodayDetailRouter] route build failed: $e\n$st');
      if (!context.mounted) return;
      await Navigator.push(
        context,
        _brandRoute(
          _DetailFallback(
            kind: kind,
            title: '出错了',
            body: '打开失败：$e',
            icon: Icons.error_outline,
            accent: DesignTokens.resultError,
          ),
        ),
      );
    }
  }

  static Route<void> _routeFor(
    BuildContext context,
    TodaySectionKind kind,
    String? id,
  ) {
    switch (kind) {
      case TodaySectionKind.todos:
        if (id == null) {
          return _brandRoute(const TodoScreen());
        }
        final exists = context.read<TodoProvider>().todos.any(
          (t) => t.id == id,
        );
        if (!exists) return _emptyRoute(kind, '这个待办不存在或已被删除');
        return _brandRoute(TodoDetailScreen(todoId: id));

      case TodaySectionKind.courses:
        if (id != null) {
          final exists = context.read<CourseProvider>().courses.any(
            (course) => course.id == id,
          );
          if (!exists) return _emptyRoute(kind, '这节课程不存在或已被删除');
          return _brandRoute(CourseScheduleScreen(initialCourseId: id));
        }
        return _brandRoute(const CourseScheduleScreen());

      case TodaySectionKind.anniversaries:
        AnniversaryType? anniversaryType;
        if (id != null) {
          final items = context.read<AnniversaryProvider>().items;
          final index = items.indexWhere((a) => a.id == id);
          if (index < 0) return _emptyRoute(kind, '这个纪念日不存在或已被删除');
          anniversaryType = items[index].type;
        }
        return switch (anniversaryType) {
          AnniversaryType.birthday => _brandRoute(
            BirthdayScreen(initialAnniversaryId: id),
          ),
          AnniversaryType.memorial => _brandRoute(
            MemorialAnniversaryScreen(initialAnniversaryId: id),
          ),
          AnniversaryType.normal => _brandRoute(
            AnniversaryScreen(
              fixedType: AnniversaryType.normal,
              initialAnniversaryId: id,
            ),
          ),
          _ => _brandRoute(AnniversaryScreen(initialAnniversaryId: id)),
        };

      case TodaySectionKind.goals:
        if (id == null) {
          return _brandRoute(const GoalScreen());
        }
        final goals = context.read<GoalProvider>().goals;
        final idx = goals.indexWhere((g) => g.id == id);
        if (idx < 0) return _emptyRoute(kind, '这个目标不存在或已被删除');
        final goal = goals[idx];
        return _brandRoute(GoalEditScreen(goal: goal));

      case TodaySectionKind.habits:
        if (id == null) {
          return _brandRoute(const HabitScreen());
        }
        final exists = context.read<HabitProvider>().habits.any(
          (h) => h.id == id,
        );
        if (!exists) return _emptyRoute(kind, '这个习惯不存在或已被删除');
        return _brandRoute(HabitDetailScreen(habitId: id));

      case TodaySectionKind.notes:
        if (id == null) {
          return _brandRoute(const NoteScreen());
        }
        final notes = context.read<NoteProvider>().notes;
        final idx = notes.indexWhere((note) => note.id == id);
        if (idx < 0) return _emptyRoute(kind, '这条随手记不存在或已被删除');
        return _brandRoute(NoteEditScreen(note: notes[idx]));

      case TodaySectionKind.diary:
        return _emptyRoute(kind, I18n.tr('feature.unavailable'));
    }
  }

  static MaterialPageRoute<void> _brandRoute(Widget child) {
    return MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child));
  }

  static Route<void> _emptyRoute(TodaySectionKind kind, String msg) {
    return _brandRoute(
      _DetailFallback(
        kind: kind,
        title: _titleFor(kind),
        body: msg,
        icon: Icons.inbox_outlined,
        accent: DesignTokens.resultEmpty,
      ),
    );
  }

  static String _titleFor(TodaySectionKind kind) {
    switch (kind) {
      case TodaySectionKind.todos:
        return '待办';
      case TodaySectionKind.courses:
        return '课程';
      case TodaySectionKind.anniversaries:
        return '纪念日';
      case TodaySectionKind.goals:
        return '目标';
      case TodaySectionKind.habits:
        return '习惯';
      case TodaySectionKind.notes:
        return '随手记';
      case TodaySectionKind.diary:
        return I18n.tr('feature.unavailable');
    }
  }
}

/// 详情不可达时的兜底页（空态 / 错误态）。
///
/// - 不直接依赖 `EmptyState / ErrorState` 三件套，当前用 `DesignTokens`
///   自绘，保持详情兜底页的布局和按钮文案与聚合页一致。
class _DetailFallback extends StatelessWidget {
  final TodaySectionKind kind;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;

  const _DetailFallback({
    required this.kind,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.space3xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: accent),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeBase,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceLg),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
