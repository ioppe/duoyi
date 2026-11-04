import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/services/focus_timer_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _brand = FocusTimerNotificationBrand(
  appTitle: '多仪',
  focusLabel: '专注中',
  shortBreakLabel: '短休息',
  longBreakLabel: '长休息',
  pausedLabel: '已暂停',
  noTaskLabel: '无关联任务',
  channelName: '专注计时',
  accentColorArgb: 0xFFC85656,
);

PomodoroState _state({
  int remainingSeconds = 600,
  int totalSeconds = 1500,
  bool isCountUp = false,
  bool isRunning = true,
  PomodoroType type = PomodoroType.focus,
  String? taskName,
  String? todoTitle,
  String? subtaskId,
}) => PomodoroState(
  remainingSeconds: remainingSeconds,
  totalSeconds: totalSeconds,
  isRunning: isRunning,
  isCountUp: isCountUp,
  type: type,
  completedSessions: 0,
  taskName: taskName,
  todoTitle: todoTitle,
  subtaskId: subtaskId,
);

FocusTimerNotificationPayload _payload({
  PomodoroState? state,
  bool paused = false,
}) => FocusTimerNotificationPayload.fromState(
  state: state ?? _state(),
  paused: paused,
  brand: _brand,
);

void main() {
  // FocusTimerNotificationService 构造时注册 MethodChannel 回调，需要 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('专注通知 payload', () {
    test('倒计时：阶段文案、剩余毫秒、进度与主题色', () {
      final payload = _payload();
      final map = payload.toMap();
      expect(map['phase'], 'focus');
      expect(map['phaseLabel'], '专注中');
      expect(map['appTitle'], '多仪');
      expect(map['channelName'], '专注计时');
      expect(map['paused'], isFalse);
      expect(map['isCountUp'], isFalse);
      expect(map['remainingMillis'], 600000);
      expect(map['totalMillis'], 1500000);
      // (1500 - 600) / 1500 = 60%
      expect(map['progressPermille'], 600);
      expect(map['accentColorArgb'], 0xFFC85656);
      expect(map['returnUri'], 'duoyi://tab/focus');
      // 无关联任务时不伪造标题，交给原生使用注入的兜底文案。
      expect(map['taskLabel'], isNull);
      expect(map['noTaskLabel'], '无关联任务');
    });

    test('暂停：冻结当前剩余时间，不清零也不显示负值', () {
      final payload = _payload(
        state: _state(remainingSeconds: 240, isRunning: false),
        paused: true,
      );
      final map = payload.toMap();
      expect(map['paused'], isTrue);
      expect(map['remainingMillis'], 240000);
      expect(map['progressPermille'], 840); // (1500-240)/1500
      expect(map['pausedLabel'], '已暂停');
    });

    test('正计时：累计毫秒向上计时，进度条由原生隐藏', () {
      final payload = _payload(
        state: _state(remainingSeconds: 90, totalSeconds: 0, isCountUp: true),
      );
      final map = payload.toMap();
      expect(map['isCountUp'], isTrue);
      expect(map['remainingMillis'], 90000);
      expect(map['totalMillis'], 0);
      expect(map['progressPermille'], 0);
    });

    test('休息阶段使用对应品牌文案', () {
      expect(
        _payload(state: _state(type: PomodoroType.shortBreak)).phaseLabel,
        '短休息',
      );
      expect(
        _payload(state: _state(type: PomodoroType.longBreak)).phaseLabel,
        '长休息',
      );
      expect(
        _payload(state: _state(type: PomodoroType.shortBreak)).phase,
        'shortBreak',
      );
    });

    test('关联任务：带出 taskLabel，子任务显示父任务/子任务', () {
      final parent = _payload(
        state: _state(taskName: '整理周报', todoTitle: '工作', subtaskId: 's1'),
      );
      expect(parent.taskLabel, '工作 / 整理周报');
      final plain = _payload(state: _state(taskName: '  阅读 '));
      expect(plain.taskLabel, '阅读');
      final blank = _payload(state: _state(taskName: '   '));
      expect(blank.taskLabel, isNull);
    });

    test('异常剩余时长不会进入通知（不出负计时）', () {
      final map = _payload(
        state: _state(remainingSeconds: -30, totalSeconds: -1),
      ).toMap();
      expect(map['remainingMillis'], 0);
      expect(map['totalMillis'], 0);
      expect(map['progressPermille'], 0);
    });

    test('进度千分比被钳制在 0..1000', () {
      expect(
        _payload(
          state: _state(remainingSeconds: 5000, totalSeconds: 1500),
        ).progressPermille,
        0,
      );
      expect(
        _payload(
          state: _state(remainingSeconds: 0, totalSeconds: 1500),
        ).progressPermille,
        1000,
      );
    });
  });

  group('品牌注入', () {
    test('相同文案与颜色视为同一品牌，不会重复推送', () {
      const first = FocusTimerNotificationBrand(
        appTitle: '多仪',
        focusLabel: '专注中',
        shortBreakLabel: '短休息',
        longBreakLabel: '长休息',
        pausedLabel: '已暂停',
        noTaskLabel: '无关联任务',
        channelName: '专注计时',
        accentColorArgb: 0xFFC85656,
      );
      const second = FocusTimerNotificationBrand(
        appTitle: '多仪',
        focusLabel: '专注中',
        shortBreakLabel: '短休息',
        longBreakLabel: '长休息',
        pausedLabel: '已暂停',
        noTaskLabel: '无关联任务',
        channelName: '专注计时',
        accentColorArgb: 0xFFC85656,
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.isUsable, isTrue);
    });

    test('缺少关键文案的品牌不可用（避免推送空通知）', () {
      const empty = FocusTimerNotificationBrand(
        appTitle: '',
        focusLabel: '',
        shortBreakLabel: '',
        longBreakLabel: '',
        pausedLabel: '',
        noTaskLabel: '',
        channelName: '',
        accentColorArgb: 0,
      );
      expect(empty.isUsable, isFalse);
    });
  });

  group('服务在非 Android 宿主上是安全 no-op', () {
    test('sync/stop 不抛异常，并记录活动状态', () async {
      final service = FocusTimerNotificationService.instance;
      service.setBrand(_brand);
      await service.sync(_state(), paused: false);
      expect(service.isActive, isTrue);
      await service.stop();
      expect(service.isActive, isFalse);
    });

    test('stop 可重复调用，之后 sync 重新激活通知', () async {
      final service = FocusTimerNotificationService.instance;
      await service.stop();
      await service.stop();
      expect(service.isActive, isFalse);
      await service.sync(_state(), paused: true);
      expect(service.isActive, isTrue);
      await service.stop();
      expect(service.isActive, isFalse);
    });
  });
}
