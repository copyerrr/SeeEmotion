// lib/features/settings/setting_page.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/tv_remote_service.dart';
import '../../services/api_helpers.dart';
import '../../utils/slide_page_route.dart';
import '../../utils/remote_point_overlay.dart';
import '../screens/home/home_page.dart';

class SettingPage extends StatefulWidget {
  final Map<String, bool> toggles;

  final String? initialSoundPitch;

  final String? initialEmotionColor;

  final int? profileId; // profile_id 추가

  const SettingPage({
    super.key,
    required this.toggles,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.profileId,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late Map<String, bool> _localToggles;
  OverlayEntry? _overlayEntry;
  final GlobalKey _soundPitchFieldKey = GlobalKey();
  final GlobalKey _emotionColorFieldKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  void _showDropdown(GlobalKey key, Widget panel, double width) {
    // 1. 기존에 열린게 있으면 닫기
    _removeOverlay();

    // 2. 버튼의 현재 화면상 위치(Global Position) 찾기
    final RenderBox? renderBox =
        key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero); // 화면 절대 좌표
    final size = renderBox.size;

    // 3. 오버레이 생성
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // (1) 배경을 클릭하면 닫히도록 투명판 깔기
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: Container(color: Colors.transparent),
            ),
          ),
          // (2) 실제 드롭다운 패널 배치 (계산된 위치 사용)
          Positioned(
            left: offset.dx,
            top: offset.dy + size.height, // 버튼 바로 아래
            width: width, // 패널 너비 지정 (이미지 제외한 너비 등)
            child: panel,
          ),
        ],
      ),
    );

    // 4. 화면에 끼워넣기
    Overlay.of(context).insert(_overlayEntry!);
  }

  // 👇 [추가] 드롭다운 닫기 함수
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // 화살표 아이콘 상태 갱신을 위해 setState 호출
    setState(() {
      _isSoundPitchExpanded = false;
      _isEmotionColorExpanded = false;
    });
  }

  // 👇 [추가] 필드의 전역 위치를 계산하는 함수
  // 👇 [추가] 특정 필드의 위치를 Stack 기준으로 계산하는 함수
  Offset? _getRelativePosition(GlobalKey fieldKey) {
    // 1. Stack(부모)과 Field(자식)의 렌더링 박스를 찾음
    final RenderBox? stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? fieldBox =
        fieldKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox == null || fieldBox == null) return null;

    // 2. Stack을 기준으로 Field의 위치(x, y)를 계산해서 반환
    try {
      return fieldBox.localToGlobal(Offset.zero, ancestor: stackBox);
    } catch (e) {
      return null;
    }
  }

  String _selectedMode = 'none';
  String? _focusedMode; // 리모컨으로 포커스된 모드 (확인 버튼으로 선택)
  final Map<String, bool> _isFirstConfirm =
      {}; // 각 모드별 첫 번째 확인 상태 (true: 첫 번째, false: 두 번째)
  bool? _previousOkButtonPressed; // 이전 okButtonPressed 값 (변경 감지용)

  String _modeName = '';
  late final TextEditingController _modeNameController;

  String _soundPitch = '없음';

  String _emotionColor = '없음';

  bool _isSoundPitchExpanded = false;

  bool _isEmotionColorExpanded = false;

  final Map<String, bool> _hoveredModes = {}; // 각 모드별 호버 상태

  bool _isApplyHovered = false; // 적용하기 버튼 호버 상태

  bool _isAddHovered = false; // 추가하기 버튼 호버 상태

  // 초기값 저장 (변경 감지용)

  String _initialModeName = '';

  String _initialSoundPitch = '없음';

  String _initialEmotionColor = '없음';

  Map<String, bool> _initialToggles = {};

  // 커스텀 모드 목록 (동적으로 추가됨)

  final List<Map<String, dynamic>> _customModes = [];

  // DB에서 가져온 모드 목록 (모든 모드 포함)
  List<Map<String, dynamic>> _modesFromDb = [];

  // ============================================================================

  // 레이아웃 상수

  // ============================================================================

  /// 왼쪽 라벨 폭

  static const double _labelWidth = 220;

  /// 라벨과 입력 필드 사이 간격

  static const double _labelGap = 18;

  /// 모드 선택 컨테이너 너비

  static const double _modeSelectorWidth = 1390;

  /// 모드 선택 컨테이너 높이

  static const double _modeSelectorHeight = 83;

  /// 모드 버튼 높이

  static const double _modeButtonHeight = 59;

  /// 모드 버튼 간격

  static const double _modeButtonSpacing = 20;

  /// 설정 섹션 너비

  static const double _settingsSectionWidth = 718;

  /// 설정 섹션 높이

  static const double _settingsSectionHeight = 500;

  /// 섹션 간 간격

  static const double _sectionGap = 60;

  /// 소리의 높낮이 필드 너비

  static const double _soundPitchFieldWidth = 460;

  /// 소리의 높낮이 이미지 크기

  static const double _soundPitchImageSize = 80;

  /// 소리의 높낮이 패널 너비 (입력 필드 너비 - 이미지 - 간격)

  static const double _soundPitchPanelWidth = 340;

  /// 감정 색상 필드 너비

  static const double _emotionColorFieldWidth = 460;

  /// 미리보기 영역 너비

  static const double _previewWidth = 560;

  /// 미리보기 영역 높이

  static const double _previewHeight = 315;

  /// 버튼 너비

  static const double _buttonWidth = 191;

  /// 버튼 높이

  static const double _buttonHeight = 60;

  /// 버튼 간 간격

  static const double _buttonSpacing = 24;

  /// 입력 필드 높이

  static const double _inputFieldHeight = 79;

  /// 드롭다운 필드 높이

  static const double _dropdownFieldHeight = 80;

  /// 필드 간 간격

  static const double _fieldSpacing = 40;

  /// 패널 옵션 높이

  static const double _panelOptionHeight = 80;

  /// 감정 색상 옵션 높이

  static const double _emotionColorOptionHeight = 79;

  /// 색상 팔레트 박스 너비 (패널 내)

  static const double _colorPaletteBoxWidth = 30;

  /// 색상 팔레트 박스 높이 (패널 내)

  static const double _colorPaletteBoxHeight = 38;

  /// 색상 팔레트 박스 너비 (필드 미리보기)

  static const double _colorPalettePreviewWidth = 18;

  /// 색상 팔레트 박스 높이 (필드 미리보기)

  static const double _colorPalettePreviewHeight = 26;

  /// settings 섹션 안에서 "소리의 높낮이 셀 아래쪽" 위치 (패널 시작 y)

  /// 계산: 10(패딩) + 79(모드이름) + 40(간격) + 80(셀높이)

  static const double _soundPitchPanelTop = 209;

  /// 소리의 높낮이 패널 왼쪽 위치

  /// 계산: 라벨 너비 + 라벨 간격 + 이미지 크기 + 간격 = 220 + 18 + 80 + 20

  static const double _soundPitchPanelLeft = 338;

  /// 감정 색상 패널 위치 (y)

  /// 계산: 10 + 79 + 40 + 80 + 40 + 80 - 약간 여유

  static const double _emotionColorPanelTop = 321;

  /// 감정 색상 패널 왼쪽 위치

  /// 계산: 라벨 너비 + 라벨 간격 = 220 + 18

  static const double _emotionColorPanelLeft = 238;

  // ============================================================================

  // 색상 상수

  // ============================================================================

  /// 폰트 패밀리

  static const String _fontFamily = 'Pretendard';

  /// 입력 필드 배경색

  static const Color _fieldBgColor = Color(0xFF333333);

  /// 메인 파란색 (버튼, 테두리 등)

  static const Color _primaryBlue = Color(0xFF3A7BFF);

  /// 적용하기 버튼 호버 색상

  static const Color _applyButtonHoverColor = Color(0xff6698FF);

  /// 추가/삭제 버튼 배경색 (기본)

  static const Color _addDeleteButtonBgColor = Color(0xFF141311);

  /// 추가/삭제 버튼 배경색 (호버)

  static const Color _addDeleteButtonHoverBgColor = Color(0xFF37342F);

  /// 모드 선택 컨테이너 배경색

  static const Color _modeSelectorBgColor = Color(0xFF333333);

  /// 구분선 색상

  static const Color _separatorColor = Color(0xFF666666);

  /// 기본 모드 버튼 배경색

  static const Color _defaultModeButtonBgColor = Color(0xFFE0E0E0);

  /// 기본 모드 버튼 호버 배경색

  static const Color _defaultModeButtonHoverBgColor = Color(0xFFAFAFAF);

  /// 커스텀 모드 버튼 배경색 (노란색)

  static const Color _customModeButtonBgColor = Color(0xFFFFD54F);

  /// 커스텀 모드 버튼 호버 배경색 (주황색)

  static const Color _customModeButtonHoverBgColor = Color(0xFFFFB800);

  /// 스크롤바 색상

  static const Color _scrollbarColor = Color(0xFFBABFC4);

  /// 토글 비활성 트랙 색상

  static const Color _toggleInactiveTrackColor = Color(0xFF4A4A4A);

  /// 미리보기 배경색

  static const Color _previewBgColor = Color(0xFFD9D9D9);

  /// 선택된 옵션 배경색 (투명도)

  static const double _selectedOptionBgOpacity = 0.15;

  /// 패널 그림자 투명도

  static const double _panelShadowOpacity = 0.3;

  /// 비활성화된 필드 투명도

  static const double _disabledFieldOpacity = 0.5;

  // ============================================================================

  // 텍스트 스타일 상수

  // ============================================================================

  /// 라벨 텍스트 스타일 (왼쪽 라벨용)

  static const TextStyle _labelTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 35,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    height: 53.2 / 38,
  );

  /// 입력 필드 텍스트 스타일

  static const TextStyle _fieldTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    height: 39.2 / 28,
  );

  /// 버튼 텍스트 스타일

  static const TextStyle _buttonTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    height: 39.2 / 28,
  );

  /// 모드 버튼 텍스트 스타일

  static const TextStyle _modeButtonTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 39.2 / 28,
  );

  /// 모드 이름 필드 힌트/카운터 텍스트 스타일

  static const TextStyle _modeNameCounterTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    height: 33.6 / 24,
  );

  /// 권장 배지 텍스트 스타일

  static const TextStyle _recommendedBadgeTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: Colors.black,
    height: 33.6 / 24,
  );

  /// 미리보기 제목 텍스트 스타일

  static const TextStyle _previewTitleTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 38,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    height: 53.2 / 38,
  );

  /// 미리보기 하단 텍스트 스타일

  static const TextStyle _previewBottomTextStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 25.2,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 30.07 / 25.2,
  );

  // ============================================================================

  // 애니메이션 상수

  // ============================================================================

  /// 버튼 애니메이션 지속 시간

  static const Duration _buttonAnimationDuration = Duration(milliseconds: 200);

  /// 모드 버튼 추가 애니메이션 지속 시간

  static const Duration _modeButtonAnimationDuration = Duration(
    milliseconds: 300,
  );

  /// 스크롤 애니메이션 지속 시간

  static const Duration _scrollAnimationDuration = Duration(milliseconds: 300);

  /// 스크롤 애니메이션 커브

  static const Curve _scrollAnimationCurve = Curves.easeOut;

  /// 모드 버튼 애니메이션 커브

  static const Curve _modeButtonAnimationCurve = Curves.easeOut;

  // ============================================================================

  // 데이터 상수

  // ============================================================================

  /// 기본 모드 목록 (없음, 영화/드라마, 다큐멘터리, 예능)

  final List<Map<String, String>> _modes = const [
    {'label': '없음', 'mode': 'none'},
    {'label': '영화/드라마', 'mode': 'movie'},
    {'label': '다큐멘터리', 'mode': 'documentary'},
    {'label': '예능', 'mode': 'variety'},
  ];

  /// 헤드라인 텍스트 데이터 (제목 + 부제목)

  final List<Map<String, dynamic>> textList = const [
    {'text': '나에게 편한 자막 스타일을 골라보세요.', 'size': 80.0, 'weight': FontWeight.w600},
    {
      'text': '시청 중에도 언제든 쉽게 바꿀 수 있어요.',
      'size': 32.0,
      'weight': FontWeight.w500,
    },
  ];

  /// 소리의 높낮이 옵션 목록

  static const List<String> _soundPitchOptions = ['없음', '1단계', '2단계', '3단계'];

  /// 토글 설정 목록 (라벨과 키가 동일)

  static const List<String> _toggleLabels = ['화자 설정', '배경음 표시', '효과음 표시'];

  // 설정 영역 스크롤 컨트롤러 (해당 영역만 스크롤 + 스크롤바 표시용)

  final ScrollController _settingsScrollController = ScrollController();

  // 모드 선택 영역 스크롤 컨트롤러

  final ScrollController _modeSelectorScrollController = ScrollController();

  // 소리의 높낮이 옵션 스크롤 컨트롤러
  final ScrollController _soundPitchScrollController = ScrollController();

  // 감정 색상 옵션 스크롤 컨트롤러
  final ScrollController _emotionColorScrollController = ScrollController();

  // Firebase 리모컨 구독
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;

  @override
  void initState() {
    super.initState();

    _modeNameController = TextEditingController(text: _modeName);

    _localToggles = Map.from(widget.toggles);

    _initialToggles = Map.from(widget.toggles);

    // 초기 소리의 높낮이 설정

    if (widget.initialSoundPitch != null) {
      _soundPitch = widget.initialSoundPitch!;

      _initialSoundPitch = widget.initialSoundPitch!;
    }

    // 초기 감정 색상 설정

    if (widget.initialEmotionColor != null) {
      _emotionColor = widget.initialEmotionColor!;

      _initialEmotionColor = widget.initialEmotionColor!;
    }

    // Firebase 리모컨 구독 시작
    _subscribeToRemoteControl();
    // 초기 포커스 설정
    _focusedMode = _selectedMode;

    // DB에서 모드 목록 불러오기
    _loadModesFromDb().then((_) {
      // 모드 목록 로딩 완료 후 현재 선택된 모드의 DB 값 불러오기
      if (_selectedMode == 'none') {
        _loadModeSettingsFromDb('none');
      }
    });
  }

  /// Firebase 리모컨 상태 구독
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      // 뒤로가기 버튼 처리
      if (data.containsKey('backButtonPressed') &&
          (data['backButtonPressed'] as bool? ?? false)) {
        if (mounted) {
          // home_page.dart로 이동 (왼쪽에서 오른쪽으로 밀리는 애니메이션)
          Navigator.of(context).pushReplacement(
            SlideLeftToRightRoute(
              page: HomePage(
                initialToggles: _localToggles,
                initialMode: _selectedMode,
                initialSoundPitch: _soundPitch,
                initialEmotionColor: _emotionColor,
                profileId: widget.profileId,
              ),
            ),
          );
          // 명령 처리 후 리셋 (한 번만 실행되도록)
          Future.delayed(const Duration(milliseconds: 100), () {
            FirebaseFirestore.instance
                .collection('tvs')
                .doc('demo_tv_01')
                .set({'backButtonPressed': false}, SetOptions(merge: true));
          });
        }
        return; // 뒤로가기 처리 후 이후 로직 중단
      }

      // 왼쪽 화살표 버튼 처리
      if (data['left'] == true) {
        _handleLeftArrow();
      }

      // 오른쪽 화살표 버튼 처리
      if (data['right'] == true) {
        _handleRightArrow();
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
      }

      // 확인 버튼 처리 - false -> true로 변경될 때만 처리
      final currentOkButtonPressed = data['okButtonPressed'] as bool? ?? false;
      if (_previousOkButtonPressed == null) {
        _previousOkButtonPressed = currentOkButtonPressed;
      } else if (_previousOkButtonPressed == false &&
          currentOkButtonPressed == true) {
        _handleConfirmButton();
        _previousOkButtonPressed = currentOkButtonPressed;
      } else {
        _previousOkButtonPressed = currentOkButtonPressed;
      }
    });
  }

  /// 왼쪽 화살표 버튼 처리 - 모드 포커스 이동
  void _handleLeftArrow() {
    // 모드 순서: 없음, 커스텀 모드들(최신순), 기본 모드들(영화/드라마, 다큐, 예능)
    final allModes = [
      'none',
      ..._customModes.map((m) => m['id'] as String), // 커스텀 모드들 먼저 (최신순)
      ..._modes.skip(1).map((m) => m['mode']!), // 기본 모드들 나중에
    ];
    final currentIndex = allModes.indexOf(_focusedMode ?? _selectedMode);
    final String newFocusedMode;
    if (currentIndex > 0) {
      newFocusedMode = allModes[currentIndex - 1];
    } else {
      // 첫 번째 모드면 마지막 모드로 순환
      newFocusedMode = allModes.last;
    }
    setState(() {
      _focusedMode = newFocusedMode;
      // 이동 시 해당 모드의 확인 상태를 첫 번째 확인으로 리셋
      _isFirstConfirm[newFocusedMode] = true;
    });
    _scrollToFocusedMode();
  }

  /// 오른쪽 화살표 버튼 처리 - 모드 포커스 이동
  void _handleRightArrow() {
    // 모드 순서: 없음, 커스텀 모드들(최신순), 기본 모드들(영화/드라마, 다큐, 예능)
    final allModes = [
      'none',
      ..._customModes.map((m) => m['id'] as String), // 커스텀 모드들 먼저 (최신순)
      ..._modes.skip(1).map((m) => m['mode']!), // 기본 모드들 나중에
    ];
    final currentIndex = allModes.indexOf(_focusedMode ?? _selectedMode);
    final String newFocusedMode;
    if (currentIndex < allModes.length - 1) {
      newFocusedMode = allModes[currentIndex + 1];
    } else {
      // 마지막 모드면 첫 번째 모드로 순환
      newFocusedMode = allModes.first;
    }
    setState(() {
      _focusedMode = newFocusedMode;
      // 이동 시 해당 모드의 확인 상태를 첫 번째 확인으로 리셋
      _isFirstConfirm[newFocusedMode] = true;
    });
    _scrollToFocusedMode();
  }

  /// 확인 버튼 처리 - 첫 번째 확인: 선택, 두 번째 확인: 적용하기
  void _handleConfirmButton() async {
    // 현재 포커스된 모드의 첫 번째 확인 상태 확인 (기본값: true)
    final currentMode = _focusedMode ?? _selectedMode;
    final isFirstConfirmForMode = _isFirstConfirm[currentMode] ?? true;

    if (isFirstConfirmForMode) {
      // 첫 번째 확인: 포커스된 모드를 선택 (마우스 클릭처럼)
      if (_focusedMode != null) {
        setState(() {
          _selectedMode = _focusedMode!;
        });

        // 모든 모드를 DB에서 불러오기 (없음, 기본 모드, 커스텀 모드 모두 포함)
        await _loadModeSettingsFromDb(_focusedMode!);

        // 모드 선택 시 DB에 저장 (선택만 저장, 적용은 두 번째 확인에서)
        _saveSelectedModeToDb(_focusedMode!);

        setState(() {
          // 현재 모드의 첫 번째 확인 상태를 false로 변경
          _isFirstConfirm[_focusedMode!] = false;
        });
      }
    } else {
      // 두 번째 확인: DB 업데이트 및 적용하기
      // 현재 설정을 DB에 저장
      await _applySettingsToDb();

      // 적용하기 버튼과 동일하게 Navigator.pop으로 데이터 반환
      Navigator.pop(context, {
        'toggles': _localToggles,
        'customModes': _customModes,
        'selectedMode': _selectedMode,
        'soundPitch': _soundPitch,
        'emotionColor': _emotionColor,
      });
    }
  }

  /// 선택된 모드를 DB에 저장
  Future<void> _saveSelectedModeToDb(String mode) async {
    // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
    const profileId = 1;

    // 'none' 모드는 DB에 저장하지 않음
    if (mode == 'none') {
      return;
    }

    // 모드 목록 가져오기 - 헬퍼 함수로 GET 요청
    final modesData = await ApiHelpers.get(
      '/caption-modes/',
      query: {'profile_id': profileId.toString()},
    );
    final modesFromDb = (modesData as List).cast<Map<String, dynamic>>();

    // 기본 모드(movie, documentary, variety) 찾기
    String? modeName;
    if (mode == 'movie')
      modeName = '영화/드라마';
    else if (mode == 'documentary')
      modeName = '다큐멘터리';
    else if (mode == 'variety') modeName = '예능';

    Map<String, dynamic> modeData;
    if (modeName != null) {
      // 기본 모드: 모드 이름으로 찾기
      modeData = modesFromDb.firstWhere(
        (m) => (m['mode_name'] as String? ?? '') == modeName,
      );
    } else if (mode.startsWith('custom_')) {
      // 커스텀 모드: ID로 찾기
      final modeId = int.parse(mode.replaceFirst('custom_', ''));
      modeData = modesFromDb.firstWhere(
        (m) => (m['id'] as int? ?? 0) == modeId,
      );
    } else {
      return;
    }

    final modeId = modeData['id'] as int;
    // 모드 선택 저장 (현재 선택된 모드 ID만 저장) - 헬퍼 함수로 PUT 요청
    await ApiHelpers.put(
      '/caption-settings/profile/$profileId',
      {'mode_id': modeId},
    );

    // 중요: 기본값으로 덮어쓰지 않음! DB에 이미 저장된 설정값을 사용
    // _saveModeDefaultSettings 호출 제거 - 사용자가 설정한 값이 유지되도록
  }

  /// 모드가 없으면 생성
  Future<void> _createModeIfNotExists(String mode, String modeName) async {
    // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
    const profileId = 1;

    try {
      bool fontSizeToggle = false;
      bool fontColorToggle = false;
      bool speaker = false;
      bool bgm = false;
      bool effect = false;

      // 모드별 기본 설정
      if (mode == 'movie') {
        fontSizeToggle = true;
        fontColorToggle = true;
        speaker = true;
        bgm = true;
        effect = true;
      } else if (mode == 'documentary') {
        fontSizeToggle = false;
        fontColorToggle = false;
        speaker = false;
        bgm = true;
        effect = true;
      } else if (mode == 'variety') {
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

      final newModeId = newModeData['id'] as int;
      // 모드 선택 저장 - 헬퍼 함수로 PUT 요청
      await ApiHelpers.put(
        '/caption-settings/profile/$profileId',
        {'mode_id': newModeId},
      );

      // 중요: 새 모드 생성 시에만 기본값 저장 (이미 생성된 모드는 덮어쓰지 않음)
      // _saveModeDefaultSettings는 새 모드 생성 시에만 호출됨 (이미 위에서 기본값으로 생성됨)
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

  /// 현재 설정을 DB에 저장 (적용하기 버튼)
  Future<void> _applySettingsToDb() async {
    // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
    const profileId = 1;

    // 선택된 모드가 없으면 저장하지 않음
    if (_selectedMode == 'none') {
      return;
    }

    // 모드 목록 가져오기 - 헬퍼 함수로 GET 요청
    final modesData = await ApiHelpers.get(
      '/caption-modes/',
      query: {'profile_id': profileId.toString()},
    );
    final modesFromDb = (modesData as List).cast<Map<String, dynamic>>();

    int modeId;

    // 기본 모드인지 커스텀 모드인지 확인
    if (_selectedMode == 'movie' ||
        _selectedMode == 'documentary' ||
        _selectedMode == 'variety') {
      // 기본 모드인 경우
      String? modeName;
      if (_selectedMode == 'movie')
        modeName = '영화/드라마';
      else if (_selectedMode == 'documentary')
        modeName = '다큐멘터리';
      else if (_selectedMode == 'variety') modeName = '예능';

      if (modeName != null) {
        final modeData = modesFromDb.firstWhere(
          (m) => (m['mode_name'] as String? ?? '') == modeName,
        );
        modeId = modeData['id'] as int;
      } else {
        return;
      }
    } else if (_selectedMode.startsWith('custom_')) {
      // 커스텀 모드인 경우
      final modeIdStr = _selectedMode.replaceFirst('custom_', '');
      modeId = int.parse(modeIdStr);
    } else {
      return;
    }

    // DB에 설정 저장 - 백엔드에서 변환 처리 (변환 로직 제거)
    await ApiHelpers.put(
      '/caption-modes/$modeId',
      {
        'sound_pitch': _soundPitch, // 원본 문자열 그대로 전송
        'emotion_color': _emotionColor, // 원본 문자열 그대로 전송
        'speaker': _localToggles['화자 설정'] ?? false,
        'bgm': _localToggles['배경음 표시'] ?? false,
        'effect': _localToggles['효과음 표시'] ?? false,
      },
    );
  }

  /// DB에서 모드 목록 불러오기
  Future<void> _loadModesFromDb() async {
    // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
    const profileId = 1;
    
    // 헬퍼 함수로 GET 요청
    final data = await ApiHelpers.get(
      '/caption-modes/',
      query: {'profile_id': profileId.toString()},
    );
    final modesFromDb = (data as List).cast<Map<String, dynamic>>();
    final modes = modesFromDb;

    // 모드 목록 정렬: 영화/드라마, 다큐, 예능 순서로 먼저, 나머지는 그 뒤에
    final sortedModes = _sortModesForSettingPage(modes);

    setState(() {
      _modesFromDb = sortedModes;

      // DB에서 가져온 커스텀 모드를 _customModes에 추가
      _customModes.clear();
      for (final mode in sortedModes) {
        final modeName = mode['mode_name'] as String? ?? '';
        // 기본 모드(없음, 영화/드라마, 다큐멘터리, 예능)는 제외하고 커스텀 모드만 추가
        if (modeName != '없음' &&
            modeName != '영화/드라마' &&
            modeName != '다큐멘터리' &&
            modeName != '예능') {
          final modeId = mode['id'] as int?;
          if (modeId != null) {
            // OracleDB에서 0/1로 오는 값을 bool로 변환하는 헬퍼 함수
            bool _toBool(dynamic value) {
              if (value == null) return false;
              if (value is bool) return value;
              if (value is int) return value != 0;
              if (value is String)
                return value.toLowerCase() == 'true' || value == '1';
              return false;
            }

            // DB에서 모드 설정 불러오기
            final fontSizeToggle = _toBool(mode['fontSize_toggle']);
            final fontColorToggle = _toBool(mode['fontColor_toggle']);
            // 백엔드에서 변환된 값 사용 (변환 로직 제거)
            final soundPitch = mode['sound_pitch'] as String? ?? '없음';
            final emotionColor = mode['emotion_color'] as String? ?? '없음';

            // 토글 설정
            final toggles = <String, bool>{
              '화자 설정': _toBool(mode['speaker']),
              '배경음 표시': _toBool(mode['bgm']),
              '효과음 표시': _toBool(mode['effect']),
              '감정 색상': _toBool(mode['is_empathy_on']),
            };

            _customModes.add({
              'id': 'custom_$modeId',
              'name': modeName,
              'soundPitch': soundPitch,
              'emotionColor': emotionColor,
              'toggles': toggles,
            });
          }
        }
      }
    });
  }

  /// 모드 목록 정렬: 커스텀 모드들(최신순), 기본 모드들 순서
  List<Map<String, dynamic>> _sortModesForSettingPage(
      List<Map<String, dynamic>> modes) {
    // 기본 모드 순서 정의
    final defaultModeOrder = ['영화/드라마', '다큐멘터리', '예능'];

    // 기본 모드와 커스텀 모드 분리
    final List<Map<String, dynamic>> defaultModes = [];
    final List<Map<String, dynamic>> customModes = [];

    for (final mode in modes) {
      final modeName = mode['mode_name'] as String? ?? '';
      if (defaultModeOrder.contains(modeName)) {
        defaultModes.add(mode);
      } else if (modeName != '없음') {
        customModes.add(mode);
      }
    }

    // 커스텀 모드를 id 기준 내림차순으로 정렬 (최신 추가가 위로)
    customModes.sort((a, b) {
      final aId = a['id'] as int? ?? 0;
      final bId = b['id'] as int? ?? 0;
      return bId.compareTo(aId); // 내림차순 (큰 id가 위로)
    });

    // 기본 모드를 순서대로 정렬
    defaultModes.sort((a, b) {
      final aName = a['mode_name'] as String? ?? '';
      final bName = b['mode_name'] as String? ?? '';
      final aIndex = defaultModeOrder.indexOf(aName);
      final bIndex = defaultModeOrder.indexOf(bName);
      return aIndex.compareTo(bIndex);
    });

    // '없음' 모드 찾기
    final noneMode = modes.firstWhere(
      (m) => (m['mode_name'] as String? ?? '') == '없음',
      orElse: () => <String, dynamic>{},
    );

    // 최종 순서: 없음, 커스텀 모드들(최신순), 기본 모드들(영화/드라마, 다큐, 예능)
    final List<Map<String, dynamic>> sorted = [];
    if (noneMode.isNotEmpty) {
      sorted.add(noneMode);
    }
    sorted.addAll(customModes);
    sorted.addAll(defaultModes);

    return sorted;
  }

  /// 포커스된 모드로 스크롤 이동
  void _scrollToFocusedMode() {
    // 스크롤 로직은 기존 _scrollModeSelectorLeft/Right와 유사하게 구현
    // 여기서는 간단히 스크롤만 처리
  }

  /// 선택된 소리의 높낮이 옵션으로 스크롤
  void _scrollToSelectedSoundPitchOption(String label) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_soundPitchScrollController.hasClients) {
        final index = _soundPitchOptions.indexOf(label);
        if (index != -1) {
          final itemHeight = _panelOptionHeight;
          final targetOffset = index * itemHeight;
          _soundPitchScrollController.animateTo(
            targetOffset.clamp(
              0.0,
              _soundPitchScrollController.position.maxScrollExtent,
            ),
            duration: _scrollAnimationDuration,
            curve: _scrollAnimationCurve,
          );
        }
      }
    });
  }

  /// 선택된 감정 색상 옵션으로 스크롤
  void _scrollToSelectedEmotionColorOption(String label) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_emotionColorScrollController.hasClients) {
        final options = ['없음', '1단계', '2단계', '3단계'];
        final index = options.indexOf(label);
        if (index != -1) {
          final itemHeight = _emotionColorOptionHeight;
          final targetOffset = index * itemHeight;
          _emotionColorScrollController.animateTo(
            targetOffset.clamp(
              0.0,
              _emotionColorScrollController.position.maxScrollExtent,
            ),
            duration: _scrollAnimationDuration,
            curve: _scrollAnimationCurve,
          );
        }
      }
    });
  }

  // 기본 모드인지 확인

  bool get _isDefaultMode {
    return _selectedMode == 'movie' ||
        _selectedMode == 'documentary' ||
        _selectedMode == 'variety';
  }

  // 커스텀 모드가 선택되었는지 확인

  bool get _isCustomModeSelected {
    return _selectedMode.startsWith('custom_');
  }

  // 추가하기 버튼을 표시할지 결정하는 함수
  bool _shouldShowAddButton() {
    // 커스텀 모드가 선택되었을 때: 모드 이름이 초기값과 다르면 표시 (이름이 변경되었을 때)
    if (_isCustomModeSelected) {
      return _modeName.trim() != _initialModeName.trim();
    }

    // 기본 모드(없음 포함): 모드 이름이 입력되었을 때만 표시
    return _modeName.trim().isNotEmpty;
  }

  // 값이 변경되었는지 확인

  bool get _hasChanges {
    return _modeName.trim() != _initialModeName.trim() ||
        _soundPitch != _initialSoundPitch ||
        _emotionColor != _initialEmotionColor ||
        !_mapsEqual(_localToggles, _initialToggles);
  }

  // ============================================================================

  // 헬퍼 함수

  // ============================================================================

  /// 두 Map이 동일한지 비교하는 헬퍼 함수 (토글 상태 비교용)

  bool _mapsEqual(Map<String, bool> map1, Map<String, bool> map2) {
    if (map1.length != map2.length) return false;

    for (var key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }

    return true;
  }

  /// 모드 설정을 초기값으로 리셋하는 함수

  void _resetToInitialValues() {
    _modeName = '';
    _modeNameController.text = '';

    _soundPitch = widget.initialSoundPitch ?? '없음';

    _emotionColor = widget.initialEmotionColor ?? '없음';

    _localToggles = Map.from(widget.toggles);

    _initialModeName = '';

    _initialSoundPitch = widget.initialSoundPitch ?? '없음';

    _initialEmotionColor = widget.initialEmotionColor ?? '없음';

    _initialToggles = Map.from(widget.toggles);
  }

  /// 모든 모드(없음 포함)의 설정값을 DB에서 불러오는 함수
  Future<void> _loadModeSettingsFromDb(String mode) async {
    // 모든 모드는 DB에서 찾기 (없음 포함)
    String? modeName;
    if (mode == 'none') {
      modeName = '없음';
    } else if (mode == 'movie') {
      modeName = '영화/드라마';
    } else if (mode == 'documentary') {
      modeName = '다큐멘터리';
    } else if (mode == 'variety') {
      modeName = '예능';
    }

    // _modesFromDb가 비어있으면 로딩 완료까지 대기 (최대 5초)
    int attempts = 0;
    while (_modesFromDb.isEmpty && attempts < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }

    if (_modesFromDb.isEmpty) {
      throw Exception('Failed to load modes from DB after multiple attempts.');
    }

    // DB에서 모드 찾기
    Map<String, dynamic> modeData;
    if (modeName != null) {
      // 기본 모드: 모드 이름으로 찾기 (없음, 영화/드라마, 다큐멘터리, 예능 모두 포함)
      modeData = _modesFromDb.firstWhere(
        (m) => (m['mode_name'] as String? ?? '') == modeName,
      );
    } else {
      // 커스텀 모드: ID로 찾기
      final modeId = int.parse(mode.replaceFirst('custom_', ''));
      modeData = _modesFromDb.firstWhere(
        (m) => (m['id'] as int? ?? 0) == modeId,
      );
    }

    // OracleDB에서 0/1로 오는 값을 bool로 변환하는 헬퍼 함수
    bool _toBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is int) return value != 0;
      if (value is String) return value.toLowerCase() == 'true' || value == '1';
      return false;
    }

    final speaker = _toBool(modeData['speaker']);
    final bgm = _toBool(modeData['bgm']);
    final effect = _toBool(modeData['effect']);
    final fontSizeToggle = _toBool(modeData['fontSize_toggle']);
    final fontColorToggle = _toBool(modeData['fontColor_toggle']);
    // 백엔드에서 변환된 값 사용 (변환 로직 제거)
    final soundPitch = modeData['sound_pitch'] as String? ?? '없음';
    final emotionColor = modeData['emotion_color'] as String? ?? '없음';

    // 모드 이름 설정 (없음 제외)
    String finalModeName = '';
    if (mode != 'none') {
      if (modeName != null) {
        // 기본 모드: 이미 modeName에 설정됨
        finalModeName = modeName;
      } else {
        // 커스텀 모드: DB에서 가져온 mode_name 사용
        finalModeName = modeData['mode_name'] as String? ?? '';
      }
    }

    setState(() {
      // 모드 이름 설정 (없음 제외)
      _modeName = finalModeName;
      _modeNameController.text = finalModeName;

      // 토글 설정 업데이트
      _localToggles['화자 설정'] = speaker;
      _localToggles['배경음 표시'] = bgm;
      _localToggles['효과음 표시'] = effect;

      // 소리의 높낮이와 감정 색상 업데이트
      _soundPitch = soundPitch;
      _emotionColor = emotionColor;

      // 초기값도 업데이트
      _initialModeName = _modeName;
      _initialToggles = Map<String, bool>.from(_localToggles);
      _initialSoundPitch = _soundPitch;
      _initialEmotionColor = _emotionColor;
    });
  }

  /// 커스텀 모드의 설정값을 불러오는 함수

  void _loadCustomModeSettings(String modeId) {
    final customMode = _customModes.firstWhere(
      (m) => m['id'] == modeId,
      orElse: () => {},
    );

    if (customMode.isNotEmpty) {
      _modeName = customMode['name'] as String;
      _modeNameController.text = _modeName;

      _soundPitch = customMode['soundPitch'] as String;

      _emotionColor = customMode['emotionColor'] as String;

      _localToggles = Map<String, bool>.from(
        customMode['toggles'] as Map<String, bool>,
      );

      _initialModeName = _modeName;

      _initialSoundPitch = _soundPitch;

      _initialEmotionColor = _emotionColor;

      _initialToggles = Map<String, bool>.from(_localToggles);
    }
  }

  /// 패널을 모두 닫는 함수

  void _closeAllPanels() {
    setState(() {
      _isSoundPitchExpanded = false;
      _isEmotionColorExpanded = false;
    });
  }

  /// 모드 선택 영역을 왼쪽으로 스크롤하는 함수

  void _scrollModeSelectorLeft() {
    if (_modeSelectorScrollController.hasClients) {
      _modeSelectorScrollController.animateTo(
        (_modeSelectorScrollController.offset - 200).clamp(
          0.0,
          _modeSelectorScrollController.position.maxScrollExtent,
        ),
        duration: _scrollAnimationDuration,
        curve: _scrollAnimationCurve,
      );
    }
  }

  /// 모드 선택 영역을 오른쪽으로 스크롤하는 함수

  void _scrollModeSelectorRight() {
    if (_modeSelectorScrollController.hasClients) {
      _modeSelectorScrollController.animateTo(
        (_modeSelectorScrollController.offset + 200).clamp(
          0.0,
          _modeSelectorScrollController.position.maxScrollExtent,
        ),
        duration: _scrollAnimationDuration,
        curve: _scrollAnimationCurve,
      );
    }
  }

  /// 모드 선택 영역을 맨 앞으로 스크롤하는 함수 (새 모드 추가 후 사용)

  void _scrollModeSelectorToStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_modeSelectorScrollController.hasClients) {
        _modeSelectorScrollController.animateTo(
          0.0,
          duration: _scrollAnimationDuration,
          curve: _scrollAnimationCurve,
        );
      }
    });
  }

  /// 새로운 커스텀 모드를 추가하는 함수

  void _addCustomMode() async {
    if (_modeName.trim().isNotEmpty) {
      // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
      const profileId = 1;

      try {
        // DB에 모드 저장 - 백엔드의 /custom 엔드포인트 사용 (변환 로직 제거)
        // 백엔드에서 sound_pitch와 emotion_color를 받아서 변환 처리
        await ApiHelpers.post(
          '/caption-modes/custom',
          {
            'profile_id': profileId,
            'mode_name': _modeName.trim().isEmpty ? null : _modeName.trim(),
            'selected_mode': null, // UI에서 선택한 모드 타입이 없으면 null
            'sound_pitch': _soundPitch, // 원본 문자열 그대로 전송
            'emotion_color': _emotionColor, // 원본 문자열 그대로 전송
            'speaker': _localToggles['화자 설정'] ?? false,
            'bgm': _localToggles['배경음 표시'] ?? false,
            'effect': _localToggles['효과음 표시'] ?? false,
          },
        );

        // DB에서 생성된 모드 ID를 가져오기 위해 모드 목록 다시 불러오기
        final modesData = await ApiHelpers.get(
          '/caption-modes/',
          query: {'profile_id': profileId.toString()},
        );
        final modesFromDb = (modesData as List).cast<Map<String, dynamic>>();
        final createdMode = modesFromDb.firstWhere(
          (m) => (m['mode_name'] as String?) == _modeName.trim(),
        );
        final modeId = createdMode['id'] as int;

        final newMode = {
          'id': 'custom_$modeId',
          'name': _modeName.trim(),
          'soundPitch': _soundPitch,
          'emotionColor': _emotionColor,
          'toggles': Map<String, bool>.from(_localToggles),
        };

        // DB에서 최신 모드 목록 다시 불러오기
        await _loadModesFromDb();

        // 새로 생성된 모드 선택
        setState(() {
          _selectedMode = 'custom_$modeId';
          _initialModeName = _modeName.trim();
          _initialSoundPitch = _soundPitch;
          _initialEmotionColor = _emotionColor;
          _initialToggles = Map<String, bool>.from(_localToggles);
        });

        _scrollModeSelectorToStart();
      } catch (e) {
        // 에러 발생 시에도 로컬에는 추가 (나중에 재시도 가능하도록)
        final newMode = {
          'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
          'name': _modeName.trim(),
          'soundPitch': _soundPitch,
          'emotionColor': _emotionColor,
          'toggles': Map<String, bool>.from(_localToggles),
        };

        setState(() {
          _customModes.insert(0, newMode);
          _selectedMode = newMode['id'] as String;
          _initialModeName = _modeName.trim();
          _initialSoundPitch = _soundPitch;
          _initialEmotionColor = _emotionColor;
          _initialToggles = Map<String, bool>.from(_localToggles);
        });
      }
    }
  }

  /// 커스텀 모드를 삭제하는 함수

  void _deleteCustomMode() async {
    if (!_selectedMode.startsWith('custom_')) {
      return;
    }

    try {
      // 커스텀 모드 ID 추출
      final modeIdStr = _selectedMode.replaceFirst('custom_', '');
      final modeId = int.tryParse(modeIdStr);

      if (modeId == null) {
        return;
      }

      // DB에서 모드 삭제 - 헬퍼 함수로 DELETE 요청
      await ApiHelpers.delete('/caption-modes/$modeId');

      // DB에서 최신 모드 목록 다시 불러오기
      await _loadModesFromDb();

      // 로컬에서도 삭제 및 초기화
      setState(() {
        _selectedMode = 'none';
        _resetToInitialValues();
      });
    } catch (e) {
      // 에러 발생 시에도 로컬에서는 삭제 (일관성 유지)
      setState(() {
        _customModes.removeWhere((mode) => mode['id'] == _selectedMode);
        _selectedMode = 'none';
        _resetToInitialValues();
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _tvStateSubscription?.cancel();
    _settingsScrollController.dispose();

    _modeSelectorScrollController.dispose();
    _soundPitchScrollController.dispose();
    _emotionColorScrollController.dispose();
    _modeNameController.dispose();

    super.dispose();
  }

  // 미리보기 영상 넣을거임

  String get _previewImage {
    switch (_selectedMode) {
      case 'movie':
        return 'assets/preview_movie.png';

      case 'documentary':
        return 'assets/preview_documentary.png';

      case 'variety':
        return 'assets/preview_variety.png';

      case 'none':
      default:
        return 'assets/preview_none.png';
    }
  }

  // 소리의 높낮이에 따른 이미지 경로

  String get _soundPitchImage {
    switch (_soundPitch) {
      case '2단계':
        return 'assets/가_middle.png';

      case '3단계':
        return 'assets/가_wide.png';

      case '1단계':
        return 'assets/가_basic.png';

      case '없음':
      default:
        return 'assets/가_none.png';
    }
  }

  // 💡 공통 클릭 위젯 (GestureDetector + MouseRegion)

  Widget _clickable({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      // 터치 포인터와 클릭 이벤트는 RemotePointerOverlay에서 처리됨

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

                // RemotePointerOverlay 없이 직접 child 표시

                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 제목+부제목

                      buildHeadLine(),

                      const SizedBox(height: 80),

                      // 모드 선택 버튼들

                      Center(child: _buildModeSelector()),

                      const SizedBox(height: 47),

                      // 메인 컨텐츠 영역 (좌우 718px 섹션 2개, 가운데 정렬)

                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: _settingsSectionWidth * 2 + _sectionGap,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 왼쪽: 모드 설정 섹션 (고정 폭 718, 높이 제한)

                                SizedBox(
                                  width: _settingsSectionWidth,
                                  height: _settingsSectionHeight,
                                  child: _buildSettingsSection(),
                                ),

                                const SizedBox(width: _sectionGap),

                                // 오른쪽: 미리보기 섹션

                                SizedBox(
                                  width: _settingsSectionWidth,
                                  child: _buildRightSection(),
                                ), //미리보기
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  //제목+부제목

  Column buildHeadLine() {
    return Column(
      children: textList.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Center(
            child: Text(
              item['text'] as String,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _fontFamily,
                fontSize: item['size'] as double,
                fontWeight: item['weight'] as FontWeight,
                color: Colors.white,
                height: 1.19,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============================================================================

  // UI 빌드 함수

  // ============================================================================

  /// 모드 선택 버튼 영역을 빌드하는 함수

  /// 왼쪽/오른쪽 화살표와 스크롤 가능한 모드 버튼들을 포함

  Widget _buildModeSelector() {
    return Container(
      width: _modeSelectorWidth,
      height: _modeSelectorHeight,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _modeSelectorBgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // 왼쪽 화살표 버튼

          buildArrowButton(Icons.chevron_left, onTap: _scrollModeSelectorLeft),

          // 모드 버튼들 (스크롤 가능)

          Expanded(
            child: SingleChildScrollView(
              controller: _modeSelectorScrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  // 없음 버튼 (맨 앞 고정, 오른쪽 margin 없음)

                  _buildModeButton('없음', 'none', hasRightMargin: false),

                  // 없음과 다음 버튼 사이 구분선

                  const SizedBox(width: _modeButtonSpacing),

                  Container(
                    width: 1,
                    height: _modeButtonHeight,
                    color: _separatorColor,
                  ),

                  const SizedBox(width: _modeButtonSpacing),

                  // 커스텀 모드 버튼들 (애니메이션 효과) - 먼저 표시 (최신순)

                  ...List.generate(_customModes.length, (index) {
                    final modeData = _customModes[index];

                    return AnimatedContainer(
                      duration: _modeButtonAnimationDuration,
                      curve: _modeButtonAnimationCurve,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: _modeButtonSpacing),
                          _buildModeButton(
                            modeData['name'] as String,
                            modeData['id'] as String,
                          ),
                        ],
                      ),
                    );
                  }),

                  // 기본 모드 버튼들 (영화/드라마, 다큐멘터리, 예능) - 나중에 표시

                  ..._modes.skip(1).map((modeData) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: _modeButtonSpacing),
                        _buildModeButton(
                          modeData['label']!,
                          modeData['mode']!,
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),

          // 오른쪽 화살표 버튼

          buildArrowButton(
            Icons.chevron_right,
            onTap: _scrollModeSelectorRight,
          ),
        ],
      ),
    );
  }

  /// 모드 버튼 위젯을 빌드하는 함수

  /// 커스텀 모드와 기본 모드를 모두 처리

  Widget _buildModeButton(
    String label,
    String mode, {
    bool hasRightMargin = true,
  }) {
    final isSelected = _selectedMode == mode;
    final isFocused = _focusedMode == mode; // 리모컨으로 포커스된 모드
    final isHovered = _hoveredModes[mode] ?? false;

    final bool isCustomMode = mode.startsWith('custom_');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _hoveredModes[mode] = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredModes[mode] = false;
        });
      },
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _selectedMode = mode;
            _focusedMode = mode; // 포커스도 함께 업데이트
            // 모드 선택 시 해당 모드의 확인 상태를 첫 번째 확인으로 리셋
            _isFirstConfirm[mode] = true;
          });

          // 모든 모드를 DB에서 불러오기 (없음, 기본 모드, 커스텀 모드 모두 포함)
          await _loadModeSettingsFromDb(mode);

          // 모드 선택 시 DB에 저장
          _saveSelectedModeToDb(mode);
        },
        child: Container(
          height: _modeButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          margin: hasRightMargin
              ? const EdgeInsets.only(right: _modeButtonSpacing)
              : null,
          decoration: BoxDecoration(
            // 커스텀 모드: 노란색 배경, 호버 시 주황색

            // 기본 모드: 회색 배경, 선택 시 투명

            color: isCustomMode
                ? (isHovered || isFocused
                    ? _customModeButtonHoverBgColor
                    : _customModeButtonBgColor)
                : (isSelected
                    ? Colors.transparent
                    : (isFocused
                        ? _defaultModeButtonHoverBgColor
                        : (isHovered
                            ? _defaultModeButtonHoverBgColor
                            : _defaultModeButtonBgColor))),

            borderRadius: BorderRadius.circular(10),

            border: isSelected
                ? Border.all(color: Colors.white, width: 2)
                : isFocused
                    ? Border.all(color: Colors.white.withOpacity(0.6), width: 2)
                    : null,
          ),
          child: Center(
            child: Text(
              label,
              style: _modeButtonTextStyle.copyWith(
                // 커스텀 모드: 항상 검정 텍스트, 기본 모드는 선택 시 흰색

                color: isCustomMode
                    ? Colors.black
                    : (isSelected ? Colors.white : Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  //왼쪽, 오른쪽 화살표 버튼

  Widget buildArrowButton(IconData icon, {VoidCallback? onTap}) {
    return _clickable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }

  // 설정 섹션 (피그마 Frame 폭 718 기준, 전용 스크롤바 스타일)

  Widget _buildSettingsSection() {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(_scrollbarColor),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(99),
        thickness: WidgetStateProperty.all(8),
      ),
      child: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: [
          // 1) 실제 스크롤 영역

          Scrollbar(
            controller: _settingsScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _settingsScrollController,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeNameField(),

                    const SizedBox(height: _fieldSpacing),

                    _buildSoundPitchField(),

                    const SizedBox(height: _fieldSpacing),

                    _buildEmotionColorField(),

                    const SizedBox(height: _fieldSpacing),

                    // 토글 설정들

                    ..._toggleLabels.map(
                      (label) => Padding(
                        padding: const EdgeInsets.only(bottom: _fieldSpacing),
                        child: _buildToggleRow(label, label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2) 패널 외부 클릭 시 닫기 (설정 영역 전체 덮는 투명 레이어)

          // 패널보다 먼저 배치하여 패널이 위에 오도록 함

          if (_isSoundPitchExpanded || _isEmotionColorExpanded)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeAllPanels,
                child: Container(color: Colors.transparent),
              ),
            ),

          // 3) 소리의 높낮이 옵션 패널 (다른 행 위로 겹쳐 표시)

          // 패널이 외부 클릭 레이어 위에 오도록 나중에 배치

          if (_isSoundPitchExpanded)
            Builder(builder: (context) {
              // 위치 계산
              final offset = _getRelativePosition(_soundPitchFieldKey);
              // 계산 전이면 숨김, 계산되면 위치 잡아서 표시
              if (offset == null) return const SizedBox();

              return Positioned(
                top: offset.dy + _dropdownFieldHeight, // 필드 Y위치 + 높이(80)
                left: offset.dx, // 필드 X위치
                child: _buildSoundPitchPanel(),
              );
            }),

          // 4) 감정 색상 패널 (자동 위치 계산)
          if (_isEmotionColorExpanded)
            Builder(builder: (context) {
              // 위치 계산
              final offset = _getRelativePosition(_emotionColorFieldKey);
              if (offset == null) return const SizedBox();

              return Positioned(
                top: offset.dy + _dropdownFieldHeight, // 필드 Y위치 + 높이(80)
                left: offset.dx, // 필드 X위치
                child: _buildEmotionColorPanel(),
              );
            }),
        ],
      ),
    );
  }

  // 공통 설정 라벨 (왼쪽 텍스트)

  Widget _buildSettingLabel(String text, {double width = _labelWidth}) {
    return SizedBox(
      width: width,
      child: Text(text, style: _labelTextStyle),
    );
  }

  // 모드 이름 입력 필드

  Widget _buildModeNameField() {
    final bool isDisabled = _isDefaultMode;
    final bool hasChanges = _hasChanges && !isDisabled;
    return Row(
      children: [
        _buildSettingLabel('모드 이름'),
        const SizedBox(width: _labelGap),
        Expanded(
          child: Opacity(
            opacity: isDisabled ? 0.5 : 1.0,
            child: Container(
              height: _inputFieldHeight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: _fieldBgColor,
                borderRadius: BorderRadius.circular(10),
                border: hasChanges
                    ? Border.all(color: _primaryBlue, width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _modeNameController,
                      enabled: !isDisabled,
                      onChanged: (value) {
                        if (value.length <= 10) {
                          setState(() {
                            _modeName = value;
                          });
                        } else {
                          // 10자 초과 시 마지막 문자 제거
                          _modeNameController.text = _modeName;
                          _modeNameController.selection =
                              TextSelection.fromPosition(
                            TextPosition(offset: _modeName.length),
                          );
                        }
                      },
                      style: _fieldTextStyle,
                      decoration: const InputDecoration(
                        hintText: '모드 이름을 적어주세요',
                        hintStyle: _fieldTextStyle,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Text(
                    hasChanges ? '필수 입력' : '10자 이내',
                    style: _modeNameCounterTextStyle.copyWith(
                      color: hasChanges ? _primaryBlue : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 소리의 높낮이 한 줄 셀

  Widget _buildSoundPitchField() {
    return Row(
      children: [
        _buildSettingLabel('말의 강도'),
        const SizedBox(width: _labelGap),
        SizedBox(
          width: _soundPitchFieldWidth,
          child: Row(
            children: [
              // 왼쪽 소리의 높낮이 이미지

              Container(
                width: _soundPitchImageSize,
                height: _soundPitchImageSize,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    _soundPitchImage,
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // 디버깅: 이미지 로드 실패 시 빨간색 배경으로 표시

                      return Container(
                        width: _soundPitchImageSize,
                        height: _soundPitchImageSize,
                        color: Colors.red.withOpacity(0.3),
                        child: const Center(
                          child: Icon(Icons.error, color: Colors.red, size: 20),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // 오른쪽 입력 필드 (340px)

              Expanded(
                child: Opacity(
                  opacity: _isDefaultMode ? _disabledFieldOpacity : 1.0,
                  child: _clickable(
                    onTap: _isDefaultMode
                        ? null
                        : () {
                            setState(() {
                              _isSoundPitchExpanded = !_isSoundPitchExpanded;
                            });
                            // 패널이 열릴 때 현재 선택된 옵션으로 스크롤
                            if (!_isSoundPitchExpanded) {
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) => setState(() {}));
                            }
                          },
                    child: Container(
                      key: _soundPitchFieldKey,
                      height: _dropdownFieldHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: _fieldBgColor,
                        borderRadius: _isSoundPitchExpanded
                            ? const BorderRadius.only(
                                topRight: Radius.circular(10),
                                bottomRight: Radius.zero,
                              )
                            : BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_soundPitch, style: _fieldTextStyle),
                          Icon(
                            _isSoundPitchExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 소리의 높낮이 옵션 패널을 빌드하는 함수

  /// 드롭다운 형태로 옵션 목록을 표시

  Widget _buildSoundPitchPanel() {
    return Material(
      elevation: 8,
      color: Colors.transparent,
      child: Container(
        width: _soundPitchPanelWidth,
        decoration: BoxDecoration(
          color: _fieldBgColor,
          borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(10),
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use

              color: Colors.black.withOpacity(_panelShadowOpacity),

              blurRadius: 8,

              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          controller: _soundPitchScrollController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _soundPitchOptions
                .map((option) => _buildSoundPitchOption(option))
                .toList(),
          ),
        ),
      ),
    );
  }

  // 소리의 높낮이 옵션 한 줄

  Widget _buildSoundPitchOption(String label) {
    final bool isSelected = _soundPitch == label;

    return _clickable(
      onTap: () {
        setState(() {
          _soundPitch = label;
          _isSoundPitchExpanded = false;
        });
        // 선택된 옵션으로 스크롤
        _removeOverlay();
        //_scrollToSelectedSoundPitchOption(label);
      },
      child: Container(
        height: _panelOptionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(_selectedOptionBgOpacity)
              : Colors.transparent,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: _fieldTextStyle),
        ),
      ),
    );
  }

  // 감정 색상 한 줄 셀

  Widget _buildEmotionColorField() {
    return Row(
      children: [
        _buildSettingLabel('감정 색상'),
        const SizedBox(width: _labelGap),
        SizedBox(
          width: _emotionColorFieldWidth,
          child: Opacity(
            opacity: _isDefaultMode ? _disabledFieldOpacity : 1.0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _isDefaultMode
                  ? null
                  : () {
                      setState(() {
                        _isEmotionColorExpanded = !_isEmotionColorExpanded;
                      });
                      // 패널이 열릴 때 현재 선택된 옵션으로 스크롤
                      if (!_isEmotionColorExpanded) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => setState(() {}));
                      }
                    },
              child: MouseRegion(
                cursor: _isDefaultMode
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: Container(
                  key: _emotionColorFieldKey,
                  height: _dropdownFieldHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _fieldBgColor,
                    borderRadius: _isEmotionColorExpanded
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                            bottomLeft: Radius.zero,
                            bottomRight: Radius.zero,
                          )
                        : BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(_emotionColor, style: _fieldTextStyle),

                          // 선택된 감정 색상 팔레트 미리보기 (없음 제외)

                          if (_emotionColor != '없음') ...[
                            const SizedBox(width: 14),
                            Row(
                              children: (() {
                                List<Color> palette = [];

                                if (_emotionColor == '1단계') {
                                  palette = _getColorPalette(1);
                                } else if (_emotionColor == '2단계') {
                                  palette = _getColorPalette(2);
                                } else if (_emotionColor == '3단계') {
                                  palette = _getColorPalette(3);
                                }

                                return palette
                                    .map(
                                      (color) => Container(
                                        width: _colorPalettePreviewWidth,
                                        height: _colorPalettePreviewHeight,
                                        margin: const EdgeInsets.only(right: 1),
                                        color: color,
                                      ),
                                    )
                                    .toList();
                              })(),
                            ),
                          ],
                        ],
                      ),
                      Icon(
                        _isEmotionColorExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 감정 색상 옵션 패널을 빌드하는 함수

  /// 드롭다운 형태로 색상 팔레트 옵션 목록을 표시

  Widget _buildEmotionColorPanel() {
    return Material(
      elevation: 8,
      color: Colors.transparent,
      child: Container(
        width: _emotionColorFieldWidth,
        decoration: BoxDecoration(
          color: _fieldBgColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use

              color: Colors.black.withOpacity(_panelShadowOpacity),

              blurRadius: 8,

              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          controller: _emotionColorScrollController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEmotionColorOption('없음', null, false),
              _buildEmotionColorOption('1단계', _getColorPalette(1), false),
              _buildEmotionColorOption('2단계', _getColorPalette(2), true),
              _buildEmotionColorOption('3단계', _getColorPalette(3), false),
            ],
          ),
        ),
      ),
    );
  }

  // 감정 색상 옵션 한 줄

  Widget _buildEmotionColorOption(
    String label,
    List<Color>? colorPalette,
    bool showRecommended,
  ) {
    final bool isSelected = _emotionColor == label;

    void selectEmotion() {
      setState(() {
        _emotionColor = label;
        _isEmotionColorExpanded = false;
      });
      // 선택된 옵션으로 스크롤
      _removeOverlay();
      //_scrollToSelectedEmotionColorOption(label);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectEmotion,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: _emotionColorOptionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withOpacity(_selectedOptionBgOpacity)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Text(label, style: _fieldTextStyle),
              if (colorPalette != null) ...[
                const SizedBox(width: 14),
                Row(
                  children: colorPalette
                      .map(
                        (color) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: selectEmotion,
                          child: Container(
                            width: _colorPaletteBoxWidth,
                            height: _colorPaletteBoxHeight,
                            margin: const EdgeInsets.only(right: 1),
                            decoration: BoxDecoration(
                              color: color,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 1)
                                  : null,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (showRecommended) ...[
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Center(
                    child: Text('권장', style: _recommendedBadgeTextStyle),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 색상 팔레트 반환 (단계별)

  List<Color> _getColorPalette(int level) {
    switch (level) {
      case 1:
        return [
          const Color(0xFFFFCDD2), // 연빨강

          const Color(0xFFFFE599), // 연노랑/주황

          const Color(0xFFFFF9C4), // 연노랑

          const Color(0xFFC8E6C9), // 연초록

          const Color(0xFFBBDEFB), // 연파랑

          const Color(0xFFE1BEE7), // 연보라

          const Color(0xFFEEEEEE), // 연회색
        ];

      case 2:
        return [
          const Color(0xFFFF6F6F), // 빨강

          const Color(0xFFFFB800), // 주황

          const Color(0xFFFFD54F), // 노랑

          const Color(0xFF81C784), // 초록

          const Color(0xFF64B5F6), // 파랑

          const Color(0xFFBA68C8), // 보라

          const Color(0xFFE0E0E0), // 회색
        ];

      case 3:
        return [
          const Color(0xFFFF5252), // 진빨강

          const Color(0xFFFFA000), // 진주황

          const Color(0xFFFFCA28), // 진노랑

          const Color(0xFF66BB6A), // 진초록

          const Color(0xFF42A5F5), // 진파랑

          const Color(0xFFAB47BC), // 진보라

          const Color(0xFFE0E0E0), // 회색
        ];

      default:
        return [];
    }
  }

  // 자막 미리보기 위젯
  Widget _buildCaptionPreview() {
    // 감정 색상 레벨에 따른 색상 팔레트 가져오기
    int colorLevel = 0;
    if (_emotionColor == '1단계') {
      colorLevel = 1;
    } else if (_emotionColor == '2단계') {
      colorLevel = 2;
    } else if (_emotionColor == '3단계') {
      colorLevel = 3;
    }

    // 감정별 색상 (기쁨: 노란색, 일반: 흰색)
    Color getEmotionColor(String emotion) {
      // 감정 색상 값이 설정되어 있으면 적용 (토글 상태와 관계없이 미리보기에서는 표시)
      if (colorLevel > 0) {
        final palette = _getColorPalette(colorLevel);
        // 기쁨(joy)은 노란색 계열 (팔레트의 2번째 또는 3번째 색상)
        if (emotion == 'joy' && palette.length >= 3) {
          return palette[2]; // 연노랑
        }
        // 일반(neutral)은 흰색
        return Colors.white;
      }
      return Colors.white;
    }

    // 폰트 크기 계산 (소리의 높낮이 값에 따라) - 미리보기용으로 작게 조정
    double getFontSize(double intensity) {
      // 소리의 높낮이 값이 설정되어 있으면 적용 (토글 상태와 관계없이 미리보기에서는 표시)
      if (_soundPitch != '없음') {
        int fontLevel = 2; // 기본값
        if (_soundPitch == '1단계') {
          fontLevel = 1;
        } else if (_soundPitch == '2단계') {
          fontLevel = 2;
        } else if (_soundPitch == '3단계') {
          fontLevel = 3;
        }
        const double baseFont = 17.0;
        const double baseChange = 8.0; // 미리보기용으로 작게 조정
        double weight;
        switch (fontLevel) {
          case 1:
            weight = 0.5;
            break;
          case 2:
            weight = 1.0;
            break;
          case 3:
            weight = 2.0;
            break;
          default:
            weight = 1.0;
        }
        double fontSize =
            baseFont + (baseChange * (intensity - 0.5) * weight * 2);
        return fontSize.clamp(9.0, 37.0);
      }
      return 17.0; // 기본값
    }

    // 이모지 가져오기 (감정 색상 값이 설정되어 있을 때만)
    String getEmotionIcon(String emotion) {
      // 감정 색상이 "없음"이 아니고, 토글이 켜져 있을 때만 이모지 표시
      if (_emotionColor != '없음' && _localToggles['감정 색상'] == true) {
        const emotionIconMap = {
          'joy': '😊',
          'sadness': '😢',
          'anger': '😡',
          'fear': '😱',
          'surprise': '😲',
          'disgust': '🤢',
          'neutral': '🙂',
        };
        return emotionIconMap[emotion] ?? '';
      }
      return '';
    }

    // 자막 텍스트 생성
    String buildCaptionText(
        String speaker, String text, String emotion, double intensity) {
      String result = '';
      // 화자 설정이 켜져 있으면 [인물] 태그 추가
      if (_localToggles['화자 설정'] == true) {
        result = speaker;
        // 감정 색상이 설정되어 있고 토글이 켜져 있으면 이모지 추가 ([인물] 태그 바로 뒤)
        if (_emotionColor != '없음' && _localToggles['감정 색상'] == true) {
          final icon = getEmotionIcon(emotion);
          if (icon.isNotEmpty) {
            result = '$speaker $icon';
          }
        }
        result += ' ';
      }
      result += text;
      return result;
    }

    // 인물1: 크게 말함 (intensity 높음), 일반 감정
    final caption1Text =
        buildCaptionText('[인물1]', '혹이 세 개인 낙타를 뭐라고 부르게? 임산부', 'neutral', 0.8);
    final caption1FontSize = getFontSize(0.8);
    final caption1Color = getEmotionColor('neutral');

    // 인물2: 작게 말함 (intensity 낮음), 기쁨 감정
    final caption2Text = buildCaptionText('[인물2]', '푸하하하', 'joy', 0.3);
    final caption2FontSize = getFontSize(0.3);
    final caption2Color = getEmotionColor('joy');

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 배경음/효과음 표시 (상단)
          if (_localToggles['배경음 표시'] == true ||
              _localToggles['효과음 표시'] == true)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Wrap(
                spacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  if (_localToggles['배경음 표시'] == true)
                    Text(
                      '[배경음] 악기소리가 들린다',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: caption1FontSize * 0.7,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  if (_localToggles['효과음 표시'] == true)
                    Text(
                      '[효과음] 웃음소리가 들린다',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: caption1FontSize * 0.7,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          // 인물1 자막 (크게, 일반)
          if (caption1Text.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _buildCaptionWithSpeakerColor(
                  caption1Text, caption1FontSize, caption1Color),
            ),
          // 인물2 자막 (작게, 기쁨)
          if (caption2Text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _buildCaptionWithSpeakerColor(
                  caption2Text, caption2FontSize, caption2Color),
            ),
        ],
      ),
    );
  }

  // 화자 색상 처리 (home_page.dart의 _buildCaptionWithSpeakerColor와 유사)
  Widget _buildCaptionWithSpeakerColor(
      String caption, double fontSize, Color defaultColor) {
    // [인물] 태그가 이미 포함된 텍스트이므로, 첫 번째 [인물] 태그만 찾아서 처리
    final RegExp speakerPattern = RegExp(r'\[인물\d+\]');
    final List<TextSpan> spans = [];
    int lastIndex = 0;
    final firstMatch = speakerPattern.firstMatch(caption);
    if (firstMatch != null) {
      // [인물] 태그 이전의 텍스트 (없어야 함)
      if (firstMatch.start > lastIndex) {
        spans.add(TextSpan(
          text: caption.substring(lastIndex, firstMatch.start),
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: defaultColor,
          ),
        ));
      }
      // [인물] 부분 (흰색 고정)
      spans.add(TextSpan(
        text: caption.substring(firstMatch.start, firstMatch.end),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ));
      lastIndex = firstMatch.end;
    }
    // [인물] 태그 이후의 텍스트 (기본 색상)
    if (lastIndex < caption.length) {
      spans.add(TextSpan(
        text: caption.substring(lastIndex),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: defaultColor,
        ),
      ));
    }
    // 매칭이 없으면 전체 텍스트를 기본 색상으로
    if (spans.isEmpty) {
      return Text(
        caption,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: defaultColor,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        softWrap: true,
      );
    }
    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
      maxLines: 3,
      softWrap: true,
    );
  }

  /// 토글 설정 행을 빌드하는 함수

  /// 라벨과 Switch 위젯을 포함

  Widget _buildToggleRow(String label, String toggleKey) {
    final bool value = _localToggles[toggleKey] ?? false;

    final bool isDisabled = _isDefaultMode;

    return Opacity(
      opacity: isDisabled ? _disabledFieldOpacity : 1.0,
      child: Row(
        children: [
          _buildSettingLabel(label, width: 200),
          const SizedBox(width: 40),
          Switch(
            value: value,
            onChanged: isDisabled
                ? null
                : (v) {
                    setState(() {
                      _localToggles[toggleKey] = v;
                    });
                  },
            activeThumbColor: _primaryBlue,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: _toggleInactiveTrackColor,
          ),
        ],
      ),
    );
  }

  // 오른쪽 섹션 (미리보기 + 버튼들)

  Widget _buildRightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('미리보기', style: _previewTitleTextStyle),
        const SizedBox(height: 8),
        Container(
          width: _previewWidth,
          height: _previewHeight,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(2.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2.8),
            child: Stack(
              children: [
                // 배경 이미지
                Image.asset(
                  'assets/setting_preview.png',
                  width: _previewWidth,
                  height: _previewHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black),
                ),
                // 자막 미리보기 오버레이
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.3), // 약간 어둡게
                    padding: const EdgeInsets.all(10),
                    child: _buildCaptionPreview(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: _previewWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 커스텀 모드가 선택되었고 모드 이름이 변경되지 않았으면 삭제하기, 아니면 추가하기
              _isCustomModeSelected &&
                      _modeName.trim() == _initialModeName.trim()
                  ? _buildDeleteButton(
                      _buttonWidth,
                      _buttonHeight,
                      _deleteCustomMode,
                    )
                  : _shouldShowAddButton()
                      ? _buildAddButton(
                          _buttonWidth,
                          _buttonHeight,
                          _hasChanges && !_isDefaultMode
                              ? _addCustomMode
                              : null,
                        )
                      : const SizedBox.shrink(), // 조건에 맞지 않으면 버튼 숨김

              const SizedBox(width: _buttonSpacing),

              _buildApplyButton(
                text: '적용하기',
                width: _buttonWidth,
                height: _buttonHeight,
                onTap: () async {
                  // 현재 설정을 DB에 저장
                  await _applySettingsToDb();

                  Navigator.pop(context, {
                    'toggles': _localToggles,
                    'customModes': _customModes,
                    'selectedMode': _selectedMode,
                    'soundPitch': _soundPitch,
                    'emotionColor': _emotionColor,
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 추가하기 버튼 (어두운 배경 + 파란색 테두리 + 플러스 아이콘)

  Widget _buildAddButton(double width, double height, VoidCallback? onTap) {
    final bool isDisabled = onTap == null;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0, // 비활성화 시 반투명

      child: GestureDetector(
        onTap: isDisabled ? null : onTap,
        child: MouseRegion(
          cursor:
              isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
          onEnter: (_) {
            if (!isDisabled) {
              setState(() => _isAddHovered = true);
            }
          },
          onExit: (_) {
            if (!isDisabled) {
              setState(() => _isAddHovered = false);
            }
          },
          child: AnimatedContainer(
            duration: _buttonAnimationDuration,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: _isAddHovered
                  ? _addDeleteButtonHoverBgColor
                  : _addDeleteButtonBgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primaryBlue, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.add, color: _primaryBlue, size: 32),
                ),
                SizedBox(width: 10),
                Text(
                  '추가하기',
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: _primaryBlue,
                    height: 39.2 / 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 삭제하기 버튼 (피그마 디자인: 어두운 배경 + 파란색 테두리 + 삭제 아이콘)

  Widget _buildDeleteButton(double width, double height, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _isAddHovered = true);
        },
        onExit: (_) {
          setState(() => _isAddHovered = false);
        },
        child: AnimatedContainer(
          duration: _buttonAnimationDuration,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _isAddHovered
                ? _addDeleteButtonHoverBgColor
                : _addDeleteButtonBgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _primaryBlue, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.delete_outline,
                  color: _primaryBlue,
                  size: 24,
                ),
              ),
              SizedBox(width: 10),
              Text(
                '삭제하기',
                style: TextStyle(
                  fontFamily: _fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: _primaryBlue,
                  height: 39.2 / 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 적용하기 버튼 (체크 아이콘 + 텍스트)

  Widget _buildApplyButton({
    required String text,
    required double width,
    required double height,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isApplyHovered = true),
        onExit: (_) => setState(() => _isApplyHovered = false),
        child: AnimatedContainer(
          duration: _buttonAnimationDuration,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _isApplyHovered ? _applyButtonHoverColor : _primaryBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.check, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 10),
              Text(text, style: _buttonTextStyle),
            ],
          ),
        ),
      ),
    );
  }
}
