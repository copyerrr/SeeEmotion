// lib/features/screens/home/home_page.dart
import 'dart:async';
import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../settings/setting_page.dart';
import '../../../services/tv_remote_service.dart';
import '../../../services/api_helpers.dart';
import '../../../utils/remote_point_overlay.dart';
import '../../../utils/subtitle_mode_notification.dart';
import '../../../utils/channel_notification.dart';
import 'package:deaftv_lgdxschool_projects/utils/loading_overlay.dart';

class HomePage extends StatefulWidget {
  final Map<String, bool>? initialToggles;
  final String? initialMode;
  final String? initialSoundPitch;
  final String? initialEmotionColor;
  final int? profileId; // profile_id 추가

  const HomePage({
    super.key,
    this.initialToggles,
    this.initialMode,
    this.initialSoundPitch,
    this.initialEmotionColor,
    this.profileId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isPanelVisible = false;
  bool _isInitialized = false; // 초기 렌더링 완료 플래그
  String _selectedMode = 'none';
  String? _focusedMode; // 리모컨으로 포커스된 모드 (확인 버튼으로 선택)
  bool _isDetailSettingsHovered = false; // 세부설정 호버 상태
  final Map<String, bool> _hoveredModes = {}; // 각 모드별 호버 상태
  OverlayEntry? _channelNotificationOverlay; // 채널 알림 Overlay

  // 모드 버튼 목록 (고정 순서)
  final List<Map<String, String>> _modes = const [
    {'label': '없음', 'mode': 'none'},
    {'label': '영화/드라마', 'mode': 'movie'},
    {'label': '다큐멘터리', 'mode': 'documentary'},
    {'label': '예능', 'mode': 'variety'},
  ];

  // 커스텀 모드 목록 (동적으로 추가됨)
  List<Map<String, dynamic>> _customModes = [];

  // DB에서 가져온 모드 목록 (모든 모드 포함)
  List<Map<String, dynamic>> _modesFromDb = [];

  // 현재 선택된 모드 ID (DB)
  int? _selectedModeId;

  // 현재 선택된 모드의 font_level (소리의 높낮이 단계)
  int _fontLevel = 2; // 기본값 2단계

  // 모드 리스트 스크롤 컨트롤러
  final ScrollController _modeScrollController = ScrollController();

  // 토글 상태 Map
  late Map<String, bool> _toggles;

  // 실시간 영상 + 자막용
  VideoPlayerController? _videoController;
  WebSocketChannel? _captionChannel;
  StreamSubscription? _captionSubscription; // WebSocket 스트림 리스너 추적
  String _currentCaption = "";
  String _previousCaption = ""; // 이전 자막
  String _currentCaptionOriginal = ""; // 원본 자막 텍스트 (이모지/태그 제거 전)
  String _previousCaptionOriginal = ""; // 이전 원본 자막 텍스트
  Color _captionColor = Colors.white;
  Color _previousCaptionColor = Colors.white; // 이전 자막 색상
  double _captionFontSize = 50.0; // 기본 폰트 크기
  double _previousCaptionFontSize = 50.0; // 이전 자막 폰트 크기
  String _captionPosition = '분리'; // 자막 위치: '하단', '상단', '분리'
  double _intensity = 0.5; // 볼륨 기반 강도 (0~1)
  String _currentBgm = ""; // 현재 배경음
  String _currentSfx = ""; // 현재 효과음
  String _videoName = "enter_web.mp4"; // 비디오 파일명
  bool _isVideoAnalyzed = false; // 비디오 분석 완료 여부

  // 채널 관련 변수
  final List<Map<String, String>> _channels = const [
    {'name': 'date', 'label': 'DATE', 'file': 'enter_web.mp4'},
    {'name': 'dacu', 'label': 'DACU', 'file': 'dacu2.mp4'},
    {'name': 'x', 'label': 'X', 'file': 'drama.mp4'},
  ];
  String _currentChannel = 'dacu'; // 현재 채널 (dacu2 테스트용)

  double _videoDuration = 0.0; // 비디오 길이 (초)
  int _reconnectLogCount = 0; // 재연결 로그 카운터
  int _errorLogCount = 0; // 에러 로그 카운터
  bool _isConnecting = false; // WebSocket 연결 중 플래그
  bool _isVideoReadyToPlay = false; // 비디오 재생 준비 완료 여부 (자막이 충분히 쌓였는지)
  bool _isSwitchingChannel = false; // 채널 전환 중 플래그 (재연결 방지용)
  Timer? _virtualTimeTimer; // 비디오가 없을 때 가상 시간 추적용 타이머
  double _virtualCurrentTime = 0.0; // 가상 현재 시간 (비디오가 없을 때 사용)
  double _savedVolume = 1.0; // 음소거 전 볼륨 저장 (0.0~1.0)
  bool _previousIsMuted = false; // 이전 음소거 상태 (변경 감지용)

  // 자막 큐 (타임스탬프 기반)
  List<Map<String, dynamic>> _captionQueue =
      []; // [{start, end, text, color, emotion, intensity, ...}]

  // 채널별 자막 큐 캐시 (채널 전환 시 재사용)
  Map<String, List<Map<String, dynamic>>> _channelCaptionCache = {};

  // 리모컨 앱 연결 (Firestore)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _tvStateSubscription;
  bool _isSettingsPageOpen = false; // 설정 페이지가 열려있는지 추적
  bool _isSubtitleModeOn = false; // 자막 모드 상태
  bool? _previousSubtitleModeOn; // 이전 subtitleModeOn 값 (변경 감지용)
  OverlayEntry? _subtitleNotificationOverlay; // 자막 모드 알림 Overlay
  OverlayEntry? _volumeNotificationOverlay; // 볼륨 알림 Overlay
  int? _lastRemoteChannelNumber; // 마지막 리모컨 채널 번호 (중복 호출 방지)
  int _currentVolume = 60; // 현재 볼륨 (0~100)
  int? _previousVolume; // 이전 볼륨 값 (변경 감지용)
  bool _currentIsMuted = false; // 현재 음소거 상태
  Timer? _volumeHideTimer; // 볼륨 UI 자동 숨김 타이머
  DateTime? _pageLoadTime; // 페이지 로드 시간 (초기 1초 동안 볼륨 UI 표시 방지용)
  bool? _previousOpenSettingsPage; // 이전 openSettingsPage 값 (변경 감지용)
  bool? _previousConfirmModeSelection; // 이전 confirmModeSelection 값 (변경 감지용)
  bool? _previousBackButtonPressed; // 이전 backButtonPressed 값 (변경 감지용)
  bool? _previousQuickModeOpen; // 이전 quickModeOpen 값 (초기 로드 시 무시용)

  // 미리보기 이미지
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

  @override
  void initState() {
    super.initState();
    // 패널이 절대 자동으로 열리지 않도록 명시적으로 false 설정
    _isPanelVisible = false;
    _isInitialized = false;
    _previousOpenSettingsPage = null; // 초기값
    _previousConfirmModeSelection = null; // 초기값
    _previousBackButtonPressed = null; // 초기값
    _previousSubtitleModeOn = null; // 초기값
    _pageLoadTime = DateTime.now(); // 페이지 로드 시간 기록

    // 초기 토글 상태 설정 (임시값, DB에서 로드한 값으로 덮어씌워짐)
    if (widget.initialToggles != null && widget.initialToggles!.isNotEmpty) {
      _toggles = Map<String, bool>.from(widget.initialToggles!);
    } else {
      _toggles = {
        '말의 강도': false,
        '감정 색상': false,
        '화자 설정': false,
        '배경음 표시': false,
        '효과음 표시': false,
      };
    }

    // DB에서 모드 목록과 현재 선택된 모드 로드 (비동기)
    _loadModesFromDb();

    // 3. 초기 채널 설정
    final initialChannel = _channels.firstWhere(
      (ch) => ch['name'] == _currentChannel,
      orElse: () => _channels[0],
    );
    _videoName = initialChannel['file'] ?? 'enter_web.mp4';

    // 4. 리모컨 앱 상태 구독 시작
    _subscribeToRemoteControl();

    // 5. (중요!!) 화면 그리기 준비 완료 신호 보내기
    // 이 부분이 없으면 퀵패널(_buildSidePanel)이 아예 그려지지 않습니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isInitialized = true; // 이것이 true가 되어야 패널이 등장합니다.

        // 초기 모드가 있다면 해당 위치로 스크롤 이동 (선택사항)
        if (widget.initialMode != null && _selectedMode != 'none') {
          if (_modeScrollController.hasClients) {
            int selectedIndex = _getVisualIndexForMode(_selectedMode);
            // ... 스크롤 로직 ...
          }
        }
      });
    });

    _initLiveVideoAndCaptions();
  }

  // 모드 이름을 모드 코드로 변환하는 헬퍼 함수
  String _modeNameToCode(String modeName) {
    switch (modeName) {
      case '없음':
        return 'none';
      case '영화/드라마':
        return 'movie';
      case '다큐멘터리':
        return 'documentary';
      case '예능':
        return 'variety';
      default:
        // 커스텀 모드는 ID로 변환
        return 'custom_unknown';
    }
  }

  // DB에서 모드 목록 불러오기
  // 기존 _loadModesFromDb 함수를 지우고 이 코드로 덮어쓰세요.
  Future<void> _loadModesFromDb() async {
    // 1. 예외처리 없이 무조건 1번 프로필 데이터 요청 (에러나면 앱 죽게 둠)
    // 헬퍼 함수로 GET 요청
    final data = await ApiHelpers.get(
      '/caption-modes/',
      query: {'profile_id': '1'},
    );
    final modes = (data as List).cast<Map<String, dynamic>>();

    // 2. 화면에 예쁘게 보이려면 '순서'는 맞춰야 함 (없음 -> 커스텀 -> 기본)
    // 이 정렬 로직은 UI 표시를 위해 필요함
    final defaultModeOrder = ['영화/드라마', '다큐멘터리', '예능'];

    final List<Map<String, dynamic>> defaultModes = [];
    final List<Map<String, dynamic>> customModes = [];
    Map<String, dynamic> noneMode = {};

    // 현재 선택된 모드 찾기 (caption_settings에서 가져온 mode_id와 매칭)
    Map<String, dynamic>? currentSelectedMode;
    int? currentModeId = _selectedModeId;

    for (final mode in modes) {
      final name = mode['mode_name'] as String? ?? '';
      final modeId = mode['id'] as int?;

      // 현재 선택된 모드 찾기 (mode_id가 일치하는 경우)
      if (currentModeId != null && modeId == currentModeId) {
        currentSelectedMode = mode;
      }

      if (name == '없음') {
        noneMode = mode;
      } else if (defaultModeOrder.contains(name)) {
        defaultModes.add(mode);
      } else {
        customModes.add(mode);
      }
    }

    // 현재 선택된 모드가 없으면 caption_settings에서 가져오기 시도
    if (currentSelectedMode == null) {
      try {
        // 프로필의 현재 선택된 모드 ID 가져오기 (caption_settings 테이블)
        final profileId = widget.profileId ?? 1;
        final data = await ApiHelpers.get(
          '/caption-settings/profile/$profileId',
        ) as Map<String, dynamic>?;
        final modeId = data?['mode_id'] as int?;

        if (modeId != null) {
          currentModeId = modeId;
          // 모드 목록에서 해당 모드 찾기
          currentSelectedMode = modes.firstWhere(
            (m) => (m['id'] as int?) == modeId,
            orElse: () => <String, dynamic>{},
          );
        }
      } catch (e) {
        // 에러 무시
      }
    }

    // 커스텀은 최신순(ID 역순), 기본 모드는 고정 순서
    customModes.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    defaultModes.sort((a, b) => defaultModeOrder
        .indexOf(a['mode_name'])
        .compareTo(defaultModeOrder.indexOf(b['mode_name'])));

    // 3. 최종 리스트 합치기
    final List<Map<String, dynamic>> finalSortedList = [];
    if (noneMode.isNotEmpty) finalSortedList.add(noneMode);
    finalSortedList.addAll(customModes);
    finalSortedList.addAll(defaultModes);

    // 4. 현재 선택된 모드로 _selectedMode와 _focusedMode 설정
    String? selectedModeCode;
    if (currentSelectedMode != null && currentSelectedMode.isNotEmpty) {
      final modeName = currentSelectedMode['mode_name'] as String? ?? '';
      final modeId = currentSelectedMode['id'] as int?;

      if (modeName == '없음' ||
          modeName == '영화/드라마' ||
          modeName == '다큐멘터리' ||
          modeName == '예능') {
        selectedModeCode = _modeNameToCode(modeName);
      } else if (modeId != null) {
        // 커스텀 모드
        selectedModeCode = 'custom_$modeId';
      }
    }

    // 5. 상태 업데이트 (화면 갱신)
    setState(() {
      _modesFromDb = finalSortedList;

      // 퀵패널 UI 그릴 때 _customModes도 쓰인다면 여기서 같이 채워줌 (단순화)
      _customModes = customModes
          .map((m) => {
                'id': 'custom_${m['id']}',
                'name': m['mode_name'],
              })
          .toList();

      // DB에서 현재 선택된 모드가 있으면 설정
      if (selectedModeCode != null) {
        _selectedMode = selectedModeCode;
        _focusedMode = selectedModeCode;
        if (currentModeId != null) {
          _selectedModeId = currentModeId;
        }
      }
    });

    // 모드 설정도 로드 (setState 밖에서 호출)
    if (selectedModeCode != null) {
      await _loadModeSettings(selectedModeCode);
    } else {
      // 선택된 모드가 없으면 '없음' 모드의 설정을 로드
      await _loadModeSettings('none');
    }
  }

  /// 모드 목록 정렬: 커스텀 모드들(최신순), 기본 모드들 순서
  List<Map<String, dynamic>> _sortModes(List<Map<String, dynamic>> modes) {
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

  // 모드 선택 시 DB에 저장
  Future<void> _saveSelectedModeToDb(String mode) async {
    // 프로필 ID는 항상 1번 (DB가 항상 1번 프로필이므로)
    const profileId = 1;

    // 'none' 모드는 DB에 저장하지 않음
    if (mode == 'none') {
      return;
    }

    // 기본 모드(movie, documentary, variety) 찾기
    String? modeName;
    if (mode == 'movie')
      modeName = '영화/드라마';
    else if (mode == 'documentary')
      modeName = '다큐멘터리';
    else if (mode == 'variety') modeName = '예능';

    // DB에서 모드 찾기
    Map<String, dynamic> modeData;
    if (modeName != null) {
      // 기본 모드: 모드 이름으로 찾기
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
      setState(() {
        _modesFromDb = modesFromDb;
      });

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

  // 모드 선택 시 DB에서 설정 불러오기
  Future<void> _loadModeSettings(String mode) async {
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

    // DB에서 모드 찾기 (예외처리 제거, 무조건 찾아야 함)
    Map<String, dynamic> modeData;
    if (modeName != null) {
      // 모드 이름으로 찾기 (없음, 영화/드라마, 다큐멘터리, 예능 모두 포함)
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
    final modeId = modeData['id'] as int?;
    final fontLevel = modeData['font_level'] as int? ?? 2;
    final fontSizeToggle = _toBool(modeData['fontSize_toggle']);
    final fontColorToggle = _toBool(modeData['fontColor_toggle']);
    final isEmpathyOn = _toBool(modeData['is_empathy_on']);

    setState(() {
      _selectedModeId = modeId;
      _fontLevel = fontLevel;
      // DB에서 가져온 토글 값들로 업데이트
      _toggles['말의 강도'] = fontSizeToggle;
      _toggles['감정 색상'] = fontColorToggle || isEmpathyOn;
      _toggles['화자 설정'] = speaker;
      _toggles['배경음 표시'] = bgm;
      _toggles['효과음 표시'] = effect;
    });

    // 모드 변경 시 현재 자막 다시 업데이트 (스타일 반영)
    if (_videoController != null && _isVideoAnalyzed) {
      final currentTime = _videoController!.value.position.inSeconds.toDouble();
      _updateCaptionForCurrentTime(currentTime);
    }
  }

  // 토글 변경 시 DB에 저장하지 않음 (임시 상태만 변경)
  // 실제 DB 저장은 setting_page에서 "적용하기" 버튼으로 수행

  @override
  void dispose() {
    _modeScrollController.dispose();
    _tvStateSubscription?.cancel();
    _hideSubtitleModeNotification();
    _hideChannelNotification();
    _hideVolumeNotification();
    // dispose에서는 await 없이 호출 (async dispose는 지원되지 않음)
    try {
      _cleanupVideoAndCaptions();
    } catch (_) {
      // 에러 무시
    }
    super.dispose();
  }

  /// 리모컨 앱 상태 구독 (Firestore)
  void _subscribeToRemoteControl() {
    _tvStateSubscription =
        TvRemoteService.getTvStateStream().listen((snapshot) async {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      // 뒤로가기 버튼 처리 - false -> true로 변경될 때만 처리
      final currentBackButtonPressed =
          data['backButtonPressed'] as bool? ?? false;
      if (_previousBackButtonPressed == null) {
        // 첫 데이터는 무조건 무시하고 현재 값만 저장
        _previousBackButtonPressed = currentBackButtonPressed;
      } else if (_previousBackButtonPressed == false &&
          currentBackButtonPressed == true) {
        // false -> true 전환만 처리
        if (_isPanelVisible) {
          setState(() {
            _isPanelVisible = false;
            _focusedMode = null;
          });
          // Firebase에도 반영
          FirebaseFirestore.instance
              .collection('tvs')
              .doc('demo_tv_01')
              .set({'quickModeOpen': false}, SetOptions(merge: true));
        }
        _previousBackButtonPressed = currentBackButtonPressed;
      } else {
        _previousBackButtonPressed = currentBackButtonPressed;
      }

      // 퀵모드 패널 열기/닫기
      if (data['quickModeOpen'] != null) {
        final quickModeOpen = data['quickModeOpen'] as bool;

        // 첫 번째 로드 시 무시하고 패널을 닫힌 상태로 유지
        if (_previousQuickModeOpen == null) {
          _previousQuickModeOpen = quickModeOpen;
          // Firebase 값이 true여도 초기에는 패널을 닫힌 상태로 강제 설정
          if (quickModeOpen) {
            setState(() {
              _isPanelVisible = false;
              _focusedMode = null;
            });
            // Firebase에도 닫힌 상태로 동기화
            FirebaseFirestore.instance
                .collection('tvs')
                .doc('demo_tv_01')
                .set({'quickModeOpen': false}, SetOptions(merge: true));
          }
        } else {
          // 상태가 다를 때만 업데이트 (중복 호출 방지)
          if (quickModeOpen != _isPanelVisible) {
            setState(() {
              _isPanelVisible = quickModeOpen;
              // 패널이 열릴 때 현재 선택된 모드로 포커스 초기화
              if (quickModeOpen) {
                _focusedMode = _selectedMode;
              } else {
                _focusedMode = null;
              }
            });
          }
          _previousQuickModeOpen = quickModeOpen;
        }
      }

      // 설정 페이지 열기 - false -> true로 변경될 때만 처리
      final currentOpenSettingsPage =
          data['openSettingsPage'] as bool? ?? false;
      if (_previousOpenSettingsPage == null) {
        // 첫 데이터는 무조건 무시하고 현재 값만 저장
        _previousOpenSettingsPage = currentOpenSettingsPage;
      } else if (_previousOpenSettingsPage == false &&
          currentOpenSettingsPage == true) {
        _openSettingsPage();
        _previousOpenSettingsPage = currentOpenSettingsPage;
      } else {
        _previousOpenSettingsPage = currentOpenSettingsPage;
      }

      // 채널 변경 처리 (중복 호출 방지)
      if (data['channel'] != null) {
        var channelNumber = (data['channel'] as num).toInt();
        final originalChannel = channelNumber; // 원본 값 저장 (로그용)
        // 채널 번호를 1~3 범위로 정규화 (4→1, 5→2, 6→3...)
        channelNumber = channelNumber <= 0 ? 3 : ((channelNumber - 1) % 3) + 1;
        // 이전 채널 번호와 다를 때만 처리
        if (_lastRemoteChannelNumber != channelNumber) {
          _lastRemoteChannelNumber = channelNumber;
          _handleRemoteChannelChange(channelNumber);
        }
      }

      // 왼쪽 화살표 버튼 처리
      if (data['left'] == true) {
        _handleLeftArrow();
      }

      // 오른쪽 화살표 버튼 처리
      if (data['right'] == true) {
        _handleRightArrow();
      }

      // confirmModeSelection 필드는 명시적으로 무시 (GuideShakePage로 이동하지 않도록)
      // false -> true 전환만 무시하고, 첫 데이터도 무시
      final currentConfirmModeSelection =
          data['confirmModeSelection'] as bool? ?? false;
      if (_previousConfirmModeSelection == null) {
        // 첫 데이터는 무조건 무시하고 현재 값만 저장
        _previousConfirmModeSelection = currentConfirmModeSelection;
      } else if (_previousConfirmModeSelection == false &&
          currentConfirmModeSelection == true) {
        _previousConfirmModeSelection = currentConfirmModeSelection;
      } else {
        _previousConfirmModeSelection = currentConfirmModeSelection;
      }

      // 확인 버튼 처리 - 확인 버튼이 눌렸고 포커스된 모드가 있을 때만 처리
      if (data['okButtonPressed'] == true) {
        if (_isPanelVisible && _focusedMode != null) {
          await _handleConfirmButton(0.0, 0.0); // 좌표는 사용하지 않으므로 임의 값
        }
      }

      // 자막 위치 변경 처리 (caption: number)
      // 0 = 분리, 1 = 상단, 2 = 하단
      if (data['caption'] != null) {
        final captionValue = (data['caption'] as num).toInt();
        String newPosition = '분리';
        if (captionValue == 1) {
          newPosition = '상단';
        } else if (captionValue == 2) {
          newPosition = '하단';
        }
        if (_captionPosition != newPosition) {
          setState(() {
            _captionPosition = newPosition;
          });
        }
      }

      // 자막 on/off 처리 (subtitleModeOn: boolean) - false -> true로 변경될 때만 처리
      if (data['subtitleModeOn'] != null) {
        final currentSubtitleModeOn = data['subtitleModeOn'] as bool;
        if (_previousSubtitleModeOn == null) {
          // 첫 데이터는 무조건 무시하고 현재 값만 저장
          _previousSubtitleModeOn = currentSubtitleModeOn;
          setState(() {
            _isSubtitleModeOn = currentSubtitleModeOn;
          });
        } else if (_previousSubtitleModeOn == false &&
            currentSubtitleModeOn == true) {
          // false -> true 전환만 처리
          setState(() {
            _isSubtitleModeOn = currentSubtitleModeOn;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSubtitleModeNotification(_isSubtitleModeOn);
          });
          _previousSubtitleModeOn = currentSubtitleModeOn;
        } else if (_previousSubtitleModeOn == true &&
            currentSubtitleModeOn == false) {
          // true -> false 전환도 처리
          setState(() {
            _isSubtitleModeOn = currentSubtitleModeOn;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSubtitleModeNotification(_isSubtitleModeOn);
          });
          _previousSubtitleModeOn = currentSubtitleModeOn;
        } else {
          _previousSubtitleModeOn = currentSubtitleModeOn;
        }
      }

      // 음소거 및 볼륨 처리 (muteToggled: map)
      if (data['muteToggled'] != null) {
        final muteToggled = data['muteToggled'] as Map<String, dynamic>?;
        if (muteToggled != null) {
          final isMuted = muteToggled['isMuted'] as bool? ?? false;
          final volume = muteToggled['volume'] as num?;

          // 이전 값 저장 (변경 감지용)
          final previousIsMuted = _previousIsMuted;
          final previousVolume = _previousVolume;

          // 현재 상태 업데이트
          setState(() {
            _currentIsMuted = isMuted;
            if (volume != null) {
              _currentVolume = volume.toInt();
            }
          });

          // 음소거 상태 변경 처리
          if (isMuted != previousIsMuted) {
            _previousIsMuted = isMuted;
            _handleMuteToggle(isMuted);
            // 음소거 상태가 변경되었을 때만 UI 표시
            _showVolumeNotification(_currentVolume, isMuted);
          }

          // 볼륨 값 변경 처리 (음소거가 아닐 때만)
          if (volume != null) {
            final volumeInt = volume.toInt();
            // 이전 볼륨과 다를 때만 처리 및 UI 표시
            if (previousVolume != null &&
                previousVolume != volumeInt &&
                !isMuted) {
              _handleVolumeChange(volume.toDouble());
              // 볼륨이 변경되었을 때만 UI 표시
              _showVolumeNotification(_currentVolume, isMuted);
            }
            // 이전 볼륨 값 업데이트
            _previousVolume = volumeInt;
          }
        }
      }

      // 터치 포인터와 클릭 이벤트는 RemotePointerOverlay에서 처리됨
    });
  }

  /// 음소거 토글 처리
  void _handleMuteToggle(bool isMuted) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    if (isMuted) {
      // 음소거: 현재 볼륨 저장 후 0으로 설정
      _savedVolume = _videoController!.value.volume;
      _videoController!.setVolume(0.0);
    } else {
      // 음소거 해제: 저장된 볼륨으로 복원
      _videoController!.setVolume(_savedVolume);
    }
  }

  /// 볼륨 변경 처리
  void _handleVolumeChange(double volume) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    // Firebase의 volume 값은 0~100 범위이므로 0.0~1.0으로 변환
    final normalizedVolume = (volume / 100.0).clamp(0.0, 1.0);

    // 음소거가 아닐 때만 볼륨 변경
    if (!_previousIsMuted) {
      _videoController!.setVolume(normalizedVolume);
      _savedVolume = normalizedVolume; // 저장된 볼륨도 업데이트
    }
  }

  /// 확인 버튼 처리 - 포커스된 모드를 실제로 선택
  Future<void> _handleConfirmButton(double clickX, double clickY) async {
    // 퀵패널이 열려있고 포커스된 모드가 있으면 모드 선택
    if (_isPanelVisible && _focusedMode != null) {
      setState(() {
        _selectedMode = _focusedMode!;
      });
      // 모드 설정을 DB에서 불러와서 토글 업데이트 (await 필수!)
      await _loadModeSettings(_focusedMode!);
      _saveSelectedModeToDb(_focusedMode!);

      // 선택된 모드 버튼으로 스크롤 이동
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_modeScrollController.hasClients) {
          final selectedIndex = _getVisualIndexForMode(_focusedMode!);
          double cumulativeWidth = 0;
          for (int i = 0; i < selectedIndex; i++) {
            final String prevLabel = _getLabelForVisualIndex(i);
            final textPainter = TextPainter(
              text: TextSpan(
                text: prevLabel,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            cumulativeWidth += textPainter.size.width + 40; // 버튼 너비 + 간격
          }
          _modeScrollController.animateTo(
            cumulativeWidth.clamp(
                0.0, _modeScrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 왼쪽 화살표 버튼 처리
  void _handleLeftArrow() {
    // 퀵패널이 열려있으면 모드 포커스만 이동 (실제 모드 변경은 확인 버튼으로)
    if (_isPanelVisible) {
      // 현재 포커스된 모드 (없으면 선택된 모드)
      final currentFocusMode = _focusedMode ?? _selectedMode;
      final currentVisualIndex = _getVisualIndexForMode(currentFocusMode);
      if (currentVisualIndex > 0) {
        // 이전 모드로 포커스 이동
        final prevMode = _getModeForVisualIndex(currentVisualIndex - 1);
        if (prevMode != null) {
          setState(() {
            _focusedMode = prevMode;
          });

          // 포커스된 모드 버튼으로 스크롤 이동
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_modeScrollController.hasClients) {
              double cumulativeWidth = 0;
              for (int i = 0; i < currentVisualIndex - 1; i++) {
                final String prevLabel = _getLabelForVisualIndex(i);
                final textPainter = TextPainter(
                  text: TextSpan(
                    text: prevLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                textPainter.layout();
                cumulativeWidth += textPainter.size.width + 40; // 버튼 너비 + 간격
              }
              _modeScrollController.animateTo(
                cumulativeWidth.clamp(
                    0.0, _modeScrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
          return; // 모드 포커스 이동했으면 종료
        }
      }
    }
  }

  /// 오른쪽 화살표 버튼 처리
  void _handleRightArrow() {
    // 퀵패널이 열려있으면 모드 포커스만 이동 (실제 모드 변경은 확인 버튼으로)
    if (_isPanelVisible) {
      // 현재 포커스된 모드 (없으면 선택된 모드)
      final currentFocusMode = _focusedMode ?? _selectedMode;
      final currentVisualIndex = _getVisualIndexForMode(currentFocusMode);
      final totalModes =
          1 + _customModes.length + (_modes.length - 1); // 없음 + 커스텀 + 기본 모드들
      if (currentVisualIndex < totalModes - 1) {
        // 다음 모드로 포커스 이동
        final nextMode = _getModeForVisualIndex(currentVisualIndex + 1);
        if (nextMode != null) {
          setState(() {
            _focusedMode = nextMode;
          });

          // 포커스된 모드 버튼으로 스크롤 이동
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_modeScrollController.hasClients) {
              double cumulativeWidth = 0;
              for (int i = 0; i < currentVisualIndex + 1; i++) {
                final String prevLabel = _getLabelForVisualIndex(i);
                final textPainter = TextPainter(
                  text: TextSpan(
                    text: prevLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                textPainter.layout();
                cumulativeWidth += textPainter.size.width + 40; // 버튼 너비 + 간격
              }
              _modeScrollController.animateTo(
                cumulativeWidth.clamp(
                    0.0, _modeScrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
          return; // 모드 포커스 이동했으면 종료
        }
      }
    }
  }

  /// 리모컨에서 보낸 채널 변경 처리
  /// 채널 번호: 1=date, 2=dacu, 3=x (정규화 후 1~3만 들어옴)
  void _handleRemoteChannelChange(int channelNumber) {
    // 채널 번호를 채널 이름으로 매핑 (정규화 후 1~3만 들어옴)
    String? targetChannelName;
    switch (channelNumber) {
      case 1:
        targetChannelName = 'date';
        break;
      case 2:
        targetChannelName = 'dacu';
        break;
      case 3:
        targetChannelName = 'x';
        break;
      default:
        // 범위 밖이면 무시 (정규화 후에는 1~3만 들어오므로 여기 도달하면 안 됨)
        return;
    }

    // 현재 채널과 다르면 변경
    if (targetChannelName != _currentChannel) {
      // 채널 알림 표시
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showChannelNotification(channelNumber);
      });
      _switchChannel(targetChannelName);
    }
  }

  /// 설정 페이지 열기
  void _openSettingsPage() async {
    // 소리만 끄고 영상은 계속 재생
    if (_videoController != null && _videoController!.value.isInitialized) {
      // 현재 볼륨 저장
      _savedVolume = _videoController!.value.volume;
      // 소리만 끄기 (볼륨 0으로 설정)
      _videoController!.setVolume(0.0);
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingPage(
          toggles: Map.from(_toggles),
          initialSoundPitch: widget.initialSoundPitch,
          initialEmotionColor: widget.initialEmotionColor,
          profileId: widget.profileId ?? 1,
        ),
      ),
    );

    // 세부설정 창 닫을 때 소리 다시 켜기 (저장된 볼륨으로 복원)
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.setVolume(_savedVolume);
    }

    // 중요: setting_page에서 돌아올 때 항상 모드 목록을 다시 불러옴 (DB 변경사항 반영)
    await _loadModesFromDb();

    if (result != null) {
      // 토글 업데이트
      if (result['toggles'] != null) {
        final newToggles = Map<String, bool>.from(result['toggles'] as Map);
        setState(() {
          _toggles = newToggles;
        });
      }

      // 선택된 모드 업데이트 및 자막 다시 불러오기
      if (result['selectedMode'] != null) {
        final newMode = result['selectedMode'] as String;
        setState(() {
          _selectedMode = newMode;
        });

        // 모드 설정 다시 불러오기 (DB에서 최신 값 가져오기)
        if (_selectedMode != 'none') {
          await _loadModeSettings(_selectedMode);
          // 모드 설정 변경 후 현재 자막 다시 업데이트
          if (_videoController != null && _isVideoAnalyzed) {
            final currentTime =
                _videoController!.value.position.inSeconds.toDouble();
            _updateCaptionForCurrentTime(currentTime);
          }
        }
      }
    } else {
      // result가 null이어도 현재 선택된 모드의 설정은 다시 불러옴 (DB 변경사항 반영)
      if (_selectedMode != 'none') {
        await _loadModeSettings(_selectedMode);
      }
    }
  }

  // 채널 전환 함수
  Future<void> _switchChannel(String channelName) async {
    if (_currentChannel == channelName) return; // 같은 채널이면 무시

    // 채널 정보 찾기
    final channel = _channels.firstWhere(
      (ch) => ch['name'] == channelName,
      orElse: () => _channels[0], // 기본값: date
    );

    // 현재 채널의 자막 큐를 캐시에 저장 (빈 큐여도 저장하여 상태 유지)
    _channelCaptionCache[_currentChannel] = List.from(_captionQueue);

    // 채널 전환 플래그 설정 (재연결 방지)
    setState(() {
      _isSwitchingChannel = true;
    });

    // 기존 비디오 및 WebSocket 정리 (완전히 정리될 때까지 대기)
    await _cleanupVideoAndCaptions();

    if (!mounted) return;

    // 새 채널의 자막 큐가 캐시에 있는지 확인
    final cachedQueue = _channelCaptionCache[channelName];
    final hasCachedCaptions = cachedQueue != null && cachedQueue.isNotEmpty;

    // 상태 업데이트
    setState(() {
      _currentChannel = channelName;
      _videoName = channel['file'] ?? 'enter_web.mp4';

      // 캐시된 자막이 있으면 복원, 없으면 초기화
      if (hasCachedCaptions) {
        _captionQueue = List.from(cachedQueue);
        _isVideoReadyToPlay = true; // 캐시된 자막이 있으면 바로 재생 가능
        _isVideoAnalyzed = true; // 이미 분석된 자막

        // 복원된 자막이 있으면 첫 자막 표시
        if (_captionQueue.isNotEmpty) {
          _updateCaptionForCurrentTime(0.0);
        }
      } else {
        _captionQueue.clear();
        _isVideoReadyToPlay = false;
        _isVideoAnalyzed = false;
      }

      _currentCaption = "";
      _previousCaption = "";
      _currentCaptionOriginal = "";
      _previousCaptionOriginal = "";
    });

    // 새 채널로 비디오 및 자막 초기화
    _initLiveVideoAndCaptions();

    // 캐시된 자막이 있으면 비디오 초기화 완료 후 재생 시작
    // 비디오 초기화는 비동기이므로, 초기화 완료 후 재생하도록 수정
    if (hasCachedCaptions) {
      // 비디오 초기화 완료를 기다리지 않고, 초기화 완료 시 자동으로 재생되도록 함
      // _initLiveVideoAndCaptions() 내부에서 처리됨
    }

    // 채널 전환 완료 (재연결 허용)
    setState(() {
      _isSwitchingChannel = false;
    });
  }

  // 비디오 및 자막 정리 함수
  Future<void> _cleanupVideoAndCaptions() async {
    // 현재 채널의 자막 큐를 캐시에 저장 (정리 전에 저장)
    if (_captionQueue.isNotEmpty) {
      _channelCaptionCache[_currentChannel] = List.from(_captionQueue);
    }

    // 비디오 컨트롤러 정리
    _videoController?.removeListener(_onVideoPositionChanged);
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;

    // WebSocket 연결 종료 (비동기로 완전히 정리)
    try {
      // 스트림 리스너 먼저 취소
      await _captionSubscription?.cancel();
      _captionSubscription = null;

      if (_captionChannel != null) {
        await _captionChannel!.sink.close();
      }
    } catch (e) {
      // 에러 무시
    } finally {
      _captionChannel = null;
      _captionSubscription = null;
      // 정리 완료를 위해 짧은 대기
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 상태 초기화 (자막 큐는 캐시에 저장했으므로 여기서는 초기화하지 않음)
    _isVideoAnalyzed = false;
    _isVideoReadyToPlay = false;
    _isConnecting = false;
    _currentCaption = "";
    _previousCaption = "";
    _captionColor = Colors.white;
    _previousCaptionColor = Colors.white;
    _captionFontSize = 24.0;
    _previousCaptionFontSize = 24.0;
    // _captionQueue.clear(); // 채널 전환 시 캐시 복원을 위해 clear하지 않음
    _videoDuration = 0.0;
  }

  // 채널 변경 함수 (리모컨 기능용)
  Future<void> changeChannel(String videoName) async {
    // 기존 비디오 및 자막 정리 (완전히 정리될 때까지 대기)
    await _cleanupVideoAndCaptions();

    // 새로운 비디오 설정
    setState(() {
      _videoName = videoName;
    });

    // 새로운 비디오 및 자막 초기화
    _initLiveVideoAndCaptions();
  }

  // 실시간 영상 & 자막 초기화
  void _initLiveVideoAndCaptions() {
    final videoPath = 'assets/$_videoName';

    // 기존 컨트롤러가 있으면 먼저 정리
    if (_videoController != null) {
      _videoController?.removeListener(_onVideoPositionChanged);
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;
    }

    _videoController = VideoPlayerController.asset(videoPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController?.setLooping(true);
          // 자동 재생하지 않음 - 자막이 충분히 쌓인 후 재생 시작

          // 비디오 길이 확인 및 저장
          if (_videoController != null &&
              _videoController!.value.isInitialized) {
            _videoDuration =
                _videoController!.value.duration.inSeconds.toDouble();
          }

          // 비디오 재생 시간 추적 시작 (자막 싱크를 위해 먼저 시작)
          _startVideoTimeTracking();

          // 캐시된 자막이 있으면 바로 재생 시작
          if (_isVideoReadyToPlay && _captionQueue.isNotEmpty) {
            // 현재 시간(0초)에 맞는 자막 즉시 표시
            _updateCaptionForCurrentTime(0.0);
            // 비디오 재생 시작
            _videoController?.play();
          }

          // 비디오 분석 요청 (캐시된 자막이 없을 때만)
          if (!_isVideoAnalyzed) {
            _analyzeVideo();
          }
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _videoController = null;
          });
        }
      });

    // WebSocket 연결 (비디오 분석 서버) - 성공할 때까지 재시도
    // 자막을 먼저 받아서 큐에 쌓은 후 비디오 재생 시작
    _connectWebSocket();
  }

  // WebSocket 연결 함수 (성공할 때까지 재시도)
  void _connectWebSocket() {
    const webSocketUrl = 'ws://localhost:8002/ws/video-captions';
    int retryDelay = 2; // 초
    const int maxDelay = 10; // 최대 대기 시간

    Future<void> connect() async {
      // 이미 연결 중이면 스킵 (더 강력한 체크)
      if (_isConnecting) {
        return;
      }

      // 이미 연결되어 있고 리스너가 설정되어 있으면 스킵
      if (_captionChannel != null && _captionSubscription != null) {
        return;
      }

      try {
        _isConnecting = true;

        // 기존 연결이 있으면 완전히 닫기
        if (_captionChannel != null) {
          try {
            // 기존 스트림 리스너 먼저 취소
            await _captionSubscription?.cancel();
            _captionSubscription = null;
            await _captionChannel!.sink.close();
            // 닫힐 때까지 대기
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (_) {
            // 이미 닫혀있을 수 있음
          }
          _captionChannel = null;
        }

        // 리스너가 여전히 남아있으면 null로 설정
        if (_captionSubscription != null) {
          _captionSubscription = null;
        }

        _captionChannel = WebSocketChannel.connect(Uri.parse(webSocketUrl));

        // 연결 상태 확인을 위한 지연
        await Future.delayed(const Duration(milliseconds: 1000));

        // 다시 한 번 확인 (다른 곳에서 이미 리스너를 설정했을 수 있음)
        if (_captionChannel != null && _captionSubscription == null) {
          // 리스너 설정 전에 시작 신호를 먼저 보내서 백엔드가 즉시 오디오 스트리밍 시작
          try {
            // 비디오는 아직 재생하지 않으므로 시작 시간은 0
            // 백엔드가 즉시 오디오 스트리밍을 시작하도록 함
            _captionChannel!.sink.add(convert.jsonEncode({
              'video_name': _videoName,
              'action': 'start',
              'video_start_time': 0.0, // 자막을 먼저 받기 위해 0으로 시작
              'audio_start_time': 0.0, // 오디오도 처음부터 시작
            }));
            setState(() {
              _isVideoAnalyzed = true; // 분석 시작됨
            });
          } catch (e) {
            // 에러 무시
          }

          // 리스너 설정 (시작 신호 전송 후, 리스너가 없는 경우에만)
          if (_captionSubscription == null) {
            _setupWebSocketListener();
          }

          retryDelay = 2; // 성공 시 재시도 딜레이 초기화
          _isConnecting = false;
          return; // 성공 시 함수 종료
        } else if (_captionSubscription != null) {
          _isConnecting = false;
          return;
        }
      } catch (e) {
        _captionChannel = null; // 실패 시 null로 설정
        _captionSubscription = null;
      }

      _isConnecting = false;
      await Future.delayed(Duration(seconds: retryDelay));

      // 지수 백오프 (최대 10초)
      retryDelay = (retryDelay * 1.5).round().clamp(2, maxDelay);

      // 재시도 (성공할 때까지)
      connect();
    }

    connect();
  }

  // WebSocket 리스너 설정
  void _setupWebSocketListener() {
    if (_captionChannel == null) {
      return;
    }

    // 기존 리스너가 있으면 스킵 (중복 방지)
    if (_captionSubscription != null) {
      return;
    }

    // 새 리스너 설정
    try {
      _captionSubscription = _captionChannel!.stream.listen(
        (msg) {
          try {
            final data = convert.jsonDecode(msg) as Map<String, dynamic>;

            // 에러 메시지 확인
            if (data.containsKey('error')) {
              return;
            }

            // 원본 데이터를 그대로 저장 (디자인은 표시 시에만 적용)
            String text = data['text'] as String? ?? '';
            if (text.isEmpty) return; // 빈 자막은 무시

            final hex = data['color'] as String? ?? '#FFFFFF';
            final emotion = data['emotion'] as String? ?? '';
            final emotionIcon = data['emotion_icon'] as String? ?? ''; // 이모지 추가
            final intensity = (data['intensity'] as num?)?.toDouble() ?? 0.5;
            final bgm = data['bgm'] as String? ?? '';
            final sfx = data['sfx'] as String? ?? '';
            final start = (data['start'] as num?)?.toDouble() ?? 0.0;
            final end = (data['end'] as num?)?.toDouble() ?? start + 1.0;

            // DX_Project_2 방식: 자막을 받을 때 fontSize 계산 (fontLevel 사용)
            // 가중치 시스템: 단계가 높을수록 intensity 변화에 더 민감하게 반응
            // 기준치(31px)에서 속삭임(intensity 낮음) → 작아짐, 큰 목소리(intensity 높음) → 커짐
            double fontSize = 40.0; // 기본값 (5포인트 감소)
            if (_toggles['말의 강도'] == true) {
              // 기준 폰트 크기 (모든 단계 동일, intensity = 0.5일 때)
              const double baseFont = 48.0; // 5포인트 감소
              // 기본 변화량 (intensity = 0.0 또는 1.0일 때의 최대 변화)
              const double baseChange = 18.0; // 5포인트 감소

              // 단계별 가중치 (단계가 높을수록 더 많이 변함)
              double weight;
              switch (_fontLevel) {
                case 1:
                  weight = 0.3; // 1단계: 작은 변화
                  break;
                case 2:
                  weight = 0.6; // 2단계: 기본 변화
                  break;
                case 3:
                  weight = 1.0; // 3단계: 큰 변화
                  break;
                default:
                  weight = 0.6;
              }

              // 기준치(0.5)를 중심으로 작아지고 커지도록 계산
              // intensity = 0.0 → baseFont - baseChange * weight (작아짐)
              // intensity = 0.5 → baseFont (기준치)
              // intensity = 1.0 → baseFont + baseChange * weight (커짐)
              fontSize =
                  baseFont + (baseChange * (intensity - 0.5) * weight * 2);

              // 최소/최대 제한 (안전장치) - 5포인트 감소
              fontSize = fontSize.clamp(28.0, 68.0);
            }

            // 자막을 큐에 추가 (타임스탬프 기준, fontSize 포함)
            // 같은 타임스탬프의 자막이 이미 있으면 업데이트 (감정 분석 결과 반영)
            setState(() {
              // 같은 start/end 시간을 가진 자막이 있는지 확인
              int existingIndex = -1;
              for (int i = 0; i < _captionQueue.length; i++) {
                final caption = _captionQueue[i];
                final captionStart = caption['start'] as double;
                final captionEnd = caption['end'] as double;
                // 타임스탬프가 거의 같으면 (0.1초 이내) 같은 자막으로 간주
                if ((captionStart - start).abs() < 0.1 &&
                    (captionEnd - end).abs() < 0.1) {
                  existingIndex = i;
                  break;
                }
              }

              if (existingIndex >= 0) {
                // 기존 자막 업데이트 (감정 분석 결과 반영)
                _captionQueue[existingIndex] = {
                  'start': start,
                  'end': end,
                  'text': text,
                  'color': hex,
                  'emotion': emotion,
                  'emotion_icon': emotionIcon, // 이모지 저장
                  'intensity': intensity,
                  'fontSize': fontSize, // fontSize 저장
                  'bgm': bgm,
                  'sfx': sfx,
                };
              } else {
                // 새로운 자막 추가
                _captionQueue.add({
                  'start': start,
                  'end': end,
                  'text': text,
                  'color': hex,
                  'emotion': emotion,
                  'emotion_icon': emotionIcon, // 이모지 저장
                  'intensity': intensity,
                  'fontSize': fontSize, // fontSize 저장
                  'bgm': bgm,
                  'sfx': sfx,
                });
              }

              // 현재 채널의 캐시도 업데이트 (실시간으로 반영)
              _channelCaptionCache[_currentChannel] = List.from(_captionQueue);

              // 큐 정렬 (start 시간 기준)
              _captionQueue.sort((a, b) =>
                  (a['start'] as double).compareTo(b['start'] as double));

              // 큐가 너무 커지지 않도록 오래된 자막 제거 (루프 고려)
              // 루프 재생이므로 자막을 제거하지 않고 유지 (전체 자막 큐 유지)
              // 대신 큐 크기가 너무 커지면 (예: 1000개 이상) 오래된 자막 제거
              if (_captionQueue.length > 1000) {
                // 가장 오래된 자막부터 제거 (하지만 루프를 위해 최소한의 자막은 유지)
                final keepCount = 500; // 최소 500개는 유지
                if (_captionQueue.length > keepCount) {
                  _captionQueue.removeRange(
                      0, _captionQueue.length - keepCount);
                }
              }

              // 현재 채널의 캐시 업데이트 (정렬 및 정리 후)
              _channelCaptionCache[_currentChannel] = List.from(_captionQueue);
            });

            // 자막이 충분히 쌓였는지 확인 (최소 3초 분량 또는 5개 이상)
            if (!_isVideoReadyToPlay &&
                _videoController != null &&
                _videoController!.value.isInitialized) {
              final queueDuration = _captionQueue.isNotEmpty
                  ? (_captionQueue.last['end'] as double) -
                      (_captionQueue.first['start'] as double)
                  : 0.0;

              if (queueDuration >= 3.0 || _captionQueue.length >= 5) {
                _startVideoPlayback();
              }
            }
          } catch (e) {
            // 에러 무시
          }
        },
        onError: (error) {
          // 채널 전환 중이 아니면 재연결 시도
          if (!_isSwitchingChannel) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!_isSwitchingChannel && mounted) {
                _connectWebSocket();
              }
            });
          }
        },
        onDone: () {
          // 채널 전환 중이 아니면 재연결 시도
          if (!_isSwitchingChannel) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!_isSwitchingChannel && mounted) {
                _connectWebSocket();
              }
            });
          }
        },
      );
    } catch (e) {
      // 에러 무시
      _captionSubscription = null;
    }
  }

  // 비디오 분석 요청
  Future<void> _analyzeVideo() async {
    try {
      // 비디오 파일 경로 (서버에서 접근 가능한 경로)
      // Flutter assets는 서버에서 접근 불가하므로, 서버에 비디오 파일이 있어야 함
      // 프로젝트 루트 기준: 'front/assets/{videoName}'
      final videoPath = 'front/assets/$_videoName';

      // 비디오 분석 요청 - 헬퍼 함수로 POST 요청
      final responseData = await ApiHelpers.postVideoAnalyzer(
        '/analyze-video',
        {
          'video_path': videoPath,
          'video_name': _videoName,
        },
        timeout: const Duration(seconds: 60),
      ) as Map<String, dynamic>;

      if (responseData['status'] == 'success') {
        setState(() {
          _isVideoAnalyzed = true;
        });
      }
    } catch (e) {
      // 분석 실패해도 계속 진행 (WebSocket으로 실시간 요청 가능)
      setState(() {
        _isVideoAnalyzed = false;
      });
    }
  }

  // 비디오 재생 시간 추적
  void _startVideoTimeTracking() {
    // 비디오 컨트롤러의 리스너로 재생 시간 추적
    _videoController?.addListener(_onVideoPositionChanged);
  }

  void _onVideoPositionChanged() {
    if (!mounted || _videoController == null) return;

    // 분석이 시작되지 않았으면 자막 요청 안 함
    if (!_isVideoAnalyzed) return;

    // 비디오 길이 업데이트 (초기화 후 변경될 수 있음)
    if (_videoController!.value.isInitialized && _videoDuration == 0.0) {
      _videoDuration = _videoController!.value.duration.inSeconds.toDouble();
    }

    // 현재 비디오 재생 시간에 맞는 자막 찾기
    var currentTime = _videoController!.value.position.inSeconds.toDouble();
    final originalTime = currentTime;

    // 루프 처리: 비디오 길이로 모듈로 연산하여 루프 시에도 자막이 이어서 표시
    if (_videoDuration > 0) {
      currentTime = currentTime % _videoDuration;
    }

    _updateCaptionForCurrentTime(currentTime);
  }

  // 비디오 재생 시작 (자막이 충분히 쌓인 후)
  void _startVideoPlayback() {
    if (_isVideoReadyToPlay ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isVideoReadyToPlay = true;
    });

    _videoController?.play();
  }

  // 현재 재생 시간에 맞는 자막 업데이트
  void _updateCaptionForCurrentTime(double currentTime) {
    // 큐가 비어있으면 자막 없음
    if (_captionQueue.isEmpty) {
      setState(() {
        if (_currentCaption.isNotEmpty) {
          _previousCaption = _currentCaption;
          _previousCaptionColor = _captionColor; // 이전 자막 색상 저장
          _previousCaptionFontSize = _captionFontSize; // 이전 자막 폰트 크기 저장
        }
        _currentCaption = "";
      });
      return;
    }

    // 큐 정렬 (start 시간 기준) - 매번 정렬하여 최신 상태 유지
    _captionQueue
        .sort((a, b) => (a['start'] as double).compareTo(b['start'] as double));

    // 현재 시간에 해당하는 자막 찾기 (시간 범위 내)
    Map<String, dynamic>? currentCaptionData;
    for (var caption in _captionQueue) {
      final start = caption['start'] as double;
      final end = caption['end'] as double;
      // 현재 시간이 자막 시간 범위 내에 있으면 선택
      if (currentTime >= start && currentTime <= end) {
        currentCaptionData = caption;
        break;
      }
    }

    // 현재 시간에 해당하는 자막이 없으면, 가장 가까운 자막 찾기
    if (currentCaptionData == null && _captionQueue.isNotEmpty) {
      // 현재 시간 이후의 가장 가까운 자막
      for (var caption in _captionQueue) {
        final start = caption['start'] as double;
        if (start > currentTime) {
          // 현재 시간과 0.5초 이내면 선택 (자막이 조금 빨리 나올 수 있음)
          if (start - currentTime < 0.5) {
            currentCaptionData = caption;
          }
          break;
        }
      }

      // 여전히 없으면 현재 시간 이전의 가장 최근 자막
      if (currentCaptionData == null) {
        for (int i = _captionQueue.length - 1; i >= 0; i--) {
          final caption = _captionQueue[i];
          final end = caption['end'] as double;
          if (end <= currentTime) {
            // 현재 시간과 가까운 자막만 표시 (1초 이내)
            if (currentTime - end < 1.0) {
              currentCaptionData = caption;
            }
            break;
          }
        }
      }

      // 여전히 없으면 루프를 고려하여 처음 자막 찾기 (비디오 끝에서 처음으로 돌아가는 경우)
      if (currentCaptionData == null &&
          _videoDuration > 0 &&
          currentTime < 1.0) {
        // 비디오 시작 부분 (0초 근처)이면 첫 번째 자막 찾기
        for (var caption in _captionQueue) {
          final start = caption['start'] as double;
          if (start < 1.0) {
            currentCaptionData = caption;
            break;
          }
        }
      }
    }

    // 자막 업데이트 (변경된 경우에만)
    // DX_Project_2 방식: 큐에 저장된 fontSize 사용 (이미 계산되어 있음)
    if (currentCaptionData != null) {
      String originalText = currentCaptionData['text'] as String; // 원본 텍스트
      final hex = currentCaptionData['color'] as String? ?? '#FFFFFF';
      final intensity = currentCaptionData['intensity'] as double;
      final fontSize = (currentCaptionData['fontSize'] as num?)?.toDouble() ??
          31.0; // 큐에서 fontSize 가져오기 (5포인트 감소)
      final bgm = currentCaptionData['bgm'] as String? ?? '';
      final sfx = currentCaptionData['sfx'] as String? ?? '';
      final emotionIcon =
          currentCaptionData['emotion_icon'] as String? ?? ''; // 이모지 가져오기

      // 원본 텍스트가 실제로 변경되었는지 확인 (이모지/태그 제거 전 원본 비교)
      final isNewCaption = _currentCaptionOriginal != originalText;

      // 디자인 레이어: 토글에 따라 표시 형식 결정
      // 1. 화자 설정이 켜져 있으면 [인물] 태그 유지, 꺼져 있으면 제거
      // 2. 감정 색상이 켜져 있으면 이모지 추가 (화자 설정과 무관)
      String displayText = originalText;

      // 화자 설정 처리: [인물] 태그 표시 여부만 결정
      if (_toggles['화자 설정'] == false) {
        // 화자 설정 OFF: [인물] 태그 제거
        displayText = displayText.replaceAll(RegExp(r'\[인물\d+\]\s*'), '');
      }
      // 화자 설정 ON: [인물] 태그 유지 (변경 없음)

      // 감정 색상 처리: 화자 설정과 완전히 독립적으로 이모지 추가
      if (_toggles['감정 색상'] == true && emotionIcon.isNotEmpty) {
        // [인물] 태그가 있으면 그 뒤에, 없으면 텍스트 앞에 이모지 추가
        if (displayText.contains(RegExp(r'\[인물\d+\]'))) {
          // [인물] 태그 뒤에 이모지 추가
          displayText = displayText.replaceAllMapped(
            RegExp(r'(\[인물\d+\])'),
            (match) => '${match.group(1)} $emotionIcon',
          );
        } else {
          // [인물] 태그가 없으면 텍스트 앞에 이모지 추가
          displayText = '$emotionIcon $displayText';
        }
      }
      // 감정 색상 OFF: 이모지 추가 안 함

      // 색상 파싱 및 설정
      Color newColor;
      if (_toggles['감정 색상'] == true) {
        newColor = _parseHexColor(hex);
      } else {
        newColor = Colors.white;
      }

      // 자막이 실제로 변경되었는지 확인 (원본 텍스트 기준)
      final captionChanged = isNewCaption ||
          _captionColor != newColor ||
          (_captionFontSize - fontSize).abs() > 0.1 ||
          _currentBgm != (bgm.isNotEmpty ? bgm : '') ||
          _currentSfx != (sfx.isNotEmpty ? sfx : '');

      if (captionChanged) {
        setState(() {
          // 새로운 자막이면 이전 자막 저장 (원본 텍스트 기준)
          if (isNewCaption && _currentCaptionOriginal.isNotEmpty) {
            _previousCaption = _currentCaption;
            _previousCaptionOriginal = _currentCaptionOriginal;
            _previousCaptionColor = _captionColor; // 이전 자막 색상 저장
            _previousCaptionFontSize = _captionFontSize; // 이전 자막 폰트 크기 저장
          }
          _currentCaption = displayText;
          _currentCaptionOriginal = originalText; // 원본 텍스트 저장
          _captionColor = newColor;
          _captionFontSize = fontSize; // 큐에서 가져온 fontSize 사용
          _intensity = intensity;
          _currentBgm = bgm.isNotEmpty ? bgm : '';
          _currentSfx = sfx.isNotEmpty ? sfx : '';
        });
      }
    } else {
      // 현재 시간에 해당하는 자막이 없으면 빈 자막 표시
      // 자막이 실제로 변경되었을 때만 업데이트
      if (_currentCaption.isNotEmpty) {
        setState(() {
          _previousCaption = _currentCaption;
          _previousCaptionColor = _captionColor; // 이전 자막 색상 저장
          _previousCaptionFontSize = _captionFontSize; // 이전 자막 폰트 크기 저장
          _currentCaption = "";
        });
      }
    }
  }

  // 비디오 시간을 서버로 전송 (연결 상태 확인 및 재연결 포함)
  void _sendVideoTimeToServer(double currentTime) {
    // WebSocket 연결 상태 확인
    if (_captionChannel == null) {
      // 연결이 없으면 재연결 시도
      if (!_isConnecting) {
        _connectWebSocket();
      }
      return;
    }

    try {
      // WebSocket이 열려있는지 확인하고 전송
      final message = convert.jsonEncode({
        'video_name': _videoName,
        'current_time': currentTime,
      });

      _captionChannel!.sink.add(message);
      _errorLogCount = 0; // 성공 시 에러 카운터 리셋
    } catch (e) {
      // 전송 실패 시 (연결이 닫혔을 수 있음)
      _errorLogCount++;

      // 연결 재시도
      _captionChannel = null;
      if (!_isConnecting) {
        _connectWebSocket();
      }
    }
  }

  Color _parseHexColor(String hex) {
    var c = hex.replaceAll('#', '');
    if (c.length == 6) c = 'FF$c';
    return Color(int.parse(c, radix: 16));
  }

  // 현재 폰트 크기 계산 (토글 상태 반영)
  // 가중치 시스템: 단계가 높을수록 intensity 변화에 더 민감하게 반응
  // 기준치(31px)에서 속삭임(intensity 낮음) → 작아짐, 큰 목소리(intensity 높음) → 커짐
  double _getCurrentFontSize() {
    if (_toggles['말의 강도'] == true && _intensity > 0) {
      // 기준 폰트 크기 (모든 단계 동일, intensity = 0.5일 때)
      const double baseFont = 48.0; // 5포인트 감소
      // 기본 변화량 (intensity = 0.0 또는 1.0일 때의 최대 변화)
      const double baseChange = 18.0; // 5포인트 감소

      // 단계별 가중치 (단계가 높을수록 더 많이 변함)
      double weight;
      switch (_fontLevel) {
        case 1:
          weight = 0.3; // 1단계: 작은 변화
          break;
        case 2:
          weight = 0.6; // 2단계: 기본 변화
          break;
        case 3:
          weight = 1.0; // 3단계: 큰 변화
          break;
        default:
          weight = 0.6;
      }

      // 기준치(0.5)를 중심으로 작아지고 커지도록 계산
      // intensity = 0.0 → baseFont - baseChange * weight (작아짐)
      // intensity = 0.5 → baseFont (기준치)
      // intensity = 1.0 → baseFont + baseChange * weight (커짐)
      double fontSize =
          baseFont + (baseChange * (_intensity - 0.5) * weight * 2);

      // 최소/최대 제한 (안전장치) - 5포인트 감소
      return fontSize.clamp(28.0, 68.0);
    }
    return 31.0; // 기본값 (5포인트 감소)
  }

  /// 자막 모드 알림을 표시하는 함수
  void _showSubtitleModeNotification(bool isOn) {
    // 기존 알림이 있으면 제거
    _hideSubtitleModeNotification();

    // OverlayEntry 생성
    _subtitleNotificationOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(child: SubtitleModeNotification(isOn: isOn)),
        ),
      ),
    );

    // Overlay에 추가
    try {
      final overlay = Overlay.of(context);
      overlay.insert(_subtitleNotificationOverlay!);
    } catch (e) {
      // 에러 무시
    }

    // 1초 후 자동으로 제거
    Future.delayed(const Duration(seconds: 1), () {
      _hideSubtitleModeNotification();
    });
  }

  /// 자막 모드 알림을 숨기는 함수
  void _hideSubtitleModeNotification() {
    _subtitleNotificationOverlay?.remove();
    _subtitleNotificationOverlay = null;
  }

  /// 채널 변경 알림을 표시하는 함수
  /// TV 화면 오른쪽 상단에 표시됨
  void _showChannelNotification(int channelNumber) {
    // 기존 알림이 있으면 제거
    _hideChannelNotification();

    // OverlayEntry 생성
    // 위치: 오른쪽 상단
    // 필요시 주석 해제하여 위치 조정 가능:
    // top: 60, right: 60 (기본값)
    // 또는 MediaQuery를 사용하여 동적 위치 설정 가능
    _channelNotificationOverlay = OverlayEntry(
      builder: (context) {
        // 필요시 MediaQuery로 화면 크기에 맞춰 위치 조정 가능
        // final screenWidth = MediaQuery.of(context).size.width;
        // final screenHeight = MediaQuery.of(context).size.height;
        return Positioned(
          top: 60, // 상단 여백 (필요시 수정)
          right: 60, // 오른쪽 여백 (필요시 수정)
          // 또는 left를 사용하여 왼쪽 기준으로 위치 설정 가능:
          // left: screenWidth - 341, // 281(width) + 60(right)
          child: IgnorePointer(
            child: Container(
              child: ChannelNotification(channelNumber: channelNumber),
            ),
          ),
        );
      },
    );

    // Overlay에 추가
    try {
      final overlay = Overlay.of(context);
      overlay.insert(_channelNotificationOverlay!);
    } catch (e) {
      // 에러 무시
    }

    // 1초 후 자동으로 제거
    Future.delayed(const Duration(seconds: 1), () {
      _hideChannelNotification();
    });
  }

  /// 채널 변경 알림을 숨기는 함수
  void _hideChannelNotification() {
    _channelNotificationOverlay?.remove();
    _channelNotificationOverlay = null;
  }

  /// 볼륨 UI를 표시하는 함수 (TV 스타일)
  /// 화면 오른쪽 가운데에 볼륨 바와 음소거 아이콘 표시
  void _showVolumeNotification(int volume, bool isMuted) {
    // 초기 로드 후 1초가 지나지 않았으면 UI 표시하지 않음
    if (_pageLoadTime != null) {
      final elapsed = DateTime.now().difference(_pageLoadTime!);
      if (elapsed.inMilliseconds < 1000) {
        return;
      }
    }

    // 기존 타이머 취소
    _volumeHideTimer?.cancel();

    // 기존 Overlay 제거
    _hideVolumeNotification();

    // OverlayEntry 생성
    _volumeNotificationOverlay = OverlayEntry(
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;

        // 화면 너비에서 양옆 여백(안전을 위해 약 80~100)을 뺀 값을 최대 너비로 계산
        final safeMaxWidth = (screenWidth - 80).clamp(0.0, 400.0);

        return SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: (screenHeight - 200) / 2,
                right: 60,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: safeMaxWidth,
                          minWidth: 150,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                isMuted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor:
                                            isMuted ? 0.0 : (volume / 100.0),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: isMuted
                                                  ? [
                                                      Colors.grey.shade600,
                                                      Colors.grey.shade400
                                                    ]
                                                  : [
                                                      Colors.blue.shade400,
                                                      Colors.blue.shade600,
                                                    ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: Center(
                                  child: Text(
                                    isMuted ? '음소거' : '$volume%',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Overlay에 추가
    try {
      final overlay = Overlay.of(context);
      overlay.insert(_volumeNotificationOverlay!);
    } catch (e) {
      // 에러 무시
    }

    // 2초 후 자동으로 제거
    _volumeHideTimer = Timer(const Duration(seconds: 2), () {
      _hideVolumeNotification();
    });
  }

  /// 볼륨 UI를 숨기는 함수
  void _hideVolumeNotification() {
    _volumeHideTimer?.cancel();
    _volumeNotificationOverlay?.remove();
    _volumeNotificationOverlay = null;
  }

  // [인물] 부분을 흰색으로 고정하는 자막 위젯 빌드
  // 자막 오버레이 빌더 (상단/중앙 위치용)
  Widget _buildCaptionOverlay() {
    // 화면 크기에 따라 동적으로 크기 조정
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 텍스트 길이에 따라 동적으로 너비 조정
    final captionLength = _currentCaption.length;
    final previousCaptionLength = _previousCaption.length;
    final maxTextLength = captionLength > previousCaptionLength
        ? captionLength
        : previousCaptionLength;

    // 텍스트 길이에 따라 최대 너비 계산 (최소 60%, 최대 90%)
    final dynamicWidth = (maxTextLength > 50)
        ? screenWidth * 0.9
        : (maxTextLength > 30)
            ? screenWidth * 0.8
            : screenWidth * 0.7;

    return Container(
      constraints: BoxConstraints(
        maxWidth: dynamicWidth,
        minWidth: screenWidth * 0.6,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04, // 화면 너비의 4%
        vertical: screenHeight * 0.02, // 화면 높이의 2%
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 배경음/효과음 표시 (자막 위) - Wrap으로 자동 줄바꿈
          if ((_currentBgm.isNotEmpty && _toggles['배경음 표시'] == true) ||
              (_currentSfx.isNotEmpty && _toggles['효과음 표시'] == true))
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              clipBehavior: Clip.none,
              children: [
                if (_currentBgm.isNotEmpty && _toggles['배경음 표시'] == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '[배경음] $_currentBgm',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: _getCurrentFontSize() * 0.8, // 자막 크기의 70%
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64B5F6), // 파란색
                      ),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_currentSfx.isNotEmpty && _toggles['효과음 표시'] == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '[효과음] $_currentSfx',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: _getCurrentFontSize() * 0.8, // 자막 크기의 70%
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFFFB74D), // 주황색
                      ),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          // 배경음/효과음과 자막 사이 간격
          if ((_currentBgm.isNotEmpty && _toggles['배경음 표시'] == true) ||
              (_currentSfx.isNotEmpty && _toggles['효과음 표시'] == true))
            SizedBox(height: screenHeight * 0.015), // 화면 높이의 1.5%
          // 이전 자막 (위 줄) - 스타일링 적용
          if (_previousCaption.isNotEmpty)
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(bottom: screenHeight * 0.01),
                child: _buildCaptionWithSpeakerColor(
                  _previousCaption,
                  _previousCaptionFontSize,
                  _toggles['감정 색상'] == true
                      ? _previousCaptionColor
                      : Colors.white,
                ),
              ),
            ),
          // 현재 자막 (아래 줄) - Flexible로 동적 크기 조정
          Flexible(
            flex: 2,
            child: _currentCaption.isEmpty
                ? Text(
                    '[자막 대기 중...]',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: _getCurrentFontSize(),
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                : _buildCaptionWithSpeakerColor(
                    _currentCaption,
                    _getCurrentFontSize(),
                    _toggles['감정 색상'] == true ? _captionColor : Colors.white,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionWithSpeakerColor(
      String caption, double fontSize, Color defaultColor) {
    // 정규식으로 [인물1], [인물2] 등의 패턴 찾기
    final RegExp speakerPattern = RegExp(r'\[인물\d+\]');
    final List<TextSpan> spans = [];
    int lastIndex = 0;

    // 모든 매칭 찾기
    final matches = speakerPattern.allMatches(caption);

    for (final match in matches) {
      // 매칭 전의 텍스트 (기본 색상)
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: caption.substring(lastIndex, match.start),
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
        text: caption.substring(match.start, match.end),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white, // FFFFFF 고정
        ),
      ));

      lastIndex = match.end;
    }

    // 마지막 매칭 이후의 텍스트 (기본 색상)
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

    // 매칭이 없으면 전체를 기본 색상으로
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: caption,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: defaultColor,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      maxLines: 3, // 동적으로 줄 수 증가
      overflow: TextOverflow.ellipsis,
      softWrap: true, // 자동 줄바꿈 활성화
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RemotePointerOverlay(
        child: Stack(
          children: [
            // 비디오 영역 + 자막 (세로 배치)
            Column(
              children: [
                // 비디오 영역 (Expanded로 남은 공간 차지)
                Expanded(
                  child: Stack(
                    children: [
                      // 배경 비디오
                      SizedBox.expand(
                        child: _videoController != null &&
                                _videoController!.value.isInitialized
                            ? VideoPlayer(_videoController!)
                            : Container(
                                color: Colors.black,
                                child: Center(
                                  child: LoadingDonutRing(
                                    size: 80,
                                    stroke: 6,
                                  ),
                                ),
                              ), // 비디오 초기화 전 로딩 화면
                      ),

                      // 비디오가 초기화되었지만 아직 재생되지 않았을 때 로딩 화면 (투명도 60%)
                      if (_videoController != null &&
                          _videoController!.value.isInitialized &&
                          !(_videoController!.value.isPlaying))
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.6), // 60% 투명도
                            child: Center(
                              child: LoadingDonutRing(
                                size: 80,
                                stroke: 6,
                              ),
                            ),
                          ),
                        ),

                      // 자막 오버레이 (상단/하단 위치일 때만 비디오 영역 내부에 표시)
                      if (_isSubtitleModeOn &&
                          (_captionPosition == '상단' ||
                              _captionPosition == '하단'))
                        Align(
                          alignment: _captionPosition == '상단'
                              ? Alignment.topCenter
                              : Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: _captionPosition == '상단' ? 100 : 0,
                              bottom: _captionPosition == '하단' ? 100 : 0,
                            ),
                            child: _buildCaptionOverlay(),
                          ),
                        ),

                      // 퀵패널이 열려 있을 때 비디오 위에 검은색 40% 오버레이
                      if (_isPanelVisible)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.6), // 40% 투명도
                          ),
                        ),
                    ],
                  ),
                ),

                // 실시간 자막 표시 (분리 위치일 때만 비디오 아래에 별도 영역으로 표시)
                if (_isSubtitleModeOn && _captionPosition == '분리')
                  Container(
                    width: double.infinity,
                    height: 200, // 고정 높이
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                    color: Colors.black,
                    child: Center(
                      child: Container(
                        // 고정 너비와 높이
                        width: MediaQuery.of(context).size.width *
                            0.8, // 화면 너비의 80%
                        height: 160, // 고정 높이
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 이전 자막 (위 줄) - 스타일링 적용
                            if (_previousCaption.isNotEmpty)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Center(
                                    child: _buildCaptionWithSpeakerColor(
                                      _previousCaption,
                                      _previousCaptionFontSize,
                                      _toggles['감정 색상'] == true
                                          ? _previousCaptionColor
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            // 현재 자막 (아래 줄)
                            Expanded(
                              child: Center(
                                child: _currentCaption.isEmpty
                                    ? Text(
                                        '[자막 대기 중...]',
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: _getCurrentFontSize(),
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : _buildCaptionWithSpeakerColor(
                                        _currentCaption,
                                        _getCurrentFontSize(),
                                        _toggles['감정 색상'] == true
                                            ? _captionColor
                                            : Colors.white,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 슬라이드 패널 (왼쪽/위/아래 30px 띄우기)
            // 리모컨으로만 열고 닫음
            Builder(
              builder: (context) {
                final leftValue = _isPanelVisible ? 30.0 : -1000.0;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  left: leftValue, // 패널이 닫혀있을 때는 완전히 화면 밖으로
                  top: 30,
                  bottom: 30,
                  child: _buildSidePanel(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 왼쪽 슬라이드 패널 퀵모드
  // ---------------------------------------------------------
  Widget _buildSidePanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelHeight = constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none, // 자식 위젯이 부모 영역 밖으로 나가도 잘리지 않도록
          children: [
            Container(
              width: 555,
              decoration: BoxDecoration(
                color: const Color(0xFF222222).withOpacity(0.92),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.zero, // 화면 모서리와 맞닿는 부분
                  topRight: Radius.circular(30),
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 28,
                  top: 40,
                  right: 28,
                  bottom: 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAddButton(),
                    const SizedBox(height: 40),
                    _buildModeButtons(),
                    const SizedBox(height: 40),
                    _buildPreviewSection(),
                    const SizedBox(height: 40),
                    const SizedBox(height: 32),
                    _buildToggleSwitches(),
                  ],
                ),
              ),
            ),
            // 닫기 버튼을 오른쪽 끝 중간에 배치 (패널 안쪽에 완전히 보이도록)
            Positioned(
              right: -24, // 패널 경계 밖으로 약간 나오도록
              top: (panelHeight - 48) / 2, // 중간 위치
              child: GestureDetector(
                onTap: () {
                  // Firebase에 패널 닫기 명령 전송
                  FirebaseFirestore.instance
                      .collection('tvs')
                      .doc('demo_tv_01')
                      .set({'quickModeOpen': false}, SetOptions(merge: true));
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------
  // 퀵모드 섹션 (이미지 + 텍스트 + 세부설정 버튼)
  // ---------------------------------------------------------
  Widget _buildAddButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 왼쪽: 이미지 + 텍스트
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 왼쪽 이미지
            Image.asset(
              'assets/quick_image.png',
              width: 48,
              height: 48,
              errorBuilder: (context, error, stackTrace) {
                return Container(width: 48, height: 48, color: Colors.grey);
              },
            ),
            const SizedBox(width: 16),
            // "퀵모드" 텍스트
            const Text(
              '퀵모드',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 32,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                height: 44.8 / 32,
              ),
            ),
          ],
        ),
        // 오른쪽: 세부설정 버튼
        _buildDetailSettingsButton(),
      ],
    );
  }

  // ---------------------------------------------------------
  // 모드 버튼 그룹 (없음 / 영화 / 다큐 / 예능)
  // ---------------------------------------------------------
  Widget _buildModeButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 왼쪽 화살표
        GestureDetector(
          onTap: () {
            if (_modeScrollController.hasClients) {
              // 한 버튼 너비만큼 왼쪽으로 스크롤
              final scrollAmount = _calculateButtonWidth();
              final newOffset = (_modeScrollController.offset - scrollAmount)
                  .clamp(0.0, _modeScrollController.position.maxScrollExtent)
                  .toDouble();
              _modeScrollController.animateTo(
                newOffset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.chevron_left, color: Colors.white70, size: 32),
            ),
          ),
        ),

        // 가로 스크롤 영역
        Container(
          width: 419,
          height: 67,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            // color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _modeScrollController,
              physics: const ClampingScrollPhysics(),
              child: _modesFromDb.isEmpty
                  ? const SizedBox(
                      width: 419,
                      height: 67,
                      child: Center(
                        child: Text(
                          '모드 로딩 중...',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        // DB에서 가져온 모드 목록을 기반으로 버튼 생성
                        ...List.generate(_modesFromDb.length, (index) {
                          final modeData = _modesFromDb[index];
                          final modeName =
                              modeData['mode_name'] as String? ?? '';
                          final modeId = modeData['id'] as int?;

                          // 모드 ID와 이름을 기반으로 mode 문자열 생성
                          String modeString;
                          bool isCustomMode;
                          String label;

                          if (modeName == '없음') {
                            modeString = 'none';
                            isCustomMode = false;
                            label = '없음';
                          } else if (modeName == '영화/드라마') {
                            modeString = 'movie';
                            isCustomMode = false;
                            label = '영화/드라마';
                          } else if (modeName == '다큐멘터리') {
                            modeString = 'documentary';
                            isCustomMode = false;
                            label = '다큐멘터리';
                          } else if (modeName == '예능') {
                            modeString = 'variety';
                            isCustomMode = false;
                            label = '예능';
                          } else {
                            // 커스텀 모드
                            modeString =
                                modeId != null ? 'custom_$modeId' : 'none';
                            isCustomMode = true;
                            label = modeName;
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 첫 번째 버튼(없음)과 두 번째 버튼 사이에 구분선 추가
                              if (index == 1) ...[
                                const SizedBox(width: 20),
                                Container(
                                    width: 1, height: 59, color: Colors.white),
                                const SizedBox(width: 20),
                              ] else if (index > 0)
                                const SizedBox(width: 20),
                              _buildModeButton(
                                label: label,
                                mode: modeString,
                                index: index,
                                isCustomMode: isCustomMode,
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
            ),
          ),
        ),

        // 오른쪽 화살표
        GestureDetector(
          onTap: () {
            if (_modeScrollController.hasClients) {
              // 한 버튼 너비만큼 오른쪽으로 스크롤
              final scrollAmount = _calculateButtonWidth();
              final newOffset = (_modeScrollController.offset + scrollAmount)
                  .clamp(0.0, _modeScrollController.position.maxScrollExtent)
                  .toDouble();
              _modeScrollController.animateTo(
                newOffset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.chevron_right, color: Colors.white70, size: 32),
            ),
          ),
        ),
      ],
    );
  }

  // 버튼의 평균 너비 계산 (스크롤 이동량 결정용) - DB 목록 기준
  double _calculateButtonWidth() {
    if (_modesFromDb.isEmpty) return 100.0; // 기본값

    double totalWidth = 0;
    for (final modeData in _modesFromDb) {
      final modeName = modeData['mode_name'] as String? ?? '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: modeName.isEmpty ? '없음' : modeName,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 28,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      totalWidth += textPainter.size.width + 48; // padding 24*2
    }
    // 평균 버튼 너비 + 간격
    return (totalWidth / _modesFromDb.length) + 20;
  }

  // 시각적 인덱스(퀵모드 버튼 순서) 계산: DB에서 가져온 모드 목록 기준
  int _getVisualIndexForMode(String modeId) {
    // DB에서 가져온 모드 목록에서 찾기
    for (int i = 0; i < _modesFromDb.length; i++) {
      final modeData = _modesFromDb[i];
      final modeName = modeData['mode_name'] as String? ?? '';
      final dbModeId = modeData['id'] as int?;

      // 모드 ID를 문자열로 변환하여 비교
      String expectedModeString;
      if (modeName == '없음') {
        expectedModeString = 'none';
      } else if (modeName == '영화/드라마') {
        expectedModeString = 'movie';
      } else if (modeName == '다큐멘터리') {
        expectedModeString = 'documentary';
      } else if (modeName == '예능') {
        expectedModeString = 'variety';
      } else {
        // 커스텀 모드
        expectedModeString = dbModeId != null ? 'custom_$dbModeId' : 'none';
      }

      if (expectedModeString == modeId) {
        return i;
      }
    }

    return -1;
  }

  // 시각적 인덱스에 해당하는 모드 ID 반환 (DB 목록 기준)
  String? _getModeForVisualIndex(int index) {
    if (index < 0 || index >= _modesFromDb.length) {
      return null;
    }

    final modeData = _modesFromDb[index];
    final modeName = modeData['mode_name'] as String? ?? '';
    final modeId = modeData['id'] as int?;

    if (modeName == '없음') {
      return 'none';
    } else if (modeName == '영화/드라마') {
      return 'movie';
    } else if (modeName == '다큐멘터리') {
      return 'documentary';
    } else if (modeName == '예능') {
      return 'variety';
    } else {
      // 커스텀 모드
      return modeId != null ? 'custom_$modeId' : null;
    }
  }

  // 시각적 인덱스에 해당하는 버튼 라벨 텍스트 반환 (DB 목록 기준)
  String _getLabelForVisualIndex(int index) {
    if (index < 0 || index >= _modesFromDb.length) {
      return '';
    }

    final modeData = _modesFromDb[index];
    final modeName = modeData['mode_name'] as String? ?? '';
    return modeName.isEmpty ? '없음' : modeName;
  }

  Widget _buildModeButton({
    required String label,
    required String mode,
    required int index,
    required bool isCustomMode,
  }) {
    final bool isSelected = _selectedMode == mode;
    final bool isFocused = _focusedMode == mode; // 리모컨으로 포커스된 모드
    final bool isHovered = _hoveredModes[mode] ?? false;

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
            // 모드 변경 시 비디오 재초기화하지 않음 (자막 큐 유지)
          });

          // 모드 선택 시 DB에서 토글 상태 불러오기 (await 필수!)
          await _loadModeSettings(mode);

          // 모드 선택 시 DB에 저장
          _saveSelectedModeToDb(mode);

          // 다음 프레임에서 버튼 위치 계산 및 스크롤 이동
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_modeScrollController.hasClients) {
              // 이전 버튼들의 누적 너비 계산 (간격 포함)
              double cumulativeWidth = 0;
              for (int i = 0; i < index; i++) {
                final String prevLabel = _getLabelForVisualIndex(i);
                final textPainter = TextPainter(
                  text: TextSpan(
                    text: prevLabel,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                textPainter.layout();
                final prevButtonWidth =
                    textPainter.size.width + 48; // padding 24*2
                cumulativeWidth +=
                    prevButtonWidth + (i > 0 ? 20 : 0); // 간격 20px
              }

              // 버튼을 맨 앞으로 보이도록 스크롤
              _modeScrollController.animateTo(
                cumulativeWidth.clamp(
                  0,
                  _modeScrollController.position.maxScrollExtent,
                ),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        },
        child: Container(
          height: 59,
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            // 커스텀 모드: 피그마 색상 #ffd54f (노란색), 호버 시 #ffb800 (주황색)
            // 기본 모드: 기존 색상
            color: isSelected
                ? Colors.transparent
                : (isCustomMode
                    ? (isHovered
                        ? const Color(0xFFFFB800) // 피그마 호버 색상
                        : const Color(0xFFFFD54F)) // 피그마 기본 색상
                    : const Color(0xFF4A4A4A)),
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: Colors.white, // 흰색 테두리 (선택된 모드)
                    width: 3,
                  )
                : isFocused
                    ? Border.all(
                        color: Colors.white
                            .withOpacity(0.6), // 반투명 흰색 테두리 (포커스된 모드)
                        width: 2,
                      )
                    : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 28,
                fontWeight: FontWeight.w500,
                // 커스텀 모드: 피그마 색상 #000000 (검정), 선택 시 흰색
                color: isSelected
                    ? Colors.white
                    : (isCustomMode ? Colors.black : Colors.white),
                height: 39.2 / 28,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 미리보기 섹션
  // ---------------------------------------------------------
  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Text(
            '미리보기',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 28,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 400,
            height: 225,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                color: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Center(
                  child: _currentCaption.isEmpty
                      ? const Text(
                          '[자막 대기 중...]',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : _buildCaptionWithSpeakerColor(
                          _currentCaption,
                          _getCurrentFontSize(),
                          _toggles['감정 색상'] == true
                              ? _captionColor
                              : Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 설정 / 세부설정
  // ---------------------------------------------------------
  Widget _buildSettingsSection() {
    final tvService = TvRemoteService();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 왼쪽: 아이콘 + 텍스트
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 설정 아이콘 (48x48 원형)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.asset('assets/settings_image.png'),
                ),
              ),
            ),
            const SizedBox(width: 13),
            // "설정" 텍스트
            const Text(
              '설정',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 32,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                height: 44.8 / 32,
              ),
            ),
          ],
        ),
        // 오른쪽: TV 조종 버튼 + 세부설정 버튼
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // TV 조종 버튼 (간단한 버튼)
            GestureDetector(
              onTap: () {
                // 간단한 TV 조종 팝업
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('TV 조종'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.power_settings_new),
                          label: const Text('전원'),
                          onPressed: () async {
                            final success = await tvService.togglePower();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(success ? '✅ 전원 명령 전송' : '❌ 전송 실패'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.volume_up),
                              label: const Text('볼륨+'),
                              onPressed: () async {
                                final success = await tvService.volumeUp();
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        success ? '✅ 볼륨+ 명령 전송' : '❌ 전송 실패'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.volume_down),
                              label: const Text('볼륨-'),
                              onPressed: () async {
                                final success = await tvService.volumeDown();
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        success ? '✅ 볼륨- 명령 전송' : '❌ 전송 실패'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'TV 조종',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildDetailSettingsButton(),
          ],
        ),
      ],
    );
  }

  // 세부설정 버튼 (텍스트 + 아이콘 중앙정렬, 호버 시 테두리)
  // 리모컨 앱의 '자막 모드 세부 설정' 버튼을 통해서만 설정 페이지로 이동
  Widget _buildDetailSettingsButton() {
    return GestureDetector(
      onTap: () {
        // Firebase에 설정 페이지 열기 이벤트 전송
        // 실제 네비게이션은 Firebase 이벤트 리스너에서 처리됨
        FirebaseFirestore.instance
            .collection('tvs')
            .doc('demo_tv_01')
            .set({'openSettingsPage': true}, SetOptions(merge: true));
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isDetailSettingsHovered = true),
        onExit: (_) => setState(() => _isDetailSettingsHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48, // 버튼 높이 고정
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(46),
            border: _isDetailSettingsHovered
                ? Border.all(color: Colors.white, width: 1)
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Text(
                  '추가하기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    height: 1.0, // 높이를 1.0으로 설정하여 정확한 중앙 정렬
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 토글 리스트
  // ---------------------------------------------------------
  Widget _buildToggleSwitches() {
    return Column(
      children: _toggles.keys.map((label) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _buildToggleItem(label),
        );
      }).toList(),
    );
  }

  Widget _buildToggleItem(String label) {
    final bool isDisabled = _selectedMode == 'none'; // 없음 모드일 때 비활성화

    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 28,
              fontWeight: FontWeight.w400,
              color: isDisabled
                  ? Colors.white.withOpacity(0.5)
                  : Colors.white, // 비활성화 시 투명도 적용
            ),
          ),
          Switch(
            value: _toggles[label]!,
            onChanged: isDisabled
                ? null
                : (v) {
                    // 없음 모드일 때 null로 설정하여 비활성화
                    setState(() {
                      _toggles[label] = v;
                      // 토글 변경 시 자막 스타일 즉시 반영 (임시 상태만 변경, DB 저장 안 함)
                    });
                    // 토글 변경 시 현재 자막 다시 업데이트 (스타일 반영)
                    if (_videoController != null && _isVideoAnalyzed) {
                      final currentTime =
                          _videoController!.value.position.inSeconds.toDouble();
                      _updateCaptionForCurrentTime(currentTime);
                    }
                  },
            activeThumbColor: const Color(0xFF3A7BFF),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF4A4A4A),
          ),
        ],
      ),
    );
  }
}
