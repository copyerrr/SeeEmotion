// lib/utils/remote_point_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import '../services/tv_remote_service.dart';

class RemotePointerOverlay extends StatefulWidget {
  final Widget child;

  const RemotePointerOverlay({super.key, required this.child});

  @override
  State<RemotePointerOverlay> createState() => _RemotePointerOverlayState();
}

class _RemotePointerOverlayState extends State<RemotePointerOverlay> {
  double _nx = -1.0; // 현재 표시되는 x 좌표 (초기값: 화면 밖)
  double _ny = -1.0; // 현재 표시되는 y 좌표 (초기값: 화면 밖)
  Timer? _hideTimer; // 포인터 자동 숨김 타이머
  bool _isVisible = false; // 포인터 표시 여부
  bool _hasReceivedFirstCoordinate = false; // 첫 좌표 수신 여부

  StreamSubscription? _sub;
  final GlobalKey _overlayKey = GlobalKey();

  // Throttle 관련 변수
  Timer? _updateThrottleTimer;
  double? _pendingX;
  double? _pendingY;
  DateTime? _lastUpdateTime;
  static const Duration _throttleInterval = Duration(
    milliseconds: 16,
  ); // ~60fps
  static const double _coordinateChangeThreshold = 0.01; // 좌표 변화 임계값

  // 호버 시뮬레이션을 위한 변수
  Offset? _previousHoverPosition; // 이전 호버 위치
  int _hoverPointerId = 0; // 호버 이벤트용 포인터 ID

  @override
  void initState() {
    super.initState();

    // Firebase에서 터치 좌표 구독
    _sub = TvRemoteService.getTvStateStream().listen(
      (snapshot) {
        if (!mounted) return;

        final data = snapshot.data();
        if (data == null) return;

        // 터치 좌표 업데이트 (throttle 적용)
        if (data.containsKey('touchX') && data.containsKey('touchY')) {
          final x = (data['touchX'] as num?)?.toDouble();
          final y = (data['touchY'] as num?)?.toDouble();

          if (x != null && y != null) {
            final clampedX = x.clamp(0.0, 1.0);
            final clampedY = y.clamp(0.0, 1.0);

            // 좌표 변화가 임계값 이상일 때만 처리
            final isFirstCoordinate = !_hasReceivedFirstCoordinate;
            final deltaX = (_nx - clampedX).abs();
            final deltaY = (_ny - clampedY).abs();
            final hasSignificantChange = deltaX > _coordinateChangeThreshold ||
                deltaY > _coordinateChangeThreshold;

            if (isFirstCoordinate || hasSignificantChange) {
              // 최신 좌표 저장 (throttle용)
              _pendingX = clampedX;
              _pendingY = clampedY;

              // 즉시 업데이트 (첫 좌표이거나 throttle 간격이 지났을 때)
              final now = DateTime.now();
              if (isFirstCoordinate ||
                  _lastUpdateTime == null ||
                  now.difference(_lastUpdateTime!) >= _throttleInterval) {
                _lastUpdateTime = now;
                _applyCoordinateUpdate(clampedX, clampedY);
              } else {
                // Throttle: 다음 간격에 업데이트 예약
                _updateThrottleTimer?.cancel();
                final timeSinceLastUpdate = now.difference(_lastUpdateTime!);
                final remainingTime = _throttleInterval - timeSinceLastUpdate;
                _updateThrottleTimer = Timer(
                  remainingTime > Duration.zero ? remainingTime : Duration.zero,
                  () {
                    if (mounted && _pendingX != null && _pendingY != null) {
                      _lastUpdateTime = DateTime.now();
                      _applyCoordinateUpdate(_pendingX!, _pendingY!);
                      _pendingX = null;
                      _pendingY = null;
                    }
                  },
                );
              }
            }
          }
        }

        // 클릭 이벤트 처리 (즉시 실행)
        if (data.containsKey('clickX') && data.containsKey('clickY')) {
          final clickX = (data['clickX'] as num?)?.toDouble();
          final clickY = (data['clickY'] as num?)?.toDouble();

          if (clickX != null && clickY != null) {
            // 마이크로태스크로 즉시 실행 (프레임 대기 없음)
            Future.microtask(() => _simulateTap(clickX, clickY));
          }
        }
      },
      onError: (error) {
        // 에러는 조용히 무시 (프로덕션 환경)
      },
    );
  }

  /// 좌표 업데이트 적용 (setState 호출)
  void _applyCoordinateUpdate(double x, double y) {
    if (!mounted) return;

    setState(() {
      _nx = x;
      _ny = y;
      _isVisible = true;
      _hasReceivedFirstCoordinate = true;
    });
    _resetHideTimer();

    _simulateHover(x, y);
  }

  /// 특정 좌표에서 호버 이벤트 시뮬레이션
  void _simulateHover(double normalizedX, double normalizedY) {
    final context = _overlayKey.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 좌표 변환 및 전역 좌표 계산
    final currentPosition = renderBox.localToGlobal(
      Offset(
        normalizedX * renderBox.size.width,
        normalizedY * renderBox.size.height,
      ),
    );

    // GestureBinding을 통해 호버 이벤트 발생
    final gestureBinding = GestureBinding.instance;
    final now = DateTime.now();
    final timeStamp = Duration(microseconds: now.microsecondsSinceEpoch);

    // 이전 위치에서 Exit 이벤트 발생 (위치가 변경된 경우)
    if (_previousHoverPosition != null &&
        _previousHoverPosition != currentPosition) {
      gestureBinding.handlePointerEvent(
        PointerExitEvent(
          position: _previousHoverPosition!,
          timeStamp: timeStamp,
          pointer: _hoverPointerId,
          kind: PointerDeviceKind.mouse,
        ),
      );
    }

    // 현재 위치에서 Hover 이벤트 발생
    gestureBinding.handlePointerEvent(
      PointerHoverEvent(
        position: currentPosition,
        timeStamp: timeStamp,
        pointer: _hoverPointerId,
        kind: PointerDeviceKind.mouse,
      ),
    );

    // 이전 위치가 없거나 변경된 경우 Enter 이벤트 발생
    if (_previousHoverPosition == null ||
        _previousHoverPosition != currentPosition) {
      gestureBinding.handlePointerEvent(
        PointerEnterEvent(
          position: currentPosition,
          timeStamp: timeStamp,
          pointer: _hoverPointerId,
          kind: PointerDeviceKind.mouse,
        ),
      );
    }

    // 현재 위치를 이전 위치로 저장
    _previousHoverPosition = currentPosition;
  }

  /// 특정 좌표에서 탭 이벤트 시뮬레이션 (최적화: 가벼운 함수)
  void _simulateTap(double normalizedX, double normalizedY) {
    final context = _overlayKey.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 좌표 변환 및 전역 좌표 계산
    final globalPosition = renderBox.localToGlobal(
      Offset(
        normalizedX * renderBox.size.width,
        normalizedY * renderBox.size.height,
      ),
    );

    // GestureBinding 한 번만 가져오기
    final gestureBinding = GestureBinding.instance;
    final now = DateTime.now();
    final timeStamp = Duration(microseconds: now.microsecondsSinceEpoch);
    final pointerId = now.microsecondsSinceEpoch % 1000000;

    // PointerDown → PointerUp 단일 탭만 발생 (즉시 처리)
    gestureBinding.handlePointerEvent(
      PointerDownEvent(
        position: globalPosition,
        timeStamp: timeStamp,
        pointer: pointerId,
        kind: PointerDeviceKind.touch,
      ),
    );

    // 즉시 PointerUp 발생 (마이크로태스크로 최소 딜레이)
    Future.microtask(() {
      gestureBinding.handlePointerEvent(
        PointerUpEvent(
          position: globalPosition,
          timeStamp: Duration(
            microseconds: DateTime.now().microsecondsSinceEpoch,
          ),
          pointer: pointerId,
          kind: PointerDeviceKind.touch,
        ),
      );
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isVisible = false; // 포인터 숨김
        });
        // 포인터가 숨겨질 때 Exit 이벤트 발생
        _simulateExit();
      }
    });
  }

  /// 포인터가 화면에서 사라질 때 Exit 이벤트 시뮬레이션
  void _simulateExit() {
    if (_previousHoverPosition == null) return;

    final gestureBinding = GestureBinding.instance;
    final now = DateTime.now();
    final timeStamp = Duration(microseconds: now.microsecondsSinceEpoch);

    gestureBinding.handlePointerEvent(
      PointerExitEvent(
        position: _previousHoverPosition!,
        timeStamp: timeStamp,
        pointer: _hoverPointerId,
        kind: PointerDeviceKind.mouse,
      ),
    );

    _previousHoverPosition = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _updateThrottleTimer?.cancel();
    // dispose 시에도 Exit 이벤트 발생
    _simulateExit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        // 좌표 변환 (픽셀 단위)
        // 유효한 좌표 범위(0.0 ~ 1.0)에 있을 때만 표시
        final isValidCoordinate =
            _nx >= 0.0 && _nx <= 1.0 && _ny >= 0.0 && _ny <= 1.0;
        final px = _nx * w;
        final py = _ny * h;

        return GestureDetector(
          key: _overlayKey,
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            // 실제 터치 이벤트는 무시 (리모컨 클릭만 처리)
          },
          child: Stack(
            children: [
              /// 뒤에 깔리는 페이지 전체
              Positioned.fill(child: widget.child),

              /// TV 화면 위 공통 포인터 (부드러운 애니메이션 적용)
              if (_isVisible && isValidCoordinate)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 50), // 부드러운 이동 애니메이션
                  curve: Curves.easeOut,
                  left: px - 22, // 44/2 = 22 (중앙 정렬)
                  top: py - 22, // 44/2 = 22 (중앙 정렬)
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _isVisible ? 1.0 : 0.0,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xff3A7BFF), // 채우기 색상
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.zero, // 왼쪽 위: 둥글기 없음
                            topRight: Radius.circular(50), // 오른쪽 위: 둥글기 50
                            bottomRight: Radius.circular(50), // 오른쪽 아래: 둥글기 50
                            bottomLeft: Radius.circular(50), // 왼쪽 아래: 둥글기 50
                          ),
                          border: Border.all(
                            color: Colors.white,
                            width: 4.0, // 테두리 두께
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
