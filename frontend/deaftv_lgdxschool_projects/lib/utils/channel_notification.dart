//채널변경 알림
// lib/utils/channel_notification.dart
import 'package:flutter/material.dart';

/// 채널 변경 알림 위젯
/// 화면 중앙에 1초간 표시되는 알림
// class ChannelNotification extends StatelessWidget {
//   final int channelNumber; // 채널 번호

//   const ChannelNotification({super.key, required this.channelNumber});
class ChannelNotification extends StatelessWidget {
  final int channelNumber;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const ChannelNotification({
    super.key,
    required this.channelNumber,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      bottom: 857,
      left: 1579,
      right: 60,
      child: Center(
        child: Container(
          width: 281,
          height: 163,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6), // black 60%
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              channelNumber.toString(),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 120,
                fontWeight: FontWeight.w600, // semibold
                color: Colors.white,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
