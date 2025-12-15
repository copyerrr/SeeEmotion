// lib/features/mode/mode_guide_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mode_select_page.dart';
import '../../utils/remote_point_overlay.dart';
import '../../services/tv_remote_service.dart';

class ModeGuidePage extends StatefulWidget {
  const ModeGuidePage({super.key});

  @override
  State<ModeGuidePage> createState() => _ModeGuidePageState();
}

class _ModeGuidePageState extends State<ModeGuidePage> {
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
        // 현재 라우트가 ModeGuidePage인지 확인 (백그라운드에서 실행 중인지 체크)
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
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ModeSelectPage(),
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

  @override
  void dispose() {
    _tvStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1b1b1b),
      body: RemotePointerOverlay(
        child: Stack(
          children: [
            // 가이드 이미지 (전체 화면에 꽉 차게)
            SizedBox.expand(
              child: Image.asset(
                'assets/mode_guide.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container();
                },
              ),
            ),
            // 넘어가기 버튼 (하단 중앙)
            Positioned(
              bottom: 450,
              left: 1500,
              right: 170,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const ModeSelectPage(),
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
                            ? Border.all(
                                color: const Color(0xff3a7bff),
                                width: 4,
                              )
                            : null,
                      ),
                      child: const Text(
                        '네, 알겠어요',
                        style: TextStyle(
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
