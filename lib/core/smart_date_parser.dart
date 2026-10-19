/// 中文自然语言日期/时间解析（Task T-39）。
///
/// 解析常见中文日期表达，例如：
/// - "明天下午3点" → 明天 15:00
/// - "下周一上午10点" → 下周一 10:00
/// - "三天后下午3点" → 三天后 15:00
/// - "5月20日下午三点" → 今年或下一年 5 月 20 日 15:00
/// - "今晚八点" → 今天 20:00
/// - "后天" → 后天日期（无时间）
/// - "今晚8点" → 今天 20:00
/// - "tomorrow at 3pm" → tomorrow 15:00
/// - "next Monday 9:30am" → next Monday 09:30
///
/// 设计目标：
/// - 纯 Dart，便于单元测试，不依赖平台。
/// - 失败时返回 [SmartDateParseResult.empty]，调用方决定降级行为。
/// - 仅做"足够好"的启发式匹配；复杂场景建议手动选择日期。
library;

import 'app_clock.dart';

class SmartDateParseResult {
  /// 解析得到的日期；时间未指定时为 null。
  final DateTime? dateTime;

  /// 解析时使用的原文片段（用于从输入中剥离）。
  final String matchedText;

  /// 是否同时解析出了小时与分钟。
  final bool hasTimeOfDay;

  const SmartDateParseResult({
    required this.dateTime,
    required this.matchedText,
    required this.hasTimeOfDay,
  });

  static const empty = SmartDateParseResult(
    dateTime: null,
    matchedText: '',
    hasTimeOfDay: false,
  );

  bool get isSuccess => dateTime != null;

  String get strippedFrom => matchedText;
}

class SmartDateParser {
  SmartDateParser._();

  static const _numberTokenPattern = r'[0-9]{1,3}|[零一二两三四五六七八九十]{1,4}';

  /// 解析 [input] 中的中文日期/时间表达。
  static SmartDateParseResult parse(String input, {DateTime? now}) {
    if (input.trim().isEmpty) return SmartDateParseResult.empty;
    final base = now == null ? AppClock.now() : AppClock.toLocal(now);
    final today = DateTime(base.year, base.month, base.day);

    final relative = _relativeDate(input, today);
    if (relative.isSuccess) return relative;

    final englishRelative = _englishRelativeDate(input, today);
    if (englishRelative.isSuccess) return englishRelative;

    final compact = _compactDayPeriodWithTime(input, today);
    if (compact.isSuccess) return compact;

    final colloquial = _colloquialDate(input, today);
    if (colloquial.isSuccess) return colloquial;

    final absolute = _absoluteDate(input, today);
    if (absolute.isSuccess) return absolute;

    final englishAbsolute = _englishAbsoluteDate(input, today);
    if (englishAbsolute.isSuccess) return englishAbsolute;

    final englishDateWithTime = _englishDateWithTime(input, today);
    if (englishDateWithTime.isSuccess) return englishDateWithTime;

    final m1 = _dateWithTime(input, today);
    if (m1.isSuccess) return m1;

    final englishTime = _englishTimePart(input, today);
    if (englishTime.isSuccess) return englishTime;

    final m3 = _timePart(input, today);
    if (m3.isSuccess) return m3;

    // 如果输入包含明显的时间标记但解析失败 → 直接返回失败，
    // 避免将"明天99点"误判为只取"明天"。
    if (_containsTimeMarker(input)) return SmartDateParseResult.empty;

    final m2 = _datePart(input, today);
    if (m2.isSuccess) return m2;

    final englishDate = _englishDatePart(input, today);
    if (englishDate.isSuccess) return englishDate;
    return SmartDateParseResult.empty;
  }

  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static SmartDateParseResult _relativeDate(String input, DateTime today) {
    final relativePattern = RegExp(
      r'([0-9]{1,3}|[零一二两三四五六七八九十]{1,4})\s*'
      r'(天|日|周|星期|个月|月)\s*(后|以后|之后)',
    );
    final relativeMatch = relativePattern.firstMatch(input);
    if (relativeMatch == null) return SmartDateParseResult.empty;

    final amount = _parseAmount(relativeMatch.group(1)!);
    if (amount <= 0) return SmartDateParseResult.empty;
    final unit = relativeMatch.group(2)!;
    final dateBase = switch (unit) {
      '天' || '日' => _addDays(today, amount),
      '周' || '星期' => _addDays(today, amount * 7),
      '个月' || '月' => _addMonthsClamped(today, amount),
      _ => today,
    };

    final afterRelative = input.substring(relativeMatch.end);
    final time = _timePart(afterRelative, dateBase);
    if (time.isSuccess) {
      return SmartDateParseResult(
        dateTime: time.dateTime,
        matchedText: input.substring(
          relativeMatch.start,
          relativeMatch.end + time.matchedText.length,
        ),
        hasTimeOfDay: true,
      );
    }

    if (_containsTimeMarker(afterRelative)) {
      return SmartDateParseResult.empty;
    }

    return SmartDateParseResult(
      dateTime: dateBase,
      matchedText: relativeMatch.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _compactDayPeriodWithTime(
    String input,
    DateTime today,
  ) {
    final pattern = RegExp(
      '(今早|今晚|今中午|明早|明晚|明中午)\\s*'
      '($_numberTokenPattern)\\s*(?:点|:|：)\\s*'
      '($_numberTokenPattern)?\\s*(?:分)?(半)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final word = match.group(1)!;
    final dateBase = word.startsWith('明') ? _addDays(today, 1) : today;
    final periodWord = word.endsWith('早')
        ? '早上'
        : word.endsWith('晚')
        ? '晚上'
        : '中午';
    final dt = _buildDateTime(
      dateBase,
      periodWord,
      match.group(2)!,
      match.group(3),
      match.group(4),
    );
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static SmartDateParseResult _absoluteDate(String input, DateTime today) {
    final pattern = RegExp(
      '(?:([0-9]{2,4})\\s*年\\s*)?'
      '($_numberTokenPattern)\\s*月\\s*'
      '($_numberTokenPattern)\\s*(?:日|号)',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final yearToken = match.group(1);
    final month = _parseAmount(match.group(2)!);
    final day = _parseAmount(match.group(3)!);
    final dateBase = yearToken == null
        ? _nextMonthDay(today, month, day)
        : _validDate(_normalizeYear(yearToken), month, day);
    if (dateBase == null) return SmartDateParseResult.empty;

    final afterDate = input.substring(match.end);
    final time = _timePart(afterDate, dateBase);
    if (time.isSuccess) {
      return SmartDateParseResult(
        dateTime: time.dateTime,
        matchedText: input.substring(
          match.start,
          match.end + time.matchedText.length,
        ),
        hasTimeOfDay: true,
      );
    }

    if (_containsTimeMarker(afterDate)) return SmartDateParseResult.empty;

    return SmartDateParseResult(
      dateTime: dateBase,
      matchedText: match.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _colloquialDate(String input, DateTime today) {
    final patterns = <RegExp>[
      RegExp(r'(下下周末|下周末|本周末|这周末|周末)'),
      RegExp(r'(下个月|下月|本月|这个月|这月)?\s*月(初|末|底)'),
      RegExp(
        '(下个月|下月|本月|这个月|这月)\\s*'
        '($_numberTokenPattern)\\s*(?:日|号)',
      ),
    ];

    RegExpMatch? bestMatch;
    DateTime? dateBase;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match == null) continue;
      final candidate = _resolveColloquialDate(match, today);
      if (candidate == null) continue;
      if (bestMatch == null || match.start < bestMatch.start) {
        bestMatch = match;
        dateBase = candidate;
      }
    }
    if (bestMatch == null || dateBase == null) {
      return SmartDateParseResult.empty;
    }

    final afterDate = input.substring(bestMatch.end);
    final time = _timePart(afterDate, dateBase);
    if (time.isSuccess) {
      return SmartDateParseResult(
        dateTime: time.dateTime,
        matchedText: input.substring(
          bestMatch.start,
          bestMatch.end + time.matchedText.length,
        ),
        hasTimeOfDay: true,
      );
    }
    if (_containsTimeMarker(afterDate)) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dateBase,
      matchedText: bestMatch.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static DateTime? _resolveColloquialDate(RegExpMatch match, DateTime today) {
    final text = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
    if (text.contains('周末')) {
      final weeks = text.startsWith('下下')
          ? 2
          : text.startsWith('下')
          ? 1
          : 0;
      return _weekendSaturday(today, weeksFromThisWeek: weeks);
    }

    if (text.contains('月初') || text.contains('月底') || text.contains('月末')) {
      final nextMonth = text.startsWith('下');
      final targetMonth = nextMonth ? _addMonthsClamped(today, 1) : today;
      if (text.contains('月初')) {
        final candidate = DateTime(targetMonth.year, targetMonth.month, 1);
        return candidate.isBefore(today)
            ? DateTime(today.year, today.month + 1, 1)
            : candidate;
      }
      return DateTime(targetMonth.year, targetMonth.month + 1, 0);
    }

    if (text.startsWith('下月') || text.startsWith('下个月')) {
      final dayToken = match.group(2);
      if (dayToken == null) return null;
      final next = _addMonthsClamped(today, 1);
      return _validDate(next.year, next.month, _parseAmount(dayToken));
    }
    if (text.startsWith('本月') ||
        text.startsWith('这个月') ||
        text.startsWith('这月')) {
      final dayToken = match.group(2);
      if (dayToken == null) return null;
      final day = _parseAmount(dayToken);
      final candidate = _validDate(today.year, today.month, day);
      if (candidate == null) return null;
      return candidate.isBefore(today)
          ? _validDate(today.year, today.month + 1, day)
          : candidate;
    }
    return null;
  }

  static DateTime _weekendSaturday(
    DateTime today, {
    required int weeksFromThisWeek,
  }) {
    final currentWeekSaturday = _addDays(
      today,
      DateTime.saturday - today.weekday,
    );
    var candidate = _addDays(currentWeekSaturday, weeksFromThisWeek * 7);
    if (weeksFromThisWeek == 0 && candidate.isBefore(today)) {
      candidate = _addDays(candidate, 7);
    }
    return DateTime(candidate.year, candidate.month, candidate.day);
  }

  static SmartDateParseResult _englishRelativeDate(
    String input,
    DateTime today,
  ) {
    final relativePattern = RegExp(
      r'\bin\s+'
      r'([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten|'
      r'eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|'
      r'nineteen|twenty)\s+'
      r'(day|days|week|weeks|month|months)'
      r'(?:\s+(?:from\s+now|later))?\b',
      caseSensitive: false,
    );
    final relativeMatch = relativePattern.firstMatch(input);
    if (relativeMatch == null) return SmartDateParseResult.empty;

    final amount = _parseEnglishAmount(relativeMatch.group(1)!);
    if (amount <= 0) return SmartDateParseResult.empty;
    final unit = relativeMatch.group(2)!.toLowerCase();
    final dateBase = switch (unit) {
      'day' || 'days' => _addDays(today, amount),
      'week' || 'weeks' => _addDays(today, amount * 7),
      'month' || 'months' => _addMonthsClamped(today, amount),
      _ => today,
    };

    final afterRelative = input.substring(relativeMatch.end);
    final time = _englishTimePart(afterRelative, dateBase);
    if (time.isSuccess) {
      return SmartDateParseResult(
        dateTime: time.dateTime,
        matchedText: input.substring(
          relativeMatch.start,
          relativeMatch.end + time.matchedText.length,
        ),
        hasTimeOfDay: true,
      );
    }

    if (_containsTimeMarker(afterRelative)) return SmartDateParseResult.empty;

    return SmartDateParseResult(
      dateTime: dateBase,
      matchedText: relativeMatch.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _englishAbsoluteDate(
    String input,
    DateTime today,
  ) {
    final pattern = RegExp(
      r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|'
      r'july|jul|august|aug|september|sep|sept|october|oct|november|nov|'
      r'december|dec)\s+'
      r'([0-9]{1,2})(?:st|nd|rd|th)?'
      r'(?:,?\s+([0-9]{2,4}))?\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final month = _englishMonth(match.group(1)!);
    final day = int.tryParse(match.group(2)!) ?? 0;
    final yearToken = match.group(3);
    final dateBase = yearToken == null
        ? _nextMonthDay(today, month, day)
        : _validDate(_normalizeYear(yearToken), month, day);
    if (dateBase == null) return SmartDateParseResult.empty;

    final afterDate = input.substring(match.end);
    final time = _englishTimePart(afterDate, dateBase);
    if (time.isSuccess) {
      return SmartDateParseResult(
        dateTime: time.dateTime,
        matchedText: input.substring(
          match.start,
          match.end + time.matchedText.length,
        ),
        hasTimeOfDay: true,
      );
    }

    if (_containsTimeMarker(afterDate)) return SmartDateParseResult.empty;

    return SmartDateParseResult(
      dateTime: dateBase,
      matchedText: match.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _englishDateWithTime(
    String input,
    DateTime today,
  ) {
    final pattern = RegExp(
      r'\b(today|tomorrow|tonight|'
      r'(?:this|next)\s+(?:mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|'
      r'thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)|'
      r'mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|'
      r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b'
      r'(?:\s+(morning|afternoon|evening|night))?'
      r'\s*(?:at|by)?\s*'
      r'([0-9]{1,3})(?::([0-5][0-9]))?\s*'
      r'(am|pm|a\.m\.|p\.m\.)?\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final phrase = match.group(1)!;
    final periodWord = match.group(2);
    final dateBase = _resolveEnglishDate(today, phrase);
    if (dateBase == null) return SmartDateParseResult.empty;
    final dt = _buildEnglishDateTime(
      dateBase,
      match.group(3)!,
      match.group(4),
      match.group(5),
      defaultPeriod: phrase.toLowerCase() == 'tonight' ? 'evening' : periodWord,
    );
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static SmartDateParseResult _englishDatePart(String input, DateTime today) {
    final pattern = RegExp(
      r'\b(today|tomorrow|tonight|'
      r'(?:this|next)\s+(?:mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|'
      r'thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)|'
      r'mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|'
      r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;
    final dt = _resolveEnglishDate(today, match.group(1)!);
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _englishTimePart(String input, DateTime today) {
    final pattern = RegExp(
      r'\s*(?:at|by)?\s*'
      r'([0-9]{1,3})(?::([0-5][0-9]))\s*'
      r'(am|pm|a\.m\.|p\.m\.)?\b'
      r'|\s*(?:at|by)\s*'
      r'([0-9]{1,3})\s*(am|pm|a\.m\.|p\.m\.)\b'
      r'|\s*([0-9]{1,3})\s*(am|pm|a\.m\.|p\.m\.)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final hourToken = match.group(1) ?? match.group(4) ?? match.group(6);
    final minuteToken = match.group(2);
    final meridiem = match.group(3) ?? match.group(5) ?? match.group(7);
    final dt = _buildEnglishDateTime(today, hourToken!, minuteToken, meridiem);
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static SmartDateParseResult _dateWithTime(String input, DateTime today) {
    // 支持 "下周一下午3点"、"本周三上午9点半" 等组合，weekWord 紧跟在 dayWord 之后
    // 形如 "下周一" 或独立的 "周一" 都允许。
    final pattern = RegExp(
      r'(今天|明天|后天|大后天|下下周|下周|本周)?\s*'
      r'(?:(周一|周二|周三|周四|周五|周六|周日|周天)|(一|二|三|四|五|六|日|天))?\s*'
      r'(凌晨|早上|早晨|上午|中午|下午|晚上|晚)?\s*'
      '($_numberTokenPattern)\\s*(?:点|:|：)\\s*'
      '($_numberTokenPattern)?\\s*(?:分)?(半)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final dayWord = match.group(1);
    final weekWordFull = match.group(2);
    final weekDigit = match.group(3);
    final weekWord = weekWordFull ?? (weekDigit != null ? '周$weekDigit' : null);
    final periodWord = match.group(4);
    final hourStr = match.group(5)!;
    final minuteStr = match.group(6);
    final halfMarker = match.group(7);

    if (dayWord == null && weekWord == null && periodWord == null) {
      // 仅日期 → 由 _timePart 处理
      return SmartDateParseResult.empty;
    }

    final dateBase = _resolveDate(today, dayWord, weekWord) ?? today;

    final dt = _buildDateTime(
      dateBase,
      periodWord,
      hourStr,
      minuteStr,
      halfMarker,
    );
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static SmartDateParseResult _datePart(String input, DateTime today) {
    // 1) "本周三" / "下周一" / "下下周日" — 周词在 dayWord 后紧跟一个数字字
    final combo = RegExp(r'(本周|下周|下下周)(一|二|三|四|五|六|日|天)').firstMatch(input);
    if (combo != null) {
      final dayWord = combo.group(1)!;
      final dayDigit = combo.group(2)!;
      final dt = _resolveDate(today, dayWord, '周$dayDigit');
      if (dt != null) {
        return SmartDateParseResult(
          dateTime: dt,
          matchedText: combo.group(0)!,
          hasTimeOfDay: false,
        );
      }
    }

    // 2) "下周" + " " + "周一" 这类显式格式 / 单独的"今天/明天/后天"等
    final pattern = RegExp(
      r'(今天|明天|后天|大后天|下下周|下周|本周)\s*(周一|周二|周三|周四|周五|周六|周日|周天)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;
    final dayWord = match.group(1);
    final weekWord = match.group(2);
    final dt = _resolveDate(today, dayWord, weekWord);
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _timePart(String input, DateTime today) {
    // 仅时间，无日期 → 今天
    final pattern = RegExp(
      r'(凌晨|早上|早晨|上午|中午|下午|晚上|晚)?\s*'
      '($_numberTokenPattern)\\s*(?:点|:|：)\\s*'
      '($_numberTokenPattern)?\\s*(?:分)?(半)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;
    final periodWord = match.group(1);
    final dt = _buildDateTime(
      today,
      periodWord,
      match.group(2)!,
      match.group(3),
      match.group(4),
    );
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static DateTime? _buildDateTime(
    DateTime dateBase,
    String? periodWord,
    String hourToken,
    String? minuteToken,
    String? halfMarker,
  ) {
    var hour = _parseAmount(hourToken);
    if (hour < 0 || hour > 23) return null;
    var minute = minuteToken == null || minuteToken.isEmpty
        ? 0
        : _parseAmount(minuteToken);
    if (halfMarker != null) minute = 30;
    if (minute < 0 || minute > 59) return null;

    if (periodWord != null) {
      if ((periodWord == '下午' || periodWord == '晚上' || periodWord == '晚') &&
          hour < 12) {
        hour += 12;
      } else if (periodWord == '中午' && hour >= 1 && hour <= 5) {
        hour += 12;
      } else if ((periodWord == '上午' ||
              periodWord == '早上' ||
              periodWord == '早晨' ||
              periodWord == '凌晨') &&
          hour == 12) {
        hour = 0;
      }
    }

    return AppClock.date(
      dateBase.year,
      dateBase.month,
      dateBase.day,
      hour,
      minute,
    );
  }

  static DateTime? _buildEnglishDateTime(
    DateTime dateBase,
    String hourToken,
    String? minuteToken,
    String? meridiem, {
    String? defaultPeriod,
  }) {
    var hour = int.tryParse(hourToken) ?? -1;
    final minute = minuteToken == null || minuteToken.isEmpty
        ? 0
        : int.tryParse(minuteToken) ?? -1;
    if (minute < 0 || minute > 59) return null;

    final normalizedMeridiem = (meridiem ?? '').toLowerCase().replaceAll(
      '.',
      '',
    );
    if (normalizedMeridiem == 'am' || normalizedMeridiem == 'pm') {
      if (hour < 1 || hour > 12) return null;
      if (normalizedMeridiem == 'pm' && hour != 12) hour += 12;
      if (normalizedMeridiem == 'am' && hour == 12) hour = 0;
    } else {
      if (hour < 0 || hour > 23) return null;
      final period = defaultPeriod?.toLowerCase();
      if ((period == 'afternoon' || period == 'evening' || period == 'night') &&
          hour >= 1 &&
          hour < 12) {
        hour += 12;
      } else if (period == 'morning' && hour == 12) {
        hour = 0;
      }
    }
    return AppClock.date(
      dateBase.year,
      dateBase.month,
      dateBase.day,
      hour,
      minute,
    );
  }

  /// 将日期词组合解析为具体 DateTime（无时间）。
  static DateTime? _resolveDate(
    DateTime today,
    String? dayWord,
    String? weekWord,
  ) {
    final weekdayMap = <String, int>{
      '周一': 1,
      '周二': 2,
      '周三': 3,
      '周四': 4,
      '周五': 5,
      '周六': 6,
      '周日': 7,
      '周天': 7,
    };

    if (weekWord != null) {
      final targetWeekday = weekdayMap[weekWord];
      if (targetWeekday == null) return null;
      final currentWeekday = today.weekday;
      // 本周一 = today + (target - current)，可能为过去日期
      // 下周一 = 下周一（=本周日 + 1） + (target - 1)
      // 下下周一 = 下下周一 + (target - 1)
      if (dayWord == '本周') {
        return _addDays(today, targetWeekday - currentWeekday);
      }
      if (dayWord == '下周') {
        // 下周一的偏移 = 8 - currentWeekday（本周日是 7-currentWeekday，再 +1）
        final mondayNextWeek = 8 - currentWeekday;
        return _addDays(today, mondayNextWeek + targetWeekday - 1);
      }
      if (dayWord == '下下周') {
        final mondayNextNextWeek = 8 - currentWeekday + 7;
        return _addDays(today, mondayNextNextWeek + targetWeekday - 1);
      }
      // 无 dayWord 前缀的孤立"周一" → 取最近的下一个周X
      var diff = targetWeekday - currentWeekday;
      if (diff <= 0) diff += 7;
      return _addDays(today, diff);
    }

    switch (dayWord) {
      case '今天':
        return today;
      case '明天':
        return _addDays(today, 1);
      case '后天':
        return _addDays(today, 2);
      case '大后天':
        return _addDays(today, 3);
      case '本周':
      case '下周':
        return _addDays(today, 8 - today.weekday);
      case '下下周':
        return _addDays(today, 15 - today.weekday);
    }
    return null;
  }

  static DateTime? _resolveEnglishDate(DateTime today, String phrase) {
    final normalized = phrase.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    switch (normalized) {
      case 'today':
      case 'tonight':
        return today;
      case 'tomorrow':
        return _addDays(today, 1);
    }

    final parts = normalized.split(' ');
    String? prefix;
    String weekdayText;
    if (parts.length == 2 && (parts.first == 'this' || parts.first == 'next')) {
      prefix = parts.first;
      weekdayText = parts.last;
    } else if (parts.length == 1) {
      weekdayText = parts.single;
    } else {
      return null;
    }

    final targetWeekday = _englishWeekday(weekdayText);
    if (targetWeekday == null) return null;
    final currentWeekday = today.weekday;
    if (prefix == 'this') {
      return _addDays(today, targetWeekday - currentWeekday);
    }
    if (prefix == 'next') {
      final mondayNextWeek = 8 - currentWeekday;
      return _addDays(today, mondayNextWeek + targetWeekday - 1);
    }
    var diff = targetWeekday - currentWeekday;
    if (diff <= 0) diff += 7;
    return _addDays(today, diff);
  }

  static int _parseAmount(String value) {
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

  static int _parseEnglishAmount(String value) {
    final number = int.tryParse(value);
    if (number != null) return number;
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
    return words[value.toLowerCase()] ?? 0;
  }

  static bool _containsTimeMarker(String input) {
    return RegExp('($_numberTokenPattern)\\s*(点|:|：)').hasMatch(input) ||
        RegExp(
          r'\b[0-9]{1,3}\s*(am|pm|a\.m\.|p\.m\.)\b',
          caseSensitive: false,
        ).hasMatch(input) ||
        RegExp(r'\b[0-9]{1,3}:[0-9]{2}\b').hasMatch(input);
  }

  static int? _englishWeekday(String value) {
    switch (value.toLowerCase()) {
      case 'mon':
      case 'monday':
        return DateTime.monday;
      case 'tue':
      case 'tuesday':
        return DateTime.tuesday;
      case 'wed':
      case 'wednesday':
        return DateTime.wednesday;
      case 'thu':
      case 'thursday':
        return DateTime.thursday;
      case 'fri':
      case 'friday':
        return DateTime.friday;
      case 'sat':
      case 'saturday':
        return DateTime.saturday;
      case 'sun':
      case 'sunday':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  static int _englishMonth(String value) {
    switch (value.toLowerCase()) {
      case 'january':
      case 'jan':
        return 1;
      case 'february':
      case 'feb':
        return 2;
      case 'march':
      case 'mar':
        return 3;
      case 'april':
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'june':
      case 'jun':
        return 6;
      case 'july':
      case 'jul':
        return 7;
      case 'august':
      case 'aug':
        return 8;
      case 'september':
      case 'sep':
      case 'sept':
        return 9;
      case 'october':
      case 'oct':
        return 10;
      case 'november':
      case 'nov':
        return 11;
      case 'december':
      case 'dec':
        return 12;
      default:
        return 0;
    }
  }

  static int _normalizeYear(String value) {
    final year = int.tryParse(value) ?? 0;
    if (year >= 100) return year;
    return 2000 + year;
  }

  static DateTime? _validDate(int year, int month, int day) {
    if (year <= 0 || month < 1 || month > 12 || day < 1) return null;
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }

  static DateTime? _nextMonthDay(DateTime today, int month, int day) {
    var year = today.year;
    for (var i = 0; i < 6; i++) {
      final candidate = _validDate(year + i, month, day);
      if (candidate != null && !candidate.isBefore(today)) return candidate;
    }
    return null;
  }

  static DateTime _addMonthsClamped(DateTime today, int months) {
    final targetMonthIndex = today.month - 1 + months;
    final targetYear = today.year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
    return DateTime(
      targetYear,
      targetMonth,
      today.day > lastDay ? lastDay : today.day,
    );
  }
}
