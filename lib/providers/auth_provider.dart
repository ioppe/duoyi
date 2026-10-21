import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/i18n.dart';
import '../core/server_connection.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? username;
  final String? email;
  final bool emailVerified;
  final String? displayName;
  final String? avatar;
  final String? bio;
  final int coinBalance;
  final int lifetimeCoins;
  final String? token;
  final bool isAdmin;
  final List<String>? adminPermissions;

  const AuthState({
    this.userId,
    this.username,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.avatar,
    this.bio,
    this.coinBalance = 0,
    this.lifetimeCoins = 0,
    this.token,
    this.isAdmin = false,
    this.adminPermissions,
  });

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'email': email,
    'email_verified': emailVerified,
    'display_name': displayName,
    'avatar': avatar,
    'bio': bio,
    'coin_balance': coinBalance,
    'lifetime_coins': lifetimeCoins,
    'token': token,
    'is_admin': isAdmin,
    if (adminPermissions != null) 'admin_permissions': adminPermissions,
  };

  factory AuthState.fromJson(Map<String, dynamic> j) => AuthState(
    userId: j['user_id'] as String?,
    username: j['username'] as String?,
    email: j['email'] as String?,
    emailVerified: j['email_verified'] == true,
    displayName: j['display_name'] as String?,
    avatar: j['avatar'] as String?,
    bio: j['bio'] as String?,
    coinBalance: _intFromJson(j['coin_balance']),
    lifetimeCoins: _intFromJson(j['lifetime_coins']),
    token: j['token'] as String?,
    isAdmin: j['is_admin'] == true,
    adminPermissions: j.containsKey('admin_permissions')
        ? _stringListFromJson(j['admin_permissions'])
        : null,
  );

  AuthState copyWith({
    String? userId,
    String? username,
    String? email,
    bool? emailVerified,
    String? displayName,
    String? avatar,
    String? bio,
    int? coinBalance,
    int? lifetimeCoins,
    String? token,
    bool? isAdmin,
    List<String>? adminPermissions,
  }) => AuthState(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    coinBalance: coinBalance ?? this.coinBalance,
    lifetimeCoins: lifetimeCoins ?? this.lifetimeCoins,
    token: token ?? this.token,
    isAdmin: isAdmin ?? this.isAdmin,
    adminPermissions: adminPermissions ?? this.adminPermissions,
  );
}

/// 登录态、运行时服务器连接与账号数据边界。
class AuthProvider extends ChangeNotifier {
  static const serverUrlStorageKey = 'auth_server_url';
  static const sessionServerStorageKey = 'auth_state_server_url';
  final ApiClient Function(String baseUrl, String? token)? _clientFactory;
  AuthState _state = const AuthState();
  late String _baseUrl;
  Map<String, dynamic> _serverConfig = const {};
  late ApiClient _client;
  int _stateMutationSerial = 0;
  int _authAttemptSerial = 0;
  Future<void> _accountTransition = Future<void>.value();
  int _refreshMeRequestSerial = 0;
  int _lastAppliedRefreshMeRequestSerial = 0;
  static const _refreshMeMinInterval = Duration(seconds: 30);
  Future<void>? _refreshMeInFlight;
  DateTime? _lastRefreshMeAt;
  String? _lastRefreshMeToken;
  int _lastRefreshMeMutationSerial = -1;
  static const _serverConfigRefreshTtl = Duration(seconds: 30);
  Future<void>? _serverConfigRefreshInFlight;
  DateTime? _lastServerConfigRefreshAt;

  /// 拉取到 /api/config 之后会触发，供 AiService / CloudSyncProvider 订阅。
  void Function(Map<String, dynamic> cfg)? onServerConfigChanged;
  Future<void> Function(AuthState state)? onAccountProfileChanged;
  Future<void> Function(Map<String, dynamic> payload)? onAccountPayloadChanged;
  Future<void> Function(AuthState previous, AuthState next)?
  onAccountIdentityChanging;
  Future<void> Function()? onAccountLoggedOut;

  AuthState get state => _state;
  String get baseUrl => _baseUrl;
  Map<String, dynamic> get serverConfig => _serverConfig;
  bool get inviteCodeRequired =>
      _serverConfig['invite_code_required'] == true ||
      _serverConfig['registration_invite_required'] == true;
  bool get registrationEnabled =>
      _serverConfig['registration_enabled'] != false &&
      _serverConfig['allow_public_registration'] != false;
  bool get registrationEmailRequired =>
      _serverConfig['registration_email_required'] == true;
  bool get emailCodeLoginEnabled =>
      _serverConfig['email_code_login_enabled'] == true;
  bool get registrationEmailAvailable =>
      _serverConfig['registration_email_available'] == true;
  bool get maintenanceMode => _serverConfig['maintenance_mode'] == true;
  String get maintenanceMessage =>
      (_serverConfig['maintenance_message'] ?? '').toString();
  ApiClient get client => _client;

  AuthProvider({
    ApiClient? client,
    AuthState initialState = const AuthState(),
    String? baseUrl,
    ApiClient Function(String baseUrl, String? token)? clientFactory,
  }) : _clientFactory = clientFactory {
    _state = initialState;
    _baseUrl = baseUrl ?? client?.baseUrl ?? ServerConnection.defaultBaseUrl();
    _client = client ?? ApiClient(baseUrl: _baseUrl, token: _state.token);
  }

  Future<void> loadFromStorage({bool refreshServerConfig = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_base_url');
    await prefs.remove('auth_base_url_admin');
    final defaultUrl = ServerConnection.defaultBaseUrl();
    final savedUrl = kIsWeb ? null : prefs.getString(serverUrlStorageKey);
    try {
      _baseUrl = savedUrl == null
          ? defaultUrl
          : ServerConnection.normalize(savedUrl);
    } on FormatException {
      _baseUrl = defaultUrl;
      await prefs.remove(serverUrlStorageKey);
    }
    final savedServer = prefs.getString(sessionServerStorageKey);
    final expectedServer = ServerConnection.identity(_baseUrl);
    final legacyServer = ServerConnection.identity(
      ServerConnection.defaultBaseUrl(isWeb: false),
    );
    final sessionMatches =
        savedServer == expectedServer ||
        (savedServer == null && expectedServer == legacyServer);
    final raw = sessionMatches ? prefs.getString('auth_state') : null;
    if (!sessionMatches) await prefs.remove('auth_state');
    var loadedState = const AuthState();
    if (raw != null && raw.isNotEmpty) {
      try {
        loadedState = AuthState.fromJson(json.decode(raw));
      } catch (_) {}
    }
    if (loadedState.isLoggedIn) {
      await _clearStoredAccountDataIfOwnerMismatched(prefs, loadedState);
    } else {
      await _clearResidualAccountDataIfSignedOut(prefs);
    }
    _state = loadedState;
    _client = _newClient(_baseUrl, _state.token);
    await prefs.setString(sessionServerStorageKey, expectedServer);
    await _persistAccountDataOwner(prefs, _state);
    notifyListeners();
    if (refreshServerConfig) {
      await refreshServerConfigFromServer();
    }
  }

  Future<void> refreshServerConfigFromServer({bool force = false}) {
    final inFlight = _serverConfigRefreshInFlight;
    if (inFlight != null) return inFlight;
    final lastRefreshAt = _lastServerConfigRefreshAt;
    if (!force &&
        _serverConfig.isNotEmpty &&
        lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _serverConfigRefreshTtl) {
      return Future.value();
    }
    final future = _refreshServerConfigFromServerNow();
    _serverConfigRefreshInFlight = future;
    return future.whenComplete(() {
      if (_serverConfigRefreshInFlight == future) {
        _serverConfigRefreshInFlight = null;
      }
    });
  }

  Future<void> _refreshServerConfigFromServerNow() async {
    final requestClient = _client;
    try {
      final cfg = await requestClient.get('/api/config');
      if (!identical(requestClient, _client)) return;
      _lastServerConfigRefreshAt = DateTime.now();
      if (jsonEncode(_serverConfig) == jsonEncode(cfg)) return;
      _serverConfig = cfg;
      onServerConfigChanged?.call(cfg);
      notifyListeners();
    } catch (_) {
      // offline or server down — 保留旧配置
    }
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      sessionServerStorageKey,
      ServerConnection.identity(_baseUrl),
    );
    if (!kIsWeb && _baseUrl.isNotEmpty) {
      await prefs.setString(serverUrlStorageKey, _baseUrl);
    }
    await prefs.setString('auth_state', json.encode(_state.toJson()));
    await _persistAccountDataOwner(prefs, _state);
  }

  void _markAccountMutation(String reason) {
    _stateMutationSerial++;
    debugPrint(
      '[auth-sync] mutation=$_stateMutationSerial reason=$reason '
      'user=${_state.userId ?? '-'} coin=${_state.coinBalance} '
      'lifetime=${_state.lifetimeCoins}',
    );
  }

  ApiClient _newClient(String url, String? token) =>
      _clientFactory?.call(url, token) ?? ApiClient(baseUrl: url, token: token);

  void _resetConnectionConfig() {
    _serverConfig = const {};
    _lastServerConfigRefreshAt = null;
    _serverConfigRefreshInFlight = null;
    _refreshMeInFlight = null;
    _lastRefreshMeAt = null;
    _refreshMeRequestSerial++;
    onServerConfigChanged?.call(_serverConfig);
  }

  String _validatedServerUrl(String value) {
    try {
      return ServerConnection.normalize(value);
    } on FormatException {
      throw ApiException(I18n.tr('auth.server.invalid'));
    }
  }

  Future<void> _runAccountTransition(Future<void> Function() action) {
    final result = _accountTransition.then((_) => action());
    _accountTransition = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _applyAuthenticatedResponse(
    Map<String, dynamic> response, {
    required ApiClient expectedClient,
    required int attempt,
    required String reason,
    String? serverUrl,
    String? token,
    ApiClient? nextClient,
  }) => _runAccountTransition(() async {
    void checkCurrent() {
      if (attempt != _authAttemptSerial ||
          !identical(expectedClient, _client)) {
        throw ApiException(I18n.tr('auth.connection_changed'));
      }
    }

    checkCurrent();
    final url = serverUrl ?? _baseUrl;
    var nextState = _stateFromAuthResponse(
      response,
      fallbackState: AuthState(token: token),
      avatarBaseUrl: url,
    );
    if (token != null) nextState = nextState.copyWith(token: token);
    if (!nextState.isLoggedIn || _stableAccountIdentity(nextState) == null) {
      throw ApiException(I18n.tr('auth.token.invalid_response'));
    }
    final previousState = _state;
    final serverChanged =
        ServerConnection.identity(url) != ServerConnection.identity(_baseUrl);
    await _notifyAccountIdentityChanging(
      previousState,
      nextState,
      force: serverChanged,
    );
    checkCurrent();
    _baseUrl = url;
    _state = nextState;
    _client = nextClient ?? _newClient(url, _state.token);
    if (serverChanged || token != null) _resetConnectionConfig();
    _markAccountMutation(reason);
    await _persistState();
    await _notifyAccountPayloadChanged(response);
    await _notifyAccountProfileChanged();
    notifyListeners();
  });

  /// Configure the signed-out password/email flow. Never reuse old credentials.
  Future<void> configureServer(String value) => _runAccountTransition(() async {
    if (kIsWeb) return;
    final url = _validatedServerUrl(value);
    if (url == _baseUrl) return;
    if (_state.isLoggedIn) {
      throw ApiException(I18n.tr('auth.server.sign_out_first'));
    }
    _authAttemptSerial++;
    _baseUrl = url;
    _client = _newClient(url, null);
    _resetConnectionConfig();
    await _persistState();
    notifyListeners();
  });

  /// Verify a candidate connection before stopping the current account's sync.
  Future<void> loginWithToken({
    required String serverUrl,
    required String token,
  }) async {
    final url = kIsWeb ? _baseUrl : _validatedServerUrl(serverUrl);
    final secret = token.trim();
    if (secret.isEmpty || RegExp(r'\s').hasMatch(secret)) {
      throw ApiException(I18n.tr('auth.token.required'));
    }
    final expectedClient = _client;
    final attempt = ++_authAttemptSerial;
    final candidate = _newClient(url, secret);
    final response = await candidate.get('/api/auth/me');
    await _applyAuthenticatedResponse(
      response,
      expectedClient: expectedClient,
      attempt: attempt,
      reason: 'token_login',
      serverUrl: url,
      token: secret,
      nextClient: candidate,
    );
    await refreshServerConfigFromServer(force: true);
  }

  Future<List<Map<String, dynamic>>> listAccessTokens() async {
    final response = await _client.get('/api/auth/tokens');
    return (response['tokens'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createAccessToken({
    required String name,
    int? expiresInDays,
  }) => _client.post('/api/auth/tokens', {
    'name': name.trim(),
    'expires_in_days': expiresInDays,
  });

  Future<void> revokeAccessToken(String id, {bool current = false}) async {
    final requestClient = _client;
    final attempt = _authAttemptSerial;
    await requestClient.delete('/api/auth/tokens/${Uri.encodeComponent(id)}');
    if (current) {
      await _clearLocalSession(
        expectedClient: requestClient,
        expectedAttempt: attempt,
      );
    }
  }

  Future<void> register({
    required String username,
    required String password,
    String? email,
    String? emailCode,
    String? displayName,
    String? inviteCode,
  }) async {
    final requestClient = _client;
    final attempt = ++_authAttemptSerial;
    final res = await requestClient.post('/api/auth/register', {
      'username': username,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      if (inviteCode != null && inviteCode.isNotEmpty) ...{
        'invite_code': inviteCode,
        'invitation_code': inviteCode,
      },
    });
    await _applyAuthenticatedResponse(
      res,
      expectedClient: requestClient,
      attempt: attempt,
      reason: 'register',
    );
    await refreshServerConfigFromServer();
  }

  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) async {
    final body = {'email': email, 'purpose': purpose};
    final result = await _postFirstAvailable(const [
      '/api/auth/email-code',
      '/api/auth/email-code/send',
      '/api/auth/email_code',
      '/api/auth/email_code/send',
      '/api/auth/email/send',
      '/api/auth/email/send-code',
      '/api/auth/send-email-code',
      '/api/auth/send-email_code',
      '/api/email-code',
      '/api/email-code/send',
      '/api/email_code',
      '/api/email_code/send',
      '/api/email/send',
      '/api/email/send-code',
      '/api/send-email-code',
      '/api/send-email_code',
    ], body);
    _throwIfEmailCodeNotDelivered(result);
    return result;
  }

  Future<Map<String, dynamic>> sendBindEmailCode({
    required String email,
  }) async {
    final result = await _postFirstAvailable(
      const [
        '/api/me/email-code',
        '/api/me/email-code/send',
        '/api/me/email_code',
        '/api/me/email_code/send',
        '/api/me/email/send',
        '/api/me/email/send-code',
        '/api/auth/email-code',
        '/api/auth/email-code/send',
        '/api/auth/email_code',
        '/api/auth/email_code/send',
        '/api/auth/email/send',
        '/api/auth/email/send-code',
        '/api/auth/send-email-code',
        '/api/auth/send-email_code',
        '/api/email-code',
        '/api/email-code/send',
        '/api/email_code',
        '/api/email_code/send',
        '/api/email/send',
        '/api/email/send-code',
        '/api/send-email-code',
        '/api/send-email_code',
        '/api/user/email-code',
        '/api/user/email-code/send',
        '/api/user/email_code',
        '/api/user/email_code/send',
        '/api/user/email/send',
        '/api/user/email/send-code',
        '/api/account/email-code',
        '/api/account/email-code/send',
        '/api/account/email_code',
        '/api/account/email_code/send',
        '/api/account/email/send',
        '/api/account/email/send-code',
      ],
      {'email': email, 'purpose': 'bind'},
    );
    _throwIfEmailCodeNotDelivered(result);
    return result;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final requestClient = _client;
    final attempt = ++_authAttemptSerial;
    final res = await requestClient.post('/api/auth/login', {
      'username': username,
      'account': username,
      if (_looksLikeEmail(username)) 'email': username,
      'password': password,
    });
    await _applyAuthenticatedResponse(
      res,
      expectedClient: requestClient,
      attempt: attempt,
      reason: 'login',
    );
    await refreshServerConfigFromServer();
  }

  Future<void> emailLogin({required String email, required String code}) async {
    final requestClient = _client;
    final attempt = ++_authAttemptSerial;
    final res = await _postFirstAvailable(
      const [
        '/api/auth/email-login',
        '/api/auth/email/login',
        '/api/auth/login/email',
        '/api/auth/email-code-login',
        '/api/auth/login/email-code',
        '/api/auth/email_code_login',
        '/api/auth/login/email_code',
        '/api/user/email-login',
        '/api/user/login/email-code',
        '/api/user/email_code_login',
        '/api/user/login/email_code',
        '/api/account/email-login',
        '/api/account/email_code_login',
        '/api/email-login',
        '/api/email/login',
        '/api/login/email',
        '/api/email-code-login',
        '/api/login/email-code',
        '/api/email_code_login',
        '/api/login/email_code',
      ],
      {'email': email, 'code': code, 'email_code': code},
    );
    await _applyAuthenticatedResponse(
      res,
      expectedClient: requestClient,
      attempt: attempt,
      reason: 'email_login',
    );
    await refreshServerConfigFromServer();
  }

  Future<void> logout() async {
    final requestClient = _client;
    final attempt = ++_authAttemptSerial;
    try {
      if (_state.isLoggedIn) {
        await _sendFirstAvailable(
          const ['POST'],
          const [
            '/api/auth/logout',
            '/api/logout',
            '/api/me/logout',
            '/api/user/logout',
            '/api/account/logout',
            '/api/auth/signout',
            '/api/auth/sign-out',
          ],
          null,
          featureName: '退出登录',
        );
      }
    } catch (_) {}
    await _clearLocalSession(
      expectedClient: requestClient,
      expectedAttempt: attempt,
    );
  }

  Future<void> _clearLocalSession({
    ApiClient? expectedClient,
    int? expectedAttempt,
  }) => _runAccountTransition(() async {
    if ((expectedClient != null && !identical(expectedClient, _client)) ||
        (expectedAttempt != null && expectedAttempt != _authAttemptSerial)) {
      return;
    }
    _authAttemptSerial++;
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await _notifyAccountLoggedOut();
    } catch (e, st) {
      cleanupError = e;
      cleanupStackTrace = st;
      await _clearAccountScopedPreferencesAfterLogoutCleanupFailure();
    }
    _state = const AuthState();
    _markAccountMutation('logout');
    _client = _newClient(_baseUrl, null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_state');
    await prefs.remove(AccountLocalDataCleaner.accountDataOwnerKey);
    notifyListeners();
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  });

  Future<void> _clearAccountScopedPreferencesAfterLogoutCleanupFailure() async {
    try {
      await AccountLocalDataCleaner.clearSharedPreferences();
    } catch (e, st) {
      debugPrint('[auth] fallback account prefs cleanup failed: $e\n$st');
    }
  }

  Future<void> _clearStoredAccountDataIfOwnerMismatched(
    SharedPreferences prefs,
    AuthState loadedState,
  ) async {
    final currentOwner = _scopedAccountIdentity(loadedState);
    if (currentOwner == null) return;
    final storedOwner = prefs
        .getString(AccountLocalDataCleaner.accountDataOwnerKey)
        ?.trim();
    if (storedOwner == null || storedOwner.isEmpty) {
      if (!_unownedStoredAccountDataLooksMismatched(prefs, loadedState)) return;
      debugPrint('[auth] clearing unowned local account data after mismatch');
      if (onAccountIdentityChanging == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
        return;
      }
      await _notifyAccountIdentityChanging(const AuthState(), loadedState);
      return;
    }
    if (storedOwner == currentOwner) return;
    // Migrate the existing single-server owner without discarding its data.
    if (storedOwner == _stableAccountIdentity(loadedState) &&
        ServerConnection.identity(_baseUrl) ==
            ServerConnection.identity(ServerConnection.defaultBaseUrl())) {
      return;
    }
    debugPrint(
      '[auth] stored account data owner mismatch: $storedOwner -> $currentOwner',
    );
    if (onAccountIdentityChanging == null) {
      await AccountLocalDataCleaner.clearSharedPreferences();
      return;
    }
    await _notifyAccountIdentityChanging(const AuthState(), loadedState);
  }

  Future<void> _clearResidualAccountDataIfSignedOut(
    SharedPreferences prefs,
  ) async {
    if (!_hasStoredAccountScopedData(prefs)) return;
    // 免费外观允许游客使用。只恢复明确由游客选择的外观，绝不恢复账号数据。
    final keepGuestAppearance =
        prefs.getBool(AccountLocalDataCleaner.guestAppearanceMarkerKey) ==
            true &&
        !prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) &&
        !prefs.containsKey('auth_state');
    final appearance = <String, Object>{
      if (keepGuestAppearance)
        for (final key in AccountLocalDataCleaner.appearancePreferenceKeys)
          if (prefs.get(key) case final Object value) key: value,
    };
    debugPrint('[auth] clearing residual account data while signed out');
    if (onAccountLoggedOut == null) {
      await AccountLocalDataCleaner.clearSharedPreferences();
    } else {
      try {
        await _notifyAccountLoggedOut();
      } catch (_) {
        await _clearAccountScopedPreferencesAfterLogoutCleanupFailure();
        rethrow;
      }
    }
    for (final entry in appearance.entries) {
      switch (entry.value) {
        case final String value:
          await prefs.setString(entry.key, value);
        case final int value:
          await prefs.setInt(entry.key, value);
        case final List<String> value:
          await prefs.setStringList(entry.key, value);
      }
    }
    if (keepGuestAppearance) {
      await prefs.setBool(
        AccountLocalDataCleaner.guestAppearanceMarkerKey,
        true,
      );
    }
  }

  bool _hasStoredAccountScopedData(SharedPreferences prefs) {
    final keys = prefs.getKeys();
    return keys.any(
      (key) =>
          AccountLocalDataCleaner.accountScopedKeys.contains(key) ||
          AccountLocalDataCleaner.accountScopedPrefixes.any(key.startsWith),
    );
  }

  bool _unownedStoredAccountDataLooksMismatched(
    SharedPreferences prefs,
    AuthState state,
  ) {
    return _storedProfileLooksDifferent(prefs, state) ||
        _storedRewardsLookDifferent(prefs, state);
  }

  bool _storedProfileLooksDifferent(SharedPreferences prefs, AuthState state) {
    final raw = prefs.getString('user_profile');
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final storedEmail = decoded['email']?.toString().trim().toLowerCase();
      final currentEmail = state.email?.trim().toLowerCase();
      if (storedEmail != null &&
          storedEmail.isNotEmpty &&
          currentEmail != null &&
          currentEmail.isNotEmpty &&
          storedEmail != currentEmail) {
        return true;
      }
      final storedName = decoded['username']?.toString().trim().toLowerCase();
      final currentNameSource = state.displayName?.trim().isNotEmpty == true
          ? state.displayName
          : state.username;
      final currentName = currentNameSource?.trim().toLowerCase();
      if (storedName != null &&
          storedName.isNotEmpty &&
          storedName != '用户' &&
          currentName != null &&
          currentName.isNotEmpty &&
          storedName != currentName) {
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _storedRewardsLookDifferent(SharedPreferences prefs, AuthState state) {
    final raw = prefs.getString('duoyi_virtual_rewards');
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final balance = _intFromJson(
        decoded['balance'] ?? decoded['coin_balance'],
      );
      final lifetime = _intFromJson(
        decoded['lifetime'] ?? decoded['lifetime_coins'],
      );
      if (balance != state.coinBalance &&
          (balance != 0 || state.coinBalance != 0)) {
        return true;
      }
      if (lifetime != state.lifetimeCoins &&
          (lifetime != 0 || state.lifetimeCoins != 0)) {
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> _persistAccountDataOwner(
    SharedPreferences prefs,
    AuthState state,
  ) async {
    final owner = _scopedAccountIdentity(state);
    if (state.isLoggedIn && owner != null) {
      await prefs.setString(AccountLocalDataCleaner.accountDataOwnerKey, owner);
    } else {
      await prefs.remove(AccountLocalDataCleaner.accountDataOwnerKey);
    }
  }

  Future<void> refreshMe({String reason = 'manual', bool force = false}) {
    if (!_state.isLoggedIn) return Future<void>.value();
    final inFlight = _refreshMeInFlight;
    if (inFlight != null) return inFlight;
    final now = DateTime.now();
    final lastRefreshAt = _lastRefreshMeAt;
    if (!force &&
        _lastRefreshMeToken == _state.token &&
        _lastRefreshMeMutationSerial == _stateMutationSerial &&
        lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _refreshMeMinInterval) {
      debugPrint('[auth-sync] refreshMe skipped: throttled reason=$reason');
      return Future<void>.value();
    }
    final future = _refreshMeNow(reason: reason);
    _refreshMeInFlight = future;
    return future.whenComplete(() {
      if (_refreshMeInFlight == future) {
        _refreshMeInFlight = null;
      }
    });
  }

  /// Web entry must validate a restored session before mounting account routes.
  /// Unlike a background profile refresh, a connection failure is actionable.
  Future<void> verifyWebSession() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _refreshMeNow(reason: 'web_entry', requireServerResponse: true);
        return;
      } on _SupersededWebSessionVerification {
        if (attempt == 1) {
          throw ApiException(I18n.tr('auth.connection_changed'));
        }
      }
    }
  }

  Future<void> _refreshMeNow({
    required String reason,
    bool requireServerResponse = false,
  }) async {
    if (!_state.isLoggedIn) return;
    void rejectSupersededVerification() {
      if (requireServerResponse) {
        throw const _SupersededWebSessionVerification();
      }
    }

    final requestId = ++_refreshMeRequestSerial;
    final mutationSerialAtStart = _stateMutationSerial;
    final tokenAtStart = _state.token;
    final userIdAtStart = _state.userId;
    final clientAtStart = _client;
    final authAttemptAtStart = _authAttemptSerial;
    debugPrint(
      '[auth-sync] refreshMe#$requestId start reason=$reason '
      'mutation=$mutationSerialAtStart user=${userIdAtStart ?? '-'}',
    );
    try {
      final me = await _getFirstAvailable(const ['/api/auth/me', '/api/me']);
      if (!identical(clientAtStart, _client)) {
        rejectSupersededVerification();
        return;
      }
      _lastRefreshMeAt = DateTime.now();
      _lastRefreshMeToken = tokenAtStart;
      _lastRefreshMeMutationSerial = mutationSerialAtStart;
      if (requestId != _refreshMeRequestSerial ||
          requestId < _lastAppliedRefreshMeRequestSerial) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: older response');
        rejectSupersededVerification();
        return;
      }
      if (!_state.isLoggedIn || _state.token != tokenAtStart) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: token changed');
        rejectSupersededVerification();
        return;
      }
      if (userIdAtStart != null &&
          _state.userId != null &&
          _state.userId != userIdAtStart) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: user changed');
        rejectSupersededVerification();
        return;
      }
      if (_stateMutationSerial != mutationSerialAtStart) {
        debugPrint(
          '[auth-sync] refreshMe#$requestId skipped: newer account mutation '
          '$_stateMutationSerial > $mutationSerialAtStart',
        );
        rejectSupersededVerification();
        return;
      }
      final nextState = _stateFromAuthResponse(
        me,
        keepToken: true,
        fallbackState: requireServerResponse
            ? AuthState(token: tokenAtStart)
            : null,
      );
      if (requireServerResponse &&
          ((nextState.userId?.trim().isEmpty ?? true) ||
              (userIdAtStart != null && nextState.userId != userIdAtStart))) {
        throw ApiException(I18n.tr('auth.token.invalid_response'));
      }
      _lastAppliedRefreshMeRequestSerial = requestId;
      if (_authStatesEqual(_state, nextState)) {
        await _notifyAccountPayloadChanged(me);
        debugPrint('[auth-sync] refreshMe#$requestId skipped: unchanged');
        return;
      }
      _state = nextState;
      await _persistState();
      await _notifyAccountPayloadChanged(me);
      await _notifyAccountProfileChanged();
      debugPrint(
        '[auth-sync] refreshMe#$requestId applied '
        'coin=${_state.coinBalance} lifetime=${_state.lifetimeCoins}',
      );
      notifyListeners();
    } on _SupersededWebSessionVerification {
      rethrow;
    } on ApiException catch (e) {
      if (!identical(clientAtStart, _client)) {
        rejectSupersededVerification();
        return;
      }
      if (_isAuthExpired(e)) {
        await _clearLocalSession(
          expectedClient: clientAtStart,
          expectedAttempt: authAttemptAtStart,
        );
      } else {
        debugPrint('[auth-sync] refreshMe#$requestId failed: ${e.message}');
        if (requireServerResponse) rethrow;
      }
    } catch (e, st) {
      debugPrint('[auth-sync] refreshMe#$requestId failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> applyServerAccountSnapshot(
    Map<dynamic, dynamic> data, {
    String reason = 'server_snapshot',
    String? expectedToken,
    String? expectedUserId,
  }) async {
    if (!_state.isLoggedIn) return;
    if (expectedToken != null && _state.token != expectedToken) {
      debugPrint('[auth-sync] $reason skipped: token changed');
      return;
    }
    if (expectedUserId != null &&
        _state.userId != null &&
        _state.userId != expectedUserId) {
      debugPrint('[auth-sync] $reason skipped: user changed');
      return;
    }
    final nextState = _stateFromAuthResponse(
      Map<String, dynamic>.from(data),
      keepToken: true,
    );
    if (expectedUserId != null &&
        nextState.userId != null &&
        nextState.userId != expectedUserId) {
      debugPrint('[auth-sync] $reason skipped: response user mismatch');
      return;
    }
    if (_authStatesEqual(_state, nextState)) {
      await _notifyAccountPayloadChanged(Map<String, dynamic>.from(data));
      debugPrint('[auth-sync] $reason skipped: unchanged');
      return;
    }
    _state = nextState;
    _markAccountMutation(reason);
    await _persistState();
    await _notifyAccountPayloadChanged(Map<String, dynamic>.from(data));
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<Map<String, dynamic>> applyThemeShopItem({
    required String itemType,
    required String itemId,
    required String title,
  }) async {
    if (!_state.isLoggedIn) {
      throw const ApiException('请先登录后再使用主题商店');
    }
    final tokenAtStart = _state.token;
    final userIdAtStart = _state.userId;
    final res = await _client.post('/api/theme-shop/apply', {
      'item_type': itemType,
      'item_id': itemId,
      'title': title,
      'activate': true,
    });
    await applyServerAccountSnapshot(
      res,
      reason: 'theme_shop_apply',
      expectedToken: tokenAtStart,
      expectedUserId: userIdAtStart,
    );
    return res;
  }

  Future<void> updateProfile({String? displayName, String? bio}) async {
    final payload = <String, Object?>{};
    if (displayName != null) {
      payload['display_name'] = displayName;
      payload['displayName'] = displayName;
    }
    if (bio != null) payload['bio'] = bio;
    final res = await _sendFirstAvailable(
      const ['PATCH', 'POST', 'PUT'],
      const [
        '/api/me/profile',
        '/api/auth/profile',
        '/api/profile',
        '/api/user/profile',
        '/api/account/profile',
      ],
      payload,
      featureName: '个人资料',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('update_profile');
    await _persistState();
    await _notifyAccountPayloadChanged(res);
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<void> bindEmail({required String email, required String code}) async {
    final body = {
      'email': email,
      'code': code,
      'email_code': code,
      'emailCode': code,
    };
    final res = await _sendFirstAvailable(
      const ['POST', 'PATCH', 'PUT'],
      const [
        '/api/me/email',
        '/api/me/email/bind',
        '/api/me/bind-email',
        '/api/auth/email',
        '/api/auth/bind-email',
        '/api/auth/email/bind',
        '/api/email',
        '/api/email/bind',
        '/api/bind-email',
        '/api/user/email',
        '/api/user/email/bind',
        '/api/user/bind-email',
        '/api/account/email',
        '/api/account/email/bind',
      ],
      body,
      featureName: '邮箱绑定',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('bind_email');
    await _persistState();
    await _notifyAccountPayloadChanged(res);
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _sendFirstAvailable(
      const ['POST'],
      const ['/api/me/password', '/api/auth/change-password'],
      {
        'current_password': currentPassword,
        'currentPassword': currentPassword,
        'old_password': currentPassword,
        'new_password': newPassword,
        'newPassword': newPassword,
        'password': newPassword,
      },
      featureName: '密码修改',
    );
    await _clearLocalSession();
  }

  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
  }) async {
    final res = await _uploadFirstAvailable(
      const [
        '/api/me/avatar',
        '/api/me/profile/avatar',
        '/api/auth/profile/avatar',
        '/api/auth/avatar',
        '/api/profile/avatar',
        '/api/avatar',
        '/api/user/profile/avatar',
        '/api/user/avatar',
        '/api/account/profile/avatar',
        '/api/account/avatar',
      ],
      fieldName: 'avatar',
      fieldNameFallbacks: const ['file', 'image'],
      filename: filename,
      bytes: bytes,
      featureName: '头像上传',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('upload_avatar');
    await _persistState();
    await _notifyAccountPayloadChanged(res);
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<Map<String, dynamic>> requestPasswordReset({required String account}) {
    final trimmed = account.trim();
    return _postFirstAvailable(
      const [
        '/api/auth/password-reset',
        '/api/auth/password-reset/request',
        '/api/auth/reset-password',
        '/api/auth/reset-password/request',
        '/api/auth/forgot-password',
        '/api/auth/forgot-password/request',
        '/api/password-reset',
        '/api/password-reset/request',
      ],
      {
        'username': trimmed,
        'account': trimmed,
        'identifier': trimmed,
        if (_looksLikeEmail(trimmed)) 'email': trimmed,
      },
    );
  }

  Future<void> confirmPasswordReset({
    String? token,
    String? account,
    String? email,
    String? code,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{
      'password': newPassword,
      'new_password': newPassword,
    };
    final identifier = (email != null && email.isNotEmpty) ? email : account;
    if (identifier != null &&
        identifier.isNotEmpty &&
        code != null &&
        code.isNotEmpty) {
      body['account'] = identifier;
      body['identifier'] = identifier;
      body['email'] = email;
      if (email == null && _looksLikeEmail(identifier)) {
        body['email'] = identifier;
      }
      body['code'] = code;
    } else {
      body['token'] = token ?? code ?? '';
    }
    await _postFirstAvailable(const [
      '/api/auth/password-reset/confirm',
      '/api/auth/reset-password/confirm',
      '/api/auth/forgot-password/confirm',
      '/api/password-reset/confirm',
    ], body);
  }

  AuthState _stateFromAuthResponse(
    Map<String, dynamic> data, {
    bool keepToken = false,
    AuthState? fallbackState,
    String? avatarBaseUrl,
  }) {
    final fallback = fallbackState ?? _state;
    final source = data['user'] ?? data['profile'] ?? data['data'];
    final payload = source is Map<String, dynamic>
        ? source
        : source is Map
        ? Map<String, dynamic>.from(source)
        : data;
    final rootToken = _stringField(
      data,
      'token',
      _stringField(data, 'access_token', fallback.token),
    );
    final rewardsPayload = _mapField(data, const [
      'virtual_rewards',
      'virtualRewards',
      'rewards',
    ]);
    final rootCoinBalance = _intField(
      data,
      'coin_balance',
      _intField(
        data,
        'coinBalance',
        rewardsPayload == null
            ? fallback.coinBalance
            : _intField(
                rewardsPayload,
                'balance',
                _intField(rewardsPayload, 'coin_balance', fallback.coinBalance),
              ),
      ),
    );
    final rootLifetimeCoins = _intField(
      data,
      'lifetime_coins',
      _intField(
        data,
        'lifetimeCoins',
        rewardsPayload == null
            ? fallback.lifetimeCoins
            : _intField(
                rewardsPayload,
                'lifetime',
                _intField(
                  rewardsPayload,
                  'lifetime_coins',
                  fallback.lifetimeCoins,
                ),
              ),
      ),
    );
    return AuthState(
      userId: _stringField(
        payload,
        'user_id',
        _stringField(payload, 'id', fallback.userId),
      ),
      username: _stringField(
        payload,
        'username',
        _stringField(payload, 'identifier', fallback.username),
      ),
      email: _stringField(payload, 'email', fallback.email),
      emailVerified: _boolField(
        payload,
        'email_verified',
        _boolField(payload, 'emailVerified', fallback.emailVerified),
      ),
      displayName: _stringField(
        payload,
        'display_name',
        _stringField(payload, 'displayName', fallback.displayName),
      ),
      avatar: _avatarField(
        payload,
        'avatar',
        _avatarField(
          payload,
          'avatar_url',
          _avatarField(
            payload,
            'avatarUrl',
            _avatarField(
              payload,
              'url',
              _avatarField(
                payload,
                'path',
                fallback.avatar,
                baseUrl: avatarBaseUrl,
              ),
              baseUrl: avatarBaseUrl,
            ),
            baseUrl: avatarBaseUrl,
          ),
          baseUrl: avatarBaseUrl,
        ),
        baseUrl: avatarBaseUrl,
      ),
      bio: _stringField(payload, 'bio', fallback.bio),
      coinBalance: _intField(
        payload,
        'coin_balance',
        _intField(payload, 'coinBalance', rootCoinBalance),
      ),
      lifetimeCoins: _intField(
        payload,
        'lifetime_coins',
        _intField(payload, 'lifetimeCoins', rootLifetimeCoins),
      ),
      token: keepToken
          ? fallback.token
          : _stringField(
              payload,
              'token',
              _stringField(payload, 'access_token', rootToken),
            ),
      isAdmin: _boolField(
        payload,
        'is_admin',
        _boolField(payload, 'isAdmin', fallback.isAdmin),
      ),
      adminPermissions: payload.containsKey('admin_permissions')
          ? _stringListFromJson(payload['admin_permissions'])
          : payload.containsKey('permissions')
          ? _stringListFromJson(payload['permissions'])
          : fallback.adminPermissions,
    );
  }

  String? _stringField(
    Map<String, dynamic> data,
    String key,
    String? fallback,
  ) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value == null) return null;
    return value.toString();
  }

  bool _boolField(Map<String, dynamic> data, String key, bool fallback) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (['true', '1', 'yes', 'y'].contains(normalized)) return true;
      if (['false', '0', 'no', 'n'].contains(normalized)) return false;
    }
    return fallback;
  }

  String? _avatarField(
    Map<String, dynamic> data,
    String key,
    String? fallback, {
    String? baseUrl,
  }) {
    final value = _stringField(data, key, fallback);
    if (value == null || value.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.hasScheme || !value.startsWith('/')) return value;
    final activeBaseUrl = baseUrl ?? _baseUrl;
    if (activeBaseUrl.isEmpty) return value;
    var normalizedBase = activeBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    var normalizedValue = value;
    if (_hasBackendApiPrefix(normalizedValue) &&
        normalizedBase.endsWith(
          String.fromCharCodes(const [47, 97, 112, 105]),
        )) {
      normalizedValue = normalizedValue.substring(4);
    }
    return '$normalizedBase$normalizedValue';
  }

  bool _hasBackendApiPrefix(String value) {
    if (value.length < 4) return false;
    return value.codeUnitAt(0) == 47 &&
        value.codeUnitAt(1) == 97 &&
        value.codeUnitAt(2) == 112 &&
        value.codeUnitAt(3) == 105 &&
        (value.length == 4 || value.codeUnitAt(4) == 47);
  }

  Future<Map<String, dynamic>> _postFirstAvailable(
    List<String> paths,
    Object? body,
  ) {
    return _sendFirstAvailable(const ['POST'], paths, body, featureName: '账号');
  }

  Future<Map<String, dynamic>> _getFirstAvailable(List<String> paths) async {
    final requestClient = _client;
    ApiException? last404;
    for (final path in paths) {
      try {
        return await requestClient.requestWithoutRouteDiagnosis('GET', path);
      } on ApiException catch (e) {
        if (!_isRouteMissing(e)) rethrow;
        last404 = e;
      }
    }
    throw last404 ?? const ApiException('404: 接口不存在');
  }

  Future<Map<String, dynamic>> _sendFirstAvailable(
    List<String> methods,
    List<String> paths,
    Object? body, {
    String featureName = '账号资料',
  }) async {
    final requestClient = _client;
    ApiException? last404;
    for (final path in paths) {
      for (final method in methods) {
        try {
          return switch (method) {
            'POST' => await requestClient.requestWithoutRouteDiagnosis(
              'POST',
              path,
              body,
            ),
            'PUT' => await requestClient.requestWithoutRouteDiagnosis(
              'PUT',
              path,
              body,
            ),
            'PATCH' => await requestClient.requestWithoutRouteDiagnosis(
              'PATCH',
              path,
              body,
            ),
            _ => await requestClient.requestWithoutRouteDiagnosis(
              method,
              path,
              body,
            ),
          };
        } on ApiException catch (e) {
          if (!_isRouteMissing(e)) rethrow;
          last404 = e;
        }
      }
    }
    throw await requestClient.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  Future<Map<String, dynamic>> _uploadFirstAvailable(
    List<String> paths, {
    required String fieldName,
    List<String> fieldNameFallbacks = const [],
    required String filename,
    required Uint8List bytes,
    String featureName = '文件上传',
  }) async {
    ApiException? last404;
    ApiException? lastRecoverableUploadError;
    final fieldNames = [
      fieldName,
      for (final fallback in fieldNameFallbacks)
        if (fallback != fieldName) fallback,
    ];
    for (final path in paths) {
      for (final method in const ['POST', 'PATCH', 'PUT']) {
        for (final uploadFieldName in fieldNames) {
          try {
            return await _client.uploadBytes(
              path,
              method: method,
              fieldName: uploadFieldName,
              filename: filename,
              bytes: bytes,
              diagnoseMissingRoute: false,
            );
          } on ApiException catch (e) {
            if (_isRouteMissing(e)) {
              last404 = e;
              break;
            }
            if (_isRecoverableUploadFieldError(e)) {
              lastRecoverableUploadError = e;
              continue;
            }
            rethrow;
          }
        }
      }
    }
    if (lastRecoverableUploadError != null) throw lastRecoverableUploadError;
    throw await _client.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  int _intField(Map<String, dynamic> data, String key, int fallback) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  Map<String, dynamic>? _mapField(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    for (final wrapperKey in const ['user', 'profile', 'data', 'payload']) {
      final wrapper = data[wrapperKey];
      if (wrapper is Map<String, dynamic>) {
        final nested = _mapField(wrapper, keys);
        if (nested != null) return nested;
      } else if (wrapper is Map) {
        final nested = _mapField(Map<String, dynamic>.from(wrapper), keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<void> _notifyAccountProfileChanged() async {
    if (!_state.isLoggedIn) return;
    final callback = onAccountProfileChanged;
    if (callback == null) return;
    try {
      await callback(_state);
    } catch (e, st) {
      debugPrint('[auth] account profile sync failed: $e\n$st');
    }
  }

  Future<void> _notifyAccountPayloadChanged(
    Map<String, dynamic> payload,
  ) async {
    if (!_state.isLoggedIn) return;
    final callback = onAccountPayloadChanged;
    if (callback == null) return;
    try {
      await callback(payload);
    } catch (e, st) {
      debugPrint('[auth] account payload sync failed: $e\n$st');
    }
  }

  Future<void> _notifyAccountIdentityChanging(
    AuthState previous,
    AuthState next, {
    bool force = false,
  }) async {
    if (!force && !_shouldClearLocalAccountDataBeforeApplying(previous, next)) {
      return;
    }
    final callback = onAccountIdentityChanging;
    try {
      if (callback == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
      } else {
        await callback(previous, next);
        // The app-level callback resets provider memory and native schedulers.
        // Run a final prefs pass here as a hard account boundary in case an
        // in-flight account-scoped write raced with that cleanup.
        await AccountLocalDataCleaner.clearSharedPreferences();
      }
    } catch (e, st) {
      debugPrint('[auth] account switch cleanup failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> _notifyAccountLoggedOut() async {
    final callback = onAccountLoggedOut;
    try {
      if (callback == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
      } else {
        await callback();
        await AccountLocalDataCleaner.clearSharedPreferences();
      }
    } catch (e, st) {
      debugPrint('[auth] account logout cleanup failed: $e\n$st');
      rethrow;
    }
  }

  bool _shouldClearLocalAccountDataBeforeApplying(
    AuthState previous,
    AuthState next,
  ) {
    if (!next.isLoggedIn) return false;
    if (!previous.isLoggedIn) return true;
    if (previous.token != next.token) return true;
    final previousIdentity = _stableAccountIdentity(previous);
    final nextIdentity = _stableAccountIdentity(next);
    if (previousIdentity != null && nextIdentity != null) {
      return previousIdentity != nextIdentity;
    }
    return previous.token != next.token;
  }

  String? _scopedAccountIdentity(AuthState state) {
    final account = _stableAccountIdentity(state);
    return account == null
        ? null
        : jsonEncode([ServerConnection.identity(_baseUrl), account]);
  }

  String? _stableAccountIdentity(AuthState state) {
    final userId = state.userId?.trim();
    if (userId != null && userId.isNotEmpty) return 'id:$userId';
    final username = state.username?.trim().toLowerCase();
    if (username != null && username.isNotEmpty) return 'username:$username';
    final email = state.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) return 'email:$email';
    return null;
  }
}

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

List<String> _stringListFromJson(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

bool _authStatesEqual(AuthState left, AuthState right) {
  return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
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

bool _isRecoverableUploadFieldError(ApiException error) {
  final message = error.message.trim().toLowerCase();
  if (!(message.startsWith('400:') || message.startsWith('422:'))) {
    return false;
  }
  return message.contains('头像文件不能为空') ||
      message.contains('file required') ||
      message.contains('field required') ||
      message.contains('missing field') ||
      message.contains('missing required');
}

bool _isAuthExpired(ApiException error) {
  final message = error.message.trim().toLowerCase();
  return message.startsWith('401:') ||
      message.startsWith('403:') ||
      message.contains('token expired') ||
      message.contains('invalid token') ||
      message.contains('account disabled') ||
      message.contains('user not found') ||
      message.contains('账号已禁用') ||
      message.contains('用户不存在') ||
      message.contains('登录已过期');
}

void _throwIfEmailCodeNotDelivered(Map<String, dynamic> result) {
  if (result['sent'] != false || _nonEmptyString(result['dev_code']) != null) {
    return;
  }
  final message =
      _nonEmptyString(result['message']) ??
      _nonEmptyString(result['detail']) ??
      '验证码邮件发送失败，请稍后重试或联系管理员检查邮箱服务。';
  throw ApiException(message);
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _SupersededWebSessionVerification implements Exception {
  const _SupersededWebSessionVerification();
}
