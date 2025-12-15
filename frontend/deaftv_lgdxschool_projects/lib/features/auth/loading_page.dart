// lib/screens/loading/loading_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

// 공통 레이아웃 util (경로는 네 프로젝트 구조에 맞게)
// 예: lib/utils/layout_utils.dart 안에 buildBasePageLayout 이 있다고 가정
import '../../utils/layout_utils.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    // 0 -> 1까지 2초 동안 반복 회전하는 컨트롤러
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(); // 계속 회전

    // 3초 후 자동으로 로그인 선택 페이지로 이동 (세 번째 페이지)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login-select');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // ✅ 모든 페이지에서 공통으로 쓰는 레이아웃
      body: buildBasePageLayout(
        context: context,
        child: _buildLoadingContent(),
      ),
    );
  }

  /// ✅ 로딩 페이지에만 쓰이는 실제 화면 구성
  Widget _buildLoadingContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 408,
            height: 452,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // LG 로고 영역
                buildLgLogo(),

                // 🔴 얇은 도넛 링 로딩 애니메이션
                //positioned 은 stack 안에서 위치를 잡음
                Positioned(
                  //lg 로고 박스 아래에 바로 붙음
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.rotate(
                        // 0 ~ 2π(360도) 계속 회전
                        angle: _controller.value * 2 * math.pi,
                        child: CustomPaint(
                          size: const Size(60, 60),
                          painter: _DonutRingPainter(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SizedBox buildLgLogo() {
    return SizedBox(
      width: 408,
      height: 408,
      child: Center(
        child: Image.asset(
          'assets/LG_logo.png',
          width: 200,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// 🔴 얇은 도넛 링(빨강 + 회색)이 회전하는 효과를 내는 페인터
class _DonutRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        // 🔴 빨강 부분 + ⚪ 회색 부분
        colors: const [
          Color(0xFFFD312E), // 빨강
          Color(0xFFFD312E), // 빨강 유지
          Color(0xFF777777), // 회색
          Color(0xFF777777), // 회색 유지
        ],
        stops: const [
          0.0, // 0% 지점
          0.25, // 25%까지 빨강
          0.25, // 25%부터 회색
          1.0, // 100%까지 회색
        ],
      ).createShader(rect);

    // 전체 링(0 ~ 360도)을 그리는데, 색 그라데이션 + 회전으로 로딩 느낌
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
