# ai_engine/emotion_wrapper.py
# ---------------------------------------------------------
# Emotion Wrapper
# ---------------------------------------------------------
# 이 모듈은 "감정 분석 모델"과 "스타일 팔레트 시스템"을 연결하는 
# 중간 통합 레이어 역할을 한다.
#
# 주요 역할:
#   1) 텍스트 입력을 받아 KLUE-BERT 기반 감정 분석을 수행
#   2) 분석된 감정(emotion) + 사용자 선택 팔레트(palette_level)를 사용하여
#      최종적으로 적용될 자막 색상(color_hex)을 결정
#   3) 프론트엔드/백엔드 통신에서
#      "emotion, confidence, color_hex" 형태의 단일 출력 구조를 제공
#
# 이 파일을 사용하면 상위 레이어(backend API, UI)는
# 감정 분석/팔레트 처리 로직을 몰라도 되고,
# analyze_emotion() 함수만 호출해서 결과를 받을 수 있다.
#
# 사용 예:
#   emotion, conf, color = analyze_emotion("정말 기쁘다!", palette_level=2)
#   → ("joy", 0.91, "#FFEB3B")
#
# ---------------------------------------------------------

from ai_engine.kluebert_emotion import kluebert_emotion
from ai_engine.style_palette import color_from_emotion


def analyze_emotion(text: str, palette_level: int = 2):
    """
    text -> (emotion, conf, color_hex)
    palette_level : 1, 2, 3 중 유저가 선택한 팔레트 번호
    """
    
    # 1) 감정 분석
    emotion, conf = kluebert_emotion(text)

    # 2) 감정 + 팔레트 레벨 → 색상
    color_hex = color_from_emotion(emotion, palette_level)

    return emotion, conf, color_hex
