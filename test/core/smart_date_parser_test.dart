import 'package:test/test.dart';

import 'package:duoyi/core/smart_date_parser.dart';

void main() {
  // 固定 now = 2026-05-15（星期五）便于断言。
  final now = DateTime(2026, 5, 15, 10, 0);

  group('SmartDateParser 基础日期', () {
    test('昨天保留过去日期，不降级为今天的时间', () {
      final day = SmartDateParser.parse('昨天整理资料', now: now);
      expect(day.dateTime, DateTime(2026, 5, 14));
      expect(day.hasTimeOfDay, isFalse);
      final timed = SmartDateParser.parse('昨天下午3点会议', now: now);
      expect(timed.dateTime, DateTime(2026, 5, 14, 15));
      expect(timed.matchedText, '昨天下午3点');
    });

    test('明天', () {
      final r = SmartDateParser.parse('明天', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.year, 2026);
      expect(r.dateTime!.month, 5);
      expect(r.dateTime!.day, 16);
      expect(r.hasTimeOfDay, isFalse);
    });

    test('后天', () {
      final r = SmartDateParser.parse('后天', now: now);
      expect(r.dateTime!.day, 17);
    });

    test('大后天', () {
      final r = SmartDateParser.parse('大后天', now: now);
      expect(r.dateTime!.day, 18);
    });

    test('三天后', () {
      final r = SmartDateParser.parse('三天后', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 18));
      expect(r.hasTimeOfDay, isFalse);
      expect(r.matchedText, '三天后');
    });

    test('两周后', () {
      final r = SmartDateParser.parse('两周后', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 29));
    });

    test('下周一', () {
      // 2026-05-15 是周五；下周一是 2026-05-18
      final r = SmartDateParser.parse('下周一', now: now);
      expect(r.dateTime!.day, 18);
    });

    test('本周三', () {
      // 2026-05-15 周五；本周三是 5-13（已过），按当前算法返回过往的"本周三"是
      // 不合理的，但解析器按字面计算 → 返回过去的日期。这里只验证落点。
      final r = SmartDateParser.parse('本周三', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.weekday, DateTime.wednesday);
    });
  });

  group('SmartDateParser 时间', () {
    test('明天下午3点', () {
      final r = SmartDateParser.parse('明天下午3点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.day, 16);
      expect(r.dateTime!.hour, 15);
      expect(r.dateTime!.minute, 0);
      expect(r.hasTimeOfDay, isTrue);
    });

    test('明天下午三点半', () {
      final r = SmartDateParser.parse('明天下午三点半', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 16, 15, 30));
      expect(r.matchedText, '明天下午三点半');
    });

    test('今晚8点', () {
      final r = SmartDateParser.parse('今天晚上8点', now: now);
      expect(r.dateTime!.day, 15);
      expect(r.dateTime!.hour, 20);
    });

    test('今晚八点', () {
      final r = SmartDateParser.parse('今晚八点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 15, 20));
      expect(r.matchedText, '今晚八点');
    });

    test('明早9点', () {
      final r = SmartDateParser.parse('明早9点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 16, 9));
      expect(r.matchedText, '明早9点');
    });

    test('后天上午9点半', () {
      final r = SmartDateParser.parse('后天上午9点半', now: now);
      expect(r.dateTime!.day, 17);
      expect(r.dateTime!.hour, 9);
      expect(r.dateTime!.minute, 30);
    });

    test('三天后下午3点', () {
      final r = SmartDateParser.parse('三天后下午3点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 18, 15));
      expect(r.hasTimeOfDay, isTrue);
      expect(r.matchedText, '三天后下午3点');
    });

    test('2周后上午9点', () {
      final r = SmartDateParser.parse('2周后上午9点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 29, 9));
    });

    test('下午3点30分', () {
      final r = SmartDateParser.parse('下午3点30分', now: now);
      expect(r.dateTime!.day, 15);
      expect(r.dateTime!.hour, 15);
      expect(r.dateTime!.minute, 30);
    });

    test('14:30 时间格式', () {
      final r = SmartDateParser.parse('14:30', now: now);
      expect(r.dateTime!.hour, 14);
      expect(r.dateTime!.minute, 30);
    });

    test('5月20日下午三点', () {
      final r = SmartDateParser.parse('5月20日下午三点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 20, 15));
      expect(r.hasTimeOfDay, isTrue);
      expect(r.matchedText, '5月20日下午三点');
    });

    test('没有年份的已过日期滚到下一年', () {
      final r = SmartDateParser.parse('5月1日', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2027, 5, 1));
      expect(r.hasTimeOfDay, isFalse);
    });

    test('显式年份日期', () {
      final r = SmartDateParser.parse('2027年1月1日9点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2027, 1, 1, 9));
    });

    test('中文数字绝对日期', () {
      final r = SmartDateParser.parse('六月一号上午十点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 6, 1, 10));
    });

    test('闰日会选择下一次合法日期', () {
      final r = SmartDateParser.parse('2月29日', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2028, 2, 29));
    });

    test('周末下午解析为本周或下个周六', () {
      final r = SmartDateParser.parse('周末下午4点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 16, 16));
      expect(r.matchedText, '周末下午4点');

      final sunday = SmartDateParser.parse(
        '周末下午4点',
        now: DateTime(2026, 5, 17, 10),
      );
      expect(sunday.dateTime, DateTime(2026, 5, 23, 16));
    });

    test('下周末和下下周末解析为对应周六', () {
      expect(
        SmartDateParser.parse('下周末上午10点', now: now).dateTime,
        DateTime(2026, 5, 23, 10),
      );
      expect(
        SmartDateParser.parse('下下周末上午10点', now: now).dateTime,
        DateTime(2026, 5, 30, 10),
      );
    });

    test('月初、月底和下个月具体日期', () {
      expect(
        SmartDateParser.parse('月底对账', now: now).dateTime,
        DateTime(2026, 5, 31),
      );
      expect(
        SmartDateParser.parse('月初复盘', now: now).dateTime,
        DateTime(2026, 6, 1),
      );
      expect(
        SmartDateParser.parse('下个月5号下午2点', now: now).dateTime,
        DateTime(2026, 6, 5, 14),
      );
    });
  });

  group('SmartDateParser English phrases', () {
    test('tomorrow at 3pm', () {
      final r = SmartDateParser.parse('tomorrow at 3pm', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 16, 15));
      expect(r.hasTimeOfDay, isTrue);
      expect(r.matchedText, 'tomorrow at 3pm');
    });

    test('next Monday 9:30am', () {
      final r = SmartDateParser.parse('next Monday 9:30am', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 18, 9, 30));
      expect(r.matchedText, 'next Monday 9:30am');
    });

    test('in 3 days at 2pm', () {
      final r = SmartDateParser.parse('in 3 days at 2pm', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 18, 14));
      expect(r.matchedText, 'in 3 days at 2pm');
    });

    test('May 20 at 3pm', () {
      final r = SmartDateParser.parse('May 20 at 3pm', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 20, 15));
      expect(r.matchedText, 'May 20 at 3pm');
    });

    test('past English month-day rolls to next year', () {
      final r = SmartDateParser.parse('May 1', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2027, 5, 1));
      expect(r.hasTimeOfDay, isFalse);
    });

    test('tonight 8 infers evening', () {
      final r = SmartDateParser.parse('tonight 8', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime, DateTime(2026, 5, 15, 20));
    });
  });

  group('SmartDateParser 失败回退', () {
    test('空字符串', () {
      expect(SmartDateParser.parse('').isSuccess, isFalse);
    });

    test('无法识别', () {
      expect(SmartDateParser.parse('完全没有日期信息的句子').isSuccess, isFalse);
    });

    test('非法小时', () {
      expect(SmartDateParser.parse('明天99点').isSuccess, isFalse);
    });

    test('相对日期非法小时', () {
      expect(SmartDateParser.parse('三天后99点').isSuccess, isFalse);
    });

    test('非法绝对日期', () {
      expect(SmartDateParser.parse('2月30日').isSuccess, isFalse);
    });

    test('invalid English time does not fall back to date-only', () {
      expect(SmartDateParser.parse('tomorrow 99pm').isSuccess, isFalse);
    });
  });
}
