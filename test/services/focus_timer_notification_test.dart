import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/services/focus_timer_notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _brand = FocusTimerNotificationBrand(
  appTitle: '多仪',
  focusLabel: '专注中',
  shortBreakLabel: '短休息',
  longBreakLabel: '长休息',
  pausedLabel: '已暂停',
  noTaskLabel: '无关联任务',
  channelName: '专注计时',
  remainingLabel: '剩余',
  elapsedLabel: '已计时',
  startActionLabel: '开始',
  pauseActionLabel: '暂停',
  resetActionLabel: '重置',
  accentColorArgb: 0xFFC85656,
);

const _otherLocaleBrand = FocusTimerNotificationBrand(
  appTitle: 'Duoyi',
  focusLabel: 'Focusing',
  shortBreakLabel: 'Short break',
  longBreakLabel: 'Long break',
  pausedLabel: 'Paused',
  noTaskLabel: 'No linked task',
  channelName: 'Focus timer',
  remainingLabel: 'Remaining',
  elapsedLabel: 'Elapsed',
  startActionLabel: 'Start',
  pauseActionLabel: 'Pause',
  resetActionLabel: 'Reset',
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
  int anchorMillis = 0,
  String controlSessionId = '',
  int controlRevision = 0,
  String controlState = '',
}) => FocusTimerNotificationPayload.fromState(
  state: state ?? _state(),
  paused: paused,
  brand: _brand,
  anchorMillis: anchorMillis,
  controlSessionId: controlSessionId,
  controlRevision: controlRevision,
  controlState: controlState,
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

    test('本地化时间前缀与按钮文案随 payload 下发（原生不硬编码）', () {
      final map = _payload().toMap();
      expect(map['remainingLabel'], '剩余');
      expect(map['elapsedLabel'], '已计时');
      expect(map['startActionLabel'], '开始');
      expect(map['pauseActionLabel'], '暂停');
      expect(map['resetActionLabel'], '重置');
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

  group('canonical 锚点与控制绑定', () {
    test('运行态透传锚点与控制三件套', () {
      final map = _payload(
        anchorMillis: 1794000000000,
        controlSessionId: 'focus-1',
        controlRevision: 3,
        controlState: 'running',
      ).toMap();
      expect(map['anchorMillis'], 1794000000000);
      expect(map['controlSessionId'], 'focus-1');
      expect(map['controlRevision'], 3);
      expect(map['controlState'], 'running');
    });

    test('暂停必须把锚点清零，冻结在传入剩余值', () {
      final map = _payload(
        state: _state(remainingSeconds: 240, isRunning: false),
        paused: true,
        anchorMillis: 1794000000000,
        controlSessionId: 'focus-1',
        controlRevision: 4,
        controlState: 'paused',
      ).toMap();
      expect(map['anchorMillis'], 0);
      expect(map['remainingMillis'], 240000);
      expect(map['controlState'], 'paused');
    });

    test('状态与动作不一致或身份缺失时不带绑定（原生不显示按钮）', () {
      // 运行态却声明 paused。
      final mismatched = _payload(
        controlSessionId: 'focus-1',
        controlRevision: 1,
        controlState: 'paused',
      ).toMap();
      expect(mismatched['controlSessionId'], '');
      expect(mismatched['controlRevision'], 0);
      expect(mismatched['controlState'], '');

      // 缺少 session / 非法 state / 负 revision。
      expect(
        _payload(
          controlRevision: 1,
          controlState: 'running',
        ).toMap()['controlSessionId'],
        '',
      );
      expect(
        _payload(
          controlSessionId: 'focus-1',
          controlRevision: 1,
          controlState: 'idle',
        ).toMap()['controlSessionId'],
        '',
      );
      expect(
        _payload(
          controlSessionId: 'focus-1',
          controlRevision: -1,
          controlState: 'running',
        ).toMap()['controlSessionId'],
        '',
      );
    });

    test('旧 payload 默认不带锚点与绑定（向后兼容）', () {
      final map = _payload().toMap();
      expect(map['anchorMillis'], 0);
      expect(map['controlSessionId'], '');
      expect(map['controlRevision'], 0);
      expect(map['controlState'], '');
    });
  });

  group('通知按钮深链解析', () {
    FocusTimerNotificationControl? parse(String uri) =>
        FocusTimerNotificationControl.parse(Uri.parse(uri));

    test('pause / start / reset 解析出绑定身份与期望状态', () {
      final pause = parse(
        'duoyi://focus-timer/pause?session=focus-1&revision=3&state=running',
      )!;
      expect(pause.action, PomodoroWidgetControlAction.pause);
      expect(pause.widgetAction, PomodoroWidgetControlAction.pause);
      expect(pause.sessionId, 'focus-1');
      expect(pause.revision, 3);
      expect(pause.expectedState, PomodoroWidgetTimerState.running);

      final start = parse(
        'duoyi://focus-timer/start?session=focus-1&revision=4&state=paused',
      )!;
      expect(start.action, PomodoroWidgetControlAction.start);
      expect(start.expectedState, PomodoroWidgetTimerState.paused);

      // reset 复用既有 stop 语义：回满时长、不产生完成记录。
      final runningReset = parse(
        'duoyi://focus-timer/reset?session=focus-1&revision=5&state=running',
      )!;
      expect(runningReset.action, PomodoroWidgetControlAction.stop);
      final pausedReset = parse(
        'duoyi://focus-timer/reset?session=focus-1&revision=6&state=paused',
      )!;
      expect(pausedReset.action, PomodoroWidgetControlAction.stop);
      expect(pausedReset.expectedState, PomodoroWidgetTimerState.paused);
    });

    test('非法 scheme / host / 多段路径 / 未知动作一律拒绝', () {
      expect(
        parse('https://focus-timer/pause?session=s&revision=1&state=running'),
        isNull,
      );
      expect(
        parse('duoyi://action/pause?session=s&revision=1&state=running'),
        isNull,
      );
      expect(
        parse(
          'duoyi://focus-timer/pause/extra?session=s&revision=1&state=running',
        ),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/?session=s&revision=1&state=running'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/stop?session=s&revision=1&state=running'),
        isNull,
      );
      expect(FocusTimerNotificationControl.parse(null), isNull);
    });

    test('畸形 session / revision / state 一律拒绝', () {
      // 缺少 session。
      expect(
        parse('duoyi://focus-timer/pause?revision=1&state=running'),
        isNull,
      );
      // session 含非法字符或超长。
      expect(
        parse(
          'duoyi://focus-timer/pause?session=focus%201&revision=1&state=running',
        ),
        isNull,
      );
      expect(
        parse(
          'duoyi://focus-timer/pause?session=${List.filled(129, 'a').join()}&revision=1&state=running',
        ),
        isNull,
      );
      // revision 非数字 / 负数 / 缺失。
      expect(
        parse('duoyi://focus-timer/pause?session=s&revision=x&state=running'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/pause?session=s&revision=-1&state=running'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/pause?session=s&state=running'),
        isNull,
      );
      // state 缺失 / 非协议值。
      expect(parse('duoyi://focus-timer/pause?session=s&revision=1'), isNull);
      expect(
        parse('duoyi://focus-timer/pause?session=s&revision=1&state=idle'),
        isNull,
      );
    });

    test('动作与期望状态不匹配时拒绝（start 只接受 paused，pause 只接受 running）', () {
      expect(
        parse('duoyi://focus-timer/start?session=s&revision=1&state=running'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/start?session=s&revision=1&state=idle'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/pause?session=s&revision=1&state=paused'),
        isNull,
      );
      expect(
        parse('duoyi://focus-timer/pause?session=s&revision=1&state=idle'),
        isNull,
      );
    });

    test('原生 controlUri 生成的 URI 能被 Dart 解析器原样接受', () {
      // 与 FocusTimerNotificationModel.controlUri 相同的拼装规则。
      for (final entry in <String, PomodoroWidgetControlAction>{
        'pause': PomodoroWidgetControlAction.pause,
        'start': PomodoroWidgetControlAction.start,
        'reset': PomodoroWidgetControlAction.stop,
      }.entries) {
        final state = entry.key == 'start' ? 'paused' : 'running';
        final control = parse(
          'duoyi://focus-timer/${entry.key}?session=focus-42&revision=7&state=$state',
        )!;
        expect(control.action, entry.value);
        expect(control.sessionId, 'focus-42');
        expect(control.revision, 7);
      }
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
        remainingLabel: '剩余',
        elapsedLabel: '已计时',
        startActionLabel: '开始',
        pauseActionLabel: '暂停',
        resetActionLabel: '重置',
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
        remainingLabel: '剩余',
        elapsedLabel: '已计时',
        startActionLabel: '开始',
        pauseActionLabel: '暂停',
        resetActionLabel: '重置',
        accentColorArgb: 0xFFC85656,
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.isUsable, isTrue);
      expect(first, isNot(_otherLocaleBrand));
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
        remainingLabel: '',
        elapsedLabel: '',
        startActionLabel: '',
        pauseActionLabel: '',
        resetActionLabel: '',
        accentColorArgb: 0,
      );
      expect(empty.isUsable, isFalse);

      // 时间前缀缺失时同样不推送：正文会退化成纯任务名。
      const missingTimeLabels = FocusTimerNotificationBrand(
        appTitle: '多仪',
        focusLabel: '专注中',
        shortBreakLabel: '短休息',
        longBreakLabel: '长休息',
        pausedLabel: '已暂停',
        noTaskLabel: '无关联任务',
        channelName: '专注计时',
        remainingLabel: ' ',
        elapsedLabel: '',
        startActionLabel: '开始',
        pauseActionLabel: '暂停',
        resetActionLabel: '重置',
        accentColorArgb: 0xFFC85656,
      );
      expect(missingTimeLabels.isUsable, isFalse);
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

    test('主题/语言重推复用同一锚点与控制绑定，不会延长期限或丢按钮', () async {
      const channel = MethodChannel('duoyi/focus_timer');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = FocusTimerNotificationService.instance;
      await service.stop();
      service.setBrand(_brand);
      calls.clear();
      const anchor = 1794000000000;
      await service.sync(
        _state(),
        paused: false,
        anchorMillis: anchor,
        controlSessionId: 'focus-1',
        controlRevision: 3,
        controlState: 'running',
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'sync');
      expect((calls.single.arguments as Map)['anchorMillis'], anchor);

      calls.clear();
      // 语言/主题切换后只用最近一次状态重推。
      service.setBrand(_otherLocaleBrand);
      await pumpEventQueue();
      expect(calls, hasLength(1));
      final repushed = calls.single.arguments as Map;
      expect(calls.single.method, 'sync');
      expect(repushed['anchorMillis'], anchor);
      expect(repushed['controlSessionId'], 'focus-1');
      expect(repushed['controlRevision'], 3);
      expect(repushed['controlState'], 'running');
      expect(repushed['remainingLabel'], 'Remaining');
      expect(repushed['remainingMillis'], 600000);

      await service.stop();
    });
  });
}
