import 'dart:io';

import 'package:duoyi/core/ai_command.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:test/test.dart';

void main() {
  test('AiCommandParser supports bounded conversational actions', () {
    final source = File('lib/core/ai_command.dart').readAsStringSync();

    expect(source, contains('enum AiCommandType'));
    expect(source, contains('addTodo'));
    expect(source, contains('addNote'));
    expect(source, isNot(contains('addDiary')));
    expect(source, contains('startFocus'));
    expect(source, contains('unknown'));

    expect(source, contains('class AiCommandBatch'));
    expect(source, contains('static AiCommandBatch parseBatch'));
    expect(source, contains(r"(?:\r?\n)+|[;；]+"));
    expect(source, contains('class AiCommandParser'));
    expect(source, contains('添加待办'));
    expect(source, contains('创建待办'));
    expect(source, contains('提醒我'));
    expect(source, contains('记笔记'));
    expect(source, isNot(contains('DiaryEntry(')));
    expect(source, contains(r'^(开始|启动|进入).*(专注|番茄)'));
  });

  test('AiCommandParser builds executable payloads and previews', () {
    final source = File('lib/core/ai_command.dart').readAsStringSync();

    expect(source, contains('SmartTodoDraftBuilder.fromText(todoPayload'));
    expect(source, contains('NoteItem('));
    expect(source, isNot(contains('DiaryEntry(')));

    expect(source, contains('创建待办'));
    expect(source, contains('保存为随手记'));
    expect(source, isNot(contains('写入今天的日记')));
    expect(source, contains('开始当前番茄钟专注计时'));
    expect(source, contains("I18n.tr('ai.command.help')"));
  });

  test(
    'AiCommandParser parses multiple commands split by lines or semicolons',
    () {
      final batch = AiCommandParser.parseBatch(
        '添加待办 每周末上午10点陪家人；记笔记 项目想法\n开始专注',
        now: DateTime(2026, 5, 15, 10),
      );

      expect(batch.executable, isTrue);
      expect(batch.commands, hasLength(3));
      expect(batch.commands[0].type, AiCommandType.addTodo);
      expect(batch.commands[0].todoDraft?.title, '陪家人');
      expect(batch.commands[0].todoDraft?.date, DateTime(2026, 5, 16, 10));
      expect(batch.commands[0].todoDraft?.recurrence.byWeekdays, [5, 6]);
      expect(
        batch.commands[0].todoDraft?.recurrence.frequency,
        RecurrenceFrequency.weekly,
      );
      expect(batch.commands[1].type, AiCommandType.addNote);
      expect(batch.commands[1].payload, '项目想法');
      expect(batch.commands[2].type, AiCommandType.startFocus);
      expect(batch.preview, contains('将执行 3 条指令'));
    },
  );

  test('retired commands never create records or fall through to todos', () {
    for (final input in [
      '写日记 今天很开心',
      '今天日记',
      '记录日记 回顾',
      'diary hello',
      'write journal hello',
    ]) {
      final command = AiCommandParser.parse(input);
      expect(command.type, AiCommandType.unknown, reason: input);
      expect(command.executable, isFalse);
      expect(command.note, isNull);
      expect(command.todoDraft, isNull);
    }
    expect(AiCommandParser.parseBatch('记笔记 保留随手记；写日记 旧动作').executable, isFalse);
    final note = AiCommandParser.parse('记笔记 项目想法');
    expect(note.type, AiCommandType.addNote);
    expect(note.note?.content, '项目想法');
  });
}
