// lib/utils/subtitle_mode_notification.dart
import 'package:flutter/material.dart';

/// 자막 모드 알림 위젯
/// 화면 중앙에 1초간 표시되는 알림
class SubtitleModeNotification extends StatelessWidget {
  final bool isOn; // 자막 모드 켜짐/꺼짐 상태

  const SubtitleModeNotification({super.key, required this.isOn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        height: 106,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          // black 60%
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            isOn ? '자막 모드 켜짐' : '자막 모드 꺼짐',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A7BFF), // #3A7BFF
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
