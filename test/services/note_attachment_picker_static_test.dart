import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('随手记接入系统文件选择器和图片内嵌预览', () {
    final screen = File('lib/screens/note_screen.dart').readAsStringSync();
    final picker = File(
      'lib/services/note_attachment_picker.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(screen, contains('NoteAttachmentPicker.pickFile'));
    expect(screen, contains("I18n.tr('note.attachment.pick_file')"));
    expect(screen, contains("I18n.tr('note.attachment.add_link')"));
    expect(screen, contains('_PreviewImageAttachment'));
    expect(screen, contains('_NoteEditorPane'));
    expect(screen, contains('_MarkdownEditingController'));
    expect(screen, contains('TextSpan buildTextSpan'));
    expect(screen, contains('_parseMarkdownLine'));
    expect(screen, contains('_parseInlineForEditor'));
    expect(screen, contains('ValueListenableBuilder<TextEditingValue>'));
    expect(screen, contains('blocks: NoteBlock.fromMarkdown(text)'));
    expect(screen, contains('blocks: NoteBlock.fromMarkdown(_ctrl.text)'));
    expect(screen, contains('blocks: NoteBlock.fromMarkdown(value.text)'));
    expect(screen, contains('_PreviewBlock'));
    expect(screen, contains('block.type == NoteBlockType.heading'));
    expect(screen, contains('block.type == NoteBlockType.checklist'));
    expect(screen, contains('block.type == NoteBlockType.divider'));
    expect(screen, contains('_InlineMarkdownText'));
    expect(screen, contains('TextDecoration.lineThrough'));
    expect(screen, contains('FontStyle.italic'));
    expect(screen, contains('fontFamily: DesignTokens.fontFamily'));
    expect(screen, contains('Icons.format_italic'));
    expect(screen, contains('Icons.format_quote'));
    expect(screen, contains('Icons.format_list_bulleted'));
    expect(screen, contains('Icons.code'));
    expect(screen, contains('Icons.link'));
    expect(screen, contains('Image.network'));
    expect(screen, contains('Image.file'));
    expect(picker, contains("package:file_selector/file_selector.dart"));
    expect(picker, contains('openFile()'));
    expect(picker, contains('_pickPortableFile'));
    expect(picker, contains('if (!_isAndroid) return _pickPortableFile();'));
    expect(picker, contains('MethodChannel'));
    expect(picker, contains("'duoyi/note_attachment_picker'"));
    expect(mainActivity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(mainActivity, contains('Intent.CATEGORY_OPENABLE'));
    expect(mainActivity, contains('takePersistableUriPermission'));
    expect(mainActivity, contains('OpenableColumns.DISPLAY_NAME'));
  });

  test('非 Android 平台通过 file_selector 选择附件，覆盖 iOS 工程路径', () {
    final picker = File(
      'lib/services/note_attachment_picker.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(pubspec, contains('file_selector:'));
    expect(iosProject, contains('PRODUCT_BUNDLE_IDENTIFIER = com.duoyi.duoyi'));
    expect(picker, contains('if (kIsWeb) return null;'));
    expect(picker, contains('final file = await openFile();'));
    expect(picker, contains('file.path.trim()'));
    expect(picker, contains('file.name.trim()'));
    expect(picker, contains('file.mimeType ??'));
    expect(
      picker,
      isNot(contains('Platform.isIOS ? null')),
      reason:
          'iOS must use the portable file_selector path, not a disabled stub.',
    );
  });

  test('随手记模型提供兼容 Markdown 的块级富文本结构', () {
    final model = File('lib/models/note.dart').readAsStringSync();

    expect(model, contains('enum NoteBlockType'));
    expect(model, contains('class NoteBlock'));
    expect(model, contains('final List<NoteBlock> blocks'));
    expect(model, contains('NoteBlock.fromMarkdown(content)'));
    expect(model, contains("'blocks': blocks.map((e) => e.toJson()).toList()"));
    expect(model, contains('NoteBlock.fromJson'));
    expect(model, contains('toMarkdownLine'));
    expect(model, contains('NoteBlockType.heading'));
    expect(model, contains('NoteBlockType.quote'));
    expect(model, contains('NoteBlockType.bullet'));
    expect(model, contains('NoteBlockType.checklist'));
    expect(model, contains('NoteBlockType.code'));
    expect(model, contains('NoteBlockType.divider'));
  });

  test('随手记列表支持搜索、置顶和归档管理', () {
    final screen = File('lib/screens/note_screen.dart').readAsStringSync();
    final provider = File(
      'lib/providers/note_provider.dart',
    ).readAsStringSync();
    final i18n = File('lib/core/i18n.dart').readAsStringSync();

    expect(screen, contains('enum _NoteLibraryView { active, archived }'));
    expect(screen, contains('AppPageSwitcher<_NoteLibraryView>'));
    expect(screen, contains("I18n.tr('note.search.hint')"));
    expect(screen, contains("I18n.tr('note.search.empty')"));
    expect(screen, contains("I18n.tr('note.archived.empty')"));
    expect(screen, contains('class _NoteListCard'));
    expect(screen, contains('PopupMenuButton<_NoteCardAction>'));
    expect(screen, contains('_NoteCardAction.pin'));
    expect(screen, contains('_NoteCardAction.archive'));
    expect(screen, contains('_NoteCardAction.restore'));
    expect(screen, contains('provider.togglePinned(note.id)'));
    expect(screen, contains('provider.setArchived(note.id, true)'));
    expect(screen, contains('provider.setArchived(note.id, false)'));
    expect(screen, contains('note.title.toLowerCase().contains(q)'));
    expect(screen, contains('note.content.toLowerCase().contains(q)'));
    expect(screen, contains('attachment.name.toLowerCase().contains(q)'));
    expect(screen, contains('pinned: widget.note?.pinned ?? false'));
    expect(screen, contains('archived: widget.note?.archived ?? false'));

    expect(provider, contains('List<NoteItem> get activeNotes'));
    expect(provider, contains('List<NoteItem> get archivedNotes'));
    expect(provider, contains('void togglePinned(String id)'));
    expect(provider, contains('void setArchived(String id, bool archived)'));
    expect(provider, contains('pinned: archived ? false : note.pinned'));
    expect(provider, contains('if (a.pinned != b.pinned)'));

    for (final key in [
      'note.search.hint',
      'note.search.clear',
      'note.active',
      'note.archived',
      'note.pin',
      'note.unpin',
      'note.archive',
      'note.restore',
    ]) {
      expect(i18n, contains("'$key'"));
    }
  });
}
