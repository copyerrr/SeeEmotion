// lib/features/mode/type_select_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/remote_point_overlay.dart';
import '../../services/api_helpers.dart';
import '../../services/tv_remote_service.dart';
import 'mode_guide_page.dart';

class TypeSelectPage extends StatefulWidget {
  const TypeSelectPage({super.key});

  @override
  State<TypeSelectPage> createState() => _TypeSelectPageState();
}

class _TypeSelectPageState extends State<TypeSelectPage> {
  int? _hoveredIndex;
  int? _focusedIndex; // 리모컨으로 포커스된 카드 인덱스
  bool? _previousOkButtonPressed; // 이전 okButtonPressed 값 (변경 감지용)
  bool? _previousLeft; // 이전 left 값 (변경 감지용)
  bool? _previousRight; // 이전 right 값 (변경 감지용)
  bool _isProcessing = false; // 중복 호출 방지 플래그

  // Firebase 리모컨 구독
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;

  @override
  void initState() {
    super.initState();
    _focusedIndex = null; // 처음에는 선택 없음
    _previousOkButtonPressed = null; // 초기값
    _previousLeft = null; // 초기값
    _previousRight = null; // 초기값
    _subscribeToRemoteControl();
  }

  /// Row 형식 카드 그리드에서 포커스 이동 (좌우)
  /// 첫 번째 줄: 0, 1
  /// 두 번째 줄: 2, 3, 4
  void _moveFocusInRow(int direction) {
    // direction: -1 (왼쪽), 1 (오른쪽)
    // 처음 선택이 없으면 첫 번째 카드(0)로 시작
    if (_focusedIndex == null) {
      setState(() {
        _focusedIndex = 0;
      });
      return;
    }

    // 첫 번째 줄 (0, 1)
    if (_focusedIndex! <= 1) {
      if (direction < 0) {
        // 왼쪽: 0 -> 4, 1 -> 0
        setState(() {
          _focusedIndex = _focusedIndex == 0 ? 4 : 0;
        });
      } else {
        // 오른쪽: 0 -> 1, 1 -> 2
        setState(() {
          _focusedIndex = _focusedIndex == 0 ? 1 : 2;
        });
      }
    }
    // 두 번째 줄 (2, 3, 4)
    else {
      if (direction < 0) {
        // 왼쪽: 2 -> 1, 3 -> 2, 4 -> 3
        setState(() {
          _focusedIndex = _focusedIndex! > 2 ? _focusedIndex! - 1 : 1;
        });
      } else {
        // 오른쪽: 2 -> 3, 3 -> 4, 4 -> 0
        setState(() {
          _focusedIndex = _focusedIndex! < 4 ? _focusedIndex! + 1 : 0;
        });
      }
    }
  }

  /// Firebase 리모컨 상태 구독
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      // 왼쪽 화살표 버튼 처리 - false -> true로 변경될 때만 처리
      final currentLeft = data['left'] as bool? ?? false;
      if (_previousLeft == null) {
        _previousLeft = currentLeft;
      } else if (_previousLeft == false && currentLeft == true) {
        _handleLeftArrow();
      }
      _previousLeft = currentLeft;

      // 오른쪽 화살표 버튼 처리 - false -> true로 변경될 때만 처리
      final currentRight = data['right'] as bool? ?? false;
      if (_previousRight == null) {
        _previousRight = currentRight;
      } else if (_previousRight == false && currentRight == true) {
        _handleRightArrow();
      }
      _previousRight = currentRight;

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

      // 확인 버튼 처리 - false -> true로 변경될 때만 처리
      final currentOkButtonPressed = data['okButtonPressed'] as bool? ?? false;

      // 첫 데이터는 무조건 무시하고 현재 값만 저장
      if (_previousOkButtonPressed == null) {
        _previousOkButtonPressed = currentOkButtonPressed;
        return;
      }

      // false -> true로 변경될 때만 처리
      final okButtonChanged =
          _previousOkButtonPressed == false && currentOkButtonPressed == true;

      if (okButtonChanged) {
        // 현재 라우트가 TypeSelectPage인지 확인 (백그라운드에서 실행 중인지 체크)
        final currentRoute = ModalRoute.of(context);
        final isCurrentPage = currentRoute?.isCurrent ?? false;
        
        // 현재 페이지가 활성화되어 있고 포커스된 카드가 있을 때만 처리
        if (isCurrentPage && _focusedIndex != null) {
          _handleConfirmButton();
        }
      }

      // 이전 값 업데이트
      _previousOkButtonPressed = currentOkButtonPressed;
    });
  }

  /// 왼쪽 화살표 버튼 처리 - Row 형식으로 좌우 이동
  void _handleLeftArrow() {
    _moveFocusInRow(-1);
  }

  /// 오른쪽 화살표 버튼 처리 - Row 형식으로 좌우 이동
  void _handleRightArrow() {
    _moveFocusInRow(1);
  }

  /// 확인 버튼 처리 - 포커스된 카드 선택
  void _handleConfirmButton() {
    if (_focusedIndex != null) {
      _selectCard(_focusedIndex!, isRemoteControl: true);
    }
  }

  /// 카드 선택 처리
  void _selectCard(int index, {bool isRemoteControl = false}) {
    // 중복 호출 방지
    if (_isProcessing) {
      return;
    }

    final List<String> titles = ['일반', '청각', '시각', '아동', '시니어'];
    if (index >= 0 && index < titles.length) {
      setState(() {
        _isProcessing = true; // 처리 시작
      });

      final title = titles[index];
      final Map<String, String> userTypeMap = {
        '일반': 'GENERAL',
        '청각': 'HEARING',
        '시각': 'VISION',
        '아동': 'CHILD',
        '시니어': 'SENIOR',
      };
      final String userType = userTypeMap[title] ?? 'GENERAL';

      // DB에 user_type 저장 - 헬퍼 함수로 PUT 요청
      ApiHelpers.put('/profiles/1', {'user_type': userType}).then((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ModeGuidePage(),
            ),
          );
        }
      }).catchError((e) {
        // 웹 환경에서는 백엔드 서버가 없을 수 있으므로 실패해도 다음 화면으로 이동
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ModeGuidePage(),
            ),
          );
        }
      }).whenComplete(() {
        if (mounted) {
          setState(() {
            _isProcessing = false; // 처리 완료
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _tvStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RemotePointerOverlay(
        child: LayoutBuilder(
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

                child: _buildModeSelectContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModeSelectContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 세로 중앙
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 제목
        _buildHeadline(),
        const SizedBox(height: 100),
        // 카드 그리드
        _buildCardGrid(),
      ],
    );
  }

  // 제목 영역
  Widget _buildHeadline() {
    return Column(
      children: [
        Text(
          '시청 유형을 선택해주세요',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 80,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.19,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text(
          '더 편안한 시청 경험을 위해, 나에게 맞는 시청 유형을 선택해주세요',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 32,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            height: 1.19,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // 카드 2 + 3 레이아웃
  Widget _buildCardGrid() {
    //이미지 경로
    final List<Map<String, String>> modes = [
      {
        'title': '일반',
        'iconPath': 'assets/일반.png',
        'iconHoverPath': 'assets/일반-1.png',
      },
      {
        'title': '청각',
        'iconPath': 'assets/청각.png',
        'iconHoverPath': 'assets/청각-1.png',
      },
      {
        'title': '시각',
        'iconPath': 'assets/시각.png',
        'iconHoverPath': 'assets/시각-1.png',
      },
      {
        'title': '아동',
        'iconPath': 'assets/아동.png',
        'iconHoverPath': 'assets/아동-1.png',
      },
      {
        'title': '시니어',
        'iconPath': 'assets/시니어.png',
        'iconHoverPath': 'assets/시니어-1.png',
      },
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 첫 번째 줄: 2개 카드
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildModeCard(
              title: modes[0]['title']!,
              iconPath: modes[0]['iconPath']!,
              iconHoverPath: modes[0]['iconHoverPath']!,
              index: 0,
            ),
            const SizedBox(width: 40),
            _buildModeCard(
              title: modes[1]['title']!, //!값이 null이 아님을 보장
              iconPath: modes[1]['iconPath']!,
              iconHoverPath: modes[1]['iconHoverPath']!,
              index: 1,
            ),
          ],
        ),
        const SizedBox(height: 40),
        // 두 번째 줄: 3개 카드
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildModeCard(
              title: modes[2]['title']!,
              iconPath: modes[2]['iconPath']!,
              iconHoverPath: modes[2]['iconHoverPath']!,
              index: 2,
            ),
            const SizedBox(width: 40),
            _buildModeCard(
              title: modes[3]['title']!,
              iconPath: modes[3]['iconPath']!,
              iconHoverPath: modes[3]['iconHoverPath']!,
              index: 3,
            ),
            const SizedBox(width: 40),
            _buildModeCard(
              title: modes[4]['title']!,
              iconPath: modes[4]['iconPath']!,
              iconHoverPath: modes[4]['iconHoverPath']!,
              index: 4,
            ),
          ],
        ),
      ],
    );
  }

  // 개별 카드
  Widget _buildModeCard({
    required String title,
    required String iconPath,
    required String iconHoverPath,
    required int index,
  }) {
    final bool isHovered = _hoveredIndex == index;
    final bool isFocused = _focusedIndex == index;
    //마우스 올리면 비율이 1.2배로 커짐
    final bool shouldHighlight = isHovered || isFocused;
    final double scale = shouldHighlight ? 1.2 : 1.0;
    final Color borderColor =
        shouldHighlight ? const Color(0xFF3A7BFF) : Colors.transparent;

    // hover 시 커져도 주변이 안 밀리도록 여유 공간 확보
    // hover시 최대 크기 만큼 미리 설정
    return SizedBox(
      width: 380 * 1.2,
      height: 200 * 1.2,
      child: MouseRegion(
        //마우스가 올라가는 순간 hover중임을 알림
        onEnter: (_) => setState(() => _hoveredIndex = index),
        //마우스가 떠나는 순간 hover중이 아님을 알림
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: () {
            // 카드 클릭 시 가이드 페이지로 이동
            _selectCard(index, isRemoteControl: false);
            // Navigator.pushReplacement(
            //   context,
            //   MaterialPageRoute(
            //     builder: (context) => const ModeGuidePage(),
            //   ),
            // );
          },
          onTapDown: (details) {
            // 탭 처리
          },
          onTapCancel: () {
            // 탭 취소 처리
          },
          child: Center(
            //hover시 카드 부드럽게 커지도록 설정
            child: AnimatedScale(
              scale: scale, //1.0 -> 1.2 로 커짐
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              //박스자체 스타일 변경
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                //박스카드 크기
                width: 380,
                height: 210,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 제목
                      buildCardTitle(title),
                      const Spacer(),
                      // 각 카드별 이미지 영역
                      buildCardImageSection(
                          shouldHighlight, iconPath, iconHoverPath),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  //카드 안에 이미지 표시
  Align buildCardImageSection(
    bool isHovered,
    String iconPath,
    String iconHoverPath,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 100,
        height: 100,
        child: _buildIconImage(
          isHovered: isHovered,
          iconPath: iconPath,
          iconHoverPath: iconHoverPath,
        ),
      ),
    );
  }

  //카드 안에 제목 표시
  Text buildCardTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 50,
        fontWeight: FontWeight.w600,
        color: Colors.black,
        height: 1.19,
      ),
    );
  }

  // 이미지 위젯 (아이콘 대신 이미지 전용)
  Widget _buildIconImage({
    required bool isHovered,
    required String iconPath,
    required String iconHoverPath,
  }) {
    final String currentPath = isHovered ? iconHoverPath : iconPath;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
      child: Image.asset(
        currentPath,
        key: ValueKey<String>(currentPath), // 이미지 변경 감지를 위한 key
        fit: BoxFit.contain,
      ),
    );
  }
}
