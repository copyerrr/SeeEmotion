//알림 위젯
//
//// lib/utils/notification.dart
import 'package:flutter/material.dart';

/// 범용 알림 위젯
/// 화면 중앙에 1초간 표시되는 알림
class VolumeNotification extends StatelessWidget {
  final String message; // 표시할 메시지

  const VolumeNotification({super.key, required this.message});

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
            message,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 25,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A7BFF), // #3A7BFF
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
