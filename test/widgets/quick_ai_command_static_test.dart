import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('QuickCaptureFab exposes AI conversational commands', () {
    final fab = File('lib/widgets/quick_capture_fab.dart').readAsStringSync();
    final command = File('lib/core/ai_command.dart').readAsStringSync();

    expect(command, contains('enum AiCommandType'));
    expect(command, contains('AiCommandType.addTodo'));
    expect(command, contains('AiCommandType.addNote'));
    expect(command, isNot(contains('AiCommandType.addDiary')));
    expect(command, contains('AiCommandType.startFocus'));
    expect(command, contains('SmartTodoDraftBuilder.fromText'));
    expect(command, contains('class AiCommandBatch'));
    expect(command, contains('parseBatch'));

    expect(fab, contains("import '../core/ai_command.dart';"));
    expect(fab, contains('Future<void> _quickAiCommand()'));
    expect(fab, contains('AiCommandParser.parseBatch(value)'));
    expect(fab, contains('Future<void> _executeAiCommands'));
    expect(fab, contains('已执行 \${commands.length} 条 AI 指令'));
    expect(fab, contains('Future<_AiCommandOutcome> _executeAiCommand('));
    expect(fab, contains('class _AiCommandOutcome'));
    expect(fab, contains('const _AiCommandOutcome.skipped()'));
    expect(fab, contains('AiCommand command,'));
    expect(fab, contains('bool showSnackBar = true'));
    expect(fab, contains('context.read<TodoProvider>().addTodo'));
    expect(fab, contains('context.read<NoteProvider>().addOrUpdateNote'));
    expect(fab, isNot(contains('DiaryProvider')));
    expect(fab, isNot(contains('_quickDiary')));
    expect(fab, isNot(contains('quick.menu.diary')));
    expect(fab, contains('context.read<PomodoroProvider>()'));
    expect(fab, contains("label: 'AI 指令'"));
  });
}
