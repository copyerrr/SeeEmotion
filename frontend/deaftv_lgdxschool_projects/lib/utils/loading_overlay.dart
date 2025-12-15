import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 🔥 재사용 가능한 도넛 로딩 애니메이션 위젯
class LoadingDonutRing extends StatefulWidget {
  final double size; // 전체 크기
  final double stroke; // 두께
  final Duration duration; // 회전 시간

  const LoadingDonutRing({
    super.key,
    this.size = 60,
    this.stroke = 4,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<LoadingDonutRing> createState() => _LoadingDonutRingState();
}

class _LoadingDonutRingState extends State<LoadingDonutRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(); // 🔄 무한 회전
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * 2 * math.pi,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _DonutRingPainter(strokeWidth: widget.stroke),
            ),
          );
        },
      ),
    );
  }
}

/// 🎨 도넛 링 Painter — 빨간/회색 링
class _DonutRingPainter extends CustomPainter {
  final double strokeWidth;

  _DonutRingPainter({this.strokeWidth = 4});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: const [
          Color(0xFFFD312E), // 빨강
          Color(0xFFFD312E),
          Color(0xFF777777), // 회색
          Color(0xFF777777),
        ],
        stops: const [0.0, 0.25, 0.25, 1.0],
      ).createShader(rect);

    canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
