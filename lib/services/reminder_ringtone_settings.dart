import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform_info.dart';
import 'native_reminder_ringtone.dart';
import 'reminder_ringtone_preview_service.dart';

enum ReminderRingtonePlatformMode {
  androidNative,
  appleSystemTimeSensitive,
  desktopSystemNotification,
  unsupported,
}

class ReminderRingtonePlatformPolicy {
  final ReminderRingtonePlatformMode mode;
  final bool supportsBuiltInSoundPicker;
  final bool supportsVolumePresets;
  final bool usesSystemNotificationSound;
  final String sectionSubtitleKey;
  final String tileTitleKey;
  final String tileSubtitleKey;

  const ReminderRingtonePlatformPolicy({
    required this.mode,
    required this.supportsBuiltInSoundPicker,
    required this.supportsVolumePresets,
    required this.usesSystemNotificationSound,
    required this.sectionSubtitleKey,
    required this.tileTitleKey,
    required this.tileSubtitleKey,
  });
}

class ReminderRingtoneSettings {
  ReminderRingtoneSettings._();

  static const String volumePreferenceKey =
      'pref_reminder_ringtone_volume_percent';
  static const String soundPreferenceKey = 'pref_reminder_ringtone_sound';
  static const String fallbackChannelSoundPreferencePrefix =
      'pref_reminder_ringtone_fallback_channel_sound_';
  static const String fallbackChannelSoundSchemaPreferencePrefix =
      'pref_reminder_ringtone_fallback_channel_sound_schema_';
  static const String legacyAlarmMigrationPreferenceKey =
      'pref_reminder_ringtone_alarm_migrated_to_soft';
  static const int androidFallbackChannelSoundSchemaVersion = 2;
  static const int defaultVolumePercent = 60;
  static const String defaultSound = 'soft';

  static const List<int> presets = <int>[40, 60, 80];
  static const List<ReminderRingtoneOption> sounds = <ReminderRingtoneOption>[
    ReminderRingtoneOption(id: 'soft', label: '柔和晨铃'),
    ReminderRingtoneOption(id: 'forest', label: '林间晨露'),
    ReminderRingtoneOption(id: 'silver', label: '银铃微光'),
    ReminderRingtoneOption(id: 'paper', label: '纸页轻响'),
    ReminderRingtoneOption(id: 'stream', label: '溪流短铃'),
    ReminderRingtoneOption(id: 'star', label: '星光提示'),
    ReminderRingtoneOption(id: 'marimba', label: '远山木琴'),
    ReminderRingtoneOption(id: 'lull', label: '轻柔和弦'),
    ReminderRingtoneOption(id: 'glass', label: '玻璃轻响'),
    ReminderRingtoneOption(id: 'bamboo', label: '竹影轻铃'),
    ReminderRingtoneOption(id: 'dawn', label: '晨光木琴'),
    ReminderRingtoneOption(id: 'wood', label: '木鱼轻点'),
    ReminderRingtoneOption(id: 'water', label: '水滴轻提示'),
    ReminderRingtoneOption(id: 'harp', label: '竖琴三音'),
    ReminderRingtoneOption(id: 'mist', label: '薄雾和铃'),
    ReminderRingtoneOption(id: 'pebble', label: '卵石轻响'),
    ReminderRingtoneOption(id: 'tide', label: '潮汐和弦'),
    ReminderRingtoneOption(id: 'chime', label: '苹果经典轻铃'),
    ReminderRingtoneOption(id: 'bell', label: '小米轻铃'),
    ReminderRingtoneOption(id: 'morning', label: '清晨三音'),
    ReminderRingtoneOption(id: 'pearl', label: '珍珠轻提示'),
    ReminderRingtoneOption(id: 'cedar', label: '雪松轻铃'),
    ReminderRingtoneOption(id: 'moon', label: '月光三音'),
    ReminderRingtoneOption(id: 'cloud', label: '云端轻响'),
    ReminderRingtoneOption(id: 'sakura', label: '樱花短铃'),
    ReminderRingtoneOption(id: 'classic', label: '经典闹钟柔和版'),
    ReminderRingtoneOption(id: 'beep', label: '短促提示音'),
    ReminderRingtoneOption(id: 'alarm', label: '强提醒闹钟'),
  ];

  static const MethodChannel _channel = MethodChannel(
    'duoyi/reminder_ringtone',
  );
  static FutureOr<void> Function(Iterable<String> keys)? onChanged;

  static ReminderRingtonePlatformPolicy get platformPolicy => platformPolicyFor(
    isAndroid: PlatformInfo.isAndroid,
    isIOS: PlatformInfo.isIOS,
    isMacOS: PlatformInfo.isMacOS,
    isLinux: PlatformInfo.isLinux,
    isWindows: PlatformInfo.isWindows,
  );

  @visibleForTesting
  static ReminderRingtonePlatformPolicy platformPolicyFor({
    required bool isAndroid,
    required bool isIOS,
    required bool isMacOS,
    required bool isLinux,
    required bool isWindows,
  }) {
    if (isAndroid) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.androidNative,
        supportsBuiltInSoundPicker: true,
        supportsVolumePresets: true,
        usesSystemNotificationSound: false,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.android',
        tileTitleKey: 'preferences.ringtone.sound',
        tileSubtitleKey: 'preferences.ringtone.section.subtitle.android',
      );
    }
    if (isIOS || isMacOS) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.appleSystemTimeSensitive,
        supportsBuiltInSoundPicker: false,
        supportsVolumePresets: false,
        usesSystemNotificationSound: true,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.apple',
        tileTitleKey: 'preferences.ringtone.system_sound',
        tileSubtitleKey: 'preferences.ringtone.system_sound.subtitle.apple',
      );
    }
    if (isLinux || isWindows) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.desktopSystemNotification,
        supportsBuiltInSoundPicker: false,
        supportsVolumePresets: false,
        usesSystemNotificationSound: true,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.desktop',
        tileTitleKey: 'preferences.ringtone.system_sound',
        tileSubtitleKey: 'preferences.ringtone.system_sound.subtitle.desktop',
      );
    }
    return const ReminderRingtonePlatformPolicy(
      mode: ReminderRingtonePlatformMode.unsupported,
      supportsBuiltInSoundPicker: false,
      supportsVolumePresets: false,
      usesSystemNotificationSound: false,
      sectionSubtitleKey: 'preferences.ringtone.section.subtitle.unsupported',
      tileTitleKey: 'preferences.ringtone.unsupported',
      tileSubtitleKey: 'preferences.ringtone.unsupported.subtitle',
    );
  }

  static Future<int> loadVolumePercent() async {
    final p = await SharedPreferences.getInstance();
    return _normalizeVolume(
      p.getInt(volumePreferenceKey) ?? defaultVolumePercent,
    );
  }

  static Future<String> loadSound() async {
    final p = await SharedPreferences.getInstance();
    return _loadAndMigrateSoundPreference(p);
  }

  static String androidRawResourceNameFor(String value) {
    return 'duoyi_${_normalizeSound(value)}';
  }

  static Future<String> loadAndroidRawResourceName() async {
    return androidRawResourceNameFor(await loadSound());
  }

  static Future<bool> androidFallbackChannelSoundNeedsRefresh(
    String channelId,
    String nextRawResourceName,
  ) async {
    final p = await SharedPreferences.getInstance();
    final key = _fallbackChannelSoundPreferenceKey(channelId);
    final schemaKey = _fallbackChannelSoundSchemaPreferenceKey(channelId);
    final previous = p.getString(key);
    final schemaVersion = p.getInt(schemaKey);
    return previous != nextRawResourceName ||
        schemaVersion != androidFallbackChannelSoundSchemaVersion;
  }

  static Future<void> markAndroidFallbackChannelSoundApplied(
    String channelId,
    String rawResourceName,
  ) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _fallbackChannelSoundPreferenceKey(channelId),
      rawResourceName,
    );
    await p.setInt(
      _fallbackChannelSoundSchemaPreferenceKey(channelId),
      androidFallbackChannelSoundSchemaVersion,
    );
  }

  static Future<void> setVolumePercent(int value, {bool preview = true}) async {
    final next = _normalizeVolume(value);
    final p = await SharedPreferences.getInstance();
    await p.setInt(volumePreferenceKey, next);
    await onChanged?.call(const [volumePreferenceKey]);
    if (!preview) {
      await applyPersistedSettingsToNative();
      return;
    }
    await _applyAndPreviewCurrentSound();
  }

  static Future<void> setSound(String value, {bool preview = true}) async {
    final next = _normalizeSound(value);
    final p = await SharedPreferences.getInstance();
    await p.setBool(legacyAlarmMigrationPreferenceKey, true);
    await p.setString(soundPreferenceKey, next);
    await onChanged?.call(const [soundPreferenceKey]);
    if (!preview) {
      await applyPersistedSettingsToNative();
      return;
    }
    await _applyAndPreviewCurrentSound();
  }

  static Future<void> previewCurrentSound() async {
    if (!_isAndroid) return;
    await _applyAndPreviewCurrentSound();
  }

  static Future<bool> applyPersistedSettingsToNative() async {
    if (!_isAndroid) return true;
    final p = await SharedPreferences.getInstance();
    final volumePercent = _normalizeVolume(
      p.getInt(volumePreferenceKey) ?? defaultVolumePercent,
    );
    final soundName = _normalizeSound(await _loadAndMigrateSoundPreference(p));
    try {
      await _channel.invokeMethod<void>('setVolumePercent', <String, Object?>{
        'volumePercent': volumePercent,
      });
      await _channel.invokeMethod<void>('setSoundName', <String, Object?>{
        'soundName': soundName,
      });
      return true;
    } catch (e, st) {
      debugPrint(
        '[ReminderRingtoneSettings] apply persisted settings failed: $e\n$st',
      );
      return false;
    }
  }

  static Future<void> _applyAndPreviewCurrentSound() async {
    if (!_isAndroid) return;
    final p = await SharedPreferences.getInstance();
    final volumePercent = _normalizeVolume(
      p.getInt(volumePreferenceKey) ?? defaultVolumePercent,
    );
    final soundName = _normalizeSound(await _loadAndMigrateSoundPreference(p));
    final nativeSettingsApplied = await applyPersistedSettingsToNative();
    String? nativeFailureMessage;
    String? nativeFailureReason;
    if (nativeSettingsApplied) {
      final nativePreview = await NativeReminderRingtone.previewCurrentSound(
        duration: NativeReminderRingtone.previewDuration,
      );
      if (nativePreview.started) {
        debugPrint(
          '[ReminderRingtoneSettings] native MediaPlayer preview started '
          'sound=$soundName volume=$volumePercent reason=${nativePreview.reason}',
        );
        return;
      }
      nativeFailureReason = nativePreview.reason;
      nativeFailureMessage = nativePreview.message;
      if (nativePreview.reason == 'active_reminder_ringing') {
        throw ReminderRingtonePreviewException(
          reason: nativePreview.reason,
          message: nativePreview.message,
        );
      }
      debugPrint(
        '[ReminderRingtoneSettings] native MediaPlayer preview failed '
        'sound=$soundName volume=$volumePercent reason=${nativePreview.reason} '
        'message=${nativePreview.message}; trying Flutter media fallback.',
      );
    } else {
      debugPrint(
        '[ReminderRingtoneSettings] native apply failed before preview '
        'sound=$soundName volume=$volumePercent; trying Flutter media fallback.',
      );
    }
    final flutterPreviewStarted = await ReminderRingtonePreviewService.instance
        .preview(
          soundName: soundName,
          volumePercent: volumePercent,
          duration: NativeReminderRingtone.previewDuration,
        );
    if (flutterPreviewStarted) {
      debugPrint(
        '[ReminderRingtoneSettings] Flutter media preview started '
        'sound=$soundName volume=$volumePercent',
      );
      return;
    }
    debugPrint(
      '[ReminderRingtoneSettings] Flutter media preview failed '
      'sound=$soundName volume=$volumePercent.',
    );
    throw ReminderRingtonePreviewException(
      reason: nativeFailureReason ?? 'native_and_flutter_preview_failed',
      message: nativeFailureMessage ?? '铃声试听启动失败，请重试。',
    );
  }

  static Future<void> stopPreview() async {
    await ReminderRingtonePreviewService.instance.stop();
    if (!_isAndroid) return;
    try {
      await NativeReminderRingtone.stopPreview();
    } catch (e, st) {
      debugPrint('[ReminderRingtoneSettings] stop preview failed: $e\n$st');
    }
  }

  static Future<String> _loadAndMigrateSoundPreference(
    SharedPreferences preferences,
  ) async {
    final stored = preferences.getString(soundPreferenceKey);
    if (stored == 'alarm' &&
        preferences.getBool(legacyAlarmMigrationPreferenceKey) != true) {
      await preferences.setBool(legacyAlarmMigrationPreferenceKey, true);
      await preferences.setString(soundPreferenceKey, defaultSound);
      await onChanged?.call(const [soundPreferenceKey]);
      return defaultSound;
    }
    return _normalizeSound(stored ?? defaultSound);
  }

  static int _normalizeVolume(int value) {
    if (value <= 40) return 40;
    if (value <= 60) return 60;
    return 80;
  }

  static String _normalizeSound(String value) {
    return sounds.any((s) => s.id == value) ? value : defaultSound;
  }

  static String _fallbackChannelSoundPreferenceKey(String channelId) {
    return '$fallbackChannelSoundPreferencePrefix$channelId';
  }

  static String _fallbackChannelSoundSchemaPreferenceKey(String channelId) {
    return '$fallbackChannelSoundSchemaPreferencePrefix$channelId';
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    return PlatformInfo.isAndroid;
  }
}

class ReminderRingtonePreviewException implements Exception {
  final String reason;
  final String message;

  const ReminderRingtonePreviewException({
    this.reason = 'unknown',
    this.message = '铃声试听启动失败，请检查系统音量或音频播放限制。',
  });

  @override
  String toString() => message;
}

class ReminderRingtoneOption {
  final String id;
  final String label;

  const ReminderRingtoneOption({required this.id, required this.label});
}
