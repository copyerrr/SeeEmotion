// lib/features/auth/login_select_page.dart
import 'package:flutter/material.dart';
import '../../utils/layout_utils.dart';

class LoginSelectPage extends StatefulWidget {
  const LoginSelectPage({super.key});

  @override
  State<LoginSelectPage> createState() => _LoginSelectPageState();
}

class _LoginSelectPageState extends State<LoginSelectPage> {
  @override
  void initState() {
    super.initState();

    // 3초 후 다음 페이지로 이동 (TypeSelectPage로)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/type-select');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: buildBasePageLayout(
        context: context,
        child: _buildLoginSelectContent(),
      ),
    );
  }

  /// 전체 로그인 선택 화면 콘텐츠
  Widget _buildLoginSelectContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 전체 화면 세로 가운데
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [_buildAccountCard()],
    );
  }

  /// 가운데 자연스럽게 정렬된 계정 카드
  Widget _buildAccountCard() {
    return SizedBox(
      width: 517,
      height: 450, // 원 + 이메일 박스 균형이 잘 맞도록 높이 증가
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // 세로 중앙 기준 정렬
        children: [
          buildLgIdImage(), // 파란 원
          const SizedBox(height: 40), // 간격
          buildLgLoginId(), // 로그인 이메일 박스
        ],
      ),
    );
  }

  /// 로그인 ID 이메일 박스
  Widget buildLgLoginId() {
    return Container(
      width: 517,
      height: 75,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(50),
      ),
      child: const Center(
        child: Text(
          'fall_seo@gmail.com',
          style: TextStyle(
            fontFamily: 'LG Smart_H',
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.085,
          ),
        ),
      ),
    );
  }

  /// 파란 원 + L 텍스트
  Widget buildLgIdImage() {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF505dff),
        borderRadius: BorderRadius.circular(160),
      ),
      child: const Center(
        child: Text(
          'L',
          style: TextStyle(
            fontFamily: 'LG Smart_H',
            fontSize: 133.33,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.08,
          ),
        ),
      ),
    );
  }
}
