/// Identity of the application's initial public release channel.
/// Versions are only comparable inside the same release channel.
class AppReleaseChannel {
  static const repository = 'skydrow98/duoyi';

  static String normalizeRepository(String value) => value.trim().toLowerCase();

  /// These historical public distribution names now refer to the initial
  /// release channel. Other forks and an explicitly disabled source are kept.
  static String resolveConfiguredRepository(String value) {
    final normalized = normalizeRepository(value);
    return const {'ioppe/duoyi', 'dq52099/duoyi'}.contains(normalized)
        ? repository
        : value.trim();
  }

  static String? repositoryFromUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority) return null;
    final segments = uri.pathSegments;
    if (uri.host.toLowerCase() == 'github.com' && segments.length >= 2) {
      return normalizeRepository('${segments[0]}/${segments[1]}');
    }
    if (uri.host.toLowerCase() == 'api.github.com' &&
        segments.length >= 3 &&
        segments[0] == 'repos') {
      return normalizeRepository('${segments[1]}/${segments[2]}');
    }
    return null;
  }

  /// Unknown/CDN origins retain the server's configured update policy.
  static bool conflictsWithOfficialChannel(String configured, String source) {
    if (normalizeRepository(configured) != repository) return false;
    final other = repositoryFromUrl(source);
    return other != null && other != repository;
  }
}
