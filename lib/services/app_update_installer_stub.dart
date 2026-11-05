export 'app_update_installer_types.dart';

import 'app_update_installer_types.dart';

/// 非 Android 平台的占位实现：不支持应用内安装，也不支持系统后台下载。
class AppUpdateInstaller {
  static const bool supportsInstall = false;

  static const bool supportsBackgroundDownload = false;

  static Future<String> downloadApk({
    required String url,
    required String fileName,
    required AppUpdateProgress onProgress,
  }) {
    throw UnsupportedError('当前平台不支持应用内下载更新');
  }

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
  }) {
    throw UnsupportedError('当前平台不支持系统后台下载更新');
  }

  static Future<AppUpdateDownloadSnapshot?> queryBackgroundDownload() async =>
      null;

  static Future<void> cancelBackgroundDownload() async {}

  static Future<bool> canInstallPackages() async => false;

  static Future<void> openInstallPermissionSettings() async {}

  static Future<bool> downloadedFileExists(String path) async => false;

  static Future<void> installApk(String path) {
    throw UnsupportedError('当前平台不支持应用内安装 APK');
  }
}
