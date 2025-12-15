// 뒤로가기 버튼 누를 때, 화면 전환 애니메이션 구현 페이지
// lib/utils/slide_page_route.dart
import 'package:flutter/material.dart';

/// 왼쪽에서 오른쪽으로 밀리는 페이지 전환 (역순 네비게이션용)
class SlideLeftToRightRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SlideLeftToRightRoute({required this.page})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 왼쪽에서 오른쪽으로 밀리는 애니메이션
          const begin = Offset(-1.0, 0.0); // 왼쪽에서 시작
          const end = Offset.zero; // 중앙으로
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      );
}
