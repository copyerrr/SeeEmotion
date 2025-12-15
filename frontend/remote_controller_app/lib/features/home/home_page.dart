import 'dart:ui';
import 'package:flutter/material.dart';
import '../remote/remote_home_page.dart';
import '../remote/remote_pad.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.206, -0.937),
            radius: 1.2,
            colors: [
              const Color(0xFFBFD3E5), // #bfd3e5
              const Color(0xFFF4FEFF), // #f4feff
              const Color(0xFFBCDFDC), // #bcdfdc
            ],
            stops: const [0.0, 0.492, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 스크롤 가능한 컨텐츠 영역
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단 헤더: 원포인트 홈
                      _TopHeader(),
                      const SizedBox(height: 20),
                      // 실시간 자막 설정 섹션
                      _SubtitleSection(),
                      const SizedBox(height: 20),
                      // 홈 위치 설정 섹션
                      _HomeLocationSection(),
                      const SizedBox(height: 40),
                      // 즐겨 찾는 제품 섹션
                      _FavoriteProductsSection(),
                      const SizedBox(height: 20),
                      // ThinQ PLAY 섹션
                      _ThinQPlaySection(),
                      const SizedBox(height: 20),
                      // 스마트 루틴 섹션
                      _SmartRoutineSection(),
                      const SizedBox(height: 25),
                      // Thin Q 활용하기 섹션
                      _ThinQUtilizationSection(),
                    ],
                  ),
                ),
              ),
              // 고정된 하단 네비게이션 바
              _BottomNavigationBar(),
            ],
          ),
        ),
      ),
    );
  }
}

// 상단 헤더
class _TopHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: SizedBox(
        width: screenWidth,
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    '서가을 홈',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      height: 1.19,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 화살표 아이콘 (24x24)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.black,
                      size: 16,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // 벨 아이콘 (24x24)
                  Icon(
                    Icons.notifications_outlined,
                    size: 24,
                    color: const Color(0xff5C5C5D),
                  ),
                  const SizedBox(width: 13),
                  // 메뉴 아이콘 (점 3개, 24x24)
                  _buildMenuIcon(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 메뉴 아이콘 (점 3개)
  Widget _buildMenuIcon() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xff5C5C5D),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xff5C5C5D),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xff5C5C5D),
            ),
          ),
        ],
      ),
    );
  }
}

// QR코드 섹션
class _HomeLocationSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: 350,
        height: 114,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 11, top: 17),
              child: Container(
                width: 80,
                height: 80,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        width: 71.71,
                        height: 71.71,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/qr_scan.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 11, top: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 210,
                      height: 41.99,
                      child: const Text(
                        '홈 기기를 QR코드로\n쉽게 연결할 수 있어요.',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('QR코드 찍으러가기 버튼을 눌렀습니다')),
                        );
                      },
                      child: Container(
                        width: 135,
                        height: 32,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFD5DBFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'QR코드 찍으러가기',
                                style: const TextStyle(
                                  color: Color(0xff4A57BF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.19,
                                  fontFamily: 'Pretendard',
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 실시간 자막 설정 섹션
class _SubtitleSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: 350,
        height: 114,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 11, top: 17),
              child: Container(
                width: 80,
                height: 80,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    Positioned(
                      left: 15,
                      top: 11,
                      child: Container(
                        width: 50,
                        height: 58.68,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/remote.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 11, top: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 210.92,
                      height: 41.99,
                      child: const Text(
                        '단순한 티비 시청을 넘어 말하는 이의\n감정과 음악 소리까 자막으로 느껴보세요',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const RemoteHomePage(),
                          ),
                        );
                      },
                      child: Container(
                        width: 135,
                        height: 32,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFD5DBFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                '실시간 자막 설정하기',
                                style: const TextStyle(
                                  color: Color(0xff4A57BF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.19,
                                  fontFamily: 'Pretendard',
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 즐겨 찾는 제품 섹션
class _FavoriteProductsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '즐겨 찾는 제품',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.19,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const RemotePad()),
                  );
                },
                child: Container(
                  width: 120,
                  height: 54.59,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Image.asset(
                        'assets/tv_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 120,
                child: const Text(
                  'TV',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.19,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ThinQ PLAY 섹션
class _ThinQPlaySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: 350,
        height: 65,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFFE4CA), Color(0xFFFF323A), Color(0xFFFF3C7B)],
            stops: [0.0, 0.476, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 6.69, bottom: 6.69),
              child: Container(
                width: 51.56,
                height: 51.56,
                decoration: BoxDecoration(
                  // color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Image.asset(
                  'assets/ThinQ_play_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 15.52),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ThinQ PLAY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        height: 1.19,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '앱을 다운로드하여 제품과 공간을 업그레이드해보세요.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.48,
                        height: 1.19,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 스마트 루틴 섹션
class _SmartRoutineSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 350,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  '스마트 루틴',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.19,
                    fontFamily: 'Pretendard',
                  ),
                ),
                Container(width: 39, height: 39),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 168,
            height: 50.90,
            padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 17.91,
                  height: 18.90,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/시계.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '루틴 알아보기',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.19,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Thin Q 활용하기 섹션
class _ThinQUtilizationSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ThinQ앱 활용하기',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.19,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 350,
            height: 114,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 17),
                  child: Container(
                    width: 80,
                    height: 80,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            width: 71.71,
                            height: 71.71,
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/house_icon.png'),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 11, top: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 210,
                          height: 41.99,
                          child: const Text(
                            '홈 위치를 설정하면 맞춤 정보와 기능을\n사용할 수 있어요.',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.29,
                              fontFamily: 'Pretendard',
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('설정하기 버튼을 눌렀습니다')),
                            );
                          },
                          child: Container(
                            width: 74,
                            height: 32,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFD5DBFF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    '설정하기',
                                    style: const TextStyle(
                                      color: Color(0xff4A57BF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      height: 1.19,
                                      fontFamily: 'Pretendard',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 하단 네비게이션 바
class _BottomNavigationBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      width: screenWidth,
      height: 86.08,
      decoration: const BoxDecoration(color: Color(0xFFEEF3F4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavItem(
              type: NavItemType.home,
              label: '홈',
              isActive: true,
              imagePath: 'assets/home_home.png',
              // 이미지 경로 예시: imagePath: 'assets/home_icon.png', activeImagePath: 'assets/home_icon_active.png'
            ),
            _NavItem(
              type: NavItemType.devices,
              label: '디바이스',
              isActive: false,

              imagePath: 'assets/device.png',
              // 이미지 경로 예시: imagePath: 'assets/devices_icon.png', activeImagePath: 'assets/devices_icon_active.png'
            ),
            _NavItem(
              type: NavItemType.care,
              label: '케어',
              isActive: false,
              imagePath: 'assets/care.png',
              // 이미지 경로 예시: imagePath: 'assets/care_icon.png', activeImagePath: 'assets/care_icon_active.png'
            ),
            _NavItem(
              type: NavItemType.menu,
              label: '메뉴',
              isActive: false,
              imagePath: 'assets/menu.png',
              // 이미지 경로 예시: imagePath: 'assets/menu_icon.png', activeImagePath: 'assets/menu_icon_active.png'
            ),
          ],
        ),
      ),
    );
  }
}

enum NavItemType { home, devices, care, menu }

// 네비게이션 아이템
class _NavItem extends StatelessWidget {
  final NavItemType type;
  final String label;
  final bool isActive;
  final String? imagePath; // 일반 상태 이미지 경로
  final String? activeImagePath; // 활성 상태 이미지 경로

  const _NavItem({
    required this.type,
    required this.label,
    this.isActive = false,
    this.imagePath,
    this.activeImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 23, height: 23, child: _buildIcon()),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xff6D6F71),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 2, //이미지와 글자 간격
            fontFamily: 'Pretendard',
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    // 활성 상태이고 activeImagePath가 있으면 우선 사용
    if (isActive && activeImagePath != null) {
      return Image.asset(
        activeImagePath!,
        width: 23,
        height: 23,
        fit: BoxFit.contain,
      );
    }

    // imagePath가 있으면 사용 (활성/비활성 모두)
    if (imagePath != null) {
      return Image.asset(
        imagePath!,
        width: 23,
        height: 23,
        fit: BoxFit.contain,
      );
    }

    // 이미지 경로가 없는 경우 빈 위젯 반환
    return const SizedBox.shrink();
  }
}
