import 'package:shared_preferences/shared_preferences.dart';

/// 只读/写 `ai_review_history` 这一个账号私有键的最小适配器。
///
/// 默认实现走 SharedPreferences；测试可以注入一个“写入阻塞/失败”的实现，
/// 用来验证存档失败不会被当成成功。不引入任何新依赖。
abstract class AiReviewHistoryStore {
  /// 既有账号私有历史键：登出/切号时由账号清理流程删除。
  static const String key = 'ai_review_history';

  Future<List<String>> read();

  /// 写入失败必须抛异常（不能静默成功）。
  Future<void> write(List<String> entries);
}

class AiReviewHistoryStoreException implements Exception {
  final String message;
  const AiReviewHistoryStoreException(this.message);

  @override
  String toString() => message;
}

/// 默认实现：写失败/被拒时先重载 SharedPreferences 的内存缓存，
/// 避免后续读取把未落盘的“推测缓存”当成已持久化内容。
class SharedPreferencesAiReviewHistoryStore extends AiReviewHistoryStore {
  SharedPreferencesAiReviewHistoryStore();

  @override
  Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AiReviewHistoryStore.key);
    if (raw == null) return const <String>[];
    return List<String>.of(raw);
  }

  @override
  Future<void> write(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = List<String>.of(entries);
    bool written;
    try {
      written = await prefs.setStringList(AiReviewHistoryStore.key, payload);
    } catch (error) {
      await _reloadQuietly(prefs);
      throw AiReviewHistoryStoreException(
        'ai review history write failed: $error',
      );
    }
    if (!written) {
      await _reloadQuietly(prefs);
      throw const AiReviewHistoryStoreException(
        'ai review history write was rejected',
      );
    }
  }

  Future<void> _reloadQuietly(SharedPreferences prefs) async {
    try {
      await prefs.reload();
    } catch (_) {
      // 重载失败也不能让调用方误以为写入成功。
    }
  }
}
