# ai_engine/config.py
# ---------------------------------------------------------
# Style Configuration Module
# ---------------------------------------------------------
# 이 파일은 감정 자막 시스템 전반에서 공통으로 참조되는
# "스타일링 관련 전역 설정값"을 관리한다.
#
# 주요 역할:
#   • pitch(높낮이 기반 말 강도) 기능 ON/OFF 및 단계 조절
#   • emotion(감정 기반 스타일링) 기능 ON/OFF
#   • 자막 폰트 크기 계산에 사용되는 강도(Intensity) 범위 정의
#
# 즉, ai_engine 내 다른 모듈들이 스타일링 로직을 적용할 때
# 공통 기준으로 이 config 값을 참조하는 구조이다.
#
# 예: pitch_level=2 라면 강도→폰트 크기 매핑은 (20 ~ 36) 범위를 사용
# ---------------------------------------------------------

STYLE_CONFIG = {
    "pitch_on": True,     # 음성 pitch 기반 말 강도 스타일 적용 여부
    "intensity_level": 2,     # 1~3 단계 (강도 범위 조절)
    "emotion_on": True,   # 감정 기반 색상/스타일 적용 ON/OFF
    "palette_level": 1,   # 1~3 단계 (팔레트 범위 조절)
    "show_speaker_prefix": False,   # 화자 접두사 표시 여부
}

# intensity 값(0~1)을 폰트 크기로 변환할 때 사용할 범위
# key: intensity_level, value: (min_font, max_font)
INTENSITY_FONT_RANGE = {
    1: (16, 28),   # pitch_level 1: 작은 변화 폭
    2: (20, 36),   # pitch_level 2: 중간 변화
    3: (24, 48),   # pitch_level 3: 큰 변화
}
