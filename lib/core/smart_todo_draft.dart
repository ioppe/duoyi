import '../models/goal.dart'
    show
        ReminderConfig,
        ReminderKind,
        ReminderPlan,
        ReminderRule,
        ReminderRuleType;
import '../models/recurrence.dart';
import '../models/todo.dart';
import 'app_clock.dart';
import 'smart_date_parser.dart';

class SmartTodoDraft {
  final String title;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final ReminderConfig reminder;
  final ReminderPlan reminderPlan;
  final RecurrenceRule recurrence;

  const SmartTodoDraft({
    required this.title,
    required this.date,
    this.dueDate,
    this.reminderAt,
    required this.reminder,
    required this.reminderPlan,
    this.recurrence = const RecurrenceRule(),
  });

  bool get hasReminder => reminderPlan.enabled && reminderPlan.rules.isNotEmpty;

  TodoItem toTodo({
    EisenhowerQuadrant quadrant = EisenhowerQuadrant.notUrgentImportant,
    TodoPriority priority = TodoPriority.none,
    String? listGroupName,
    String workspaceId = 'private',
    String? createdBy,
    String? updatedBy,
    List<Subtask>? subtasks,
  }) {
    return TodoItem(
      title: title,
      date: date,
      dueDate: dueDate,
      hasReminder: hasReminder,
      reminderAt: reminderAt,
      reminder: reminder,
      reminderPlan: reminderPlan,
      recurrence: recurrence,
      quadrant: quadrant,
      priority: priority,
      listGroupName: listGroupName,
      workspaceId: workspaceId,
      createdBy: createdBy,
      updatedBy: updatedBy,
      subtasks: subtasks,
    );
  }
}

class SmartTodoDraftBuilder {
  SmartTodoDraftBuilder._();

  static SmartTodoDraft fromText(
    String input, {
    DateTime? now,
    ReminderKind defaultReminderKind = ReminderKind.push,
  }) {
    final trimmed = _normalizeSpaces(input);
    final fallbackNow = now == null ? AppClock.now() : AppClock.toLocal(now);
    final recurrence = _parseRecurrence(trimmed, fallbackNow);
    final parsed = SmartDateParser.parse(
      recurrence.dateInput ?? trimmed,
      now: fallbackNow,
    );

    if (!parsed.isSuccess) {
      return SmartTodoDraft(
        title: recurrence.isActive
            ? _stripDatePhrases(trimmed, recurrence.matchedTexts)
            : trimmed,
        // 解析失败时回退到当前应用时区时刻（保留时分），与成功路径的
        // `date` 语义一致，调用方可直接用作提醒/日程起点。
        date: fallbackNow,
        reminder: const ReminderConfig.disabled(),
        reminderPlan: const ReminderPlan.disabled(),
        recurrence: recurrence.rule,
      );
    }

    var parsedDate = parsed.dateTime!;
    if (recurrence.isActive &&
        parsed.hasTimeOfDay &&
        parsedDate.isBefore(fallbackNow)) {
      final next = recurrence.rule.nextAfter(AppClock.dateOnly(parsedDate));
      if (next != null) {
        parsedDate = AppClock.date(
          next.year,
          next.month,
          next.day,
          parsedDate.hour,
          parsedDate.minute,
        );
      }
    }
    if (!recurrence.isActive && parsed.hasTimeOfDay) {
      parsedDate = _nudgeSameMinutePastTime(parsedDate, fallbackNow);
    }
    final title = recurrence.isActive
        ? _stripDatePhrases(trimmed, recurrence.matchedTexts)
        : _stripDatePhrase(trimmed, parsed.matchedText);

    if (!parsed.hasTimeOfDay) {
      return SmartTodoDraft(
        title: title,
        date: parsedDate,
        reminder: const ReminderConfig.disabled(),
        reminderPlan: const ReminderPlan.disabled(),
        recurrence: recurrence.rule,
      );
    }

    final reminder = ReminderConfig(
      enabled: true,
      kind: defaultReminderKind,
      hour: parsedDate.hour,
      minute: parsedDate.minute,
      daysBefore: 0,
      vibrate: true,
      fullScreen: defaultReminderKind == ReminderKind.alarm,
    );
    final plan = ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: 'smart-date-${parsedDate.millisecondsSinceEpoch}',
          enabled: true,
          type: ReminderRuleType.absolute,
          kind: defaultReminderKind,
          hour: parsedDate.hour,
          minute: parsedDate.minute,
          vibrate: true,
          fullScreen: defaultReminderKind == ReminderKind.alarm,
        ),
      ],
    );

    return SmartTodoDraft(
      title: title,
      date: parsedDate,
      dueDate: parsedDate,
      reminderAt: parsedDate,
      reminder: reminder,
      reminderPlan: plan,
      recurrence: recurrence.rule,
    );
  }

  static String _stripDatePhrase(String input, String matchedText) {
    return _stripDatePhrases(input, [matchedText]);
  }

  static DateTime _nudgeSameMinutePastTime(DateTime parsed, DateTime now) {
    if (!parsed.isBefore(now)) return parsed;
    final sameMinute =
        parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day &&
        parsed.hour == now.hour &&
        parsed.minute == now.minute;
    if (!sameMinute) return parsed;
    return parsed.add(
      Duration(
        seconds: 60 - parsed.second,
        milliseconds: -parsed.millisecond,
        microseconds: -parsed.microsecond,
      ),
    );
  }

  static String _stripDatePhrases(String input, Iterable<String> matchedTexts) {
    var next = input;
    for (final matchedText in matchedTexts) {
      if (matchedText.trim().isEmpty) continue;
      next = next.replaceFirst(matchedText, '');
    }
    final stripped = _normalizeSpaces(next);
    return stripped.isEmpty ? input : stripped;
  }

  static String _normalizeSpaces(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static _SmartRecurrenceParseResult _withRecurrenceEnding(
    _SmartRecurrenceParseResult result,
    String input,
    DateTime now,
  ) {
    final ending = _parseRecurrenceEnding(input, now);
    if (!ending.hasAny) return result;
    return _SmartRecurrenceParseResult(
      rule: result.rule.copyWith(
        endDate: ending.endDate,
        maxOccurrences: ending.maxOccurrences,
      ),
      matchedText: result.matchedText,
      dateInput: result.dateInput,
      extraMatchedTexts: ending.matchedTexts,
    );
  }

  static _SmartRecurrenceEnding _parseRecurrenceEnding(
    String input,
    DateTime now,
  ) {
    final matchedTexts = <String>[];
    DateTime? endDate;
    int? maxOccurrences;

    final zhEnd = _parseChineseRecurrenceEndDate(input, now);
    if (zhEnd != null) {
      endDate = zhEnd.endDate;
      matchedTexts.add(zhEnd.matchedText);
    } else {
      final enEnd = _parseEnglishRecurrenceEndDate(input, now);
      if (enEnd != null) {
        endDate = enEnd.endDate;
        matchedTexts.add(enEnd.matchedText);
      }
    }

    final zhCount = RegExp(
      '(?:共|重复|持续)\\s*($_numberTokenPattern)\\s*(?:次|遍|回)',
    ).firstMatch(input);
    if (zhCount != null) {
      maxOccurrences = _parsePositiveChineseAmount(zhCount.group(1)!);
      matchedTexts.add(zhCount.group(0)!);
    } else {
      final enCount = RegExp(
        r'\bfor\s+([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten|'
        r'eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|'
        r'eighteen|nineteen|twenty)\s+(?:times|occurrences?)\b',
        caseSensitive: false,
      ).firstMatch(input);
      if (enCount != null) {
        maxOccurrences = _parsePositiveEnglishAmount(enCount.group(1)!);
        matchedTexts.add(enCount.group(0)!);
      }
    }

    return _SmartRecurrenceEnding(
      endDate: endDate,
      maxOccurrences: maxOccurrences,
      matchedTexts: matchedTexts,
    );
  }

  static _SmartRecurrenceEndDate? _parseChineseRecurrenceEndDate(
    String input,
    DateTime now,
  ) {
    final pattern = RegExp(
      '(?:直到|截止(?:到)?|到)\\s*([^，,。；;]+?)(?:为止)?(?=\$|[，,。；;])',
    );
    for (final match in pattern.allMatches(input)) {
      final parsed = SmartDateParser.parse(match.group(1)!, now: now);
      if (!parsed.isSuccess) continue;
      return _SmartRecurrenceEndDate(
        endDate: parsed.dateTime!,
        matchedText: match.group(0)!,
      );
    }
    return null;
  }

  static _SmartRecurrenceEndDate? _parseEnglishRecurrenceEndDate(
    String input,
    DateTime now,
  ) {
    final pattern = RegExp(r'\buntil\s+([^,.;]+)', caseSensitive: false);
    for (final match in pattern.allMatches(input)) {
      final parsed = SmartDateParser.parse(match.group(1)!, now: now);
      if (!parsed.isSuccess) continue;
      return _SmartRecurrenceEndDate(
        endDate: parsed.dateTime!,
        matchedText: match.group(0)!,
      );
    }
    return null;
  }

  static _SmartRecurrenceParseResult _parseRecurrence(
    String input,
    DateTime now,
  ) {
    final yearlyZh = _parseChineseYearlyRecurrence(input);
    if (yearlyZh != null) return _withRecurrenceEnding(yearlyZh, input, now);

    final monthlyZh = _parseChineseMonthlyRecurrence(input, now);
    if (monthlyZh != null) return _withRecurrenceEnding(monthlyZh, input, now);

    final weekdayZh = _parseChineseWorkdayRecurrence(input, now);
    if (weekdayZh != null) return _withRecurrenceEnding(weekdayZh, input, now);

    final dailyZh = _parseChineseDailyRecurrence(input);
    if (dailyZh != null) return _withRecurrenceEnding(dailyZh, input, now);

    final weeklyZh = _parseChineseWeeklyRecurrence(input, now);
    if (weeklyZh != null) return _withRecurrenceEnding(weeklyZh, input, now);

    final yearlyEn = _parseEnglishYearlyRecurrence(input);
    if (yearlyEn != null) return _withRecurrenceEnding(yearlyEn, input, now);

    final monthlyEn = _parseEnglishMonthlyRecurrence(input, now);
    if (monthlyEn != null) return _withRecurrenceEnding(monthlyEn, input, now);

    final workdayEn = _parseEnglishWorkdayRecurrence(input, now);
    if (workdayEn != null) return _withRecurrenceEnding(workdayEn, input, now);

    final dailyEn = _parseEnglishDailyRecurrence(input);
    if (dailyEn != null) return _withRecurrenceEnding(dailyEn, input, now);

    final weeklyEn = _parseEnglishWeeklyRecurrence(input, now);
    if (weeklyEn != null) return _withRecurrenceEnding(weeklyEn, input, now);

    return const _SmartRecurrenceParseResult();
  }

  static _SmartRecurrenceParseResult? _parseChineseDailyRecurrence(
    String input,
  ) {
    final intervalMatch = RegExp(
      '(?:每\\s*($_numberTokenPattern)\\s*天|每隔一天|隔天)\\s*'
      '($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (intervalMatch != null) {
      final interval = intervalMatch.group(1) == null
          ? 2
          : _parsePositiveChineseAmount(intervalMatch.group(1)!);
      final time = _cleanPart(intervalMatch.group(2));
      return _SmartRecurrenceParseResult(
        rule: RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          interval: interval,
        ),
        matchedText: intervalMatch.group(0)!,
        dateInput: _joinParts(['今天', time]),
      );
    }

    final match = RegExp(
      '每天\\s*($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (match == null) return null;
    final time = _cleanPart(match.group(1));
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
      matchedText: match.group(0)!,
      dateInput: _joinParts(['今天', time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseChineseWorkdayRecurrence(
    String input,
    DateTime now,
  ) {
    final match = RegExp(
      '每(?:个)?工作日\\s*($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (match == null) return null;
    final time = _cleanPart(match.group(1));
    final first = _firstWeekdayFrom(now, const [0, 1, 2, 3, 4]);
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: [0, 1, 2, 3, 4],
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([_chineseDatePhraseForWeekday(first, now), time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseChineseWeeklyRecurrence(
    String input,
    DateTime now,
  ) {
    final weekendMatch = RegExp(
      '每\\s*($_numberTokenPattern)?\\s*(?:个)?(?:周末|星期末)\\s*'
      '($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (weekendMatch != null) {
      final interval = weekendMatch.group(1) == null
          ? 1
          : _parsePositiveChineseAmount(weekendMatch.group(1)!);
      final days = const [5, 6];
      final first = _firstWeekdayFrom(now, days);
      final time = _cleanPart(weekendMatch.group(2));
      return _SmartRecurrenceParseResult(
        rule: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: interval,
          byWeekdays: days,
        ),
        matchedText: weekendMatch.group(0)!,
        dateInput: _joinParts([_chineseDatePhraseForWeekday(first, now), time]),
      );
    }

    final match = RegExp(
      '每\\s*($_numberTokenPattern)?\\s*(?:周|星期)\\s*'
      '(?:周|星期)?([一二三四五六日天1-7、,，和及]+)\\s*'
      '($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (match == null) return null;
    final interval = match.group(1) == null
        ? 1
        : _parsePositiveChineseAmount(match.group(1)!);
    final days = _parseChineseWeekdays(match.group(2)!);
    if (days.isEmpty) return null;
    final first = _firstWeekdayFrom(now, days);
    final time = _cleanPart(match.group(3));
    return _SmartRecurrenceParseResult(
      rule: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: interval,
        byWeekdays: days,
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([_chineseDatePhraseForWeekday(first, now), time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseChineseMonthlyRecurrence(
    String input,
    DateTime now,
  ) {
    final match = RegExp(
      '每\\s*($_numberTokenPattern)?\\s*(?:个)?月\\s*'
      '($_numberTokenPattern)\\s*(?:日|号)\\s*'
      '($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (match == null) return null;
    final interval = match.group(1) == null
        ? 1
        : _parsePositiveChineseAmount(match.group(1)!);
    final day = _parseChineseAmount(match.group(2)!);
    if (day < 1 || day > 31) return null;
    final time = _cleanPart(match.group(3));
    return _SmartRecurrenceParseResult(
      rule: RecurrenceRule(
        frequency: RecurrenceFrequency.monthly,
        interval: interval,
        byMonthDay: day,
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([
        '${_nextMonthDateForDay(now, day, interval: interval).month}月$day日',
        time,
      ]),
    );
  }

  static _SmartRecurrenceParseResult? _parseChineseYearlyRecurrence(
    String input,
  ) {
    final match = RegExp(
      '每年\\s*($_numberTokenPattern)\\s*月\\s*'
      '($_numberTokenPattern)\\s*(?:日|号)\\s*'
      '($_chineseTimePattern)?\\s*(?:的)?',
    ).firstMatch(input);
    if (match == null) return null;
    final month = _parseChineseAmount(match.group(1)!);
    final day = _parseChineseAmount(match.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final time = _cleanPart(match.group(3));
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(frequency: RecurrenceFrequency.yearly),
      matchedText: match.group(0)!,
      dateInput: _joinParts(['$month月$day日', time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseEnglishDailyRecurrence(
    String input,
  ) {
    final intervalMatch = RegExp(
      r'\b(?:every\s+([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten)\s+days|every\s+other\s+day)\b(?:\s+(' +
          _englishTimePattern +
          r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (intervalMatch != null) {
      final interval = intervalMatch.group(1) == null
          ? 2
          : _parsePositiveEnglishAmount(intervalMatch.group(1)!);
      final time = _cleanPart(intervalMatch.group(2));
      return _SmartRecurrenceParseResult(
        rule: RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          interval: interval,
        ),
        matchedText: intervalMatch.group(0)!,
        dateInput: _joinParts(['today', time]),
      );
    }

    final match = RegExp(
      r'\b(?:every\s+day|daily)\b(?:\s+(' + _englishTimePattern + r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final time = _cleanPart(match.group(1));
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
      matchedText: match.group(0)!,
      dateInput: _joinParts(['today', time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseEnglishWorkdayRecurrence(
    String input,
    DateTime now,
  ) {
    final match = RegExp(
      r'\bevery\s+weekdays?\b(?:\s+(' + _englishTimePattern + r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final time = _cleanPart(match.group(1));
    final first = _firstWeekdayFrom(now, const [0, 1, 2, 3, 4]);
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: [0, 1, 2, 3, 4],
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([_englishDatePhraseForWeekday(first, now), time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseEnglishWeeklyRecurrence(
    String input,
    DateTime now,
  ) {
    final weekendMatch = RegExp(
      r'\bevery\s+(?:([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten)\s+weeks?\s+)?weekends?\b(?:\s+('
      '$_englishTimePattern'
      r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (weekendMatch != null) {
      final interval = weekendMatch.group(1) == null
          ? 1
          : _parsePositiveEnglishAmount(weekendMatch.group(1)!);
      final days = const [5, 6];
      final first = _firstWeekdayFrom(now, days);
      final time = _cleanPart(weekendMatch.group(2));
      return _SmartRecurrenceParseResult(
        rule: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: interval,
          byWeekdays: days,
        ),
        matchedText: weekendMatch.group(0)!,
        dateInput: _joinParts([_englishDatePhraseForWeekday(first, now), time]),
      );
    }

    final match = RegExp(
      r'\bevery\s+(?:([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten)\s+weeks?\s+(?:on\s+)?)?('
      '$_englishWeekdayPattern'
      r'(?:\s*(?:,|and)?\s*'
      '$_englishWeekdayPattern'
      r')*)\b(?:\s+('
      '$_englishTimePattern'
      r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final interval = match.group(1) == null
        ? 1
        : _parsePositiveEnglishAmount(match.group(1)!);
    final days = _parseEnglishWeekdays(match.group(2)!);
    if (days.isEmpty) return null;
    final time = _cleanPart(match.group(3));
    final first = _firstWeekdayFrom(now, days);
    return _SmartRecurrenceParseResult(
      rule: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: interval,
        byWeekdays: days,
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([_englishDatePhraseForWeekday(first, now), time]),
    );
  }

  static _SmartRecurrenceParseResult? _parseEnglishMonthlyRecurrence(
    String input,
    DateTime now,
  ) {
    final match = RegExp(
      r'\b(?:every\s+(?:([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten)\s+)?months?|monthly)\b\s*(?:on\s+(?:the\s+)?)?'
      r'([0-9]{1,2})(?:st|nd|rd|th)?\b(?:\s+('
      '$_englishTimePattern'
      r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final interval = match.group(1) == null
        ? 1
        : _parsePositiveEnglishAmount(match.group(1)!);
    final day = int.tryParse(match.group(2)!) ?? 0;
    if (day < 1 || day > 31) return null;
    final time = _cleanPart(match.group(3));
    return _SmartRecurrenceParseResult(
      rule: RecurrenceRule(
        frequency: RecurrenceFrequency.monthly,
        interval: interval,
        byMonthDay: day,
      ),
      matchedText: match.group(0)!,
      dateInput: _joinParts([
        '${_englishMonthName(_nextMonthDateForDay(now, day, interval: interval).month)} $day',
        time,
      ]),
    );
  }

  static _SmartRecurrenceParseResult? _parseEnglishYearlyRecurrence(
    String input,
  ) {
    final match = RegExp(
      r'\b(?:every\s+year|yearly)\b\s*(?:on\s+)?'
      r'(january|jan|february|feb|march|mar|april|apr|may|june|jun|'
      r'july|jul|august|aug|september|sep|sept|october|oct|november|nov|'
      r'december|dec)\s+([0-9]{1,2})(?:st|nd|rd|th)?\b(?:\s+('
      '$_englishTimePattern'
      r'))?',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final time = _cleanPart(match.group(3));
    return _SmartRecurrenceParseResult(
      rule: const RecurrenceRule(frequency: RecurrenceFrequency.yearly),
      matchedText: match.group(0)!,
      dateInput: _joinParts(['${match.group(1)} ${match.group(2)}', time]),
    );
  }

  static List<int> _parseChineseWeekdays(String value) {
    final days = <int>{};
    for (final rune in value.runes) {
      final day = switch (String.fromCharCode(rune)) {
        '一' || '1' => 0,
        '二' || '2' => 1,
        '三' || '3' => 2,
        '四' || '4' => 3,
        '五' || '5' => 4,
        '六' || '6' => 5,
        '日' || '天' || '7' => 6,
        _ => null,
      };
      if (day != null) days.add(day);
    }
    return days.toList()..sort();
  }

  static List<int> _parseEnglishWeekdays(String value) {
    final days = <int>{};
    for (final match in RegExp(
      _englishWeekdayPattern,
      caseSensitive: false,
    ).allMatches(value)) {
      final day = _englishWeekday(match.group(0)!);
      if (day != null) days.add(day);
    }
    return days.toList()..sort();
  }

  static int _firstWeekdayFrom(DateTime now, List<int> weekdays) {
    final todayIndex = now.weekday - 1;
    final sorted = [...weekdays]..sort();
    for (final day in sorted) {
      if (day >= todayIndex) return day;
    }
    return sorted.first;
  }

  static String _chineseDatePhraseForWeekday(int weekday, DateTime now) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final prefix = weekday >= now.weekday - 1 ? '本周' : '下周';
    return '$prefix${names[weekday]}';
  }

  static String _englishDatePhraseForWeekday(int weekday, DateTime now) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final name = names[weekday];
    return weekday == now.weekday - 1 ? 'this $name' : name;
  }

  static int? _englishWeekday(String value) {
    switch (value.toLowerCase()) {
      case 'mon':
      case 'monday':
        return 0;
      case 'tue':
      case 'tuesday':
        return 1;
      case 'wed':
      case 'wednesday':
        return 2;
      case 'thu':
      case 'thursday':
        return 3;
      case 'fri':
      case 'friday':
        return 4;
      case 'sat':
      case 'saturday':
        return 5;
      case 'sun':
      case 'sunday':
        return 6;
      default:
        return null;
    }
  }

  static String _englishMonthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  static DateTime _nextMonthDateForDay(
    DateTime now,
    int day, {
    int interval = 1,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final safeInterval = interval < 1 ? 1 : interval;
    for (var offset = 0; offset < 24; offset += safeInterval) {
      final monthIndex = now.month - 1 + offset;
      final year = now.year + monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      if (day > DateTime(year, month + 1, 0).day) continue;
      final candidate = DateTime(year, month, day);
      if (!candidate.isBefore(today)) return candidate;
    }
    return today;
  }

  static int _parseChineseAmount(String value) {
    final number = int.tryParse(value);
    if (number != null) return number;
    const digits = {
      '零': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!value.contains('十')) return digits[value] ?? 0;
    final parts = value.split('十');
    final tens = parts.first.isEmpty ? 1 : digits[parts.first] ?? 0;
    final ones = parts.length > 1 && parts[1].isNotEmpty
        ? digits[parts[1]] ?? 0
        : 0;
    return tens * 10 + ones;
  }

  static int _parsePositiveChineseAmount(String value) {
    final amount = _parseChineseAmount(value);
    return amount <= 0 ? 1 : amount;
  }

  static int _parsePositiveEnglishAmount(String value) {
    final number = int.tryParse(value);
    if (number != null) return number <= 0 ? 1 : number;
    const words = {
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
      'twenty': 20,
    };
    return words[value.toLowerCase()] ?? 1;
  }

  static String _joinParts(List<String?> parts) {
    return parts
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .join(' ');
  }

  static String? _cleanPart(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _SmartRecurrenceParseResult {
  final RecurrenceRule rule;
  final String matchedText;
  final String? dateInput;
  final List<String> extraMatchedTexts;

  const _SmartRecurrenceParseResult({
    this.rule = const RecurrenceRule(),
    this.matchedText = '',
    this.dateInput,
    this.extraMatchedTexts = const [],
  });

  bool get isActive => rule.isActive && matchedText.isNotEmpty;

  Iterable<String> get matchedTexts sync* {
    if (matchedText.trim().isNotEmpty) yield matchedText;
    for (final text in extraMatchedTexts) {
      if (text.trim().isNotEmpty) yield text;
    }
  }
}

class _SmartRecurrenceEnding {
  final DateTime? endDate;
  final int? maxOccurrences;
  final List<String> matchedTexts;

  const _SmartRecurrenceEnding({
    required this.endDate,
    required this.maxOccurrences,
    required this.matchedTexts,
  });

  bool get hasAny => endDate != null || maxOccurrences != null;
}

class _SmartRecurrenceEndDate {
  final DateTime endDate;
  final String matchedText;

  const _SmartRecurrenceEndDate({
    required this.endDate,
    required this.matchedText,
  });
}

const _numberTokenPattern = r'[0-9]{1,3}|[零一二两三四五六七八九十]{1,4}';
const _chineseTimePattern =
    r'(?:凌晨|早上|早晨|上午|中午|下午|晚上|晚)?\s*'
    r'(?:[0-9]{1,3}|[零一二两三四五六七八九十]{1,4})\s*'
    r'(?:点|:|：)\s*(?:[0-9]{1,3}|[零一二两三四五六七八九十]{1,4})?\s*'
    r'(?:分)?(?:半)?';
const _englishWeekdayPattern =
    r'(?:mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|'
    r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)';
const _englishTimePattern =
    r'(?:(?:at|by)\s*[0-9]{1,2}(?::[0-5][0-9])?\s*'
    r'(?:am|pm|a\.m\.|p\.m\.)?|'
    r'[0-9]{1,2}:[0-5][0-9]\s*(?:am|pm|a\.m\.|p\.m\.)?|'
    r'[0-9]{1,2}\s*(?:am|pm|a\.m\.|p\.m\.))';
