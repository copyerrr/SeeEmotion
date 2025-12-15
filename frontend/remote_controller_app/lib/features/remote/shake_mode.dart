import 'package:vibration/vibration.dart';

/// 진동 기능을 제공하는 클래스
class ShakeMode {
  /// 진동 실행
  /// [duration] 진동 지속 시간 (밀리초), 기본값 100ms
  static Future<void> vibrate({int duration = 500}) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: duration);
    }
  }

  /// 진동 가능 여부 확인
  static Future<bool> hasVibrator() async {
    return await Vibration.hasVibrator() ?? false;
  }
}
