import 'dart:io';

import 'package:duoyi/services/app_update_installer.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统 DownloadManager 后台下载的状态机：启动、进度、完成、失败、取消、重启恢复。
///
/// 宿主机不是 Android，因此用 [debugForceAppUpdateBackgroundDownload]
/// 打开后台下载分支，并通过 `duoyi/update` 通道 mock 系统侧回答。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('duoyi/update');
  late List<MethodCall> calls;
  Map<String, Object?>? Function(MethodCall call)? responder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = <MethodCall>[];
    responder = null;
    debugForceAppUpdateBackgroundDownload = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responder?.call(call);
        });
  });

  tearDown(() {
    debugForceAppUpdateBackgroundDownload = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('快照解析区分五种状态与未知状态，失败不算完成', () {
    final running = AppUpdateDownloadSnapshot.fromChannel({
      'downloadId': 11,
      'status': 'running',
      'receivedBytes': 50,
      'totalBytes': 200,
      'localPath': null,
      'versionName': '2.0.1',
      'fileName': 'duoyi-2.0.1.apk',
      'url': 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
    });
    expect(running, isNotNull);
    expect(running!.status, AppUpdateDownloadStatus.running);
    expect(running.progress, 0.25);
    expect(running.hasDownloadedFile, isFalse);

    for (final status in ['pending', 'paused', 'success', 'failed']) {
      final snapshot = AppUpdateDownloadSnapshot.fromChannel({
        'downloadId': 1,
        'status': status,
      });
      expect(snapshot!.status.name, status);
    }

    final failed = AppUpdateDownloadSnapshot.fromChannel({
      'downloadId': 2,
      'status': 'failed',
      'receivedBytes': 200,
      'totalBytes': 200,
      'localPath': '/tmp/duoyi-2.0.1.apk',
    });
    expect(failed!.status.isSuccessful, isFalse);
    expect(failed.hasDownloadedFile, isFalse);

    final unknown = AppUpdateDownloadSnapshot.fromChannel({
      'downloadId': 3,
      'status': 'something-new',
    });
    expect(unknown!.status, AppUpdateDownloadStatus.unknown);
    expect(unknown.status.isSuccessful, isFalse);

    expect(
      AppUpdateDownloadSnapshot.fromChannel({'status': 'running'}),
      isNull,
    );
    expect(AppUpdateDownloadSnapshot.fromChannel(null), isNull);

    final noTotal = AppUpdateDownloadSnapshot.fromChannel({
      'downloadId': 4,
      'status': 'running',
      'receivedBytes': 10,
      'totalBytes': -1,
    });
    expect(noTotal!.progress, isNull);
    expect(noTotal.totalBytes, isNull);
  });

  test('启动下载立即返回，进度来自真实任务状态', () async {
    responder = (call) {
      switch (call.method) {
        case 'startBackgroundDownload':
          return {
            'downloadId': 7301,
            'status': 'running',
            'receivedBytes': 100,
            'totalBytes': 400,
            'versionName': '2.0.1',
            'fileName': 'duoyi-2.0.1.apk',
            'url': 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
          };
        case 'queryBackgroundDownload':
          return {
            'downloadId': 7301,
            'status': 'running',
            'receivedBytes': 200,
            'totalBytes': 400,
            'versionName': '2.0.1',
            'fileName': 'duoyi-2.0.1.apk',
            'url': 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
          };
      }
      return null;
    };
    final service = _serviceWithUpdate();
    addTearDown(service.dispose);

    await service.downloadAndInstallLatest(accentColor: 0xFFC85656);

    expect(calls.first.method, 'startBackgroundDownload');
    final startArgs = calls.first.arguments as Map;
    expect(startArgs['url'], 'https://cdn.duoyi.test/duoyi-2.0.1.apk');
    expect(startArgs['fileName'], 'duoyi-2.0.1.apk');
    expect(startArgs['accentColor'], 0xFFC85656);
    expect(service.downloading, isTrue);
    expect(service.downloadId, 7301);
    expect(service.backgroundDownloadActive, isTrue);
    expect(service.downloadProgress, 0.25);

    await service.debugPollDownloadForTest();

    expect(service.downloadProgress, 0.5);
    expect(service.hasDownloadedInstaller, isFalse);
  });

  test('下载成功后才算完成，失败状态不会被当成完成', () async {
    final tmp = await Directory.systemTemp.createTemp('duoyi_dm_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final apk = File('${tmp.path}/duoyi-2.0.1.apk');
    await apk.writeAsBytes(const [1, 2, 3]);

    responder = (call) {
      switch (call.method) {
        case 'startBackgroundDownload':
          return {'downloadId': 42, 'status': 'pending', 'receivedBytes': 0};
        case 'queryBackgroundDownload':
          return {
            'downloadId': 42,
            'status': 'success',
            'receivedBytes': 3,
            'totalBytes': 3,
            'localPath': apk.path,
            'versionName': '2.0.1',
            'fileName': 'duoyi-2.0.1.apk',
            'url': 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
          };
      }
      return null;
    };
    final service = _serviceWithUpdate();
    addTearDown(service.dispose);

    await service.downloadAndInstallLatest();
    expect(service.downloadCompleted, isFalse);

    await service.debugPollDownloadForTest();

    expect(service.downloadStatus?.isSuccessful, isTrue);
    expect(service.downloading, isFalse);
    expect(service.hasDownloadedInstaller, isTrue);
    expect(service.downloadedFilePath, apk.path);
    expect(service.error, isNull);

    responder = (call) => {
      'downloadId': 43,
      'status': 'failed',
      'receivedBytes': 0,
      'totalBytes': 100,
      'reason': 'failed:1006',
    };
    await service.debugPollDownloadForTest();

    expect(service.downloadStatus?.isFailed, isTrue);
    expect(service.downloadCompleted, isFalse);
    expect(service.downloading, isFalse);
    expect(service.downloadFailureReason, isNotNull);
    expect(service.error, isNotNull);
  });

  test('成功但文件缺失按失败处理，不会假完成', () async {
    responder = (call) {
      if (call.method == 'startBackgroundDownload') {
        return {'downloadId': 51, 'status': 'pending'};
      }
      return {
        'downloadId': 51,
        'status': 'success',
        'receivedBytes': 10,
        'totalBytes': 10,
        'localPath': '/nonexistent/duoyi-2.0.1.apk',
      };
    };
    final service = _serviceWithUpdate();
    addTearDown(service.dispose);

    await service.downloadAndInstallLatest();
    await service.debugPollDownloadForTest();

    expect(service.downloadStatus?.isFailed, isTrue);
    expect(service.hasDownloadedInstaller, isFalse);
    expect(service.downloading, isFalse);
    expect(service.downloadFailureReason, 'missing_file');
  });

  test('取消只删除当前任务并清空进度', () async {
    responder = (call) => call.method == 'startBackgroundDownload'
        ? {
            'downloadId': 61,
            'status': 'running',
            'receivedBytes': 10,
            'totalBytes': 100,
          }
        : null;
    final service = _serviceWithUpdate();
    addTearDown(service.dispose);

    await service.downloadAndInstallLatest();
    expect(service.downloading, isTrue);

    await service.cancelDownload();

    expect(calls.last.method, 'cancelBackgroundDownload');
    expect(service.downloading, isFalse);
    expect(service.downloadStatus, isNull);
    expect(service.downloadProgress, isNull);
    expect(service.downloadId, isNull);
  });

  test('服务重建后能从原生任务恢复进度', () async {
    responder = (call) => {
      'downloadId': 71,
      'status': 'paused',
      'receivedBytes': 30,
      'totalBytes': 60,
      'versionName': '2.0.1',
      'fileName': 'duoyi-2.0.1.apk',
      'url': 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
    };
    final service = AppUpdateService(
      repo: '',
      currentVersion: '2.0.0',
      currentVersionCode: 142023,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        throw const SocketException('offline');
      }),
    );
    addTearDown(service.dispose);

    await service.refreshDownloadState();

    expect(calls.single.method, 'queryBackgroundDownload');
    expect(service.backgroundDownloadActive, isTrue);
    expect(service.downloading, isTrue);
    expect(service.downloadProgress, 0.5);
    expect(service.downloadId, 71);
    expect(service.latestVersion, '2.0.1');
  });

  test('不会重复创建同一个下载任务', () async {
    responder = (call) => {
      'downloadId': 81,
      'status': 'running',
      'receivedBytes': 10,
      'totalBytes': 100,
    };
    final service = _serviceWithUpdate();
    addTearDown(service.dispose);

    await service.downloadAndInstallLatest();
    await service.downloadAndInstallLatest();
    await service.startBackgroundDownload();

    final starts = calls
        .where((call) => call.method == 'startBackgroundDownload')
        .length;
    expect(starts, 1);
  });
}

AppUpdateService _serviceWithUpdate() {
  final service =
      AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          throw const SocketException('offline');
        }),
      )..debugSetUpdatePolicyForTest(
        latestVersion: '2.0.1',
        latestVersionCode: 200001,
        minimumSupportedVersion: '2.0.0',
        forceUpdateRequired: true,
        latestUrl: 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
      );
  return service;
}
