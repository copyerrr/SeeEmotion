// lib/features/mode/mode_select_page.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../services/tv_remote_service.dart';
import '../../services/api_helpers.dart';
import '../../utils/remote_point_overlay.dart';
import 'guide_page.dart';

class ModeSelectPage extends StatefulWidget {
  const ModeSelectPage({super.key});

  @override
  State<ModeSelectPage> createState() => _ModeSelectPageState();
}

class _ModeSelectPageState extends State<ModeSelectPage> {
  String? _selectedMode; // 선택된 모드
  String? _focusedMode; // 리모컨으로 포커스된 모드 (확인 버튼으로 선택)
  bool? _previousOkButtonPressed; // 이전 okButtonPressed 값 (변경 감지용)
  bool? _previousLeft; // 이전 left 값 (변경 감지용)
  bool? _previousRight; // 이전 right 값 (변경 감지용)
  bool _isReady = false; // 페이지 준비 완료 여부 (초기 로드 후 짧은 지연)

  bool _isVideoAreaHovered = false; // 영상 영역 호버 상태
  String? _mouseFocusedMode; // 마우스로 포커스된 모드 (첫 클릭 시 설정)
  VideoPlayerController? _previewVideoController; // 미리보기 비디오 컨트롤러

  // 모드 목록 (순서 고정)

  final List<Map<String, String>> _modes = const [
    {'label': '없음', 'mode': 'none'},
    {'label': '영화/드라마', 'mode': 'movie'},
    {'label': '다큐멘터리', 'mode': 'documentary'},
    {'label': '예능', 'mode': 'variety'},
  ];

  // Firebase 리모컨 구독
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;

  @override
  void initState() {
    super.initState();
    // 처음부터 첫 번째 모드(없음)에 포커스 설정
    _focusedMode = _modes.first['mode'];
    _previousOkButtonPressed = null; // 초기값
    _previousLeft = null; // 초기값
    _previousRight = null; // 초기값
    _isReady = true; // 즉시 Firebase 이벤트 처리 시작

    _subscribeToRemoteControl();
    
    // 초기 비디오 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final videoPath = _getVideoPathForMode(_focusedMode);
      _initializePreviewVideo(videoPath);
    });
  }

  /// Firebase 리모컨 상태 구독
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      // 페이지가 준비되지 않았으면 모든 이벤트 무시
      if (!_isReady) {
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      // 왼쪽 화살표 버튼 처리 - false -> true로 변경될 때만 처리
      final currentLeft = data['left'] as bool? ?? false;
      if (_previousLeft == null) {
        // 첫 데이터는 무조건 무시하고 현재 값만 저장
        _previousLeft = currentLeft;
      } else if (_previousLeft == false && currentLeft == true) {
        _handleLeftArrow();
        _previousLeft = currentLeft;
      } else {
        _previousLeft = currentLeft;
      }

      // 오른쪽 화살표 버튼 처리 - false -> true로 변경될 때만 처리
      final currentRight = data['right'] as bool? ?? false;
      if (_previousRight == null) {
        // 첫 데이터는 무조건 무시하고 현재 값만 저장
        _previousRight = currentRight;
      } else if (_previousRight == false && currentRight == true) {
        _handleRightArrow();
        _previousRight = currentRight;
      } else {
        _previousRight = currentRight;
      }

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
        return; // 첫 데이터는 left/right도 처리하지 않도록 return
      }

      // false -> true로 변경될 때만 처리
      final okButtonChanged =
          _previousOkButtonPressed == false && currentOkButtonPressed == true;

      if (okButtonChanged) {
        // 현재 라우트가 ModeSelectPage인지 확인 (백그라운드에서 실행 중인지 체크)
        final currentRoute = ModalRoute.of(context);
        final isCurrentPage = currentRoute?.isCurrent ?? false;
        
        // 현재 페이지가 활성화되어 있고 포커스된 모드가 있을 때만 처리
        if (isCurrentPage && _focusedMode != null) {
          _handleConfirmButton();
        }
      }

      // 이전 값 업데이트
      _previousOkButtonPressed = currentOkButtonPressed;
    });
  }

  /// 왼쪽 화살표 버튼 처리 - 포커스만 이동
  void _handleLeftArrow() {
    // 처음 선택이 없으면 첫 번째 모드로 시작
    if (_focusedMode == null) {
      setState(() {
        _focusedMode = _modes.first['mode'];
      });
      final videoPath = _getVideoPathForMode(_focusedMode);
      _initializePreviewVideo(videoPath);
      return;
    }
    final currentIndex = _modes.indexWhere((m) => m['mode'] == _focusedMode);
    String? newMode;
    if (currentIndex > 0) {
      newMode = _modes[currentIndex - 1]['mode'];
    } else {
      // 첫 번째 모드면 마지막 모드로 순환
      newMode = _modes.last['mode'];
    }
    setState(() {
      _focusedMode = newMode;
    });
    final videoPath = _getVideoPathForMode(newMode);
    _initializePreviewVideo(videoPath);
  }

  /// 오른쪽 화살표 버튼 처리 - 포커스만 이동
  void _handleRightArrow() {
    // 처음 선택이 없으면 첫 번째 모드로 시작
    if (_focusedMode == null) {
      setState(() {
        _focusedMode = _modes.first['mode'];
      });
      final videoPath = _getVideoPathForMode(_focusedMode);
      _initializePreviewVideo(videoPath);
      return;
    }
    final currentIndex = _modes.indexWhere((m) => m['mode'] == _focusedMode);
    String? newMode;
    if (currentIndex < _modes.length - 1) {
      newMode = _modes[currentIndex + 1]['mode'];
    } else {
      // 마지막 모드면 첫 번째 모드로 순환
      newMode = _modes.first['mode'];
    }
    setState(() {
      _focusedMode = newMode;
    });
    final videoPath = _getVideoPathForMode(newMode);
    _initializePreviewVideo(videoPath);
  }

  /// 확인 버튼 처리 - 포커스된 모드를 선택하고 페이지 이동
  void _handleConfirmButton() {
    if (_focusedMode != null) {
      setState(() {
        _selectedMode = _focusedMode; // 포커스된 모드를 선택
      });
      // DB에 모드 저장
      _saveSelectedModeToDb(_focusedMode!);
      _navigateToHome();
    }
  }

  /// 선택된 모드를 DB에 저장하고 기본 설정 적용
  Future<void> _saveSelectedModeToDb(String mode) async {
    try {
      // 'none' 모드는 DB에 저장하지 않음
      if (mode == 'none') {
        return;
      }

      // 프로필 ID (기본값 1 사용)
      const int profileId = 1;

      // 모드 목록 가져오기 - 헬퍼 함수로 GET 요청
      final modesData = await ApiHelpers.get(
        '/caption-modes/',
        query: {'profile_id': profileId.toString()},
      );
      final modesFromDb = (modesData as List).cast<Map<String, dynamic>>();

      // 모드 이름을 한글로 변환
      String? modeName;
      if (mode == 'movie')
        modeName = '영화/드라마';
      else if (mode == 'documentary')
        modeName = '다큐멘터리';
      else if (mode == 'variety') modeName = '예능';

      if (modeName == null) {
        return;
      }

      // DB에서 모드 찾기
      try {
        final modeData = modesFromDb.firstWhere(
          (m) => (m['mode_name'] as String? ?? '') == modeName,
        );

        final modeId = modeData['id'] as int?;
        if (modeId != null) {
          // 모드 선택 저장 - 헬퍼 함수로 PUT 요청
          await ApiHelpers.put(
            '/caption-settings/profile/$profileId',
            {'mode_id': modeId},
          );

          // 모드별 기본 설정을 DB에 저장
          await _saveModeDefaultSettings(mode, modeId);
        }
      } catch (e) {
        // 모드가 없으면 생성 시도
        await _createModeIfNotExists(mode, modeName, profileId);
      }
    } catch (e) {
      // 에러 무시
    }
  }

  /// 모드가 없으면 생성
  Future<void> _createModeIfNotExists(
      String mode, String modeName, int profileId) async {
    try {
      bool fontSizeToggle = false;
      bool fontColorToggle = false;
      bool speaker = false;
      bool bgm = false;
      bool effect = false;

      // 모드별 기본 설정
      if (mode == 'movie') {
        // 드라마/영화: font level 2, color level 2, font on, color on, 화자 on, 배경음 on, 효과음 on
        fontSizeToggle = true;
        fontColorToggle = true;
        speaker = true;
        bgm = true;
        effect = true;
      } else if (mode == 'documentary') {
        // 다큐: font off, color off, 화자 off, 배경음 on, 효과음 on
        fontSizeToggle = false;
        fontColorToggle = false;
        speaker = false;
        bgm = true;
        effect = true;
      } else if (mode == 'variety') {
        // 예능: font level 2, color level 2, font on, color on, 화자 off, 배경음 on, 효과음 off
        fontSizeToggle = true;
        fontColorToggle = true;
        speaker = false;
        bgm = true;
        effect = false;
      }

      // 모드 생성 - 헬퍼 함수로 POST 요청
      await ApiHelpers.post(
        '/caption-modes/',
        {
          'profile_id': profileId,
          'mode_name': modeName,
          'is_empathy_on': true,
          'fontSize_toggle': fontSizeToggle,
          'fontColor_toggle': fontColorToggle,
          'speaker': speaker,
          'bgm': bgm,
          'effect': effect,
        },
      );

      // 생성 후 다시 모드 목록 가져오기
      final modesData = await ApiHelpers.get(
        '/caption-modes/',
        query: {'profile_id': profileId.toString()},
      );
      final modesFromDb = (modesData as List).cast<Map<String, dynamic>>();
      final newModeData = modesFromDb.firstWhere(
        (m) => (m['mode_name'] as String? ?? '') == modeName,
      );

      final newModeId = newModeData['id'] as int?;
      if (newModeId != null) {
        // 모드 선택 저장 - 헬퍼 함수로 PUT 요청
        await ApiHelpers.put(
          '/caption-settings/profile/$profileId',
          {'mode_id': newModeId},
        );

        // 모드별 기본 설정을 DB에 저장 (font_level, color_level 포함)
        await _saveModeDefaultSettings(mode, newModeId);
      }
    } catch (e) {
      // 에러 무시
    }
  }

  /// 모드별 기본 설정을 DB에 저장 - 백엔드에서 처리 (변환 로직 제거)
  Future<void> _saveModeDefaultSettings(String mode, int modeId) async {
    try {
      // 모드별 기본 설정 - 백엔드에서 처리
      await ApiHelpers.put(
        '/caption-modes/$modeId/default-settings',
        {'mode_type': mode},
      );
    } catch (e) {
      // 에러 무시
    }
  }

  /// 홈 페이지로 이동 (GuideShakePage 건너뛰고 직접 HomePage로 이동)
  void _navigateToHome() {
    // 페이지 이동 전 비디오 정리 (소리 끄기)
    _disposePreviewVideo();
    Map<String, bool>? initialToggles;
    String? initialSoundPitch;
    String? initialEmotionColor;

    // 모드별 기본 설정
    if (_selectedMode == 'movie') {
      // 드라마/영화: font level 2, color level 2, font on, color on, 화자 on, 배경음 on, 효과음 on
      initialToggles = {
        '소리의 높낮이': true,
        '감정 색상': true,
        '화자 설정': true,
        '배경음 표시': true,
        '효과음 표시': true,
      };
      initialSoundPitch = '2단계';
      initialEmotionColor = '2단계';
    } else if (_selectedMode == 'documentary') {
      // 다큐: font off, color off, 화자 off, 배경음 on, 효과음 on
      initialToggles = {
        '소리의 높낮이': false,
        '감정 색상': false,
        '화자 설정': false,
        '배경음 표시': true,
        '효과음 표시': true,
      };
      initialSoundPitch = '없음';
      initialEmotionColor = '없음';
    } else if (_selectedMode == 'variety') {
      // 예능: font level 2, color level 2, font on, color on, 화자 off, 배경음 on, 효과음 off
      initialToggles = {
        '소리의 높낮이': true,
        '감정 색상': true,
        '화자 설정': false,
        '배경음 표시': true,
        '효과음 표시': false,
      };
      initialSoundPitch = '2단계';
      initialEmotionColor = '2단계';
    }

    // GuideShakePage로 이동 (정상적인 플로우)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuideShakePage(
          initialToggles: initialToggles,
          initialMode: _selectedMode,
          initialSoundPitch: initialSoundPitch,
          initialEmotionColor: initialEmotionColor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tvStateSubscription?.cancel();
    _disposePreviewVideo();
    super.dispose();
  }

  // 모드별 영상 경로 매핑
  // 포커스된 모드에 따라 미리보기 비디오 경로 반환
  String? _getVideoPathForMode(String? mode) {
    if (mode == null) return null;
    
    // 미리보기 비디오 매핑
    switch (mode) {
      case 'none': // 없음
        return 'assets/general_preview.mp4';
      case 'movie': // 영화/드라마
        return 'assets/drama_preview.mp4';
      case 'documentary': // 다큐멘터리
        return 'assets/dacu_preview.mp4';
      case 'variety': // 예능
        return 'assets/date_preview.mp4';
      default:
        return null;
    }
  }

  // 비디오 컨트롤러 초기화 및 관리
  Future<void> _initializePreviewVideo(String? videoPath) async {
    // 기존 컨트롤러 정리
    await _disposePreviewVideo();

    if (videoPath == null || !mounted) return;

    try {
      _previewVideoController = VideoPlayerController.asset(videoPath)
        ..initialize().then((_) {
          if (mounted && _previewVideoController != null) {
            setState(() {});
            _previewVideoController!.setLooping(true);
            _previewVideoController!.setVolume(0.0); // 소리 끄기
            _previewVideoController!.play();
          }
        }).catchError((error) {
          // 에러 무시
        });
    } catch (e) {
      // 에러 무시
    }
  }

  // 비디오 컨트롤러 정리
  Future<void> _disposePreviewVideo() async {
    if (_previewVideoController != null) {
      await _previewVideoController!.pause();
      await _previewVideoController!.dispose();
      _previewVideoController = null;
    }
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

                child: _buildContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  //전체 컨텐츠 레이아웃

  Widget _buildContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeadline(), // 🔥 통일된 메인 제목

          const SizedBox(height: 48),

          //버튼 컨테이너 영역

          _buildButtonContainer(),

          const SizedBox(height: 48),

          //영상 영역

          _buildVideoArea(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------

  // 통일된 제목 스타일 (Headline)

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

            height: 1.193, // ★ 통일
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

  // -------------------------------------------------------------

  // 버튼 컨테이너 (Segmented Control 스타일)

  Widget _buildButtonContainer() {
    // 선택된 버튼의 인덱스 찾기 (선택된 모드가 없으면 포커스된 모드 사용)

    int selectedIndex = -1;
    String? modeToHighlight = _selectedMode ?? _focusedMode;

    if (modeToHighlight != null) {
      for (int i = 0; i < _modes.length; i++) {
        if (_modes[i]['mode'] == modeToHighlight) {
          selectedIndex = i;
          break;
        }
      }
    }

    // 컨테이너 크기 계산 (버튼 4개 + 간격 3개 + 패딩)

    const double buttonWidth = 250.0;

    const double buttonGap = 8.0;

    const double padding = 8.0;

    final double containerWidth = (buttonWidth * _modes.length) +
        (buttonGap * (_modes.length - 1)) +
        (padding * 2);

    return Center(
      child: Container(
        width: containerWidth,
        padding: const EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topLeft,
          children: [
            // 버튼들 (Row가 컨테이너 전체 너비를 차지하도록 수정)

            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_modes.length, (index) {
                final modeData = _modes[index];

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index > 0) const SizedBox(width: buttonGap),
                    _buildModeButton(
                      label: modeData['label']!,
                      mode: modeData['mode']!,
                      isSelected: _selectedMode == modeData['mode'],
                    ),
                  ],
                );
              }),
            ),

            // 하이라이트 스트로크 (선택된 버튼 위치로 이동)

            if (selectedIndex >= 0) _buildHighlightStroke(selectedIndex),
          ],
        ),
      ),
    );
  }

  // 하이라이트 스트로크 위젯

  Widget _buildHighlightStroke(int selectedIndex) {
    // 버튼 너비와 간격

    const double buttonWidth = 250.0;

    const double buttonGap = 8.0;

    const double padding = 8.0;

    // 선택된 버튼의 left 위치 계산

    double left = padding;

    for (int i = 0; i < selectedIndex; i++) {
      left += buttonWidth + buttonGap;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      left: left,
      child: Container(
        width: buttonWidth,
        height: 59,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1),
        ),
      ),
    );
  }

  // -------------------------------------------------------------

  // 개별 버튼 UI

  Widget _buildModeButton({
    required String label,
    required String mode,
    required bool isSelected,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        // 마우스 호버 시 포커스만 설정 (선택하지 않음)
        setState(() {
          _mouseFocusedMode = mode;
          _focusedMode = mode; // 리모컨 포커스도 함께 업데이트
        });
        final videoPath = _getVideoPathForMode(mode);
        _initializePreviewVideo(videoPath);
      },
      onExit: (_) {
        // 마우스가 벗어나면 마우스 포커스만 해제 (리모컨 포커스는 유지)
        setState(() {
          if (_mouseFocusedMode == mode) {
            _mouseFocusedMode = null;
          }
        });
      },
      child: GestureDetector(
        onTap: () {
          // 마우스 클릭 시: 이미 포커스되어 있으면 선택하고 이동, 아니면 포커스만 설정
          if (_mouseFocusedMode == mode && _focusedMode == mode) {
            // 이미 포커스되어 있으면 선택하고 이동
            setState(() {
              _selectedMode = mode;
            });
            _saveSelectedModeToDb(mode);
            _navigateToHome();
          } else {
            // 포커스되지 않았으면 포커스만 설정
            setState(() {
              _mouseFocusedMode = mode;
              _focusedMode = mode;
            });
          }
        },
        child: Container(
          width: 250,

          height: 59,

          // border는 하이라이트 스트로크로 처리하므로 제거

          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Pretendard',

                fontSize: 28,

                fontWeight: FontWeight.w400,

                color: Colors.white,

                height: 1.4, // lineHeight: 39.2px / fontSize: 28px ≈ 1.4
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------

  // 영상 영역

  // 모드에 따라 다른 영상/이미지 표시

  Widget _buildVideoArea() {
    // 포커스된 모드에 따라 미리보기 이미지 표시 (선택된 모드가 없으면 포커스된 모드 사용)
    final String? modeForPreview = _selectedMode ?? _focusedMode;
    final videoPath = _getVideoPathForMode(modeForPreview);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _isVideoAreaHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isVideoAreaHovered = false;
        });
      },
      child: GestureDetector(
        onTap: () {
          // 마우스 클릭 시: 포커스된 모드가 있으면 선택하고 이동, 없으면 첫 번째 모드로 포커스 설정
          if (_focusedMode != null) {
            // 이미 포커스되어 있으면 선택하고 이동
            setState(() {
              _selectedMode = _focusedMode;
            });
            _saveSelectedModeToDb(_focusedMode!);
            _navigateToHome();
          } else {
            // 포커스가 없으면 첫 번째 모드로 포커스 설정 (호버 상태)
            setState(() {
              _focusedMode = _modes.first['mode'];
              _mouseFocusedMode = _modes.first['mode'];
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 800,
          height: 500,
          decoration: BoxDecoration(
            color: const Color(0xFFD9D9D9),
            borderRadius: BorderRadius.circular(20),
            border: _isVideoAreaHovered
                ? Border.all(color: Colors.white, width: 4)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: videoPath != null && _previewVideoController != null && _previewVideoController!.value.isInitialized
                ? IgnorePointer(
                    child: SizedBox(
                      width: 800,
                      height: 500,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _previewVideoController!.value.size.width,
                          height: _previewVideoController!.value.size.height,
                          child: VideoPlayer(_previewVideoController!),
                        ),
                      ),
                    ),
                  )
                : _buildPlaceholder(),
          ),
        ),
      ),
    );
  }

  // 플레이스홀더 (선택되지 않았거나 영상을 찾을 수 없을 때)

  Widget _buildPlaceholder() {
    final String? modeForPreview = _selectedMode ?? _focusedMode;
    return Container(
      width: 800,
      height: 500,
      color: const Color(0xFFD9D9D9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 120,
              color: Colors.black.withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            Text(
              modeForPreview == null ? '시청 유형을 선택해주세요' : '영상 영역',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 32,
                fontWeight: FontWeight.w500,
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              modeForPreview == null
                  ? '위에서 시청 유형을 선택하면 영상이 표시됩니다'
                  : '클릭하여 홈으로 이동',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 20,
                fontWeight: FontWeight.w400,
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
