// lib/services/shake_detector_service.dart
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/tv_remote_service.dart';
import '../features/remote/shake_mode.dart';

/// 흔들기 감지 서비스
/// 가속도계 센서를 사용하여 흔들기를 감지하고 Firebase에 이벤트를 전송합니다.
class ShakeDetectorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 흔들기 감지 임계값
  // ⁉️⁉️⁉️성수야 현정아 여기 임계값 수정해줘⁉️⁉️⁉️
  static const double _shakeThreshold = 20.0; // 가속도 임계값
  static const int _shakeTimeWindow = 500; // 흔들기 감지 시간 윈도우 (ms)
  static const int _shakeCountThreshold = 2; // 흔들기로 인정할 최소 횟수

  DateTime? _lastShakeTime;
  int _shakeCount = 0;
  bool _isDetecting = false;

  /// 흔들기 감지 시작
  void startDetecting() {
    if (_isDetecting) return;

    _isDetecting = true;
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        _handleAccelerometerEvent(event);
      },
      onError: (error) {
        print('가속도계 센서 오류: $error');
      },
    );
  }

  /// 흔들기 감지 중지
  void stopDetecting() {
    _isDetecting = false;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _shakeCount = 0;
    _lastShakeTime = null;
  }

  /// 가속도계 이벤트 처리
  void _handleAccelerometerEvent(AccelerometerEvent event) {
    // 가속도 벡터의 크기 계산
    final double acceleration =
        (event.x * event.x + event.y * event.y + event.z * event.z) / 9.81;

    // 임계값을 넘으면 흔들기로 간주
    if (acceleration > _shakeThreshold) {
      final now = DateTime.now();

      // 시간 윈도우 내에 있는지 확인
      if (_lastShakeTime == null ||
          now.difference(_lastShakeTime!).inMilliseconds < _shakeTimeWindow) {
        _shakeCount++;
        _lastShakeTime = now;

        // 흔들기 횟수가 임계값을 넘으면 이벤트 발생
        if (_shakeCount >= _shakeCountThreshold) {
          _onShakeDetected();
          _shakeCount = 0;
          _lastShakeTime = null;
        }
      } else {
        // 시간 윈도우를 벗어나면 카운트 리셋
        _shakeCount = 1;
        _lastShakeTime = now;
      }
    }
  }

  /// 흔들기 감지 시 호출되는 콜백
  void _onShakeDetected() {
    print('흔들기 감지됨! 퀵모드 토글 전송');

    // 진동 피드백
    ShakeMode.vibrate(duration: 100);

    // Firebase에 퀵모드 토글 이벤트 전송
    TvRemoteService.toggleQuickMode();
  }

  /// 리소스 정리
  void dispose() {
    stopDetecting();
  }
}
