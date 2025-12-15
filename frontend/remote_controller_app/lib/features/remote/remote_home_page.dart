import 'package:flutter/material.dart';

import 'remote_pad.dart';

class RemoteHomePage extends StatelessWidget {
  const RemoteHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101116),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 디자인 기준 사이즈(Figma 기준)
            const designWidth = 390.0;
            const designHeight = 844.0;

            return Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: designWidth,
                  height: designHeight,
                  child: const RemotePad(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
