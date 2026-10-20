import '../core/app_clock.dart';
import '../widgets/app_page_tabs.dart';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/note_provider.dart';
import '../models/note.dart';
import '../services/note_attachment_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

enum _NoteLibraryView { active, archived }

enum _NoteCardAction { pin, unpin, archive, restore, delete }

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _searchCtrl = TextEditingController();
  _NoteLibraryView _view = _NoteLibraryView.active;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_refresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final notes = _filterNotes(
      _view == _NoteLibraryView.active
          ? provider.activeNotes
          : provider.archivedNotes,
      _searchCtrl.text,
    );
    final hasAnyNotes = provider.notes.isNotEmpty;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('note.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: I18n.tr('note.archived'),
            onPressed: () => setState(() {
              _view = _view == _NoteLibraryView.active
                  ? _NoteLibraryView.archived
                  : _NoteLibraryView.active;
            }),
          ),
        ],
      ),
      body: !hasAnyNotes
          ? EmptyState(
              icon: Icons.edit_note,
              message: I18n.tr('note.empty.message'),
              actionLabel: I18n.tr('note.empty.action'),
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NoteEditScreen()),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: AppSecondaryControlTheme(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: I18n.tr('note.search.clear'),
                                onPressed: _searchCtrl.clear,
                              ),
                        hintText: I18n.tr('note.search.hint'),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: AppPageSwitcher<_NoteLibraryView>(
                    options: [
                      AppPageOption(
                        value: _NoteLibraryView.active,
                        text:
                            '${I18n.tr('note.active')} ${provider.activeNotes.length}',
                      ),
                      AppPageOption(
                        value: _NoteLibraryView.archived,
                        text:
                            '${I18n.tr('note.archived')} ${provider.archivedNotes.length}',
                      ),
                    ],
                    value: _view,
                    onChanged: (value) => setState(() => _view = value),
                  ),
                ),
                Expanded(
                  child: notes.isEmpty
                      ? _FilteredNotesEmptyState(
                          archived: _view == _NoteLibraryView.archived,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                          itemCount: notes.length,
                          itemBuilder: (context, index) {
                            final note = notes[index];
                            return Dismissible(
                              key: ValueKey('${_view.name}-${note.id}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: _view == _NoteLibraryView.active
                                      ? cs.tertiary
                                      : cs.primary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: Icon(
                                  _view == _NoteLibraryView.active
                                      ? Icons.archive_outlined
                                      : Icons.unarchive_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) => provider.setArchived(
                                note.id,
                                _view == _NoteLibraryView.active,
                              ),
                              child: _NoteListCard(
                                note: note,
                                archived: _view == _NoteLibraryView.archived,
                                onOpen: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NoteEditScreen(note: note),
                                  ),
                                ),
                                onAction: (action) =>
                                    _handleNoteAction(provider, note, action),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NoteEditScreen()),
        ),
        child: const Icon(Icons.edit),
      ),
    );
  }

  List<NoteItem> _filterNotes(List<NoteItem> notes, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(q) ||
              note.content.toLowerCase().contains(q) ||
              note.attachments.any(
                (attachment) =>
                    attachment.name.toLowerCase().contains(q) ||
                    attachment.uri.toLowerCase().contains(q),
              ),
        )
        .toList(growable: false);
  }

  void _handleNoteAction(
    NoteProvider provider,
    NoteItem note,
    _NoteCardAction action,
  ) {
    switch (action) {
      case _NoteCardAction.pin:
      case _NoteCardAction.unpin:
        provider.togglePinned(note.id);
        break;
      case _NoteCardAction.archive:
        provider.setArchived(note.id, true);
        break;
      case _NoteCardAction.restore:
        provider.setArchived(note.id, false);
        break;
      case _NoteCardAction.delete:
        provider.deleteNote(note.id);
        break;
    }
  }
}

class _FilteredNotesEmptyState extends StatelessWidget {
  final bool archived;

  const _FilteredNotesEmptyState({required this.archived});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              archived ? Icons.inventory_2_outlined : Icons.search_off_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              archived
                  ? I18n.tr('note.archived.empty')
                  : I18n.tr('note.search.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteListCard extends StatelessWidget {
  final NoteItem note;
  final bool archived;
  final VoidCallback onOpen;
  final ValueChanged<_NoteCardAction> onAction;

  const _NoteListCard({
    required this.note,
    required this.archived,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: note.pinned
            ? cs.primary.withValues(alpha: 0.28)
            : cs.outlineVariant.withValues(alpha: 0.4),
      ),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.pinned) ...[
                Icon(Icons.push_pin, size: 18, color: cs.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<_NoteCardAction>(
                tooltip: I18n.tr('note.more'),
                onSelected: onAction,
                itemBuilder: (context) => [
                  if (!archived)
                    PopupMenuItem(
                      value: note.pinned
                          ? _NoteCardAction.unpin
                          : _NoteCardAction.pin,
                      child: ListTile(
                        leading: Icon(
                          note.pinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin,
                        ),
                        title: AppSecondaryMenuText(
                          note.pinned
                              ? I18n.tr('note.unpin')
                              : I18n.tr('note.pin'),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  PopupMenuItem(
                    value: archived
                        ? _NoteCardAction.restore
                        : _NoteCardAction.archive,
                    child: ListTile(
                      leading: Icon(
                        archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                      ),
                      title: AppSecondaryMenuText(
                        archived
                            ? I18n.tr('note.restore')
                            : I18n.tr('note.archive'),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _NoteCardAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: cs.error),
                      title: AppSecondaryMenuText(
                        I18n.tr('action.delete'),
                        color: cs.error,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (note.preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.preview,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attachment in note.attachments.take(3))
                  _AttachmentChip(attachment: attachment, compact: true),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (archived) ...[
                Icon(Icons.inventory_2_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  I18n.tr('note.archived'),
                  style: TextStyle(fontSize: 11, color: cs.primary),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                I18nDateFormat.fullDateTime(AppClock.toLocal(note.updatedAt)),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NoteEditScreen extends StatefulWidget {
  final NoteItem? note;
  const NoteEditScreen({super.key, this.note});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late _MarkdownEditingController _ctrl;
  late List<NoteAttachment> _attachments;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _ctrl = _MarkdownEditingController(text: widget.note?.content ?? '');
    _attachments = [...?widget.note?.attachments];
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _saveAndPop() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      final now = DateTime.now();
      context.read<NoteProvider>().addOrUpdateNote(
        NoteItem(
          id: widget.note?.id ?? now.millisecondsSinceEpoch.toString(),
          content: text,
          format: 'markdown',
          blocks: NoteBlock.fromMarkdown(text),
          attachments: List.unmodifiable(_attachments),
          pinned: widget.note?.pinned ?? false,
          archived: widget.note?.archived ?? false,
          createdAt: widget.note?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    } else if (widget.note != null) {
      context.read<NoteProvider>().deleteNote(widget.note!.id);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('note.edit.title')),
        actions: [
          IconButton(
            icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility),
            tooltip: _preview ? I18n.tr('note.edit') : I18n.tr('note.preview'),
            onPressed: () => setState(() => _preview = !_preview),
          ),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveAndPop),
        ],
      ),
      body: Column(
        children: [
          _NoteFormatToolbar(
            onHeading: () => _insertPrefix('# '),
            onBold: () => _wrapSelection('**'),
            onItalic: () => _wrapSelection('*'),
            onQuote: () => _insertPrefix('> '),
            onBullet: () => _insertPrefix('- '),
            onChecklist: () => _insertPrefix('- [ ] '),
            onCode: () => _wrapSelection('`'),
            onLink: _insertLink,
            onAttachment: _addAttachment,
          ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _attachments.length; i++)
                      _AttachmentChip(
                        attachment: _attachments[i],
                        onDeleted: () =>
                            setState(() => _attachments.removeAt(i)),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _preview
                  ? _MarkdownPreview(
                      content: _ctrl.text,
                      blocks: NoteBlock.fromMarkdown(_ctrl.text),
                      attachments: _attachments,
                    )
                  : _NoteEditorPane(
                      controller: _ctrl,
                      attachments: _attachments,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _insertPrefix(String prefix) {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    final start = selection.isValid ? selection.start : text.length;
    final lineStart = start <= 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final next = text.replaceRange(lineStart, lineStart, prefix);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
  }

  void _wrapSelection(String marker) {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.start : text.length;
      final next = text.replaceRange(offset, offset, '$marker$marker');
      _ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: offset + marker.length),
      );
      return;
    }
    final selected = selection.textInside(text);
    final next = text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: selection.end + marker.length * 2,
      ),
    );
  }

  void _insertLink() {
    final text = _ctrl.text;
    final selection = _ctrl.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text)
        : I18n.tr('note.link.placeholder');
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final replacement = '[$selected](https://)';
    final next = text.replaceRange(start, end, replacement);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length - 1,
      ),
    );
  }

  Future<void> _addAttachment() async {
    final source = await showAppModalSheet<_AttachmentSource>(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: '添加附件',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSettingsTile(
              icon: Icons.folder_open_outlined,
              color: Theme.of(ctx).colorScheme.primary,
              title: I18n.tr('note.attachment.pick_file'),
              subtitle: I18n.tr('note.attachment.pick_file.subtitle'),
              onTap: () => Navigator.pop(ctx, _AttachmentSource.file),
            ),
            AppSettingsTile(
              icon: Icons.link_outlined,
              color: Theme.of(ctx).colorScheme.secondary,
              title: I18n.tr('note.attachment.add_link'),
              subtitle: I18n.tr('note.attachment.add_link.subtitle'),
              onTap: () => Navigator.pop(ctx, _AttachmentSource.manual),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == _AttachmentSource.file) {
      final picked = await NoteAttachmentPicker.pickFile();
      if (picked != null) {
        setState(() => _attachments.add(picked));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('note.attachment.file_not_selected')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (!mounted) return;
    final nameCtrl = TextEditingController();
    final uriCtrl = TextEditingController();
    final mimeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(I18n.tr('note.attachment.dialog_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: I18n.tr('note.attachment.name'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: uriCtrl,
              decoration: InputDecoration(
                labelText: I18n.tr('note.attachment.uri'),
                hintText: I18n.tr('note.attachment.uri_hint'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: mimeCtrl,
              decoration: InputDecoration(
                labelText: I18n.tr('note.attachment.type'),
                hintText: I18n.tr('note.attachment.type_hint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.add')),
          ),
        ],
      ),
    );
    final uri = uriCtrl.text.trim();
    final name = nameCtrl.text.trim().isEmpty
        ? I18n.tr('note.attachment.default_name')
        : nameCtrl.text.trim();
    final mimeType = mimeCtrl.text.trim();
    nameCtrl.dispose();
    uriCtrl.dispose();
    mimeCtrl.dispose();
    if (ok != true) return;
    if (uri.isEmpty) return;
    setState(
      () => _attachments.add(
        NoteAttachment(name: name, uri: uri, mimeType: mimeType),
      ),
    );
  }
}

enum _AttachmentSource { file, manual }

class _NoteEditorPane extends StatelessWidget {
  final TextEditingController controller;
  final List<NoteAttachment> attachments;

  const _NoteEditorPane({required this.controller, required this.attachments});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = _NoteTextEditor(controller: controller);
        if (constraints.maxWidth < 760) return editor;
        return Row(
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 28),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => _MarkdownPreview(
                  content: value.text,
                  blocks: NoteBlock.fromMarkdown(value.text),
                  attachments: attachments,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoteTextEditor extends StatelessWidget {
  final TextEditingController controller;

  const _NoteTextEditor({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      autofocus: true,
      decoration: InputDecoration(
        hintText: I18n.tr('note.editor.hint'),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
      ),
      style: const TextStyle(fontSize: 16, height: 1.5),
    );
  }
}

class _MarkdownEditingController extends TextEditingController {
  _MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    final cs = Theme.of(context).colorScheme;
    return TextSpan(
      style: base,
      children: _parseMarkdownDocument(text, base, cs),
    );
  }

  List<InlineSpan> _parseMarkdownDocument(
    String source,
    TextStyle base,
    ColorScheme cs,
  ) {
    if (source.isEmpty) return const [TextSpan(text: '')];
    final spans = <InlineSpan>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.addAll(_parseMarkdownLine(lines[i], base, cs));
    }
    return spans;
  }

  List<InlineSpan> _parseMarkdownLine(
    String line,
    TextStyle base,
    ColorScheme cs,
  ) {
    final markerStyle = base.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      fontWeight: DesignTokens.fontWeightStrong,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
    final indentLength = line.length - line.trimLeft().length;
    final indent = indentLength == 0 ? '' : line.substring(0, indentLength);
    final trimmed = line.substring(indentLength);
    final spans = <InlineSpan>[];
    if (indent.isNotEmpty) spans.add(TextSpan(text: indent));

    if (trimmed.startsWith('# ')) {
      spans.add(TextSpan(text: '# ', style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(2),
          base.copyWith(
            fontSize: ((base.fontSize ?? 14) + 4).clamp(16.0, 18.0),
            fontWeight: DesignTokens.fontWeightStrong,
          ),
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('> ')) {
      spans.add(TextSpan(text: '> ', style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(2),
          base.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ')) {
      final checked = trimmed.startsWith('- [x] ');
      spans.add(TextSpan(text: trimmed.substring(0, 6), style: markerStyle));
      spans.addAll(
        _parseInlineForEditor(
          trimmed.substring(6),
          checked
              ? base.copyWith(
                  color: cs.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                )
              : base,
          cs,
        ),
      );
      return spans;
    }
    if (trimmed.startsWith('- ')) {
      spans.add(TextSpan(text: '- ', style: markerStyle));
      spans.addAll(_parseInlineForEditor(trimmed.substring(2), base, cs));
      return spans;
    }
    return spans..addAll(_parseInlineForEditor(trimmed, base, cs));
  }

  List<InlineSpan> _parseInlineForEditor(
    String source,
    TextStyle base,
    ColorScheme cs,
  ) {
    final markerStyle = base.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
      fontWeight: DesignTokens.fontWeightStrong,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans
            ..add(TextSpan(text: '**', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 2, end),
                style: base.copyWith(fontWeight: DesignTokens.fontWeightStrong),
              ),
            )
            ..add(TextSpan(text: '**', style: markerStyle));
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans
            ..add(TextSpan(text: '`', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, end),
                style: base.copyWith(
                  fontFamily: DesignTokens.fontFamilyRounded,
                  backgroundColor: cs.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            )
            ..add(TextSpan(text: '`', style: markerStyle));
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans
            ..add(TextSpan(text: '[', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, closeLabel),
                style: base.copyWith(
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
            ..add(
              TextSpan(
                text: source.substring(closeLabel, closeUrl + 1),
                style: markerStyle,
              ),
            );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans
            ..add(TextSpan(text: '*', style: markerStyle))
            ..add(
              TextSpan(
                text: source.substring(i + 1, end),
                style: base.copyWith(fontStyle: FontStyle.italic),
              ),
            )
            ..add(TextSpan(text: '*', style: markerStyle));
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}

class _NoteFormatToolbar extends StatelessWidget {
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onAttachment;

  const _NoteFormatToolbar({
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
    required this.onAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.title,
              tooltip: I18n.tr('note.toolbar.heading'),
              onPressed: onHeading,
            ),
            _ToolButton(
              icon: Icons.format_bold,
              tooltip: I18n.tr('note.toolbar.bold'),
              onPressed: onBold,
            ),
            _ToolButton(
              icon: Icons.format_italic,
              tooltip: I18n.tr('note.toolbar.italic'),
              onPressed: onItalic,
            ),
            _ToolButton(
              icon: Icons.format_quote,
              tooltip: I18n.tr('note.toolbar.quote'),
              onPressed: onQuote,
            ),
            _ToolButton(
              icon: Icons.format_list_bulleted,
              tooltip: I18n.tr('note.toolbar.bullet'),
              onPressed: onBullet,
            ),
            _ToolButton(
              icon: Icons.checklist,
              tooltip: I18n.tr('note.toolbar.checklist'),
              onPressed: onChecklist,
            ),
            _ToolButton(
              icon: Icons.code,
              tooltip: I18n.tr('note.toolbar.code'),
              onPressed: onCode,
            ),
            _ToolButton(
              icon: Icons.link,
              tooltip: I18n.tr('note.toolbar.link'),
              onPressed: onLink,
            ),
            _ToolButton(
              icon: Icons.attach_file,
              tooltip: I18n.tr('note.toolbar.attachment'),
              onPressed: onAttachment,
            ),
            const SizedBox(width: 8),
            Text(
              'Markdown',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback? onDeleted;
  final bool compact;

  const _AttachmentChip({
    required this.attachment,
    this.onDeleted,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        _isWebUri(uri) ? Icons.link : Icons.insert_drive_file_outlined,
        size: compact ? 14 : 16,
      ),
      label: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: TextStyle(fontSize: compact ? 11 : 12),
      onDeleted: onDeleted,
      onPressed: uri == null
          ? null
          : () async {
              final target = _isWebUri(uri)
                  ? uri
                  : Uri.file(attachment.uri, windows: false);
              await launchUrl(target, mode: LaunchMode.externalApplication);
            },
    );
  }

  bool _isWebUri(Uri? uri) => uri?.scheme == 'http' || uri?.scheme == 'https';
}

class _MarkdownPreview extends StatelessWidget {
  final String content;
  final List<NoteBlock>? blocks;
  final List<NoteAttachment> attachments;

  const _MarkdownPreview({
    required this.content,
    this.blocks,
    required this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final noteBlocks =
        blocks ??
        (content.trim().isEmpty
            ? [
                NoteBlock(
                  id: 'empty',
                  type: NoteBlockType.paragraph,
                  text: I18n.tr('note.preview.empty'),
                ),
              ]
            : NoteBlock.fromMarkdown(content));
    final images = attachments.where((attachment) => attachment.isImage);
    return ListView(
      children: [
        for (final image in images)
          _PreviewImageAttachment(attachment: image, colorScheme: cs),
        for (final block in noteBlocks)
          _PreviewBlock(block: block, colorScheme: cs),
      ],
    );
  }
}

class _PreviewImageAttachment extends StatelessWidget {
  final NoteAttachment attachment;
  final ColorScheme colorScheme;

  const _PreviewImageAttachment({
    required this.attachment,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    Widget image;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      image = Image.network(
        attachment.uri,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else if (uri != null && uri.scheme == 'file') {
      image = Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else if (attachment.uri.startsWith('/')) {
      image = Image.file(
        File(attachment.uri),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    } else {
      image = _imageFallback();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  final NoteBlock block;
  final ColorScheme colorScheme;

  const _PreviewBlock({required this.block, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.heading) {
      final style = block.level <= 1
          ? Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: DesignTokens.fontWeightStrong,
            )
          : Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: DesignTokens.fontWeightStrong,
            );
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _InlineMarkdownText(text: block.text, style: style),
      );
    }
    if (block.type == NoteBlockType.quote) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
          color: colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: _InlineMarkdownText(
          text: block.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.checklist) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: block.checked
                  ? Colors.green
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: _InlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.circle,
                size: 6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _InlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.code) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          block.text,
          style: const TextStyle(
            fontFamily: DesignTokens.fontFamilyRounded,
            fontSize: 14,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: colorScheme.outlineVariant),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _InlineMarkdownText(text: block.text),
    );
  }
}

class _InlineMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _InlineMarkdownText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    return Text.rich(TextSpan(style: base, children: _parseInline(text, base)));
  }

  List<InlineSpan> _parseInline(String source, TextStyle base) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 2, end),
              style: base.copyWith(fontWeight: DesignTokens.fontWeightStrong),
            ),
          );
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(
                fontFamily: DesignTokens.fontFamilyRounded,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, closeLabel),
              style: base.copyWith(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}
