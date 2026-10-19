import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('quick capture templates are persisted and exposed from the FAB', () {
    final model = File(
      'lib/models/quick_capture_template.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();
    final fab = File('lib/widgets/quick_capture_fab.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final i18n = File('lib/core/i18n.dart').readAsStringSync();
    final zhArb = File('lib/l10n/app_zh.arb').readAsStringSync();
    final enArb = File('lib/l10n/app_en.arb').readAsStringSync();
    final generatedZh = File(
      'lib/l10n/generated/app_localizations_zh.dart',
    ).readAsStringSync();
    final generatedEn = File(
      'lib/l10n/generated/app_localizations_en.dart',
    ).readAsStringSync();
    final requirement = File('docs/requirement-v2.md').readAsStringSync();

    expect(model, contains('enum QuickCaptureTemplateKind'));
    expect(model, contains('static List<QuickCaptureTemplate> builtIns()'));
    expect(model, contains('TodoPriority priority'));
    expect(model, contains('String? listGroupName'));
    expect(model, contains('ReminderPlan reminderPlan'));
    expect(model, contains('Habit toHabit'));
    expect(model, contains('TodoItem toTodo'));

    expect(provider, contains('QuickCaptureTemplateProvider'));
    expect(provider, contains('duoyi_quick_capture_templates_v1'));
    expect(provider, contains('saveTemplate'));
    expect(provider, contains('deleteTemplate'));

    expect(main, contains('QuickCaptureTemplateProvider()'));
    expect(main, contains('quick capture templates storage'));
    expect(
      main,
      contains(
        'ChangeNotifierProvider.value(value: quickCaptureTemplateProvider)',
      ),
    );

    expect(fab, contains('quick.menu.template'));
    expect(fab, contains('_showTemplateSheet'));
    expect(fab, contains('_showSaveTemplateDialog'));
    expect(fab, contains('_applyTemplate'));
    expect(fab, contains('provider.saveTemplate'));
    expect(fab, contains('template.toTodo(input)'));
    expect(fab, contains('template.toHabit(input)'));
    expect(fab, contains('GestureDetector'));
    expect(
      fab,
      contains(
        'onLongPress: widget.label == null ? _showTemplateSheet : _toggle',
      ),
    );
    expect(fab, contains('onTap: _showTemplateSheet'));
    expect(fab, contains('triggerMode: TooltipTriggerMode.manual'));

    for (final key in const [
      'quick.menu.template',
      'quick.template.title',
      'quick.template.save',
      'quick.template.kind.todo',
      'quick.template.kind.habit',
      'quick.template.reminder15',
      'quick.template.todo_done',
      'quick.template.habit_done',
    ]) {
      expect(i18n, contains("'$key'"), reason: key);
    }
    for (final arbKey in const [
      'quickMenuTemplate',
      'quickTemplateTitle',
      'quickTemplateSave',
      'quickTemplateKindTodo',
      'quickTemplateKindHabit',
      'quickTemplateReminder15',
      'quickTemplateTodoDone',
      'quickTemplateHabitDone',
    ]) {
      expect(zhArb, contains('"$arbKey"'), reason: arbKey);
      expect(enArb, contains('"$arbKey"'), reason: arbKey);
      expect(generatedZh, contains('String get $arbKey'), reason: arbKey);
      expect(generatedEn, contains('String get $arbKey'), reason: arbKey);
    }

    expect(requirement, contains('R16.3 快捷模板功能'));
    expect(requirement, contains('模板包含标题前缀、默认标签、默认优先级、默认提醒规则'));
    expect(requirement, contains('**[已实现基础]**'));
  });
}
