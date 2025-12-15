// lib/utils/layout_utils.dart
import 'package:flutter/material.dart';

/// LG TV용 공통 레이아웃 래퍼
/// - 화면 가운데 정렬
/// - 최대 너비 1920
/// - 데스크탑/모바일에 따라 padding 다르게 줌
Widget buildBasePageLayout({
  required BuildContext context,
  required Widget child,
}) {
  return LayoutBuilder(
    // 1024 이상이면 데스크탑 레이아웃, 미만이면 모바일/태블릿
    builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 1024;

      return Center(
        child: Container(
          // 화면이 최대 1920까지 보이기
          constraints: const BoxConstraints(maxWidth: 1920),
          // 가장자리 여백
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 120.0 : 40.0,
            vertical: 60.0,
          ),
          // 👉 실제 페이지별 내용
          child: child,
        ),
      );
    },
  );
}
