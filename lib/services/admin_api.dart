import 'api_client.dart';

class AdminPage {
  final List<Map<String, dynamic>> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  const AdminPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory AdminPage.fromJson(
    Map<String, dynamic> json, {
    required int fallbackLimit,
    required int fallbackOffset,
  }) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const ApiException('接口返回结构错误：分页 items 需要列表');
    }
    final items = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      if (item is! Map) {
        throw const ApiException('接口返回结构错误：分页 items 只能包含对象');
      }
      items.add(Map<String, dynamic>.from(item));
    }
    final total = ((json['total'] as num?) ?? items.length).toInt();
    final limit = ((json['limit'] as num?) ?? fallbackLimit).toInt();
    final offset = ((json['offset'] as num?) ?? fallbackOffset).toInt();
    final hasMore = json['has_more'] == true || offset + items.length < total;
    return AdminPage(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasMore: hasMore,
    );
  }

  factory AdminPage.fromItems(
    List<Map<String, dynamic>> items, {
    required int limit,
    required int offset,
  }) {
    return AdminPage(
      items: items,
      total: items.length,
      limit: limit,
      offset: offset,
      hasMore: false,
    );
  }
}

/// 薄封装的管理员 API。所有方法需使用已登录为管理员的 ApiClient。
class AdminApi {
  final ApiClient client;

  const AdminApi(this.client);

  Map<String, dynamic> _flattenSystemSettingsPayload(
    Map<String, dynamic> payload,
  ) {
    final flattened = <String, dynamic>{};
    final runtime = payload['runtime_status'];
    if (runtime is Map) {
      flattened.addAll(Map<String, dynamic>.from(runtime));
    }
    final settings = payload['settings'];
    if (settings is List) {
      for (final item in settings) {
        if (item is! Map) continue;
        final key = item['key'];
        if (key is! String || key.isEmpty) continue;
        flattened[key] = item['value'];
      }
    }
    if (flattened.isEmpty) {
      flattened.addAll(payload);
    }
    return flattened;
  }

  String _path(String base, Map<String, Object?> params) {
    final query = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value.toString();
      if (text.isEmpty) continue;
      query[entry.key] = text;
    }
    if (query.isEmpty) return base;
    return Uri(path: base, queryParameters: query).toString();
  }

  Future<AdminPage> _getPage(
    String base, {
    Map<String, Object?> params = const {},
    int limit = 20,
    int offset = 0,
  }) async {
    final pageParams = <String, Object?>{
      ...params,
      'limit': limit,
      'offset': offset,
    };
    final path = _path(base, pageParams);
    final raw = await client.getRaw(path);
    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('items')) {
        return AdminPage.fromJson(
          raw,
          fallbackLimit: limit,
          fallbackOffset: offset,
        );
      }
      throw ApiException('接口返回结构错误：$base 缺少 items 分页字段');
    }
    if (raw is! List) {
      throw ApiException('接口返回结构错误：$base 需要分页对象或列表');
    }
    return AdminPage.fromItems(
      raw.cast<Map<String, dynamic>>(),
      limit: limit,
      offset: offset,
    );
  }

  // ---- Stats ----
  Future<Map<String, dynamic>> stats() => client.get('/api/admin/stats');

  // ---- Settings ----
  Future<Map<String, dynamic>> getSettings({String? scope}) async {
    final path = _path('/api/admin/settings', {'scope': scope});
    try {
      return await client.requestWithoutRouteDiagnosis('GET', path);
    } on ApiException catch (e) {
      if (!_isRouteMissing(e) || scope != null) rethrow;
    }
    final payload = await getSystemSettings();
    return _flattenSystemSettingsPayload(payload);
  }

  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      return await client.requestWithoutRouteDiagnosis(
        'GET',
        '/api/admin/system-settings',
      );
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
    }
    final legacy = await client.requestWithoutRouteDiagnosis(
      'GET',
      '/api/admin/settings',
    );
    return <String, dynamic>{
      'settings': legacy.entries
          .map(
            (entry) => <String, dynamic>{
              'key': entry.key,
              'value': entry.value,
              'category': '',
              'description': '',
            },
          )
          .toList(),
      'runtime_status': legacy,
      'local_backups': const [],
    };
  }

  Future<Map<String, dynamic>> updateSystemSettings(
    Map<String, dynamic> settings,
  ) async {
    try {
      return await client.requestWithoutRouteDiagnosis(
        'POST',
        '/api/admin/system-settings',
        settings,
      );
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
    }
    await _sendFirstAvailable(
      const ['PATCH', 'POST'],
      const ['/api/admin/settings'],
      settings,
      featureName: '管理员系统设置',
    );
    return getSystemSettings();
  }

  Future<Map<String, dynamic>> updateSettings({
    bool? inviteCodeRequired,
    bool? registrationEnabled,
    bool? registrationEmailRequired,
    bool? maintenanceMode,
    String? maintenanceMessage,
    bool? forceUpdateRequired,
    String? latestVersion,
    String? minimumSupportedVersion,
    String? updateNotes,
    String? updateDownloadUrl,
    int? defaultRegistrationCoins,
  }) async {
    final body = <String, dynamic>{};
    if (inviteCodeRequired != null) {
      body['invite_code_required'] = inviteCodeRequired;
    }
    if (registrationEnabled != null) {
      body['registration_enabled'] = registrationEnabled;
    }
    if (registrationEmailRequired != null) {
      body['registration_email_required'] = registrationEmailRequired;
    }
    if (maintenanceMode != null) body['maintenance_mode'] = maintenanceMode;
    if (maintenanceMessage != null) {
      body['maintenance_message'] = maintenanceMessage;
    }
    if (forceUpdateRequired != null) {
      body['force_update_required'] = forceUpdateRequired;
    }
    if (latestVersion != null) body['latest_version'] = latestVersion;
    if (minimumSupportedVersion != null) {
      body['minimum_supported_version'] = minimumSupportedVersion;
    }
    if (updateNotes != null) body['update_notes'] = updateNotes;
    if (updateDownloadUrl != null) {
      body['update_download_url'] = updateDownloadUrl;
    }
    if (defaultRegistrationCoins != null) {
      body['default_registration_coins'] = defaultRegistrationCoins;
    }
    try {
      return await client.requestWithoutRouteDiagnosis(
        'PATCH',
        '/api/admin/settings',
        body,
      );
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
    }
    return _sendFirstAvailable(
      const ['POST', 'PATCH'],
      const ['/api/admin/settings', '/api/admin/system-settings'],
      body,
      featureName: '管理员更新设置',
    );
  }

  // ---- Users ----
  Future<AdminPage> listUsersPage({
    String? query,
    String? status,
    bool? online,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/users',
    params: {'q': query, 'status': status, 'online': online, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listUsers({String? query}) async {
    return (await listUsersPage(query: query, limit: 100, offset: 0)).items;
  }

  Future<Map<String, dynamic>> createUser({
    required String username,
    String? password,
    String? displayName,
    String? email,
    String? groupId,
    String? roleId,
    bool isAdmin = false,
    bool isDisabled = false,
    List<String>? adminPermissions,
  }) {
    final body = <String, dynamic>{
      'username': username,
      'is_admin': isAdmin,
      'is_disabled': isDisabled,
    };
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      body['display_name'] = displayName.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      body['email'] = email.trim();
    }
    if (groupId != null && groupId.trim().isNotEmpty) {
      body['group_id'] = groupId.trim();
    }
    if (roleId != null && roleId.trim().isNotEmpty) {
      body['role_id'] = roleId.trim();
    }
    if (adminPermissions != null) {
      body['admin_permissions'] = adminPermissions;
    }
    return client.post('/api/admin/users', body);
  }

  Future<Map<String, dynamic>> updateUser(
    String userId, {
    bool? isAdmin,
    bool? isDisabled,
    String? newPassword,
    String? groupId,
    String? roleId,
    List<String>? adminPermissions,
  }) async {
    final body = <String, dynamic>{};
    if (isAdmin != null) body['is_admin'] = isAdmin;
    if (isDisabled != null) body['is_disabled'] = isDisabled;
    if (newPassword != null && newPassword.isNotEmpty) {
      body['new_password'] = newPassword;
    }
    if (groupId != null) body['group_id'] = groupId;
    if (roleId != null) body['role_id'] = roleId;
    if (adminPermissions != null) {
      body['admin_permissions'] = adminPermissions;
    }
    return client.patch('/api/admin/users/$userId', body);
  }

  Future<void> setUserAdminPermissions(
    String userId, {
    required List<String> permissions,
  }) async {
    await updateUser(userId, adminPermissions: permissions);
  }

  Future<Map<String, dynamic>> adjustUserCoins(
    String userId, {
    required int delta,
    String? reason,
  }) async {
    final body = <String, dynamic>{'delta': delta};
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    final response = await client.post('/api/admin/users/$userId/coins', body);
    return _validateCoinAdjustmentResponse(response);
  }

  Map<String, dynamic> _validateCoinAdjustmentResponse(
    Map<String, dynamic> response,
  ) {
    final balance = response['balance'];
    final lifetime = response['lifetime'];
    final serverVersion = response['server_version'];
    if (balance is! num || lifetime is! num || serverVersion is! num) {
      throw const ApiException('接口返回结构错误：时光币调整缺少余额字段');
    }
    return response;
  }

  Future<String> exportUsersCsv({
    String? query,
    String? status,
    bool? online,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/users/export.csv', {
      'q': query,
      'status': status,
      'online': online,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> bulkUpdateUserStatus({
    required List<String> userIds,
    required bool isDisabled,
  }) => client.post('/api/admin/users/bulk-status', {
    'user_ids': userIds,
    'is_disabled': isDisabled,
  });

  Future<AdminPage> listGroupsPage({int limit = 20, int offset = 0}) async {
    try {
      return await _getPage('/api/admin/groups', limit: limit, offset: offset);
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
    }
    ApiException? last404;
    for (final path in const [
      '/api/admin/user-groups',
      '/api/admin/user_groups',
      '/api/admin/userGroups',
    ]) {
      try {
        return await _getPage(path, limit: limit, offset: offset);
      } on ApiException catch (e) {
        if (!_isRouteMissing(e)) rethrow;
        last404 = e;
      }
    }
    throw last404 ?? const ApiException('404: 接口不存在');
  }

  Future<List<Map<String, dynamic>>> listGroups() async {
    Object? raw;
    try {
      raw = await client.getRaw('/api/admin/groups?limit=500&offset=0');
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      raw = await _getRawFirstAvailable(const [
        '/api/admin/user-groups?limit=500&offset=0',
        '/api/admin/user_groups?limit=500&offset=0',
        '/api/admin/userGroups?limit=500&offset=0',
      ]);
    }
    final items = raw is Map<String, dynamic> && raw['items'] is List
        ? raw['items']
        : raw;
    if (items is! List) {
      throw const ApiException('接口返回结构错误：用户组需要列表');
    }
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> saveGroup({
    String? id,
    required String name,
    String description = '',
    int? defaultTimeCoins,
    bool isActive = true,
  }) {
    final body = <String, dynamic>{
      'name': name,
      'description': description,
      'default_time_coins': ?defaultTimeCoins,
      'is_active': isActive,
    };
    final groupId = id?.trim();
    if (groupId == null || groupId.isEmpty) {
      return _sendFirstAvailable(
        const ['POST'],
        const [
          '/api/admin/groups',
          '/api/admin/user-groups',
          '/api/admin/user_groups',
          '/api/admin/userGroups',
        ],
        body,
      );
    }
    return _sendFirstAvailable(
      const ['PATCH', 'PUT'],
      [
        '/api/admin/groups/$groupId',
        '/api/admin/user-groups/$groupId',
        '/api/admin/user_groups/$groupId',
        '/api/admin/userGroups/$groupId',
      ],
      body,
    );
  }

  Future<Map<String, dynamic>> deleteGroup(String groupId) {
    final id = groupId.trim();
    return _sendFirstAvailable(
      const ['DELETE'],
      [
        '/api/admin/groups/$id',
        '/api/admin/user-groups/$id',
        '/api/admin/user_groups/$id',
        '/api/admin/userGroups/$id',
      ],
      null,
      featureName: '管理员用户组删除',
    );
  }

  Future<List<Map<String, dynamic>>> listRoles() async {
    final raw = await client.getRaw('/api/admin/roles');
    if (raw is! List) {
      throw const ApiException('接口返回结构错误：角色需要列表');
    }
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> saveRole({
    String? id,
    required String name,
    String description = '',
    List<String> permissions = const [],
    bool isActive = true,
  }) {
    final body = <String, dynamic>{
      'name': name,
      'description': description,
      'permissions': permissions,
      'permission_codes': permissions,
      'is_active': isActive,
    };
    final roleId = id?.trim();
    if (roleId == null || roleId.isEmpty) {
      return client.post('/api/admin/roles', body);
    }
    return client.patch('/api/admin/roles/$roleId', body);
  }

  Future<void> deleteUser(String userId) =>
      client.delete('/api/admin/users/$userId');

  Future<Map<String, dynamic>> _sendFirstAvailable(
    List<String> methods,
    List<String> paths,
    Object? body, {
    String featureName = '管理员',
  }) async {
    ApiException? last404;
    for (final path in paths) {
      for (final method in methods) {
        try {
          return switch (method) {
            'PATCH' => await client.requestWithoutRouteDiagnosis(
              'PATCH',
              path,
              body,
            ),
            'PUT' => await client.requestWithoutRouteDiagnosis(
              'PUT',
              path,
              body,
            ),
            'DELETE' => await client.requestWithoutRouteDiagnosis(
              'DELETE',
              path,
              body,
            ),
            _ => await client.requestWithoutRouteDiagnosis('POST', path, body),
          };
        } on ApiException catch (e) {
          if (!_isRouteMissing(e)) rethrow;
          last404 = e;
        }
      }
    }
    throw await client.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  Future<Object?> _getRawFirstAvailable(List<String> paths) async {
    ApiException? last404;
    for (final path in paths) {
      try {
        return await client.getRaw(path);
      } on ApiException catch (e) {
        if (!_isRouteMissing(e)) rethrow;
        last404 = e;
      }
    }
    throw last404 ?? const ApiException('404: 接口不存在');
  }

  // ---- Announcements ----
  Future<AdminPage> listAnnouncementsPage({
    String? query,
    String? status,
    String? level,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/announcements',
    params: {'q': query, 'status': status, 'level': level, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listAnnouncements() async {
    return (await listAnnouncementsPage(limit: 100, offset: 0)).items;
  }

  Future<int> createAnnouncement({
    required String title,
    required String body,
    String level = 'info',
    bool published = true,
  }) async {
    final res = await client.post('/api/admin/announcements', {
      'title': title,
      'body': body,
      'level': level,
      'published': published,
    });
    return (res['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> updateAnnouncement(
    int id, {
    String? title,
    String? body,
    String? level,
    bool? published,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (body != null) payload['body'] = body;
    if (level != null) payload['level'] = level;
    if (published != null) payload['published'] = published;
    await client.patch('/api/admin/announcements/$id', payload);
  }

  Future<void> deleteAnnouncement(int id) =>
      client.delete('/api/admin/announcements/$id');

  // ---- Feedback ----
  Future<AdminPage> listFeedbackPage({
    String? status,
    String? query,
    String? category,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/feedback',
    params: {'status': status, 'q': query, 'category': category, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listFeedback({String? status}) async {
    return (await listFeedbackPage(
      status: status,
      limit: 100,
      offset: 0,
    )).items;
  }

  Future<Map<String, dynamic>> getFeedbackDetail(int id) =>
      client.get('/api/admin/feedback/$id');

  Future<void> replyFeedback({
    required int feedbackId,
    required String reply,
    String status = 'resolved',
  }) => client.post('/api/admin/feedback/reply', {
    'feedback_id': feedbackId,
    'reply': reply,
    'status': status,
  });

  Future<void> bulkUpdateFeedbackStatus({
    required List<int> feedbackIds,
    required String reply,
    String status = 'in_progress',
  }) => client.post('/api/admin/feedback/bulk-status', {
    'feedback_ids': feedbackIds,
    'reply': reply,
    'status': status,
  });

  Future<void> closeFeedback(int id, {String reply = '已关闭。'}) =>
      bulkUpdateFeedbackStatus(
        feedbackIds: [id],
        reply: reply,
        status: 'closed',
      );

  Future<String> exportFeedbackCsv({
    String? status,
    String? query,
    String? category,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/feedback/export.csv', {
      'status': status,
      'q': query,
      'category': category,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> deleteFeedback(int id) =>
      client.delete('/api/admin/feedback/$id');

  // ---- Invite codes ----
  Future<AdminPage> listInviteCodesPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/invite-codes',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listInviteCodes() async {
    return (await listInviteCodesPage(limit: 100, offset: 0)).items;
  }

  Future<List<String>> createInviteCodes({
    int count = 1,
    String note = '',
  }) async {
    final res = await client.post('/api/admin/invite-codes', {
      'count': count,
      'note': note,
    });
    return (res['codes'] as List<dynamic>? ?? const []).cast<String>();
  }

  Future<void> deleteInviteCode(String code) =>
      client.delete('/api/admin/invite-codes/$code');

  // ---- Audit log ----
  Future<AdminPage> auditLogPage({
    String? action,
    String? query,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/audit-log',
    params: {'action': action, 'q': query, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> auditLog({String? action}) async {
    return (await auditLogPage(action: action, limit: 100, offset: 0)).items;
  }

  // ---- AI diagnostic ----
  Future<Map<String, dynamic>> testAi({
    bool? aiEnabled,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    final payload = <String, Object?>{};
    if (aiEnabled != null) payload['ai_enabled'] = aiEnabled;
    if (baseUrl != null) payload['ai_base_url'] = baseUrl;
    if (apiKey != null) payload['ai_api_key'] = apiKey;
    if (model != null) payload['ai_model'] = model;
    final body = payload.isEmpty ? null : payload;
    try {
      return await client.post(
        '/api/admin/ai/test',
        body,
        const Duration(seconds: 30),
      );
    } on ApiException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      return client.post('/api/admin/provider-healthcheck', {
        'apply_switch': false,
        ...payload,
      }, const Duration(seconds: 30));
    }
  }

  // ---- Reminder email diagnostic ----
  Future<Map<String, dynamic>> testReminderEmail() =>
      client.post('/api/admin/reminders/email/test');

  // ---- Account email diagnostic ----
  Future<Map<String, dynamic>> testAccountEmail() =>
      client.post('/api/admin/account-email/test');

  // ---- Backups ----
  Future<AdminPage> listBackupsPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/backups',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listBackups() async {
    return (await listBackupsPage(limit: 100, offset: 0)).items;
  }

  Future<String> exportBackupsCsv({
    String? query,
    String? status,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/backups/export.csv', {
      'q': query,
      'status': status,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> wipeBackup(String userId) =>
      client.delete('/api/admin/backups/$userId');

  Future<AdminPage> listServerBackupsPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/server-backups',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listServerBackups() async {
    return (await listServerBackupsPage(limit: 100, offset: 0)).items;
  }

  Future<String> exportServerBackupsCsv({
    String? query,
    String? status,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/server-backups/export.csv', {
      'q': query,
      'status': status,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<Map<String, dynamic>> runServerBackup() =>
      client.post('/api/admin/server-backups/run');
}

bool _isRouteMissing(ApiException error) {
  final message = error.message.trimLeft();
  if (message.startsWith('405:')) {
    final detail = message.substring(4).split('\n').first.trim().toLowerCase();
    return detail == 'method not allowed' ||
        detail == '{"detail":"method not allowed"}';
  }
  if (!message.startsWith('404:')) return false;
  final detail = message.substring(4).split('\n').first.trim().toLowerCase();
  return detail == 'not found' ||
      detail == '{"detail":"not found"}' ||
      detail == '接口不存在' ||
      detail == 'route not found';
}
