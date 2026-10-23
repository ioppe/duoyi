import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shares mobile keyboard dismissal across pages, dialogs and modal sheets.
class KeyboardDismissScope extends StatefulWidget {
  final Widget child;

  const KeyboardDismissScope({super.key, required this.child});

  static void dismiss({FocusNode? focusNode}) {
    (focusNode ?? FocusManager.instance.primaryFocus)?.unfocus();
    hideKeyboard();
  }

  static void hideKeyboard() {
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  @override
  State<KeyboardDismissScope> createState() => _KeyboardDismissScopeState();
}

class _KeyboardDismissScopeState extends State<KeyboardDismissScope> {
  bool _wasEditing = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChanged);
    _handleFocusChanged();
  }

  void _handleFocusChanged() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final isEditing =
        focusContext?.findAncestorStateOfType<EditableTextState>() != null;
    if (_wasEditing && !isEditing) KeyboardDismissScope.hideKeyboard();
    _wasEditing = isEditing;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                _wasEditing = false;
                KeyboardDismissScope.dismiss(focusNode: intent.focusNode);
                return null;
              },
            ),
      },
      child: widget.child,
    );
  }
}

/// Retains Material scrolling and platform effects, adding drag-to-dismiss.
class KeyboardDismissScrollBehavior extends MaterialScrollBehavior {
  const KeyboardDismissScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;
}

/// Clears the outgoing route's focus history before another route can restore it.
class KeyboardDismissNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) KeyboardDismissScope.dismiss();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    KeyboardDismissScope.dismiss();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) KeyboardDismissScope.dismiss();
  }
}
