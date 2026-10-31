import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:duoyi/services/reminder_ringtone_settings.dart';
import 'package:duoyi/services/reminder_ringtone_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ReminderRingtoneSettings.onChanged = null;
  });

  tearDown(() {
    ReminderRingtoneSettings.onChanged = null;
  });

  test('loads defaults when ringtone settings are absent', () async {
    expect(
      await ReminderRingtoneSettings.loadVolumePercent(),
      ReminderRingtoneSettings.defaultVolumePercent,
    );
    expect(ReminderRingtoneSettings.defaultVolumePercent, 60);
    expect(
      ReminderRingtoneSettings.defaultSound,
      isNot('alarm'),
      reason: '默认提醒铃声应使用柔和铃声，不能默认强提醒警报',
    );
    expect(
      ReminderRingtoneSettings.defaultSound,
      'soft',
      reason: '默认提醒铃声使用柔和晨铃，避免新用户第一次提醒像警报。',
    );
    expect(
      await ReminderRingtoneSettings.loadSound(),
      ReminderRingtoneSettings.defaultSound,
    );
  });

  test('persists preset volume and selected ringtone', () async {
    await ReminderRingtoneSettings.setVolumePercent(80);
    await ReminderRingtoneSettings.setSound('classic', preview: false);

    expect(await ReminderRingtoneSettings.loadVolumePercent(), 80);
    expect(await ReminderRingtoneSettings.loadSound(), 'classic');
  });

  for (final operation in ['volume', 'sound']) {
    test('$operation 保存等待同步标记回调完成', () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      ReminderRingtoneSettings.onChanged = (_) {
        entered.complete();
        return gate.future;
      };
      var finished = false;
      final saved =
          (operation == 'volume'
                  ? ReminderRingtoneSettings.setVolumePercent(
                      80,
                      preview: false,
                    )
                  : ReminderRingtoneSettings.setSound('bell', preview: false))
              .then((_) => finished = true);
      await entered.future;
      expect(finished, isFalse);
      final prefs = await SharedPreferences.getInstance();
      if (operation == 'volume') {
        expect(prefs.getInt(ReminderRingtoneSettings.volumePreferenceKey), 80);
      } else {
        expect(
          prefs.getString(ReminderRingtoneSettings.soundPreferenceKey),
          'bell',
        );
      }
      gate.complete();
      await saved;
      expect(finished, isTrue);
    });
  }

  test(
    'migrates legacy alarm default to soft once without blocking opt-in',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ReminderRingtoneSettings.soundPreferenceKey,
        'alarm',
      );

      expect(
        await ReminderRingtoneSettings.loadSound(),
        ReminderRingtoneSettings.defaultSound,
      );
      expect(
        prefs.getBool(
          ReminderRingtoneSettings.legacyAlarmMigrationPreferenceKey,
        ),
        isTrue,
      );
      expect(
        prefs.getString(ReminderRingtoneSettings.soundPreferenceKey),
        ReminderRingtoneSettings.defaultSound,
      );

      await ReminderRingtoneSettings.setSound('alarm', preview: false);

      expect(await ReminderRingtoneSettings.loadSound(), 'alarm');
    },
  );

  test('normalizes unsupported volume and ringtone values', () async {
    await ReminderRingtoneSettings.setVolumePercent(73);
    await ReminderRingtoneSettings.setSound('missing', preview: false);

    expect(await ReminderRingtoneSettings.loadVolumePercent(), 80);
    expect(
      await ReminderRingtoneSettings.loadSound(),
      ReminderRingtoneSettings.defaultSound,
    );
  });

  test('exposes multiple named ringtone options beyond volume presets', () {
    expect(
      ReminderRingtoneSettings.sounds.map((sound) => sound.id),
      containsAll(<String>[
        'soft',
        'forest',
        'silver',
        'paper',
        'stream',
        'star',
        'marimba',
        'lull',
        'glass',
        'bamboo',
        'dawn',
        'wood',
        'water',
        'harp',
        'mist',
        'pebble',
        'tide',
        'alarm',
        'chime',
        'bell',
        'morning',
        'pearl',
        'cedar',
        'moon',
        'cloud',
        'sakura',
        'beep',
        'classic',
      ]),
    );
    expect(ReminderRingtoneSettings.sounds.first.id, 'soft');
    expect(ReminderRingtoneSettings.sounds.first.label, '柔和晨铃');
    expect(
      ReminderRingtoneSettings.sounds
          .firstWhere((sound) => sound.id == 'forest')
          .label,
      '林间晨露',
    );
    expect(
      ReminderRingtoneSettings.sounds
          .firstWhere((sound) => sound.id == 'classic')
          .label,
      '经典闹钟柔和版',
    );
    expect(ReminderRingtoneSettings.sounds.length, greaterThanOrEqualTo(24));
    expect(ReminderRingtoneSettings.presets, <int>[40, 60, 80]);
  });

  test('new gentle built-in ringtones use stable Android raw names', () {
    const newSounds = <String, String>{
      'forest': '林间晨露',
      'silver': '银铃微光',
      'paper': '纸页轻响',
      'stream': '溪流短铃',
      'star': '星光提示',
      'marimba': '远山木琴',
      'cedar': '雪松轻铃',
      'moon': '月光三音',
      'cloud': '云端轻响',
      'sakura': '樱花短铃',
    };
    final labelsById = {
      for (final sound in ReminderRingtoneSettings.sounds)
        sound.id: sound.label,
    };
    final rawFileNames = Directory('android/app/src/main/res/raw')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();

    expect(labelsById['soft'], '柔和晨铃');
    expect(
      ReminderRingtoneSettings.androidRawResourceNameFor(
        ReminderRingtoneSettings.defaultSound,
      ),
      'duoyi_soft',
    );
    for (final entry in newSounds.entries) {
      expect(labelsById[entry.key], entry.value);
      expect(
        ReminderRingtoneSettings.androidRawResourceNameFor(entry.key),
        'duoyi_${entry.key}',
      );
      expect(rawFileNames, contains('duoyi_${entry.key}.wav'));
    }
  });

  test('ringtone changes use native preview with Flutter asset fallback', () {
    final source = File(
      'lib/services/reminder_ringtone_settings.dart',
    ).readAsStringSync();
    final previewService = File(
      'lib/services/reminder_ringtone_preview_service.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final native = File(
      'lib/services/native_reminder_ringtone.dart',
    ).readAsStringSync();

    expect(source, contains('setSound(String value, {bool preview = true})'));
    expect(source, contains('await _applyAndPreviewCurrentSound();'));
    expect(source, contains('ReminderRingtonePreviewException'));
    expect(source, contains('native_and_flutter_preview_failed'));
    expect(source, contains('铃声试听启动失败，请重试。'));
    expect(source, isNot(contains('播放器调用失败')));
    expect(source, isNot(contains('fellBackToDefault')));
    expect(source, isNot(contains('已尝试降级')));
    expect(source, isNot(contains('默认轻铃')));
    expect(
      source,
      contains(
        'final nativeSettingsApplied = await applyPersistedSettingsToNative();',
      ),
    );
    expect(source, contains('ReminderRingtonePreviewService.instance'));
    expect(source, contains('flutterPreviewStarted'));
    expect(source, contains('native MediaPlayer preview started'));
    expect(
      source,
      contains('NativeReminderRingtone.previewCurrentSound('),
      reason: 'Android 试听应优先使用原生 MediaPlayer 直接播放 raw 资源。',
    );
    expect(
      source.indexOf('NativeReminderRingtone.previewCurrentSound('),
      lessThan(source.indexOf('ReminderRingtonePreviewService.instance')),
      reason: '设置页 Android 试听先走 native direct preview，Flutter 媒体播放只作为兜底。',
    );
    expect(
      ReminderRingtonePreviewService.assetPathFor('soft'),
      'sounds/reminders/duoyi_soft.wav',
    );
    expect(previewService, contains("import 'focus_sound_service.dart';"));
    expect(previewService, contains('FocusSoundService.mediaAudioContext'));
    expect(previewService, contains('focus.previewAsset'));
    expect(previewService, contains('AudioPlayer? _player'));
    expect(previewService, contains('AssetSource(assetPath)'));
    expect(
      previewService,
      contains('activeFocusPlayback'),
      reason: '提醒试听优先复用番茄媒体链路，但不能抢断正在播放的番茄/白噪音。',
    );
    expect(previewService, contains('FocusSoundService.instance.stop()'));
    expect(
      ReminderRingtonePreviewService.previewAudioContext.android.usageType,
      AndroidUsageType.media,
      reason: '设置页提醒试听必须优先走 media audio path，和番茄专注保持一致。',
    );
    expect(previewService, isNot(contains('AndroidUsageType.alarm')));
    expect(previewService, isNot(contains('AudioCache(prefix: \'\')')));
    expect(previewService, contains(r'sounds/reminders/duoyi_$soundName.wav'));
    expect(mainActivity, contains('"setSoundName"'));
    expect(mainActivity, contains('ReminderRingtoneService.setSoundName'));
    expect(mainActivity, contains('"setVolumePercent"'));
    expect(mainActivity, contains('ReminderRingtoneService.setVolumePercent'));
    expect(mainActivity, contains('"previewCurrentSound"'));
    expect(mainActivity, contains('"stopPreview"'));
    expect(mainActivity, contains('result.success(null)'));
    expect(service, contains('fun previewCurrentSound'));
    expect(service, contains('MediaPlayer()'));
    expect(service, contains('media_volume_zero'));
    expect(service, contains('AudioManager.STREAM_MUSIC'));
    expect(service, contains('AudioManager.STREAM_ALARM'));
    final previewStart = service.indexOf('fun previewCurrentSound');
    final previewEnd = service.indexOf('@Synchronized', previewStart);
    expect(previewStart, greaterThanOrEqualTo(0));
    expect(previewEnd, greaterThan(previewStart));
    final previewCurrentSound = service.substring(previewStart, previewEnd);
    expect(previewCurrentSound, isNot(contains('alarm_volume_zero')));
    expect(service, contains('alarm_volume_zero_media_fallback'));
    expect(service, contains('mediaAudioAttributes()'));
    expect(
      service.indexOf('reason = "media_volume_zero"'),
      lessThan(service.indexOf('val soundName = selectedSoundName')),
      reason: '媒体音量为 0 时不能创建 MediaPlayer 并返回假成功。',
    );
    expect(
      service.indexOf('val mediaVolume = audioManager.getStreamVolume'),
      lessThan(service.indexOf('fun stopPreview()')),
      reason: 'native 试听需要记录媒体和闹钟音量用于日志。',
    );
    expect(service, isNot(contains('AudioManager.STREAM_NOTIFICATION')));
    expect(service, contains('AudioAttributes.USAGE_ALARM'));
    expect(
      service.indexOf('AudioAttributes.USAGE_ALARM'),
      lessThan(service.indexOf('fun previewCurrentSound')),
      reason: '正式提醒仍走 native alarm audio path。',
    );
    expect(service, contains('AudioAttributes.USAGE_MEDIA'));
    expect(
      service.indexOf('private fun previewAudioAttributes()'),
      greaterThan(service.indexOf('fun previewCurrentSound')),
      reason: 'native preview 应使用媒体 audio attributes，和番茄专注的前台试听行为一致。',
    );
    expect(service, contains('stopPreview()'));
    expect(service, contains('activeReminderId != null'));
    expect(service, contains('active_reminder_ringing'));
    expect(
      source,
      contains("nativePreview.reason == 'active_reminder_ringing'"),
    );
    expect(
      service,
      isNot(
        contains(
          'appContext.stopService(Intent(appContext, ReminderRingtoneService::class.java))',
        ),
      ),
    );
    expect(service, contains('audio_resource_missing'));
    expect(service, contains('tone_fallback_started'));
    expect(service, isNot(contains('当前铃声暂不可播放')));
    expect(service, isNot(contains('铃声播放器初始化失败')));
    expect(service, contains('val normalized = value.coerceIn(40, 80)'));
    expect(service, contains('.getInt(volumeKey, 60)'));
    expect(service, contains('.coerceIn(40, 80)'));
    expect(native, contains('static const int previewNotificationId'));
    expect(native, contains('static const Duration previewDuration'));
    expect(native, contains('Future<bool> preview({'));
    expect(native, contains("_tryInvoke('showNow'"));
    expect(native, contains("'vibrate': false"));
    expect(native, contains('unawaited('));
    expect(native, contains("_tryInvoke('cancel'"));
    expect(
      native,
      contains('Future<NativeReminderPreviewResult> previewCurrentSound'),
    );
    expect(native, contains("'previewCurrentSound'"));
    expect(native, contains('铃声试听启动失败，请重试。'));
    expect(native, isNot(contains('播放器调用失败')));
    expect(source, contains('native_and_flutter_preview_failed'));
    expect(source, isNot(contains('铃声播放器初始化失败')));
    expect(native, contains("static Future<void> stopPreview()"));
    expect(native, isNot(contains('await cancel(previewNotificationId)')));
    expect(screen, contains('Future<void> _reloadRingtoneSettings() async'));
    expect(screen, contains('await _reloadRingtoneSettings();'));
    expect(screen, contains('Future<void> _previewCurrentSound() async'));
    expect(screen, contains("tooltip: '试听当前铃声'"));
    expect(screen, contains('ReminderRingtoneSettings.previewCurrentSound()'));
    expect(screen, contains('ReminderRingtoneSettings.stopPreview()'));
    expect(screen, contains('正在试听当前提醒铃声'));
    expect(screen, contains('if (_previewing) return;'));
    expect(screen, contains('_previewing = true;'));
    expect(screen, contains(r"successMessage: '已切换为 $label，并开始试听'"));
    expect(screen, contains("successMessage: '已切换音量并开始试听'"));
  });

  test('ringtone volume changes also trigger Flutter preview by default', () {
    final source = File(
      'lib/services/reminder_ringtone_settings.dart',
    ).readAsStringSync();

    final volumeStart = source.indexOf(
      'static Future<void> setVolumePercent(int value, {bool preview = true})',
    );
    final volumeEnd = source.indexOf(
      'static Future<void> setSound',
      volumeStart,
    );
    expect(volumeStart, greaterThanOrEqualTo(0));
    expect(volumeEnd, greaterThan(volumeStart));
    final method = source.substring(volumeStart, volumeEnd);

    expect(method, contains('await _applyAndPreviewCurrentSound();'));
    expect(
      source,
      contains(
        'final nativeSettingsApplied = await applyPersistedSettingsToNative();',
      ),
    );
    expect(source, contains('ReminderRingtonePreviewService.instance'));
    expect(source, contains('flutterPreviewStarted'));
    expect(source, contains('native_and_flutter_preview_failed'));
    expect(source, contains('native MediaPlayer preview started'));
    expect(source, contains('static Future<void> previewCurrentSound()'));
    expect(source, contains('static Future<void> stopPreview()'));
    expect(
      source,
      isNot(contains('NativeReminderRingtone.clearLastDeliveryIssue()')),
    );
    expect(
      source,
      isNot(contains('NativeReminderRingtone.lastDeliveryIssue()')),
    );
    expect(
      source,
      contains('static Future<bool> applyPersistedSettingsToNative()'),
    );
  });

  test('built-in ringtone options map to non-empty Android raw resources', () {
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final soundIds = ReminderRingtoneSettings.sounds
        .map((sound) => sound.id)
        .toList(growable: false);

    for (final sound in ReminderRingtoneSettings.sounds) {
      final file = File('android/app/src/main/res/raw/duoyi_${sound.id}.wav');
      expect(
        ReminderRingtoneSettings.androidRawResourceNameFor(sound.id),
        'duoyi_${sound.id}',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'duoyi_${sound.id}.wav missing',
      );
      expect(
        file.lengthSync(),
        greaterThan(4096),
        reason: 'duoyi_${sound.id}.wav must not be an empty placeholder',
      );
      expect(
        _wavPcm16Rms(file),
        greaterThan(1200),
        reason:
            'duoyi_${sound.id}.wav must be clearly audible; near-silent built-in sounds make reminders look broken.',
      );
      final header = file.openSync();
      try {
        expect(String.fromCharCodes(header.readSync(4)), 'RIFF');
        header.setPositionSync(8);
        expect(String.fromCharCodes(header.readSync(4)), 'WAVE');
      } finally {
        header.closeSync();
      }
      expect(service, contains('R.raw.duoyi_${sound.id}'));
    }
    expect(soundIds.toSet(), hasLength(soundIds.length));
    expect(
      _extractServiceMappedSoundIds(service),
      unorderedEquals(soundIds),
      reason: 'Android service soundResId must map every Dart ringtone option.',
    );
    expect(
      _extractNormalizeSoundIds(service),
      unorderedEquals(soundIds),
      reason: 'Android service normalizeSoundName must accept every option.',
    );
    expect(
      _extractNormalizeSoundIds(receiver),
      unorderedEquals(soundIds),
      reason: 'Fallback notification receiver must accept every option.',
    );
    expect(
      Directory('android/app/src/main/res/raw')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.startsWith('duoyi_') && name.endsWith('.wav'))
          .map(
            (name) => name
                .replaceFirst('duoyi_', '')
                .replaceFirst(RegExp(r'\.wav$'), ''),
          ),
      unorderedEquals(soundIds),
      reason: 'Raw ringtone files should not drift from the in-app catalog.',
    );
    expect(
      ReminderRingtoneSettings.androidRawResourceNameFor('missing'),
      'duoyi_soft',
    );
    expect(
      alarmService,
      contains('ReminderRingtoneSettings.loadAndroidRawResourceName()'),
    );
    expect(
      localNotifications,
      contains('ReminderRingtoneSettings.loadAndroidRawResourceName()'),
    );
    expect(
      '$alarmService\n$localNotifications',
      isNot(contains("RawResourceAndroidNotificationSound('duoyi_chime')")),
    );
  });

  test('tracks selected ringtone used by Android fallback channels', () async {
    const channelId = 'duoyi_alarm_fullscreen_v18';

    expect(
      await ReminderRingtoneSettings.loadAndroidRawResourceName(),
      'duoyi_soft',
    );
    expect(
      await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
        channelId,
        'duoyi_soft',
      ),
      isTrue,
      reason: '首次运行要强制重建渠道，修复旧包遗留的静音默认渠道。',
    );
    await ReminderRingtoneSettings.markAndroidFallbackChannelSoundApplied(
      channelId,
      'duoyi_soft',
    );
    expect(
      await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
        channelId,
        'duoyi_soft',
      ),
      isFalse,
    );

    await ReminderRingtoneSettings.setSound('bell', preview: false);
    expect(
      await ReminderRingtoneSettings.loadAndroidRawResourceName(),
      'duoyi_bell',
    );
    expect(
      await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
        channelId,
        'duoyi_bell',
      ),
      isTrue,
    );

    await ReminderRingtoneSettings.markAndroidFallbackChannelSoundApplied(
      channelId,
      'duoyi_bell',
    );
    expect(
      await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
        channelId,
        'duoyi_bell',
      ),
      isFalse,
    );
    expect(
      await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
        channelId,
        'duoyi_classic',
      ),
      isTrue,
    );
  });

  test('uses native built-in ringtone controls on Android only', () {
    final policy = ReminderRingtoneSettings.platformPolicyFor(
      isAndroid: true,
      isIOS: false,
      isMacOS: false,
      isLinux: false,
      isWindows: false,
    );

    expect(policy.mode, ReminderRingtonePlatformMode.androidNative);
    expect(policy.supportsBuiltInSoundPicker, isTrue);
    expect(policy.supportsVolumePresets, isTrue);
    expect(policy.usesSystemNotificationSound, isFalse);
    expect(
      policy.sectionSubtitleKey,
      'preferences.ringtone.section.subtitle.android',
    );
  });

  test('uses system time-sensitive notification sounds on Apple platforms', () {
    for (final flags in const [
      (isIOS: true, isMacOS: false),
      (isIOS: false, isMacOS: true),
    ]) {
      final policy = ReminderRingtoneSettings.platformPolicyFor(
        isAndroid: false,
        isIOS: flags.isIOS,
        isMacOS: flags.isMacOS,
        isLinux: false,
        isWindows: false,
      );

      expect(
        policy.mode,
        ReminderRingtonePlatformMode.appleSystemTimeSensitive,
      );
      expect(policy.supportsBuiltInSoundPicker, isFalse);
      expect(policy.supportsVolumePresets, isFalse);
      expect(policy.usesSystemNotificationSound, isTrue);
      expect(policy.tileTitleKey, 'preferences.ringtone.system_sound');
      expect(
        policy.tileSubtitleKey,
        'preferences.ringtone.system_sound.subtitle.apple',
      );
    }
  });

  test('uses desktop system notification sounds on Linux and Windows', () {
    for (final flags in const [
      (isLinux: true, isWindows: false),
      (isLinux: false, isWindows: true),
    ]) {
      final policy = ReminderRingtoneSettings.platformPolicyFor(
        isAndroid: false,
        isIOS: false,
        isMacOS: false,
        isLinux: flags.isLinux,
        isWindows: flags.isWindows,
      );

      expect(
        policy.mode,
        ReminderRingtonePlatformMode.desktopSystemNotification,
      );
      expect(policy.supportsBuiltInSoundPicker, isFalse);
      expect(policy.supportsVolumePresets, isFalse);
      expect(policy.usesSystemNotificationSound, isTrue);
      expect(
        policy.tileSubtitleKey,
        'preferences.ringtone.system_sound.subtitle.desktop',
      );
    }
  });

  test('marks platforms without local notifications as unsupported', () {
    final policy = ReminderRingtoneSettings.platformPolicyFor(
      isAndroid: false,
      isIOS: false,
      isMacOS: false,
      isLinux: false,
      isWindows: false,
    );

    expect(policy.mode, ReminderRingtonePlatformMode.unsupported);
    expect(policy.supportsBuiltInSoundPicker, isFalse);
    expect(policy.supportsVolumePresets, isFalse);
    expect(policy.usesSystemNotificationSound, isFalse);
    expect(policy.tileTitleKey, 'preferences.ringtone.unsupported');
  });
}

int _wavPcm16Rms(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    if (chunkId == 'data') {
      final chunkEnd = math.min(chunkStart + chunkSize, bytes.length);
      var sumSquares = 0.0;
      var count = 0;
      for (var i = chunkStart; i + 1 < chunkEnd; i += 2) {
        final sample = data.getInt16(i, Endian.little).toDouble();
        sumSquares += sample * sample;
        count++;
      }
      if (count == 0) return 0;
      return math.sqrt(sumSquares / count).round();
    }
    offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  return 0;
}

List<String> _extractServiceMappedSoundIds(String source) {
  final matches = RegExp(
    r'"([a-z0-9_]+)" -> R\.raw\.duoyi_([a-z0-9_]+)',
  ).allMatches(source);
  return [
    for (final match in matches)
      if (match.group(1) == match.group(2)) match.group(1)!,
  ];
}

List<String> _extractNormalizeSoundIds(String source) {
  final methodStart = source.indexOf('private fun normalizeSoundName');
  expect(methodStart, greaterThanOrEqualTo(0));
  final whenStart = source.indexOf('return when (value) {', methodStart);
  expect(whenStart, greaterThan(methodStart));
  final elseStart = source.indexOf('else -> "soft"', whenStart);
  expect(elseStart, greaterThan(whenStart));
  final block = source.substring(whenStart, elseStart);
  return RegExp(
    r'"([a-z0-9_]+)"',
  ).allMatches(block).map((match) => match.group(1)!).toList();
}
