import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin api exposes permissions and coin adjustment contracts', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    expect(adminApi, contains('Future<void> setUserAdminPermissions'));
    expect(adminApi, contains("body['admin_permissions'] = adminPermissions"));
    expect(adminApi, contains('String? groupId'));
    expect(adminApi, contains('String? roleId'));
    expect(adminApi, contains("body['group_id'] = groupId"));
    expect(adminApi, contains("body['role_id'] = roleId"));
    expect(adminApi, contains(r"'/api/admin/users/$userId'"));
    expect(adminApi, contains('Future<Map<String, dynamic>> adjustUserCoins'));
    expect(adminApi, contains("'delta': delta"));
    expect(adminApi, contains("body['reason'] = reason.trim();"));
    expect(adminApi, contains('_validateCoinAdjustmentResponse'));
    expect(adminApi, contains("response['balance']"));
    expect(adminApi, contains("response['lifetime']"));
    expect(adminApi, contains("response['server_version']"));
    expect(adminApi, contains('时光币调整缺少余额字段'));
    expect(
      adminApi,
      contains('return _validateCoinAdjustmentResponse(response);'),
    );
    expect(
      adminApi,
      contains("throw const ApiException('接口返回结构错误：时光币调整缺少余额字段')"),
    );
    expect(adminApi, contains(r"'/api/admin/users/$userId/coins'"));
    expect(
      adminApi,
      contains(r"client.post('/api/admin/users/$userId/coins', body)"),
      reason: '时光币调整应直连当前主路由，避免连续探测兼容别名导致 404 噪声。',
    );
    for (final noisyFallback in [
      r"'/api/admin/users/$userId/quota/adjust'",
      r"'/api/admin/users/$userId/time-coins/adjust'",
      r"'/api/admin/users/$userId/time_coin_balance/adjust'",
      r"'/api/admin/users/$userId/coin-adjustment'",
    ]) {
      expect(
        adminApi,
        isNot(contains(noisyFallback)),
        reason: '$noisyFallback 应只作为后端兼容别名，不再由前端主动试探。',
      );
    }
    expect(adminApi, contains('Future<AdminPage> listGroupsPage'));
    expect(adminApi, contains('Future<List<Map<String, dynamic>>> listGroups'));
    expect(adminApi, contains("'/api/admin/groups',"));
    expect(adminApi, contains('return await _getPage(path'));
    expect(
      adminApi,
      contains("client.getRaw('/api/admin/groups?limit=500&offset=0')"),
    );
    expect(adminApi, contains('Future<Map<String, dynamic>> saveGroup'));
    expect(adminApi, contains('Future<Map<String, dynamic>> deleteGroup'));
    expect(adminApi, isNot(contains('defaultGenerateQuota')));
    expect(adminApi, isNot(contains('defaultEditQuota')));
    expect(adminApi, isNot(contains("'default_generate_quota'")));
    expect(adminApi, isNot(contains("'default_edit_quota'")));
    expect(adminApi, isNot(contains("'image_mode'")));
    expect(adminApi, contains('_sendFirstAvailable('));
    expect(adminApi, contains("'/api/admin/groups'"));
    expect(adminApi, contains("'/api/admin/user-groups'"));
    expect(adminApi, contains("'/api/admin/user_groups'"));
    expect(adminApi, contains(r"'/api/admin/groups/$groupId'"));
    expect(adminApi, contains("const ['DELETE']"));
    expect(adminApi, contains('管理员用户组删除'));
    expect(adminApi, contains('Future<List<Map<String, dynamic>>> listRoles'));
    expect(adminApi, contains("client.getRaw('/api/admin/roles')"));
    expect(adminApi, contains('Future<Map<String, dynamic>> saveRole'));
    expect(adminApi, contains("client.post('/api/admin/roles', body)"));
    expect(
      adminApi,
      contains(r"client.patch('/api/admin/roles/$roleId', body)"),
    );

    final backend = File('backend/main.py').readAsStringSync();
    final statsSource = backend.substring(
      backend.indexOf('@app.get("/api/admin/stats")'),
      backend.indexOf('@app.get("/api/admin/users")'),
    );
    expect(statsSource, isNot(contains('virtual_rewards')));
    expect(statsSource, isNot(contains('coin_balance')));
    expect(statsSource, isNot(contains('lifetime_coins')));
    expect(
      backend,
      contains('"coin_balance": coin_balance'),
      reason: '历史余额字段继续提供给旧客户端。',
    );
    expect(
      backend,
      contains('"lifetime_coins": lifetime_coins'),
      reason: '累计余额保持历史兼容，不在管理界面展示。',
    );
    expect(backend, contains('@app.post("/api/admin/users/{user_id}/coins")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "coins")'));
    expect(
      backend,
      contains('SET virtual_rewards=?, sync_version=?, updated_at=?'),
    );
    expect(backend, contains('"user.coins_adjust"'));
    expect(backend, contains('admin_permissions_value = ('));
    expect(backend, contains('if req.admin_permissions is not None'));
    expect(backend, contains('else req.adminPermissions'));
    expect(backend, contains('if admin_permissions_value is not None:'));
    expect(
      backend,
      contains('UPDATE users SET admin_permissions=? WHERE id=?'),
    );
    expect(
      backend,
      contains('def _ensure_admin_management_permission'),
      reason: '只有 users 权限不能修改管理员身份、角色或权限。',
    );
    expect(
      backend,
      contains('touches_admin_management'),
      reason: '修改管理员身份、角色或权限时需要额外门禁，避免 users 权限自提权。',
    );
    expect(
      backend,
      contains('return _user_response(fresh, db=db)'),
      reason: '管理员保存用户组/角色后需要返回最新用户对象，避免前端拿不到 group_id/role_id。',
    );
    expect(
      backend,
      contains(
        'def group_int(field: str, fallback: int, *aliases: str) -> int:',
      ),
      reason: '后端更新用户组时需要兼容默认时光币的蛇形和驼峰字段。',
    );
    expect(
      backend,
      contains(
        '_setting_set(db, "default_registration_coins", default_time_coins)',
      ),
      reason: '默认用户组额度需要同步默认注册时光币。',
    );
    final defaults = File('backend/settings_defaults.py').readAsStringSync();
    expect(defaults, contains('"default_registration_coins": 100'));
    expect(backend, contains('default_settings = build_settings_defaults('));
    expect(adminApi, contains("detail == 'not found'"));
    expect(
      adminApi,
      isNot(contains("if (message.startsWith('404:')) return true;")),
      reason: '业务 404 不能被当成路由不存在继续 fallback。',
    );
  });

  test('backend gates granular admin feature permissions', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "settings")'),
    );
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "feedback")'),
    );
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "announcements")'),
    );
    expect(backend, contains('_ensure_admin_permission(db, actor, "invites")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "audit")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "backup")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "ai")'));
    expect(backend, contains('@app.get("/api/admin/permissions")'));
    expect(backend, contains('@app.get("/api/admin/groups")'));
    expect(backend, contains('@app.post("/api/admin/groups")'));
    expect(backend, contains('@app.put("/api/admin/groups/{group_id}")'));
    expect(backend, contains('@app.patch("/api/admin/groups/{group_id}")'));
    expect(backend, contains('@app.delete("/api/admin/groups/{group_id}")'));
    expect(backend, contains('默认用户组不能删除'));
    expect(backend, contains('fallback_group_id'));
    expect(backend, contains('@app.get("/api/admin/roles")'));
    expect(backend, contains('@app.post("/api/admin/roles")'));
    expect(backend, contains('@app.put("/api/admin/roles/{role_id}")'));
    expect(backend, contains('@app.patch("/api/admin/roles/{role_id}")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "groups")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "roles")'));
    expect(
      backend,
      contains(
        '_ensure_admin_any_permission(db, actor, ("permissions", "roles", "users"))',
      ),
    );
    expect(
      backend,
      contains(
        '_ensure_admin_any_permission(db, user_id, ("roles", "permissions"))',
      ),
    );
    expect(backend, contains('AI_SETTING_KEYS'));
    expect(backend, contains('BACKUP_SETTING_KEYS'));
    expect(backend, contains('BACKUP_ADMIN_SETTING_KEYS'));
    expect(backend, contains('ADMIN_SETTINGS_SCOPES'));
  });

  test(
    'admin group editor omits historical defaults instead of overwriting them',
    () {
      final adminScreen = File(
        'lib/screens/admin_screen.dart',
      ).readAsStringSync();
      final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
      expect(adminScreen, isNot(contains('defaultTimeCoins:')));
      expect(adminScreen, isNot(contains('default_registration_coins')));
      expect(adminApi, contains('int? defaultTimeCoins'));
      expect(adminApi, contains("'default_time_coins': ?defaultTimeCoins"));
      expect(adminScreen, isNot(contains('default_generate_quota')));
      expect(adminScreen, isNot(contains('default_edit_quota')));
      expect(adminScreen, isNot(contains('image_mode')));
    },
  );

  test('backend feedback history exposes optional pagination', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('@app.get("/api/feedback/me")'));
    expect(backend, contains('page: Optional[int] = None'));
    expect(backend, contains('page_size: Optional[int] = None'));
    expect(backend, contains('"total_pages"'));
    expect(backend, contains('"page_size"'));
    expect(backend, contains('if page is None and page_size is None:'));
  });

  test('admin user list keeps permissions and hides currency metrics', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(adminScreen, contains('const String _adminAllPermission'));
    expect(adminScreen, contains('const String _adminNoPermission'));
    expect(
      adminScreen,
      contains('const Map<String, String> _adminPermissionLabels'),
    );
    expect(adminScreen, isNot(contains("'coins': '时光币'")));
    expect(adminScreen, contains("'groups': '用户组'"));
    expect(adminScreen, contains("'roles': '角色'"));
    expect(adminScreen, contains("'permissions': '权限字典'"));
    expect(adminScreen, contains('List<String> _adminUserPermissions'));
    expect(adminScreen, contains('String _adminPermissionsLabel'));
    expect(adminScreen, contains('List<Map<String, dynamic>> _groups = [];'));
    expect(adminScreen, contains('List<Map<String, dynamic>> _roles = [];'));
    expect(adminScreen, contains('widget.api.listGroups()'));
    expect(adminScreen, contains('widget.api.listRoles()'));
    expect(adminScreen, contains('String? _groupsRolesError;'));
    expect(
      adminScreen,
      contains('Future<List<Map<String, dynamic>>> _loadUserGroupsForUsers'),
    );
    expect(
      adminScreen,
      contains('Future<List<Map<String, dynamic>>> _loadUserRolesForUsers'),
    );
    expect(
      adminScreen,
      contains("errors.add(_adminErrorMessage(error, '用户组'))"),
    );
    expect(
      adminScreen,
      contains("errors.add(_adminErrorMessage(error, '角色'))"),
    );
    expect(adminScreen, contains('用户组或角色加载失败'));
    expect(
      adminScreen,
      isNot(
        contains('listGroups().catchError((_) => <Map<String, dynamic>>[])'),
      ),
    );
    expect(
      adminScreen,
      isNot(
        contains('listRoles().catchError((_) => <Map<String, dynamic>>[])'),
      ),
    );
    expect(adminScreen, contains('Future<void> _editGroup'));
    expect(adminScreen, contains('Future<void> _editRole'));
    expect(adminScreen, contains('用户组与角色'));
    expect(adminScreen, contains('widget.api.saveGroup('));
    expect(adminScreen, contains('widget.api.saveRole('));
    expect(adminScreen, isNot(contains('默认时光币')));
    expect(adminScreen, isNot(contains('图片额度模式')));
    expect(adminScreen, isNot(contains('生图')));
    expect(adminScreen, isNot(contains('改图')));
    expect(adminScreen, contains("title: '基础功能'"));
    expect(adminScreen, contains("title: '个人数据'"));
    expect(adminScreen, contains("title: '管理功能'"));
    expect(adminScreen, contains("title: '系统功能'"));
    expect(adminScreen, contains("u['admin_permissions']"));
    expect(adminScreen, contains("u['group_id']"));
    expect(adminScreen, contains("u['role_id']"));
    for (final hidden in [
      "u['coin_balance']",
      "u['lifetime_coins']",
      'pageCoinBalance',
      'pageLifetimeCoins',
    ]) {
      expect(adminScreen, isNot(contains(hidden)), reason: hidden);
    }
    final dashboardBody = adminScreen.substring(
      adminScreen.indexOf('class _DashboardTab'),
      adminScreen.indexOf('class _GridCards'),
    );
    expect(dashboardBody, isNot(contains("'时光币余额'")));
    expect(dashboardBody, isNot(contains("'累计时光币'")));
    expect(adminScreen, contains(r"'管理权限: ${_adminPermissionsLabel"));
    expect(adminScreen, contains(r"'用户组: ${_adminEntityName"));
    expect(adminScreen, contains(r"'角色: ${_adminEntityName"));
    expect(adminScreen, isNot(contains(r"'时光币: ${_adminIntValue")));
    expect(adminScreen, contains("label: '细分权限'"));
    expect(adminScreen, contains(r"'当前排序: ${_adminUserSortLabel(_sort)}'"));
    expect(adminScreen, contains('ListView.separated'));
    expect(adminScreen, contains('_AdminPaginationBar('));
    expect(
      adminScreen,
      contains(
        'return Border.all(\n'
        '    color: theme.colorScheme.outline.withValues(alpha: alpha),\n'
        '    width: 0.45,\n'
        '  );',
      ),
    );
    expect(
      adminScreen,
      isNot(contains('Border.all(color: theme.colorScheme.outline')),
    );
  });

  test(
    'admin user menu retains permission gates and hides currency operations',
    () {
      final adminScreen = File(
        'lib/screens/admin_screen.dart',
      ).readAsStringSync();

      expect(adminScreen, contains('Future<void> _editAdminPermissions'));
      expect(adminScreen, contains('Future<void> _editUserGroupRole'));
      expect(adminScreen, isNot(contains('Future<void> _adjustCoins')));
      expect(
        adminScreen,
        contains('selfAdminPermissions: auth.state.adminPermissions'),
      );
      expect(
        adminScreen,
        contains('final List<String>? selfAdminPermissions;'),
      );
      expect(adminScreen, isNot(contains('bool get _canManageCoins')));
      expect(adminScreen, contains("bool get _canManageGroups"));
      expect(adminScreen, contains("bool get _canAssignGroups"));
      expect(
        adminScreen,
        contains('bool get _canAssignGroups => _canManageGroups'),
      );
      expect(adminScreen, contains("bool get _canManageRoles"));
      expect(adminScreen, contains("bool get _canManagePermissions"));
      expect(adminScreen, contains("bool get _canManageAdminAccess"));
      expect(adminScreen, contains("_canUseAdminPermission('groups')"));
      expect(adminScreen, contains("_canUseAdminPermission('roles')"));
      expect(adminScreen, contains("_canUseAdminPermission('permissions')"));
      expect(adminScreen, contains("case 'permissions':"));
      expect(adminScreen, contains("case 'group_role':"));
      expect(adminScreen, isNot(contains("case 'coins':")));
      expect(adminScreen, contains("value: 'permissions'"));
      expect(adminScreen, contains("? '设置管理权限' : '设置管理权限（无权限）'"));
      expect(adminScreen, contains('设置管理权限（无权限）'));
      expect(adminScreen, contains('缺少权限管理权限'));
      expect(adminScreen, contains("value: 'group_role'"));
      expect(adminScreen, contains('设置用户组/角色'));
      expect(adminScreen, contains('缺少用户组或角色管理权限'));
      expect(
        adminScreen,
        contains('isAdmin: _hasAllAdminPermission ? isAdmin : false'),
      );
      expect(adminScreen, contains('widget.api.updateUser('));
      expect(adminScreen, contains('activeOnly: true'));
      expect(adminScreen, contains("item['is_active'] == false"));
      expect(adminScreen, contains("isInactive ? ' · 停用' : ''"));
      expect(
        adminScreen,
        contains('groupId: _canAssignGroups ? selectedGroupId : null'),
      );
      expect(
        adminScreen,
        contains('roleId: _canManageRoles ? selectedRoleId : null'),
      );
      expect(adminScreen, isNot(contains("value: 'coins'")));
      expect(adminScreen, isNot(contains('调整时光币')));
      expect(adminScreen, contains('isAdmin: isAdmin ? null : true'));
      expect(adminScreen, contains('final roleIdForPromotion ='));
      expect(adminScreen, contains('existingRoleId.isNotEmpty'));
      expect(
        adminScreen,
        contains('roleId: isAdmin ? null : roleIdForPromotion'),
      );
      expect(adminScreen, contains('adminPermissions: permissions'));
      expect(
        adminScreen,
        isNot(contains('await widget.api.setUserAdminPermissions(')),
      );
      expect(adminScreen, isNot(contains('widget.api.adjustUserCoins(')));
      expect(adminScreen, contains("SnackBar(content: Text('管理权限已更新'))"));
      expect(
        adminScreen,
        contains('parseAdminPermissions(raw, isAdmin: isAdmin)'),
      );
    },
  );

  test('admin group and coin contracts keep snake case output with camel aliases', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final backend = File('backend/main.py').readAsStringSync();

    final apiUpdateUser = adminApi.substring(
      adminApi.indexOf('Future<Map<String, dynamic>> updateUser'),
      adminApi.indexOf('Future<void> setUserAdminPermissions'),
    );
    expect(apiUpdateUser, contains("body['group_id'] = groupId"));
    expect(apiUpdateUser, contains("body['role_id'] = roleId"));
    expect(apiUpdateUser, isNot(contains("body['groupId']")));
    expect(apiUpdateUser, isNot(contains("body['roleId']")));

    final apiSaveGroup = adminApi.substring(
      adminApi.indexOf('Future<Map<String, dynamic>> saveGroup'),
      adminApi.indexOf('Future<List<Map<String, dynamic>>> listRoles'),
    );
    expect(apiSaveGroup, contains("'default_time_coins'"));
    expect(apiSaveGroup, contains("'is_active'"));
    for (final removed in [
      'default_generate_quota',
      'default_edit_quota',
      'default_generate_history_retention',
      'default_edit_history_retention',
      'image_mode',
    ]) {
      expect(apiSaveGroup, isNot(contains("'$removed'")));
    }

    final apiAdjustCoins = adminApi.substring(
      adminApi.indexOf('Future<Map<String, dynamic>> adjustUserCoins'),
      adminApi.indexOf('Map<String, dynamic> _validateCoinAdjustmentResponse'),
    );
    expect(
      apiAdjustCoins,
      contains("final body = <String, dynamic>{'delta': delta};"),
    );
    expect(
      apiAdjustCoins,
      contains(r"client.post('/api/admin/users/$userId/coins', body)"),
    );

    final userUpdateModel = backend.substring(
      backend.indexOf('class UserUpdate'),
      backend.indexOf('class UserCreate'),
    );
    for (final field in [
      'group_id',
      'groupId',
      'role_id',
      'roleId',
      'admin_permissions',
      'adminPermissions',
      'coin_balance',
      'coinBalance',
      'time_coin_balance',
      'timeCoinBalance',
      'coin_delta',
      'coinDelta',
      'time_coin_delta',
      'timeCoinDelta',
    ]) {
      expect(userUpdateModel, contains('$field: Optional'));
    }

    final coinModel = backend.substring(
      backend.indexOf('class UserCoinAdjustment'),
      backend.indexOf('class AdminGroupUpsert'),
    );
    for (final field in [
      'coin_balance',
      'coinBalance',
      'target_balance',
      'targetBalance',
      'time_coins',
      'timeCoins',
      'time_coin_balance',
      'timeCoinBalance',
      'coin_delta',
      'coinDelta',
      'time_coin_delta',
      'timeCoinDelta',
      'credit_balance',
      'creditBalance',
    ]) {
      expect(coinModel, contains('$field: Optional'));
    }

    final groupModel = backend.substring(
      backend.indexOf('class AdminGroupUpsert'),
      backend.indexOf('class AdminRoleUpsert'),
    );
    for (final field in [
      'default_time_coins',
      'defaultTimeCoins',
      'is_active',
      'isActive',
    ]) {
      expect(groupModel, contains('$field: Optional'));
    }
    for (final removed in [
      'default_generate_quota',
      'defaultGenerateQuota',
      'default_edit_quota',
      'defaultEditQuota',
      'default_generate_history_retention',
      'defaultGenerateHistoryRetention',
      'default_edit_history_retention',
      'defaultEditHistoryRetention',
      'image_mode',
      'imageMode',
    ]) {
      expect(groupModel, isNot(contains('$removed: Optional')));
    }

    final saveGroup = backend.substring(
      backend.indexOf('def _admin_save_group'),
      backend.indexOf('# ---- Users ----'),
    );
    expect(saveGroup, isNot(contains('image_mode_value')));
    expect(saveGroup, isNot(contains('default_generate_quota')));
    expect(saveGroup, isNot(contains('default_edit_quota')));
    expect(saveGroup, contains('is_active_value = req.is_active'));
    expect(saveGroup, contains('is_active_value = req.isActive'));
    expect(
      saveGroup,
      contains('group_int("default_time_coins", 100, "defaultTimeCoins")'),
    );
    expect(saveGroup, contains('"default_registration_coins"'));

    final createUser = backend.substring(
      backend.indexOf('def admin_create_user'),
      backend.indexOf('@app.get("/api/admin/users")'),
    );
    expect(
      createUser,
      contains(
        'group_id_value = req.group_id if req.group_id is not None else req.groupId',
      ),
    );
    expect(
      createUser,
      contains(
        'role_id_value = req.role_id if req.role_id is not None else req.roleId',
      ),
    );
    expect(createUser, contains('else req.adminPermissions'));

    final updateUser = backend.substring(
      backend.indexOf('def admin_update_user'),
      backend.indexOf('def _coin_adjustment_delta'),
    );
    expect(
      updateUser,
      contains(
        'group_id_value = req.group_id if req.group_id is not None else req.groupId',
      ),
    );
    expect(
      updateUser,
      contains(
        'role_id_value = req.role_id if req.role_id is not None else req.roleId',
      ),
    );
    expect(updateUser, contains('else req.adminPermissions'));
    expect(updateUser, contains('coinBalance=req.coinBalance'));
    expect(updateUser, contains('timeCoinBalance=req.timeCoinBalance'));
    expect(updateUser, contains('coinDelta=req.coinDelta'));
    expect(updateUser, contains('timeCoinDelta=req.timeCoinDelta'));

    final coinDelta = backend.substring(
      backend.indexOf('def _coin_adjustment_delta'),
      backend.indexOf('def _admin_adjust_user_coins_impl'),
    );
    expect(coinDelta, contains('if req.coin_balance is not None'));
    expect(coinDelta, contains('if req.coinBalance is not None'));
    expect(coinDelta, contains('if req.time_coin_balance is not None'));
    expect(coinDelta, contains('if req.timeCoinBalance is not None'));
    expect(coinDelta, contains('if req.coin_delta is not None'));
    expect(coinDelta, contains('if req.coinDelta is not None'));
  });
}
