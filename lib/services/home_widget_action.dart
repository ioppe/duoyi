import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart';
import '../models/pomodoro.dart' show PomodoroWidgetTimerState;
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
  pausePomodoro,
  stopPomodoro,
  quickTodo,
}

/// `duoyi://action/...` 后台动作的解析结果。
///
/// 新版专注控制（start/pause/stop）可带一套绑定字段
/// `session` / `revision` / `state` / `scope`：四个字段必须同时齐全且合法，
/// 才算“绑定控制”；任意缺失、非法、过长或空值都拒绝解析。
/// 完全不带这四个字段的 legacy `start_pomodoro` 仍按原登录 owner 规则执行。
@immutable
class HomeWidgetActionRequest {
  final HomeWidgetActionKind kind;
  final String? targetId;
  final String? text;

  /// 绑定控制：不透明 session id。
  final String? focusSessionId;

  /// 绑定控制：单调 revision（>= 0）。
  final int? focusRevision;

  /// 绑定控制：发出按钮时的小组件快照状态。
  final PomodoroWidgetTimerState? focusState;

  /// 绑定控制：小组件所属账号/匿名 scope 身份。
  final String? focusScope;

  const HomeWidgetActionRequest._({
    required this.kind,
    this.targetId,
    this.text,
    this.focusSessionId,
    this.focusRevision,
    this.focusState,
    this.focusScope,
  });

  static const String scheme = 'duoyi';
  static const String actionHost = 'action';

  /// 绑定字段长度上限：超长的 ID/scope 直接拒绝，避免原生侧拼出异常 URI。
  static const int maxFocusSessionIdLength = 128;
  static const int maxFocusScopeLength = 256;

  bool get isFocusControl =>
      kind == HomeWidgetActionKind.startPomodoro ||
      kind == HomeWidgetActionKind.pausePomodoro ||
      kind == HomeWidgetActionKind.stopPomodoro;

  /// 带完整绑定字段的专注控制（新版按钮）。
  bool get isBoundFocusControl => isFocusControl && focusSessionId != null;

  /// 允许未登录执行：只有完整的绑定 focus 控制（本地匿名专注）可以，
  /// legacy 无绑定请求仍然需要登录 owner 校验。
  bool get allowsSignedOutExecution => isBoundFocusControl;

  /// 解析后台动作；不是可后台执行的 `duoyi://action/...` 时返回 null。
  ///
  /// `quick_todo` 必须带非空 `text`：没有文字时保持原有行为，打开 App 让
  /// 用户填写完整表单，后台不创建占位待办。
  static HomeWidgetActionRequest? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != actionHost) {
      return null;
    }
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final query = uri.queryParameters;
    switch (action) {
      case 'complete_todo':
        final id = _nonEmpty(query['id']);
        if (id == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.completeTodo,
          targetId: id,
        );
      case 'checkin_habit':
        final id = _nonEmpty(query['id']);
        if (id == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.checkinHabit,
          targetId: id,
        );
      case 'start_pomodoro':
        return _focusControlRequest(
          HomeWidgetActionKind.startPomodoro,
          query,
          allowLegacy: true,
        );
      case 'pause_pomodoro':
        return _focusControlRequest(
          HomeWidgetActionKind.pausePomodoro,
          query,
          allowLegacy: false,
        );
      case 'stop_pomodoro':
        return _focusControlRequest(
          HomeWidgetActionKind.stopPomodoro,
          query,
          allowLegacy: false,
        );
      case 'quick_todo':
        final text = _nonEmpty(query['text']);
        if (text == null) return null;
        return HomeWidgetActionRequest._(
          kind: HomeWidgetActionKind.quickTodo,
          text: text,
        );
      default:
        return null;
    }
  }

  /// 专注控制的绑定校验。
  ///
  /// 只要出现 session/revision/state/scope 任一字段，就必须四段齐全且合法；
  /// 状态与动作不匹配（如 paused 发 pause、idle 发 stop）同样拒绝。
  static HomeWidgetActionRequest? _focusControlRequest(
    HomeWidgetActionKind kind,
    Map<String, String> query, {
    required bool allowLegacy,
  }) {
    final hasAnyBinding =
        query.containsKey('session') ||
        query.containsKey('revision') ||
        query.containsKey('state') ||
        query.containsKey('scope');
    if (!hasAnyBinding) {
      return allowLegacy ? HomeWidgetActionRequest._(kind: kind) : null;
    }
    final sessionId = _nonEmpty(query['session']);
    if (sessionId == null || sessionId.length > maxFocusSessionIdLength) {
      return null;
    }
    final rawRevision = _nonEmpty(query['revision']);
    final revision = rawRevision == null ? null : int.tryParse(rawRevision);
    if (revision == null || revision < 0) return null;
    final state = PomodoroWidgetTimerState.fromWire(query['state']);
    if (state == null) return null;
    final scope = _nonEmpty(query['scope']);
    if (scope == null || scope.length > maxFocusScopeLength) return null;
    final allowedStates = switch (kind) {
      HomeWidgetActionKind.startPomodoro => const <PomodoroWidgetTimerState>{
        PomodoroWidgetTimerState.idle,
        PomodoroWidgetTimerState.paused,
      },
      HomeWidgetActionKind.pausePomodoro => const <PomodoroWidgetTimerState>{
        PomodoroWidgetTimerState.running,
      },
      HomeWidgetActionKind.stopPomodoro => const <PomodoroWidgetTimerState>{
        PomodoroWidgetTimerState.running,
        PomodoroWidgetTimerState.paused,
      },
      _ => const <PomodoroWidgetTimerState>{},
    };
    if (!allowedStates.contains(state)) return null;
    return HomeWidgetActionRequest._(
      kind: kind,
      focusSessionId: sessionId,
      focusRevision: revision,
      focusState: state,
      focusScope: scope,
    );
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

  /// 未登录且无任何账号残留时的固定 focus 控制 scope。
  static const String localFocusControlScope = 'local';

  /// 当前 focus 控制 scope 身份（新版绑定按钮必须与之相等）。
  ///
  /// - 已登录且 owner / 服务器 / 账号完全匹配：`jsonEncode([owner, server])`；
  /// - 未登录且 token、accountIdentity、stored owner 全部为空：本地匿名固定值
  ///   [localFocusControlScope]（与 App 本身可离线专注的能力对齐，只放行 focus）；
  /// - owner 残留、ownerMissing、ownerMismatch、换号：null，绑定按钮全部失效。
  String? get focusControlScope {
    if (blockReason == HomeWidgetActionBlockReason.none) {
      return jsonEncode(<String>[owner ?? '', sessionServer ?? '']);
    }
    if (!hasSession && owner == null && accountIdentity == null) {
      return localFocusControlScope;
    }
    return null;
  }
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
