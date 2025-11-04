import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';

const platform = MethodChannel('com.example.pharm_parrot_flutter/window');

/// 윈도우 및 COM Port 설정을 파일에 저장합니다
Future<void> saveWindowSettingsToFile(
    int left, int top, int width, int height, 
    {bool useComPort = false, int comPortNumber = 4}) async {
  try {
    // 앱 데이터 디렉토리에 저장
    final appDataDir = Directory.systemTemp.path;
    final settingsFile =
        File('$appDataDir/pharm_parrot_window_settings.json');

    final settings = {
      'left': left,
      'top': top,
      'width': width,
      'height': height,
      'useComPort': useComPort,
      'comPortNumber': comPortNumber,
    };

    await settingsFile.writeAsString(jsonEncode(settings));
  } catch (e) {
    print('윈도우 설정 파일 저장 실패: $e');
  }
}

/// 파일에서 윈도우 및 COM Port 설정을 읽습니다
Future<Map<String, dynamic>> loadWindowSettingsFromFile() async {
  try {
    final appDataDir = Directory.systemTemp.path;
    final settingsFile =
        File('$appDataDir/pharm_parrot_window_settings.json');

    if (await settingsFile.exists()) {
      final contents = await settingsFile.readAsString();
      final settings = jsonDecode(contents) as Map<String, dynamic>;
      return {
        'left': settings['left'] as int? ?? 1004,
        'top': settings['top'] as int? ?? 0,
        'width': settings['width'] as int? ?? 540,
        'height': settings['height'] as int? ?? 1020,
        'useComPort': settings['useComPort'] as bool? ?? false,
        'comPortNumber': settings['comPortNumber'] as int? ?? 4,
      };
    }
  } catch (e) {
    print('윈도우 설정 파일 로드 실패: $e');
  }

  return {
    'left': 1004,
    'top': 0,
    'width': 540,
    'height': 1020,
    'useComPort': false,
    'comPortNumber': 4,
  };
}

/// 윈도우 위치와 크기를 실시간으로 변경합니다
Future<void> applyWindowSettings(int left, int top, int width, int height) async {
  try {
    await platform.invokeMethod('setWindowGeometry', {
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    });
  } catch (e) {
    print('윈도우 설정 적용 실패: $e');
  }
}
