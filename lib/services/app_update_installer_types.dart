/// 应用内更新下载的共享类型。
///
/// Android 端由系统 DownloadManager 在后台下载，Flutter 只通过
/// `duoyi/update` 通道查询任务状态；其它平台仍走页内 http 流。
library;

typedef AppUpdateProgress = void Function(int receivedBytes, int? totalBytes);

/// 更新通知/进度的默认强调色（多仪品牌红 #C85656）。
const int defaultAppUpdateAccentColor = 0xFFC85656;

/// 仅测试使用：强制把「系统后台下载」视为可用，以便在宿主平台
/// （flutter test 跑在 macOS/Linux）上通过 MethodChannel mock 验证状态机。
/// 生产运行时不设置，默认 false，不影响真实平台能力判断。
bool debugForceAppUpdateBackgroundDownload = false;

/// 系统下载任务的真实状态。
///
/// 只有 [success] 才算完成；[failed] 永远不能当成完成，
/// 无法识别的状态落在 [unknown]，既不算完成也不算失败。
enum AppUpdateDownloadStatus {
  pending,
  running,
  paused,
  success,
  failed,
  unknown;

  static AppUpdateDownloadStatus parse(Object? raw) {
    switch ((raw ?? '').toString().trim().toLowerCase()) {
      case 'pending':
        return AppUpdateDownloadStatus.pending;
      case 'running':
        return AppUpdateDownloadStatus.running;
      case 'paused':
        return AppUpdateDownloadStatus.paused;
      case 'success':
        return AppUpdateDownloadStatus.success;
      case 'failed':
        return AppUpdateDownloadStatus.failed;
      default:
        return AppUpdateDownloadStatus.unknown;
    }
  }

  bool get isActive =>
      this == AppUpdateDownloadStatus.pending ||
      this == AppUpdateDownloadStatus.running ||
      this == AppUpdateDownloadStatus.paused;

  bool get isSuccessful => this == AppUpdateDownloadStatus.success;

  bool get isFailed => this == AppUpdateDownloadStatus.failed;
}

/// 一个系统下载任务的快照。
class AppUpdateDownloadSnapshot {
  final int downloadId;
  final AppUpdateDownloadStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final String? localPath;
  final String? reason;
  final String? versionName;
  final String? fileName;
  final String? url;

  const AppUpdateDownloadSnapshot({
    required this.downloadId,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes,
    this.localPath,
    this.reason,
    this.versionName,
    this.fileName,
    this.url,
  });

  /// 真实进度；总量未知时返回 null，UI 应显示不确定进度条。
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0 || receivedBytes < 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  /// 已完成且本地文件路径存在时才算拿到安装包。
  bool get hasDownloadedFile {
    final path = localPath?.trim() ?? '';
    return status.isSuccessful && path.isNotEmpty;
  }

  String? get trimmedLocalPath {
    final path = localPath?.trim() ?? '';
    return path.isEmpty ? null : path;
  }

  /// 从原生返回的 Map 解析快照；结构不认识时返回 null。
  static AppUpdateDownloadSnapshot? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final downloadId = _intValue(raw['downloadId']);
    if (downloadId == null || downloadId <= 0) return null;
    final total = _intValue(raw['totalBytes']);
    return AppUpdateDownloadSnapshot(
      downloadId: downloadId,
      status: AppUpdateDownloadStatus.parse(raw['status']),
      receivedBytes: _intValue(raw['receivedBytes']) ?? 0,
      totalBytes: total != null && total > 0 ? total : null,
      localPath: _stringValue(raw['localPath']),
      reason: _stringValue(raw['reason']),
      versionName: _stringValue(raw['versionName']),
      fileName: _stringValue(raw['fileName']),
      url: _stringValue(raw['url']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim());
  }

  static String? _stringValue(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}
