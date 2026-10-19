import 'i18n.dart';
import '../models/note.dart';
import 'smart_todo_draft.dart';

enum AiCommandType { addTodo, addNote, startFocus, unknown }

class AiCommandBatch {
  final String rawText;
  final List<AiCommand> commands;

  const AiCommandBatch({required this.rawText, required this.commands});

  bool get executable =>
      commands.isNotEmpty && commands.every((command) => command.executable);

  String get preview {
    if (commands.isEmpty) {
      return I18n.tr('ai.command.help');
    }
    if (commands.length == 1) return commands.single.preview;
    final lines = <String>['将执行 ${commands.length} 条指令：'];
    for (var i = 0; i < commands.length; i++) {
      lines.add('${i + 1}. ${commands[i].preview}');
    }
    return lines.join('\n');
  }
}

class AiCommand {
  final AiCommandType type;
  final String rawText;
  final String payload;
  final SmartTodoDraft? todoDraft;
  final NoteItem? note;

  const AiCommand({
    required this.type,
    required this.rawText,
    required this.payload,
    this.todoDraft,
    this.note,
  });

  bool get executable => type != AiCommandType.unknown;

  String get title => switch (type) {
    AiCommandType.addTodo => '创建待办',
    AiCommandType.addNote => '保存笔记',
    AiCommandType.startFocus => '开始专注',
    AiCommandType.unknown => '无法识别',
  };

  String get preview {
    final todo = todoDraft;
    if (type == AiCommandType.addTodo && todo != null) {
      final date =
          '${todo.date.year}-${todo.date.month.toString().padLeft(2, '0')}-${todo.date.day.toString().padLeft(2, '0')}';
      final reminder = todo.hasReminder
          ? '，提醒 ${todo.date.hour.toString().padLeft(2, '0')}:${todo.date.minute.toString().padLeft(2, '0')}'
          : '';
      return '创建待办「${todo.title}」，日期 $date$reminder';
    }
    if (type == AiCommandType.addNote) return '保存为随手记：$payload';
    if (type == AiCommandType.startFocus) return '开始当前番茄钟专注计时';
    return I18n.tr('ai.command.help');
  }
}

class AiCommandParser {
  const AiCommandParser._();

  static AiCommandBatch parseBatch(String input, {DateTime? now}) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const AiCommandBatch(rawText: '', commands: []);
    }
    final parts = raw
        .split(RegExp(r'(?:\r?\n)+|[;；]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final commands = parts.isEmpty
        ? <AiCommand>[]
        : [for (final part in parts) parse(part, now: now)];
    return AiCommandBatch(rawText: raw, commands: commands);
  }

  static AiCommand parse(String input, {DateTime? now}) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const AiCommand(
        type: AiCommandType.unknown,
        rawText: '',
        payload: '',
      );
    }
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    final startFocus = RegExp(r'^(开始|启动|进入).*(专注|番茄)').hasMatch(normalized);
    if (startFocus) {
      return AiCommand(
        type: AiCommandType.startFocus,
        rawText: raw,
        payload: normalized,
      );
    }

    final notePayload = _stripPrefix(normalized, const [
      '记笔记',
      '记录笔记',
      '保存笔记',
      '写笔记',
      '记一下',
    ]);
    if (notePayload != null) {
      final at = now ?? DateTime.now();
      return AiCommand(
        type: AiCommandType.addNote,
        rawText: raw,
        payload: notePayload,
        note: NoteItem(
          id: at.microsecondsSinceEpoch.toString(),
          content: notePayload,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }

    if (RegExp(
      r'^(?:(?:写|记录|今天|新增|创建|添加)\s*)?日记|^(?:(?:write|create|add)\s+)?(?:diary|journal)\b',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return AiCommand(type: AiCommandType.unknown, rawText: raw, payload: '');
    }

    final todoPayload =
        _stripPrefix(normalized, const [
          '添加待办',
          '创建待办',
          '新增待办',
          '加待办',
          '提醒我',
          '安排',
        ]) ??
        normalized;
    final draft = SmartTodoDraftBuilder.fromText(todoPayload, now: now);
    return AiCommand(
      type: AiCommandType.addTodo,
      rawText: raw,
      payload: todoPayload,
      todoDraft: draft,
    );
  }

  static String? _stripPrefix(String input, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (!input.startsWith(prefix)) continue;
      final payload = input.substring(prefix.length).trim();
      return payload.isEmpty ? null : payload;
    }
    return null;
  }
}
