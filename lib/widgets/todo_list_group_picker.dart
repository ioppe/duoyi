import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/todo_templates.dart';
import '../models/list_group.dart';
import '../providers/list_group_provider.dart';
import 'surface_components.dart';

/// 收起时只显示当前选择；展开后在有界的纵向面板中搜索、选择和管理清单。
class TodoListGroupPicker extends StatefulWidget {
  final String value;
  final List<String> names;
  final ListGroupProvider? provider;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool canCreate;
  final bool Function(ListGroup group)? canManage;
  final bool Function() isCurrent;

  const TodoListGroupPicker({
    super.key,
    required this.value,
    required this.names,
    required this.provider,
    required this.onChanged,
    required this.isCurrent,
    this.enabled = true,
    this.canCreate = true,
    this.canManage,
  });

  @override
  State<TodoListGroupPicker> createState() => _TodoListGroupPickerState();
}

enum _ListAction { rename, delete }

class _TodoListGroupPickerState extends State<TodoListGroupPicker> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _scroll = ScrollController();
  bool _expanded = false;
  bool _editing = false;
  bool _busy = false;
  ListGroup? _renaming;
  String? _errorKey;

  bool get _enabled => widget.enabled && !_busy;
  String _normalized(String name) => ListGroupProvider.normalizedName(name);

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _nameFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TodoListTemplate? _template(String name) {
    for (final template in TodoListTemplates.all) {
      if (_normalized(template.name) == _normalized(name)) return template;
    }
    return null;
  }

  ListGroup? _custom(String name) {
    for (final group in widget.provider?.groups ?? const <ListGroup>[]) {
      if (_normalized(group.name) == _normalized(name)) return group;
    }
    return null;
  }

  List<String> _matches(String query) {
    final q = _normalized(query);
    if (q.isEmpty) return widget.names;
    final exact = <String>[];
    final prefix = <String>[];
    final contains = <String>[];
    for (final name in widget.names) {
      final normalized = _normalized(name);
      if (normalized == q) {
        exact.add(name);
      } else if (normalized.startsWith(q)) {
        prefix.add(name);
      } else if (normalized.contains(q)) {
        contains.add(name);
      }
    }
    return [...exact, ...prefix, ...contains];
  }

  bool _canManage(ListGroup group) {
    for (final current in widget.provider?.groups ?? const <ListGroup>[]) {
      if (current.id == group.id) {
        return _template(current.name) == null &&
            (widget.canManage?.call(current) ?? true);
      }
    }
    return false;
  }

  void _revealPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _expanded) {
        Scrollable.ensureVisible(context, alignment: 0.1);
      }
    });
  }

  void _toggle() {
    if (!_enabled) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _expanded = !_expanded;
      _editing = false;
      _renaming = null;
      _errorKey = null;
      _search.clear();
    });
    _revealPanel();
  }

  void _select(String value) {
    if (!_enabled || !widget.isCurrent()) return;
    _nameFocus.unfocus();
    FocusScope.of(context).unfocus();
    widget.onChanged(value);
    setState(() {
      _expanded = false;
      _editing = false;
      _errorKey = null;
      _search.clear();
    });
  }

  void _beginEdit(ListGroup group) {
    if (!_enabled || widget.provider == null || !widget.isCurrent()) return;
    if (!_canManage(group)) return;
    setState(() {
      _editing = true;
      _renaming = group;
      _errorKey = null;
      _name.text = group.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _nameFocus.requestFocus();
    });
  }

  void _cancelEdit() {
    _nameFocus.unfocus();
    setState(() {
      _editing = false;
      _renaming = null;
      _errorKey = null;
    });
    _revealPanel();
  }

  Future<void> _saveName(String input, {ListGroup? group}) async {
    final provider = widget.provider;
    if (!_enabled || provider == null || !widget.isCurrent()) return;
    final isCurrent = widget.isCurrent;
    if (group == null ? !widget.canCreate : !_canManage(group)) {
      setState(() => _errorKey = 'todo.create.read_only');
      return;
    }
    final clean = input.trim();
    if (group == null) {
      for (final name in widget.names) {
        if (_normalized(name) == _normalized(clean)) {
          _select(name);
          return;
        }
      }
    }
    final error = provider.validateName(
      clean,
      excludingId: group?.id,
      otherNames: widget.names.where(
        (name) => group == null || _normalized(name) != _normalized(group.name),
      ),
    );
    if (error != null) {
      setState(() => _errorKey = error);
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final result = group == null
          ? await provider.create(clean, provider.nextSortOrder)
          : await provider.rename(group.id, clean);
      if (!mounted || !isCurrent()) return;
      if (group == null ||
          _normalized(widget.value) == _normalized(group.name)) {
        widget.onChanged(result.name);
      }
      _nameFocus.unfocus();
      setState(() {
        _editing = false;
        _renaming = null;
        _search.clear();
        if (group == null) _expanded = false;
      });
      _revealPanel();
    } on ListGroupNameException catch (error) {
      if (mounted && isCurrent()) setState(() => _errorKey = error.messageKey);
    } catch (_) {
      if (mounted && isCurrent()) {
        setState(() => _errorKey = 'list_group.save_failed');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ListGroup group) async {
    final provider = widget.provider;
    if (!_enabled || provider == null || !widget.isCurrent()) return;
    if (!_canManage(group)) {
      setState(() => _errorKey = 'todo.create.read_only');
      return;
    }
    final isCurrent = widget.isCurrent;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await provider.delete(group.id);
      if (!mounted || !isCurrent()) return;
      if (_normalized(widget.value) == _normalized(group.name)) {
        widget.onChanged('');
      }
      setState(_search.clear);
      _revealPanel();
    } catch (_) {
      if (mounted && isCurrent()) {
        setState(() => _errorKey = 'list_group.save_failed');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _icon(String name, ColorScheme cs) {
    final template = _template(name);
    return Icon(
      name.isEmpty
          ? Icons.folder_open_outlined
          : template?.icon ?? Icons.folder_outlined,
      size: DesignTokens.controlIconSize,
      color: template?.color ?? cs.primary,
    );
  }

  Widget _option(String name, ColorScheme cs, {bool manage = false}) {
    final selected = _normalized(widget.value) == _normalized(name);
    final group = manage && _template(name) == null ? _custom(name) : null;
    final manageable = group != null && (widget.canManage?.call(group) ?? true);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: InkWell(
          key: ValueKey('todo_list_group_$name'),
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          onTap: _enabled ? () => _select(name) : null,
          child: Padding(
            padding: const EdgeInsets.only(left: DesignTokens.spaceMd),
            child: Row(
              children: [
                _icon(name, cs),
                const SizedBox(width: DesignTokens.spaceSm),
                Expanded(
                  child: Text(
                    name.isEmpty ? I18n.tr('list_group.ungrouped') : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceXs,
                    ),
                    child: Icon(
                      Icons.check,
                      size: DesignTokens.controlIconSize,
                      color: cs.primary,
                    ),
                  ),
                if (manageable)
                  PopupMenuButton<_ListAction>(
                    key: ValueKey('todo_list_group_manage_${group.id}'),
                    tooltip: I18n.tr('list_group.manage'),
                    enabled: _enabled,
                    icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                    onSelected: (action) {
                      if (action == _ListAction.rename) {
                        _beginEdit(group);
                      } else {
                        _delete(group);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _ListAction.rename,
                        child: Text(I18n.tr('list_group.rename')),
                      ),
                      PopupMenuItem(
                        value: _ListAction.delete,
                        child: Text(I18n.tr('action.delete')),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: DesignTokens.spaceMd),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String key) => Padding(
    padding: const EdgeInsets.fromLTRB(
      DesignTokens.spaceXs,
      DesignTokens.spaceMd,
      DesignTokens.spaceXs,
      DesignTokens.spaceSm,
    ),
    child: Text(I18n.tr(key), style: appSecondaryControlLabelStyle(context)),
  );

  Widget _editor(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            I18n.tr('list_group.rename'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          AppFormFieldTheme(
            child: TextField(
              key: const ValueKey('todo_list_group_input'),
              controller: _name,
              focusNode: _nameFocus,
              enabled: _enabled,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: I18n.tr('list_group.name'),
                errorText: _errorKey == null ? null : I18n.tr(_errorKey!),
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _errorKey = null),
              onSubmitted: (_) => _saveName(_name.text, group: _renaming),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Row(
            children: [
              TextButton(
                key: const ValueKey('todo_list_group_create_cancel'),
                onPressed: _enabled ? _cancelEdit : null,
                child: Text(I18n.tr('action.cancel')),
              ),
              const Spacer(),
              Flexible(
                child: FilledButton(
                  key: const ValueKey('todo_list_group_create_confirm'),
                  onPressed: _enabled
                      ? () => _saveName(_name.text, group: _renaming)
                      : null,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: DesignTokens.controlIconSize,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(I18n.tr('action.save')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _browser(ColorScheme cs) {
    final query = _search.text.trim();
    final matching = _matches(query);
    final canCreate = widget.canCreate && widget.provider != null;
    final offerCreate =
        canCreate &&
        query.isNotEmpty &&
        !widget.names.any((name) => _normalized(name) == _normalized(query));
    final defaults = matching.where((name) => _template(name) != null).toList();
    final custom = matching.where((name) => _template(name) == null).toList();
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(14);
    final rowHeight = math.max(
      DesignTokens.formFieldMinHeight,
      scale * 2.4 + DesignTokens.spaceLg,
    );
    final available = media.size.height - media.viewInsets.bottom;
    final maxHeight = (available * 0.4).clamp(128.0, 320.0);
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('todo_list_group_search'),
            controller: _search,
            enabled: _enabled,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              labelText: I18n.tr(
                canCreate ? 'list_group.search_or_create' : 'list_group.search',
              ),
              errorText: _errorKey == null ? null : I18n.tr(_errorKey!),
              errorMaxLines: 3,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: I18n.tr('action.clear'),
                      onPressed: _enabled
                          ? () => setState(() {
                              _search.clear();
                              _errorKey = null;
                            })
                          : null,
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) {
              setState(() => _errorKey = null);
              if (_scroll.hasClients) _scroll.jumpTo(0);
            },
            onSubmitted: (_) {
              if (matching.length == 1) {
                _select(matching.single);
              } else if (matching.isNotEmpty &&
                  _normalized(matching.first) == _normalized(query)) {
                _select(matching.first);
              } else if (matching.isEmpty && offerCreate) {
                _saveName(query);
              }
            },
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 3 : 2;
              final desired = query.isNotEmpty
                  ? (matching.length + (offerCreate ? 1 : 0)) * rowHeight +
                        DesignTokens.formFieldMinHeight
                  : rowHeight +
                        (defaults.isEmpty
                            ? 0
                            : ((defaults.length / columns).ceil() * rowHeight +
                                  DesignTokens.controlMinHeight)) +
                        (custom.isEmpty
                            ? 0
                            : custom.length * rowHeight +
                                  DesignTokens.controlMinHeight);
              final height = math.min(maxHeight, math.max(rowHeight, desired));
              return SizedBox(
                height: height,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: CustomScrollView(
                    key: const ValueKey('todo_list_group_options'),
                    controller: _scroll,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      if (query.isEmpty) ...[
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: rowHeight,
                            child: _option('', cs),
                          ),
                        ),
                        if (defaults.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _heading('list_group.built_in'),
                          ),
                          SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: rowHeight,
                                  crossAxisSpacing: DesignTokens.spaceXs,
                                  mainAxisSpacing: DesignTokens.spaceXs,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _option(defaults[index], cs),
                              childCount: defaults.length,
                            ),
                          ),
                        ],
                        if (custom.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _heading('list_group.custom'),
                          ),
                      ] else
                        SliverToBoxAdapter(
                          child: _heading('list_group.results'),
                        ),
                      if (query.isNotEmpty && matching.isEmpty && !offerCreate)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(DesignTokens.spaceLg),
                            child: Text(
                              I18n.tr('list_group.no_matches'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      SliverFixedExtentList(
                        itemExtent: rowHeight,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _option(
                            (query.isEmpty ? custom : matching)[index],
                            cs,
                            manage: true,
                          ),
                          childCount:
                              (query.isEmpty ? custom : matching).length,
                        ),
                      ),
                      if (offerCreate)
                        SliverToBoxAdapter(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: rowHeight),
                            child: TextButton.icon(
                              key: const ValueKey('todo_list_group_create'),
                              onPressed: _enabled
                                  ? () => _saveName(query)
                                  : null,
                              style: TextButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DesignTokens.spaceMd,
                                  vertical: DesignTokens.spaceSm,
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: DesignTokens.controlIconSize,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.add),
                              label: Text(
                                I18n.tr(
                                  'list_group.create_named',
                                ).replaceAll('{name}', query),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(
          color: _expanded
              ? cs.primary.withValues(alpha: 0.4)
              : cs.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: _expanded,
            child: InkWell(
              key: const ValueKey('todo_list_group_selector'),
              onTap: widget.enabled && !_busy ? _toggle : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.formFieldMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceLg,
                    vertical: DesignTokens.spaceMd,
                  ),
                  child: Row(
                    children: [
                      _icon(widget.value, cs),
                      const SizedBox(width: DesignTokens.spaceMd),
                      Expanded(
                        child: Text(
                          widget.value.isEmpty
                              ? I18n.tr('list_group.ungrouped')
                              : widget.value,
                          key: const ValueKey('todo_list_group_selected_name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontSize: DesignTokens.fontSizeMd,
                                height: 1.5,
                              ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceSm),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: cs.outlineVariant),
            _editing ? _editor(cs) : _browser(cs),
          ],
        ],
      ),
    );
  }
}
