import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_update_installer_types.dart';

export 'app_update_installer_types.dart';

class AppUpdateInstaller {
  static const _channel = MethodChannel('duoyi/update');

  static bool get supportsInstall {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Android 用系统 DownloadManager 在后台下载；其它平台没有该能力。
  static bool get supportsBackgroundDownload => supportsInstall;

  static Future<String> downloadApk({
    required String url,
    required String fileName,
    required AppUpdateProgress onProgress,
  }) async {
    final dir = Directory('${Directory.systemTemp.path}/duoyi_updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safeName');
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'duoyi/update'
        ..headers['Accept'] = 'application/vnd.android.package-archive,*/*';
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载失败: HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return file.path;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  /// 交给系统 DownloadManager 在一个独立进程里下载。
  ///
  /// 立即返回首个任务快照，进度/结果由之后的 [queryBackgroundDownload] 查询。
  static Future<AppUpdateDownloadSnapshot?> startBackgroundDownload({
    required String url,
    required String fileName,
    required String versionName,
    int? versionCode,
    required int accentColor,
    required String notificationTitle,
    required String notificationText,
    required String installActionLabel,
    required String channelName,
    required String channelDescription,
  }) async {
    if (!_backgroundDownloadAllowed) {
      throw UnsupportedError('当前平台不支持系统后台下载更新');
    }
    final target = Uri.tryParse(url.trim());
    if (target == null ||
        !(target.isScheme('https') || target.isScheme('http'))) {
      throw ArgumentError.value(url, 'url', '只支持 http/https 下载地址');
    }
    final raw = await _channel
        .invokeMapMethod<String, Object?>('startBackgroundDownload', {
          'url': url.trim(),
          'fileName': _safeApkFileName(fileName, versionName),
          'versionName': versionName,
          'versionCode': versionCode,
          'accentColor': accentColor,
          'notificationTitle': notificationTitle,
          'notificationText': notificationText,
          'installActionLabel': installActionLabel,
          'channelName': channelName,
          'channelDescription': channelDescription,
        });
    return AppUpdateDownloadSnapshot.fromChannel(raw);
  }

  /// 查询本应用自己持有的下载任务；没有任务时返回 null。
  static Future<AppUpdateDownloadSnapshot?> queryBackgroundDownload() async {
    if (!_backgroundDownloadAllowed) return null;
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'queryBackgroundDownload',
    );
    return AppUpdateDownloadSnapshot.fromChannel(raw);
  }

  /// 只取消本应用当前的下载任务。
  static Future<void> cancelBackgroundDownload() async {
    if (!_backgroundDownloadAllowed) return;
    await _channel.invokeMethod<void>('cancelBackgroundDownload');
  }

  static bool get _backgroundDownloadAllowed =>
      supportsBackgroundDownload || debugForceAppUpdateBackgroundDownload;

  static String _safeApkFileName(String fileName, String versionName) {
    final cleaned = fileName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    final base = cleaned.isEmpty
        ? 'duoyi-${versionName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.apk'
        : cleaned;
    final withExtension = base.toLowerCase().endsWith('.apk')
        ? base
        : '$base.apk';
    return withExtension.length > 96
        ? withExtension.substring(withExtension.length - 96)
        : withExtension;
  }

  static Future<bool> canInstallPackages() async {
    if (!supportsInstall) return false;
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    if (!supportsInstall) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<bool> downloadedFileExists(String path) async {
    if (path.trim().isEmpty) return false;
    return File(path).exists();
  }

  static Future<void> installApk(String path) async {
    if (!supportsInstall) {
      throw UnsupportedError('当前平台不支持应用内安装 APK');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
