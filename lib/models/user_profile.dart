class UserProfile {
  /// 历史默认占位名：未设置昵称时沿用它，展示层应换成本地化默认名。
  static const defaultUsername = '用户';

  String username;
  String avatarInitials;
  String displayName;
  String email;
  bool emailVerified;
  String avatarUrl;
  String bio;
  int totalTodosCompleted;
  int totalFocusMinutes;
  int currentStreak;
  int bestStreak;
  DateTime? updatedAt;
  DateTime? lastSyncTime;

  UserProfile({
    this.username = defaultUsername,
    this.avatarInitials = '我',
    this.displayName = '',
    this.email = '',
    this.emailVerified = false,
    this.avatarUrl = '',
    this.bio = '',
    this.totalTodosCompleted = 0,
    this.totalFocusMinutes = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.updatedAt,
    this.lastSyncTime,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'avatarInitials': avatarInitials,
    'displayName': displayName,
    'email': email,
    'emailVerified': emailVerified,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'totalTodosCompleted': totalTodosCompleted,
    'totalFocusMinutes': totalFocusMinutes,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
    'updatedAt': updatedAt?.toIso8601String(),
    'lastSyncTime': lastSyncTime?.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    username: json['username'] ?? defaultUsername,
    avatarInitials: json['avatarInitials'] ?? '我',
    displayName: json['displayName'] ?? '',
    email: json['email'] ?? '',
    emailVerified: json['emailVerified'] == true,
    avatarUrl: json['avatarUrl'] ?? '',
    bio: json['bio'] ?? '',
    totalTodosCompleted: json['totalTodosCompleted'] ?? 0,
    totalFocusMinutes: json['totalFocusMinutes'] ?? 0,
    currentStreak: json['currentStreak'] ?? 0,
    bestStreak: json['bestStreak'] ?? 0,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'])
        : null,
    lastSyncTime: json['lastSyncTime'] != null
        ? DateTime.parse(json['lastSyncTime'])
        : null,
  );

  /// 展示用昵称，优先级与「我的」页一致：
  /// 账号显示名 [preferredDisplayName] → 本地 [displayName] → 账号用户名，
  /// 再回落本地 [username]；未设置时使用本地化 [fallbackName]。
  /// 首尾空白视为未设置，避免把空白/纯空格当成昵称。
  String effectiveDisplayName(
    String fallbackName, {
    String? preferredDisplayName,
    String? preferredUsername,
  }) {
    for (final candidate in <String?>[preferredDisplayName, displayName]) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    for (final candidate in <String?>[preferredUsername, username]) {
      final accountName = candidate?.trim() ?? '';
      if (accountName.isNotEmpty && accountName != defaultUsername) {
        return accountName;
      }
    }
    return fallbackName.trim();
  }

  int get productivityScore {
    int score = 0;
    score += (totalTodosCompleted * 2).clamp(0, 30);
    score += (totalFocusMinutes ~/ 60 * 3).clamp(0, 30);
    score += (currentStreak * 5).clamp(0, 25);
    score += (bestStreak * 2).clamp(0, 15);
    return score.clamp(0, 100);
  }
}
