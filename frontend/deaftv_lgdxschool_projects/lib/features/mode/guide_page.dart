// lib/features/mode/guide_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/home/home_page.dart';
import '../../utils/remote_point_overlay.dart';
import '../../services/tv_remote_service.dart';

/// 제네릭 가이드 페이지 위젯
class GuidePage extends StatefulWidget {
  final String imagePath; // 가이드 이미지 경로
  final String buttonText; // 버튼 텍스트
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final Widget? nextPage; // 다음 페이지 (null이면 HomePage로 이동)
  final double? buttonBottom; // 버튼 하단 위치 (null이면 기본값 사용)
  final double? buttonLeft; // 버튼 왼쪽 위치 (null이면 기본값 사용)
  final double? buttonRight; // 버튼 오른쪽 위치 (null이면 기본값 사용)

  const GuidePage({
    super.key,
    required this.imagePath,
    this.buttonText = '네, 알겠어요',
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.nextPage,
    this.buttonBottom,
    this.buttonLeft,
    this.buttonRight,
  });

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  bool _isButtonHovered = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;
  bool? _previousOkButtonPressed; // 이전 okButtonPressed 값 (변경 감지용)

  @override
  void initState() {
    super.initState();
    _previousOkButtonPressed = null;
    _subscribeToRemoteControl();
  }

  /// Firebase 리모컨 상태 구독
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      // 확인 버튼 처리 - false -> true로 변경될 때만 처리
      final currentOkButtonPressed = data['okButtonPressed'] as bool? ?? false;
      if (_previousOkButtonPressed == null) {
        _previousOkButtonPressed = currentOkButtonPressed;
      } else if (_previousOkButtonPressed == false &&
          currentOkButtonPressed == true) {
        // 현재 라우트가 GuidePage인지 확인 (백그라운드에서 실행 중인지 체크)
        final currentRoute = ModalRoute.of(context);
        final isCurrentPage = currentRoute?.isCurrent ?? false;
        
        // 현재 페이지가 활성화되어 있을 때만 처리
        if (isCurrentPage) {
          _navigateToNext();
        }
        _previousOkButtonPressed = currentOkButtonPressed;
      } else {
        _previousOkButtonPressed = currentOkButtonPressed;
      }
    });
  }

  /// 다음 페이지로 이동
  void _navigateToNext() {
    if (!mounted) return;
    if (widget.nextPage != null) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              widget.nextPage!,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0); // 오른쪽에서 시작
            const end = Offset.zero; // 왼쪽으로 이동
            const curve = Curves.easeInOut;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => HomePage(
            initialToggles: widget.initialToggles,
            initialMode: widget.initialMode,
            initialSoundPitch: widget.initialSoundPitch,
            initialEmotionColor: widget.initialEmotionColor,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0); // 오른쪽에서 시작
            const end = Offset.zero; // 왼쪽으로 이동
            const curve = Curves.easeInOut;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tvStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xff1b1b1b),
      body: RemotePointerOverlay(
        child: Stack(
          children: [
            // 가이드 이미지 (전체 화면에 꽉 차게)
            SizedBox.expand(
              child: Image.asset(
                widget.imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container();
                },
              ),
            ),
            // 넘어가기 버튼 (위치 커스터마이징 가능)
            // buttonBottom, buttonLeft, buttonRight가 null이면 기본값 사용 (guide_shake.png용)
            Positioned(
              bottom: widget.buttonBottom ?? 119,
              left: widget.buttonLeft ?? 959,
              right: widget.buttonRight ?? 711,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (widget.nextPage != null) {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  widget.nextPage!,
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0); // 오른쪽에서 시작
                            const end = Offset.zero; // 왼쪽으로 이동
                            const curve = Curves.easeInOut;

                            var tween = Tween(begin: begin, end: end).chain(
                              CurveTween(curve: curve),
                            );

                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    } else {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  HomePage(
                            initialToggles: widget.initialToggles,
                            initialMode: widget.initialMode,
                            initialSoundPitch: widget.initialSoundPitch,
                            initialEmotionColor: widget.initialEmotionColor,
                          ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0); // 오른쪽에서 시작
                            const end = Offset.zero; // 왼쪽으로 이동
                            const curve = Curves.easeInOut;

                            var tween = Tween(begin: begin, end: end).chain(
                              CurveTween(curve: curve),
                            );

                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    }
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _isButtonHovered = true),
                    onExit: (_) => setState(() => _isButtonHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: _isButtonHovered ? Colors.white : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: _isButtonHovered
                            ? Border.all(color: Color(0xff3a7bff), width: 4)
                            : null,
                      ),
                      child: Text(
                        widget.buttonText,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 구체적인 가이드 페이지들
// ============================================

/// 흔들기 가이드 페이지
class GuideShakePage extends StatelessWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;

  const GuideShakePage({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
  });

  @override
  Widget build(BuildContext context) {
    return GuidePage(
      imagePath: 'assets/1speak_guide.png',
      buttonText: '네, 알겠어요',
      initialToggles: initialToggles,
      initialMode: initialMode,
      initialSoundPitch: initialSoundPitch,
      initialEmotionColor: initialEmotionColor,
      // 버튼 위치 설정 (필요시 주석 해제하여 수정)
      buttonBottom: 150,
      buttonLeft: 835,
      buttonRight: 835,
      nextPage: GuidePage2(
        initialToggles: initialToggles,
        initialMode: initialMode,
        initialSoundPitch: initialSoundPitch,
        initialEmotionColor: initialEmotionColor,
      ),
    );
  }
}

/// 가이드 페이지 2
class GuidePage2 extends StatelessWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final Widget? nextPage;

  const GuidePage2({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.nextPage,
  });

  @override
  Widget build(BuildContext context) {
    return GuidePage(
      imagePath: 'assets/2color_guide.png', // 이미지 경로를 여기에 설정
      buttonText: '네, 알겠어요',
      initialToggles: initialToggles,
      initialMode: initialMode,
      initialSoundPitch: initialSoundPitch,
      initialEmotionColor: initialEmotionColor,
      // 버튼 위치 설정 (필요시 주석 해제하여 수정)
      buttonBottom: 150,
      buttonLeft: 835,
      buttonRight: 835,
      // 무조건 다음 페이지(GuidePage3)로 이동
      nextPage: GuidePage3(
        initialToggles: initialToggles,
        initialMode: initialMode,
        initialSoundPitch: initialSoundPitch,
        initialEmotionColor: initialEmotionColor,
      ),
    );
  }
}

/// 가이드 페이지 3
class GuidePage3 extends StatelessWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final Widget? nextPage;

  const GuidePage3({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.nextPage,
  });

  @override
  Widget build(BuildContext context) {
    return GuidePage(
      imagePath: 'assets/3speaker_guide.png', // 이미지 경로를 여기에 설정
      buttonText: '네, 알겠어요',
      initialToggles: initialToggles,
      initialMode: initialMode,
      initialSoundPitch: initialSoundPitch,
      initialEmotionColor: initialEmotionColor,
      // 버튼 위치 설정 (필요시 주석 해제하여 수정)
      buttonBottom: 150,
      buttonLeft: 835,
      buttonRight: 835,
      // 무조건 다음 페이지(GuidePage4)로 이동
      nextPage: GuidePage4(
        initialToggles: initialToggles,
        initialMode: initialMode,
        initialSoundPitch: initialSoundPitch,
        initialEmotionColor: initialEmotionColor,
      ),
    );
  }
}

/// 가이드 페이지 4
class GuidePage4 extends StatelessWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final Widget? nextPage;

  const GuidePage4({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.nextPage,
  });

  @override
  Widget build(BuildContext context) {
    return GuidePage(
      imagePath: 'assets/4back_guide.png', // 이미지 경로를 여기에 설정
      buttonText: '네, 알겠어요',
      initialToggles: initialToggles,
      initialMode: initialMode,
      initialSoundPitch: initialSoundPitch,
      initialEmotionColor: initialEmotionColor,
      // 버튼 위치 설정 (필요시 주석 해제하여 수정)
      buttonBottom: 150,
      buttonLeft: 835,
      buttonRight: 835,
      // 무조건 다음 페이지(GuidePage5)로 이동
      nextPage: GuidePage5(
        initialToggles: initialToggles,
        initialMode: initialMode,
        initialSoundPitch: initialSoundPitch,
        initialEmotionColor: initialEmotionColor,
      ),
    );
  }
}

/// 가이드 페이지 5
class GuidePage5 extends StatelessWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final Widget? nextPage;

  const GuidePage5({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.nextPage,
  });

  @override
  Widget build(BuildContext context) {
    return GuidePage(
      imagePath: 'assets/guide_shake.png', // 이미지 경로를 여기에 설정
      buttonText: '네, 알겠어요',
      initialToggles: initialToggles,
      initialMode: initialMode,
      initialSoundPitch: initialSoundPitch,
      initialEmotionColor: initialEmotionColor,
      nextPage: nextPage,
    );
  }
}
