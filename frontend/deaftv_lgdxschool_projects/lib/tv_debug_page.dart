// lib/tv_debug_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:deaftv_lgdxschool_projects/services/tv_remote_service.dart';

class TvDebugPage extends StatelessWidget {
  const TvDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: TvRemoteService.getTvStateStream(), // tvs/demo_tv_01 구독
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text(
                '연결 중...',
                style: TextStyle(color: Colors.white),
              );
            }

            if (!snapshot.hasData || snapshot.data!.data() == null) {
              return const Text(
                '데이터 없음',
                style: TextStyle(color: Colors.white),
              );
            }

            final data = snapshot.data!.data()!;
            final volume = data['volume'] ?? 0;
            var channel = (data['channel'] ?? 1) as int;
            // 채널 번호를 1~3 범위로 정규화 (4→1, 5→2, 6→3...)
            channel = channel <= 0 ? 3 : ((channel - 1) % 3) + 1;
            final mode = data['mode'] ?? 'OFF';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '채널: $channel',
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  '볼륨: $volume',
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  '자막 모드: $mode',
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
