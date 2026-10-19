import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/app_config.dart';

/// 跨平台 HTTP 封装(web/android/linux 通用)。
class ApiClient {
  static const String requiredApiContractVersion = '2026-06-01.3';
  static const String requiredApiContractRoutesHash = '48881df2412c4ae0';

  String baseUrl;
  String? token;
  final http.Client _httpClient;
  String? _backendContractDiagnosis;
  bool _backendContractDiagnosisLoaded = false;

  ApiClient({this.baseUrl = '', this.token, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Duration? timeout,
  ]) => _send('POST', path, body: body, timeout: timeout);
  Future<Map<String, dynamic>> patch(String path, [Object? body]) =>
      _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> put(String path, [Object? body]) =>
      _send('PUT', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Object? body,
  ]) => _send(method.toUpperCase(), path, body: body);

  Future<Map<String, dynamic>> requestWithoutRouteDiagnosis(
    String method,
    String path, [
    Object? body,
  ]) => _send(
    method.toUpperCase(),
    path,
    body: body,
    diagnoseMissingRoute: false,
  );

  Future<ApiException> missingRoutesException({
    required String featureName,
    required List<String> paths,
    ApiException? fallback,
  }) async {
    final diagnosis = await _backendContractDiagnosisText();
    final primaryPath = paths.isEmpty ? '/api/*' : paths.first;
    final details = <String>[
      '$featureName接口均未命中：${paths.join('、')}。',
      if (diagnosis == null || diagnosis.isEmpty)
        '无法读取 /api/config，可能是后端版本过旧，或反向代理没有把 /api/* 转发到后端。'
      else
        diagnosis,
      if (fallback != null && fallback.message.isNotEmpty)
        '最后一次错误：${fallback.message}',
    ];
    return ApiException('当前后端未部署本版本接口：$primaryPath。${details.join('')}');
  }

  Future<List<dynamic>> getList(String path) async {
    final res = await _sendRaw('GET', path);
    if (res is List) return res;
    throw ApiException('接口返回结构错误：$path 需要列表，实际为 ${_shapeName(res)}');
  }

  Future<dynamic> getRaw(String path) => _sendRaw('GET', path);

  Future<String> getText(String path) async {
    if (baseUrl.isEmpty && !kIsWeb) {
      throw const ApiException('请先在登录页配置服务器地址，再使用登录、公告和云同步。');
    }
    final uri = _uriFor(path);
    final headers = <String, String>{'Accept': 'text/plain, text/csv'};
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response resp;
    try {
      resp = await _httpClient
          .get(uri, headers: headers)
          .timeout(AppConfig.fileTimeout);
    } on TimeoutException {
      throw ApiException('连接服务器超时：${_serverLabel(uri)}');
    } catch (e) {
      throw ApiException(
        '无法连接服务器 ${_serverLabel(uri)}：${_friendlyNetworkError(uri, e)}',
      );
    }

    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return raw;
    }
    String detail = raw;
    try {
      final m = json.decode(raw);
      if (m is Map && m['detail'] != null) detail = m['detail'].toString();
    } catch (_) {}
    throw ApiException(
      await _buildHttpErrorMessage(resp.statusCode, detail, path),
    );
  }

  Future<Map<String, dynamic>> uploadBytes(
    String path, {
    String method = 'POST',
    required String fieldName,
    required String filename,
    required Uint8List bytes,
    bool diagnoseMissingRoute = true,
  }) async {
    if (baseUrl.isEmpty && !kIsWeb) {
      throw const ApiException('请先在登录页配置服务器地址，再使用登录、公告和云同步。');
    }
    final uri = _uriFor(path);
    final request = http.MultipartRequest(method.toUpperCase(), uri);
    if (token != null && token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: _contentTypeForFilename(filename),
      ),
    );

    http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(AppConfig.fileTimeout);
    } on TimeoutException {
      throw ApiException('连接服务器超时：${_serverLabel(uri)}');
    } catch (e) {
      throw ApiException(
        '无法连接服务器 ${_serverLabel(uri)}：${_friendlyNetworkError(uri, e)}',
      );
    }

    final raw = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      if (raw.isEmpty) return <String, dynamic>{};
      final decoded = _decodeJson(raw, path);
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiException('接口返回结构错误：$path 需要对象，实际为 ${_shapeName(decoded)}');
    }
    String detail = raw;
    try {
      final m = json.decode(raw);
      if (m is Map && m['detail'] != null) detail = m['detail'].toString();
    } catch (_) {}
    throw ApiException(
      await _buildHttpErrorMessage(
        streamed.statusCode,
        detail,
        path,
        diagnoseMissingRoute: diagnoseMissingRoute,
      ),
    );
  }

  Stream<String> streamLines(String path) async* {
    if (baseUrl.isEmpty && !kIsWeb) {
      throw const ApiException('请先在登录页配置服务器地址，再使用登录、公告和云同步。');
    }
    final uri = _uriFor(path);
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';
    if (token != null && token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    http.StreamedResponse resp;
    try {
      resp = await _httpClient.send(request).timeout(AppConfig.httpTimeout);
    } on TimeoutException {
      throw ApiException('连接服务器超时：${_serverLabel(uri)}');
    } catch (e) {
      throw ApiException(
        '无法连接服务器 ${_serverLabel(uri)}：${_friendlyNetworkError(uri, e)}',
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final raw = await resp.stream.bytesToString();
      String detail = raw;
      try {
        final m = json.decode(raw);
        if (m is Map && m['detail'] != null) detail = m['detail'].toString();
      } catch (_) {}
      throw ApiException(
        await _buildHttpErrorMessage(resp.statusCode, detail, path),
      );
    }

    yield* resp.stream.transform(utf8.decoder).transform(const LineSplitter());
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    bool diagnoseMissingRoute = true,
  }) async {
    final raw = await _sendRaw(
      method,
      path,
      body: body,
      timeout: timeout,
      diagnoseMissingRoute: diagnoseMissingRoute,
    );
    if (raw is Map<String, dynamic>) return raw;
    throw ApiException('接口返回结构错误：$path 需要对象，实际为 ${_shapeName(raw)}');
  }

  Future<dynamic> _sendRaw(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    bool diagnoseMissingRoute = true,
  }) async {
    // baseUrl 为空时走相对路径(web 前后端同域反代)；
    // 安装端使用 AuthProvider 保存的运行时服务器地址。
    if (baseUrl.isEmpty && !kIsWeb) {
      throw const ApiException('请先在登录页配置服务器地址，再使用登录、公告和云同步。');
    }
    final uri = _uriFor(path);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response resp;
    final encoded = body == null ? null : json.encode(body);
    final requestTimeout = timeout ?? AppConfig.httpTimeout;
    try {
      switch (method) {
        case 'GET':
          resp = await _httpClient
              .get(uri, headers: headers)
              .timeout(requestTimeout);
          break;
        case 'POST':
          resp = await _httpClient
              .post(uri, headers: headers, body: encoded)
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          resp = await _httpClient
              .patch(uri, headers: headers, body: encoded)
              .timeout(requestTimeout);
          break;
        case 'PUT':
          resp = await _httpClient
              .put(uri, headers: headers, body: encoded)
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          resp = await _httpClient
              .delete(uri, headers: headers, body: encoded)
              .timeout(requestTimeout);
          break;
        default:
          throw ApiException('不支持的方法: $method');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('连接服务器超时：${_serverLabel(uri)}');
    } catch (e) {
      throw ApiException(
        '无法连接服务器 ${_serverLabel(uri)}：${_friendlyNetworkError(uri, e)}',
      );
    }

    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (raw.isEmpty) return const <String, dynamic>{};
      return _decodeJson(raw, path);
    }
    String detail = raw;
    try {
      final m = json.decode(raw);
      if (m is Map && m['detail'] != null) detail = m['detail'].toString();
    } catch (_) {}
    throw ApiException(
      await _buildHttpErrorMessage(
        resp.statusCode,
        detail,
        path,
        diagnoseMissingRoute: diagnoseMissingRoute,
      ),
    );
  }

  Uri _uriFor(String path) {
    if (baseUrl.isEmpty) return Uri.parse(path);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    var normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (_hasBackendApiPrefix(normalizedPath) &&
        normalizedBase.endsWith(
          String.fromCharCodes(const [47, 97, 112, 105]),
        )) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.length - 4);
    }
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  bool _hasBackendApiPrefix(String value) {
    if (value.length < 4) return false;
    return value.codeUnitAt(0) == 47 &&
        value.codeUnitAt(1) == 97 &&
        value.codeUnitAt(2) == 112 &&
        value.codeUnitAt(3) == 105 &&
        (value.length == 4 || value.codeUnitAt(4) == 47);
  }

  dynamic _decodeJson(String raw, String path) {
    try {
      return json.decode(raw);
    } catch (e) {
      throw ApiException('接口返回不是有效 JSON：$path');
    }
  }

  String _serverLabel(Uri uri) {
    if (uri.host.isEmpty) return uri.toString();
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String _friendlyNetworkError(Uri uri, Object error) {
    if (uri.host == 'duoyi.example.com') {
      return '当前仍是示例服务器地址，请在登录页填写实际服务器地址。';
    }
    final text = error.toString();
    if (text.contains('Failed host lookup')) return '域名无法解析';
    if (text.contains('Connection refused')) return '服务器拒绝连接';
    if (text.contains('No route to host')) return '网络不可达';
    return text;
  }

  Future<String> _buildHttpErrorMessage(
    int statusCode,
    String detail,
    String path, {
    bool diagnoseMissingRoute = true,
  }) async {
    final base = '$statusCode: $detail';
    if (!diagnoseMissingRoute ||
        !_isMissingRouteStatus(statusCode) ||
        !_hasBackendApiPrefix(path)) {
      return base;
    }
    if (!_looksLikeMissingRouteDetail(statusCode, detail)) return base;
    if (path == '/api/config') return base;
    final hint = await _backendContractHint(path);
    if (hint == null || hint.isEmpty) return base;
    return '$base\n$hint';
  }

  bool _isMissingRouteStatus(int statusCode) =>
      statusCode == 404 || statusCode == 405;

  bool _looksLikeMissingRouteDetail(int statusCode, String detail) {
    final normalized = detail.trim().toLowerCase();
    if (statusCode == 405) {
      return normalized == 'method not allowed' ||
          normalized == '{"detail":"method not allowed"}';
    }
    if (normalized.isEmpty) return true;
    if (normalized.startsWith('<!doctype html') ||
        normalized.startsWith('<html') ||
        normalized.contains('<title>404') ||
        normalized.contains('404 not found')) {
      return true;
    }
    return normalized == 'not found' ||
        normalized == '{"detail":"not found"}' ||
        normalized == 'route not found' ||
        normalized == '接口不存在';
  }

  Future<String?> _backendContractHint(String failedPath) async {
    final diagnosis = await _backendContractDiagnosisText();
    if (diagnosis == null || diagnosis.isEmpty) return null;
    return '当前后端未部署本版本接口：$failedPath。$diagnosis';
  }

  Future<String?> _backendContractDiagnosisText() async {
    if (_backendContractDiagnosisLoaded) return _backendContractDiagnosis;
    _backendContractDiagnosisLoaded = true;
    if (baseUrl.isEmpty && !kIsWeb) return null;
    final uri = _uriFor('/api/config');
    final configLabel = '${_serverLabel(uri)}${uri.path}';
    try {
      final response = await _httpClient
          .get(uri, headers: const {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _backendContractDiagnosis =
            '当前服务器 $configLabel 返回 ${response.statusCode}，可能是旧后端或反向代理未转发 /api/*。请部署当前 backend/main.py 后再重试。';
        return _backendContractDiagnosis;
      }
      final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        _backendContractDiagnosis =
            '当前服务器 $configLabel 没有返回 JSON 配置，可能被前端静态站或反向代理接管。请检查 /api/* 转发。';
        return _backendContractDiagnosis;
      }
      final contractVersion = decoded['api_contract_version']?.toString() ?? '';
      final routesHash = decoded['required_routes_hash']?.toString() ?? '';
      final features = decoded['features'];
      final missingContract = contractVersion.isEmpty;
      final outdatedContract =
          contractVersion.isNotEmpty &&
          contractVersion.compareTo(requiredApiContractVersion) < 0;
      final missingRoutesHash = routesHash.isEmpty;
      final mismatchedRoutesHash =
          routesHash.isNotEmpty && routesHash != requiredApiContractRoutesHash;
      if (!missingContract &&
          !outdatedContract &&
          !missingRoutesHash &&
          !mismatchedRoutesHash) {
        return null;
      }
      final serverVersion = decoded['version']?.toString();
      final featureSummary = features is Map
          ? features.entries
                .where((entry) => entry.value == true)
                .map((entry) => entry.key.toString())
                .join(', ')
          : '';
      final parts = <String>[
        '当前服务器 $configLabel。',
        if (serverVersion != null && serverVersion.isNotEmpty)
          '后端版本 $serverVersion。',
        if (missingContract)
          '缺少接口契约 api_contract_version。'
        else if (outdatedContract)
          '接口契约 $contractVersion 低于客户端要求 $requiredApiContractVersion。',
        if (missingRoutesHash)
          '缺少必备路由摘要 required_routes_hash。'
        else if (mismatchedRoutesHash)
          '必备路由摘要 $routesHash 与客户端要求 $requiredApiContractRoutesHash 不一致。',
        '请部署当前 backend/main.py 后再重试。',
        if (featureSummary.isNotEmpty) '已声明能力：$featureSummary。',
      ];
      _backendContractDiagnosis = parts.join('');
      return _backendContractDiagnosis;
    } catch (e) {
      _backendContractDiagnosis =
          '无法读取当前服务器 $configLabel：$e。可能是旧后端、接口未部署，或反向代理没有把 /api/* 转发到后端。';
      return _backendContractDiagnosis;
    }
  }

  MediaType? _contentTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return null;
  }

  String _shapeName(Object? value) {
    if (value == null) return 'null';
    if (value is List) return '列表';
    if (value is Map) return '对象';
    return value.runtimeType.toString();
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

const defaultUserVisibleBackendErrorMessage = '服务暂不可用，请稍后重试或联系管理员';

bool isBackendCompatibilityDiagnosticMessage(String message) =>
    message.contains('当前后端未部署本版本接口') ||
    message.contains('当前后端未部署本版本更新接口') ||
    message.contains('缺少接口契约 api_contract_version') ||
    (message.contains('接口契约') && message.contains('低于客户端要求')) ||
    message.contains('必备路由摘要') ||
    message.contains('required_routes_hash') ||
    message.contains('可能是旧后端') ||
    message.contains('反向代理未转发 /api/*');

String userVisibleApiError(
  Object error, {
  String fallbackMessage = defaultUserVisibleBackendErrorMessage,
}) {
  final message = error is ApiException ? error.message : error.toString();
  if (isBackendCompatibilityDiagnosticMessage(message)) {
    return fallbackMessage;
  }
  return message;
}
