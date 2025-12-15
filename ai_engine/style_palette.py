# ai_engine/style_palette.py
# ---------------------------------------------------------
# 3개의 전역 팔레트 정의
#  - key: 팔레트 레벨 (1, 2, 3)
#  - value: 감정별 대표 색상 딕셔너리
# ---------------------------------------------------------
PALETTES = {
    1: {  # 팔레트 1단계 (가장 부드러운/연한 느낌)
        "joy":      "#FFF9C4",
        "sadness":  "#BBDEFB",
        "anger":    "#FFCDD2",
        "fear":     "#E1BEE7",
        "surprise": "#FAD9A4",
        "disgust":  "#C8E6C9",
        "neutral":  "#FFFFFF",
    },
    2: {  # 팔레트 2단계 (중간 강도)
        "joy":      "#FFEF47",
        "sadness":  "#64B5F6",
        "anger":    "#EF5350",
        "fear":     "#CC8FD6",
        "surprise": "#F7C778",
        "disgust":  "#81C784",
        "neutral":  "#FFFFFF",
    },
    3: {  # 팔레트 3단계 (가장 진한/강한 느낌)
        "joy":      "#F5DC00",
        "sadness":  "#1976D2",
        "anger":    "#C62828",
        "fear":     "#AA44BB",
        "surprise": "#F3A62A",
        "disgust":  "#2E7D32",
        "neutral":  "#FFFFFF",
    },
}


# ---------------------------------------------------------
# 감정(emotion) + 팔레트 레벨(level 1~3) → 색상 1개 반환
# ---------------------------------------------------------
def color_from_emotion(emotion: str, level: int) -> str:
    """
    emotion : 'joy', 'sadness' 같은 감정 코드
    level   : 1, 2, 3 단계 (사용자가 고른 팔레트 번호)
    반환값  : 해당 팔레트에서 감정에 대응되는 HEX 색상 코드
    """
    
    # level을 1~3 범위로 강제
    level = max(1, min(3, level))

    palette = PALETTES.get(level, PALETTES[1])

    # 정의되지 않은 감정이면 neutral 사용
    if emotion not in palette:
        emotion = "neutral"

    return palette[emotion]


# ---------------------------------------------------------
# 프론트에서 팔레트 전체가 필요할 때 쓰기 좋은 헬퍼
# ---------------------------------------------------------
def get_palette(level: int) -> dict:
    """
    지정한 팔레트 레벨에 해당하는 감정별 색상 dict 반환.
    (웹/앱에서 미리보기용으로 쓰기 좋음)
    """
    level = max(1, min(3, level))
    return PALETTES[level]
