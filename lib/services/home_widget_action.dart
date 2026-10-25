import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart';
import '../models/todo.dart';
import '../providers/auth_provider.dart' show AuthProvider, AuthState;
import 'account_local_data_cleaner.dart';

/// 桌面小组件可以在后台直接执行的动作。
///
/// 只有“按钮类”操作能在后台完成；导航、标题、查看详情仍然通过
/// `HomeWidgetLaunchIntent` 打开 App。
enum HomeWidgetActionKind {
  completeTodo,
  checkinHabit,
  startPomodoro,
  quickTodo,
}

/// `duoyi://action/...` 后台动作的解析结果。
@immutable
class HomeWidgetActionRequest {
  final HomeWidgetActionKind kind;
  final String? targetId;
  final String? text;

  const HomeWidgetActionRequest._({
    required this.kind,
    this.targetId,
    this.text,
  });

  static const String scheme = 'duoyi';
  static const String actionHost = 'action';

  /// 解析后台动作；不是可后台执行的 `duoyi://action/...` 时返回 null。
  ///
  /// `quick_todo` 必须带非空 `text`：没有文字时保持原有行为，打开 App 让
  /// 用户填写完整表单，后台不创建占位待办。
  static HomeWidgetActionRequest? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != actionHost) {
      return null;
    }
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    switch (action) {
      case 'complete_todo':
        final id = _nonEmpty(uri.queryParameters['id']);
        if (id == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.completeTodo,
          targetId: id,
        );
      case 'checkin_habit':
        final id = _nonEmpty(uri.queryParameters['id']);
        if (id == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.checkinHabit,
          targetId: id,
        );
      case 'start_pomodoro':
        return const HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.startPomodoro,
        );
      case 'quick_todo':
        final text = _nonEmpty(uri.queryParameters['text']);
        if (text == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.quickTodo,
          text: text,
        );
      default:
        return null;
    }
  }
}

/// 后台动作被账号边界拦下的原因。
enum HomeWidgetActionBlockReason {
  none,
  signedOut,
  ownerMissing,
  ownerMismatch,
}

/// 后台动作执行前的账号边界快照。
///
/// 语义必须与 `AuthProvider` 写 `AccountLocalDataCleaner.accountDataOwnerKey`
/// 的方式一致（`lib/providers/auth_provider.dart:1603` 起）：
/// owner 是 `jsonEncode([serverIdentity, account])`，账号部分是
/// `id:<userId>` / `username:<小写>` / `email:<小写>` 的优先级回退。
/// 早期版本可能只存未带服务器前缀的账号部分，`AuthProvider` 会把它当作同服务器
/// 的旧数据迁移，这里同样接受。
@immutable
class HomeWidgetAccountScope {
  static const String authStateKey = 'auth_state';

  final String? owner;
  final String? userId;
  final String? username;
  final String? email;
  final String? token;
  final String? sessionServer;

  const HomeWidgetAccountScope._({
    required this.owner,
    required this.userId,
    required this.username,
    required this.email,
    required this.token,
    required this.sessionServer,
  });

  factory HomeWidgetAccountScope.fromPreferences(SharedPreferences prefs) {
    return HomeWidgetAccountScope.fromValues(
      authStateJson: prefs.getString(authStateKey),
      storedOwner: prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
      sessionServer: prefs.getString(AuthProvider.sessionServerStorageKey),
    );
  }

  @visibleForTesting
  factory HomeWidgetAccountScope.fromValues({
    required String? authStateJson,
    required String? storedOwner,
    required String? sessionServer,
  }) {
    final state = _decodeAuthState(authStateJson);
    return HomeWidgetAccountScope._(
      owner: _nonEmpty(storedOwner),
      userId: _nonEmpty(state?.userId),
      username: _nonEmpty(state?.username),
      email: _nonEmpty(state?.email),
      token: _nonEmpty(state?.token),
      sessionServer: _nonEmpty(sessionServer),
    );
  }

  bool get hasSession => token != null;

  /// `AuthProvider` 记录的账号身份（`id:` / `username:` / `email:` 前缀）。
  String? get accountIdentity =>
      stableAccountIdentityOf(userId: userId, username: username, email: email);

  /// 是否允许后台写账号数据。未登录、owner 缺失或与当前账号不符时都不允许，
  /// 避免把上一账号的数据写进新账号。
  HomeWidgetActionBlockReason get blockReason {
    if (!hasSession) return HomeWidgetActionBlockReason.signedOut;
    final identity = accountIdentity;
    final stored = _decodeStoredOwner(owner);
    if (identity == null || stored == null) {
      return HomeWidgetActionBlockReason.ownerMissing;
    }
    final server = sessionServer;
    if (stored.server == null) {
      // 旧版 owner 只有账号部分，`AuthProvider` 只在默认服务器上迁移它。
      return stored.account == identity
          ? HomeWidgetActionBlockReason.none
          : HomeWidgetActionBlockReason.ownerMismatch;
    }
    if (server == null || stored.server != server) {
      return HomeWidgetActionBlockReason.ownerMismatch;
    }
    return stored.account == identity
        ? HomeWidgetActionBlockReason.none
        : HomeWidgetActionBlockReason.ownerMismatch;
  }

  bool get isCurrentAccount => blockReason == HomeWidgetActionBlockReason.none;
}

/// 与 `AuthProvider._stableAccountIdentity` 相同的账号身份格式。
///
/// 依赖顺序（userId → username → email）和前缀必须与
/// `lib/providers/auth_provider.dart:1610` 保持一致，否则后台 owner 校验会误判。
String? stableAccountIdentityOf({
  String? userId,
  String? username,
  String? email,
}) {
  final id = _nonEmpty(userId);
  if (id != null) return 'id:$id';
  final name = _nonEmpty(username)?.toLowerCase();
  if (name != null) return 'username:$name';
  final mail = _nonEmpty(email)?.toLowerCase();
  if (mail != null) return 'email:$mail';
  return null;
}

/// 桌面“完成待办”的目标校验结果。
enum HomeWidgetTodoTargetState { ready, missing, alreadyCompleted }

/// 桌面“完成待办”是否可执行（主 isolate 提示文案与后台动作共用同一判断）。
HomeWidgetTodoTargetState homeWidgetTodoTargetState(TodoItem? todo) {
  if (todo == null) return HomeWidgetTodoTargetState.missing;
  if (todo.isCompleted) return HomeWidgetTodoTargetState.alreadyCompleted;
  return HomeWidgetTodoTargetState.ready;
}

/// 桌面“快捷打卡”的目标校验结果。
enum HomeWidgetHabitTargetState {
  ready,
  missing,
  unsupportedKind,
  notActiveToday,
  alreadyCompleted,
}

/// 桌面“快捷打卡”是否可执行（主 isolate 提示文案与后台动作共用同一判断）。
HomeWidgetHabitTargetState homeWidgetHabitTargetState(Habit? habit) {
  if (habit == null) return HomeWidgetHabitTargetState.missing;
  if (habit.kind != HabitKind.positive) {
    return HomeWidgetHabitTargetState.unsupportedKind;
  }
  if (!habit.isActiveToday()) return HomeWidgetHabitTargetState.notActiveToday;
  if (habit.isCompletedToday()) {
    return HomeWidgetHabitTargetState.alreadyCompleted;
  }
  return HomeWidgetHabitTargetState.ready;
}

AuthState? _decodeAuthState(String? raw) {
  final text = _nonEmpty(raw);
  if (text == null) return null;
  try {
    final decoded = json.decode(text);
    if (decoded is Map<String, dynamic>) return AuthState.fromJson(decoded);
    if (decoded is Map) {
      return AuthState.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    // 损坏的登录态等同于未登录：后台动作直接 no-op。
  }
  return null;
}

({String? server, String account})? _decodeStoredOwner(String? raw) {
  final text = _nonEmpty(raw);
  if (text == null) return null;
  if (!text.startsWith('[')) {
    return (server: null, account: text);
  }
  try {
    final decoded = json.decode(text);
    if (decoded is List && decoded.length == 2) {
      final server = _nonEmpty(decoded[0]?.toString());
      final account = _nonEmpty(decoded[1]?.toString());
      if (server != null && account != null) {
        return (server: server, account: account);
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
