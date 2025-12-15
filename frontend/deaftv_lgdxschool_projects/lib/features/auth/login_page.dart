// lib/screens/login/login_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deaftv_lgdxschool_projects/utils/layout_utils.dart'; // 🔹
import '../../services/tv_remote_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;
  bool? _previousQrCodeClicked; // 이전 qrCodeClicked 값 저장

  @override
  void initState() {
    super.initState();
    _subscribeToRemoteControl();
  }

  @override
  void dispose() {
    _tvStateSubscription?.cancel();
    super.dispose();
  }

  /// Firebase 리모컨 상태 구독
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      // 홈으로 이동 (go_home)
      final currentGoHome = data['go_home'] as bool? ?? false;
      if (currentGoHome == true) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/home',
            (route) => false, // 모든 이전 라우트 제거
          );
        }
        return; // 홈으로 이동하므로 이후 처리 중단
      }

      // qrCodeClicked가 false -> true로 변경되면 다음 페이지로 이동
      final currentQrCodeClicked = data['qrCodeClicked'] as bool? ?? false;

      if (_previousQrCodeClicked == null) {
        // 첫 데이터 수신: 이전 값 저장만 하고 처리하지 않음
        _previousQrCodeClicked = currentQrCodeClicked;
      } else if (_previousQrCodeClicked == false &&
          currentQrCodeClicked == true) {
        // false -> true 변경 감지: 다음 페이지로 이동
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/loading');
        }
        _previousQrCodeClicked = currentQrCodeClicked;
      } else {
        // 다른 경우: 이전 값만 업데이트
        _previousQrCodeClicked = currentQrCodeClicked;
      }
    });
  }

  Future<void> _handleQRCodeTap() async {
    setState(() {}); // 지금은 상태 변화 없음. 나중에 로딩 표시 추가할 때 활용 가능.

    // 로딩 시뮬레이션 (0.5초 후 로딩 페이지로 이동)
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/loading');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 🔹 공통 레이아웃 래퍼 사용
      body: buildBasePageLayout(
        context: context,
        child: buildMainPagesLayout(context), // 이 페이지 전용 UI
      ),
    );
  }

  // 첫번째 로그인 페이지 메인 레이아웃 (텍스트 + QR 코드 Row)
  Row buildMainPagesLayout(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(top: 200),
            child: _buildTextContent(),
          ),
        ),
        const SizedBox(width: 80),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 200),
            child: _buildQRCodeArea(context),
          ),
        ),
        // _buildQRCodeArea(context),
      ],
    );
  }

  // 첫번째 로그인 페이지 텍스트
  Widget _buildTextContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   '로그인 방법을 선택요',
        //   style: TextStyle(
        //     fontFamily: 'Pretendard',
        //     fontSize: 40,
        //     fontWeight: FontWeight.w600,
        //     color: Colors.white,
        //     height: 1.2,
        //   ),
        // ),
        // const SizedBox(height: 110),
        Text(
          'ThinQ 앱으로 로그인',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 80,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 118),
        _buildInstructionText('1. 모바일 기기에서 ThinQ앱을 실행해주세요'),
        const SizedBox(height: 40),
        _buildInstructionText('2. + 버튼을 눌러 메뉴를 연 뒤 제품 추가에서 TV를 선택해주세요'),
        const SizedBox(height: 40),
        _buildInstructionText('3. QR 코드를 스캔해주세요'),
      ],
    );
  }

  Widget _buildInstructionText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.2,
      ),
    );
  }

  // 첫 페이지 QR 코드 영역
  Widget _buildQRCodeArea(BuildContext context) {
    return GestureDetector(
      onTap: _handleQRCodeTap, // 클릭하면 로딩 페이지로 이동
      child: Container(
        width: 415,
        height: 416,
        decoration: BoxDecoration(
          // color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Image.asset('assets/qr_code.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
