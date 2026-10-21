import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/list_group.dart';
import '../services/account_local_data_cleaner.dart';

class ListGroupNameException implements Exception {
  final String messageKey;
  const ListGroupNameException(this.messageKey);
}

class _ListGroupAccountChanged extends StateError {
  _ListGroupAccountChanged() : super('Account changed');
}

class ListGroupProvider extends ChangeNotifier {
  // AuthProvider binds account-scoped preferences to server + account, and
  // AccountLocalDataCleaner clears this key before switching either identity.
  static const storageKey = 'duoyi_list_groups_v1';
  final List<ListGroup> _items = [];
  Future<void> _storageQueue = Future<void>.value();
  int _storageGeneration = 0;
  int _loadedAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  VoidCallback? onLocalChanged;

  List<ListGroup> get groups =>
      List.unmodifiable(allGroups.where((item) => !item.isDeleted));

  /// Includes tombstones for upload and last-write-wins merging.
  List<ListGroup> get allGroups =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _loadedAccountGeneration,
      )
      ? List.unmodifiable(_items)
      : const [];

  int get nextSortOrder =>
      allGroups.fold<int>(
        -1,
        (value, item) => item.sortOrder > value ? item.sortOrder : value,
      ) +
      1;

  static String normalizedName(String name) => name.trim().toLowerCase();

  String? validateName(
    String name, {
    String? excludingId,
    Iterable<String> otherNames = const [],
  }) => _validateName(
    name,
    groups,
    excludingId: excludingId,
    otherNames: otherNames,
  );

  static String? _validateName(
    String name,
    Iterable<ListGroup> items, {
    String? excludingId,
    Iterable<String> otherNames = const [],
  }) {
    final clean = name.trim();
    if (clean.isEmpty) return 'list_group.name_required';
    if (clean.runes.length > 24) return 'list_group.name_length';
    final normalized = normalizedName(clean);
    if (items.any(
          (item) =>
              !item.isDeleted &&
              item.id != excludingId &&
              normalizedName(item.name) == normalized,
        ) ||
        otherNames.any((item) => normalizedName(item) == normalized)) {
      return 'list_group.name_duplicate';
    }
    return null;
  }

  Future<void> loadFromStorage() async {
    try {
      await _withStorage<void>((prefs, isCurrent) async {
        _replace(decodeStoredGroups(prefs.getString(storageKey)));
      });
    } on _ListGroupAccountChanged {
      // The account transition superseded this hydration request.
    }
  }

  void resetLocalState() {
    _storageGeneration++;
    _items.clear();
    _loadedAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    notifyListeners();
  }

  Future<ListGroup> create(String name, int sortOrder) => _mutate((items) {
    final error = _validateName(name, items);
    if (error != null) throw ListGroupNameException(error);
    final now = DateTime.now();
    final group = ListGroup(
      name: name,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    items.add(group);
    return group;
  });

  Future<ListGroup> rename(String id, String name) => _mutate((items) {
    final index = items.indexWhere((item) => item.id == id && !item.isDeleted);
    if (index == -1) throw StateError('Unknown list group');
    final error = _validateName(name, items, excludingId: id);
    if (error != null) throw ListGroupNameException(error);
    final previous = items[index];
    final next = previous.copyWith(name: name, updatedAt: _nextStamp(previous));
    items[index] = next;
    return next;
  });

  Future<void> delete(String id) => _mutate<void>((items) {
    final index = items.indexWhere((item) => item.id == id && !item.isDeleted);
    if (index == -1) return;
    final previous = items[index];
    items[index] = previous.copyWith(
      isDeleted: true,
      updatedAt: _nextStamp(previous),
    );
  });

  Future<void> mergeRemote(List<Map> remote) => _mutate<void>((items) {
    final merged = mergeGroups(items, decodeGroups(remote));
    items
      ..clear()
      ..addAll(merged);
  }, localChange: false);

  DateTime _nextStamp(ListGroup item) {
    final now = DateTime.now();
    return now.isAfter(item.updatedAt)
        ? now
        : item.updatedAt.add(const Duration(microseconds: 1));
  }

  Future<T> _mutate<T>(
    T Function(List<ListGroup>) action, {
    bool localChange = true,
  }) => _withStorage<T>((prefs, isCurrent) async {
    // Re-read on every mutation so a sync writeback cannot be overwritten
    // by an older in-memory snapshot.
    final items = decodeStoredGroups(prefs.getString(storageKey));
    final result = action(items);
    final sorted = mergeGroups(const [], items);
    final encoded = jsonEncode(sorted.map((item) => item.toJson()).toList());
    final changed = prefs.getString(storageKey) != encoded;
    if (changed) await prefs.setString(storageKey, encoded);
    if (!isCurrent()) throw _ListGroupAccountChanged();
    _replace(sorted);
    if (changed && localChange) onLocalChanged?.call();
    return result;
  });

  Future<T> _withStorage<T>(
    Future<T> Function(SharedPreferences, bool Function()) action,
  ) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool isCurrent() =>
        generation == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    final future = _storageQueue.then<T>((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrent()) throw _ListGroupAccountChanged();
      final result = await action(prefs, isCurrent);
      if (!isCurrent()) throw _ListGroupAccountChanged();
      return result;
    });
    _storageQueue = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return future;
  }

  void _replace(Iterable<ListGroup> items) {
    _items
      ..clear()
      ..addAll(items);
    _loadedAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    notifyListeners();
  }

  static List<ListGroup> decodeStoredGroups(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decodeGroups(decoded) : [];
    } on FormatException {
      return [];
    }
  }

  static List<ListGroup> decodeGroups(Iterable<dynamic> raw) {
    final result = <ListGroup>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final group = ListGroup.fromJson(Map<String, dynamic>.from(item));
        if (group.id.isEmpty ||
            group.name.isEmpty ||
            group.name.runes.length > 24) {
          continue;
        }
        result.add(group);
      } on Object catch (error) {
        debugPrint('[ListGroupProvider] ignored invalid record: $error');
      }
    }
    return mergeGroups(const [], result);
  }

  static List<ListGroup> mergeGroups(
    Iterable<ListGroup> current,
    Iterable<ListGroup> remote,
  ) {
    final byId = <String, ListGroup>{};
    for (final item in [...current, ...remote]) {
      final previous = byId[item.id];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList()..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  }
}
