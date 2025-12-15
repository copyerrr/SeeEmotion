"""
화자(speaker) 처리 유틸
Deepgram speaker → 우리 UI 인물번호 매핑
"""
from collections import Counter

# ---------------------------------------------------------
# 화자(speaker) 처리 유틸
# ---------------------------------------------------------
# Deepgram speaker → 우리 UI 인물번호 매핑 저장
#   - key: Deepgram speaker id (0,1,2,…)
#   - val: 우리 쪽 인물번호(1,2,3,…)  → 화면에 [인물1], [인물2] 이런 식으로 표시
SPEAKER_MAP = {}

NEXT_SPEAKER_LABEL = 1  # 인물1, 인물2, ... 이런 식으로 증가

# 화면에 마지막으로 사용한 인물 번호 (stabilize_speaker 에서 사용)
LAST_SPEAKER = None

def get_major_speaker(alt):
    """
    Deepgram alternative 객체에서
    해당 문장/구간에서 가장 많이 등장한 speaker id 를 리턴 (개선 버전).
    speaker 정보가 없으면 None.
    
    개선사항:
    - 단어가 2개 이상일 때만 화자 정보 사용 (1개 단어는 신뢰도 낮음)
    - 가장 많이 등장한 화자의 비율이 50% 이상일 때만 반환
    """
    if not getattr(alt, "words", None):
        return None
    
    words = alt.words
    if not words or len(words) < 2:  # 단어가 1개 이하면 화자 정보 신뢰도 낮음
        return None
    
    speakers = [
        getattr(w, "speaker", None)
        for w in words
        if getattr(w, "speaker", None) is not None
    ]
    
    if not speakers or len(speakers) < 2:  # 화자 정보가 있는 단어가 2개 미만이면 None
        return None
    
    counter = Counter(speakers)
    total = len(speakers)
    
    # 가장 많이 등장한 화자와 그 비율
    major_id, count = counter.most_common(1)[0]
    ratio = count / total
    
    # 가장 많은 화자가 50% 이상을 차지할 때만 반환 (신뢰도 향상)
    if ratio >= 0.5:
        return major_id
    
    return None

def map_speaker_id(raw_id):
    """
    Deepgram speaker id (0,1,2,…)를
    우리 쪽 인물번호(1,2,3,…)로 매핑.
    한 번 매핑된 값은 계속 유지된다.
    """
    global NEXT_SPEAKER_LABEL
    
    if raw_id is None:
        return None
    
    if raw_id not in SPEAKER_MAP:
        SPEAKER_MAP[raw_id] = NEXT_SPEAKER_LABEL
        NEXT_SPEAKER_LABEL += 1
    
    return SPEAKER_MAP[raw_id]

def stabilize_speaker(raw_id, text: str, min_len: int = 5):
    """
    화자 id 를 '안정화'해서 리턴하는 헬퍼 (개선 버전).
    
    - raw_id      : Deepgram이 준 speaker id (0,1,2,… 또는 None)
    - text        : 이번 segment의 자막 텍스트
    - min_len     : 이 길이 이하의 짧은 문장에서는 화자를 바꾸지 않음 (기본 5글자)
    
    규칙:
      1) text가 너무 짧으면 (기본 5글자 이하) → 이전 화자(LAST_SPEAKER) 유지
      2) raw_id 가 None 이면 → 이전 화자 유지
      3) 공백/문장부호만 있는 경우 → 이전 화자 유지
      4) 위 두 경우가 아니면 → map_speaker_id 로 매핑하고 그 값을 LAST_SPEAKER로 저장
    """
    global LAST_SPEAKER
    
    # 공백/문장부호만 있는 경우 이전 화자 유지
    if not text or not text.strip():
        return LAST_SPEAKER
    
    # 실제 텍스트 길이 계산 (공백 제외)
    text_clean = text.strip()
    
    # 너무 짧은 텍스트(추임새, 단발음 등)는 화자 전환 안 함 (5글자 이상에서만 전환)
    if len(text_clean) <= min_len:
        return LAST_SPEAKER
    
    # Deepgram id → 우리 인물 번호(1,2,3,…)로 매핑
    mapped = map_speaker_id(raw_id)
    
    # speaker 정보가 없으면 이전 화자 유지
    if mapped is None:
        return LAST_SPEAKER
    
    # 정상적인 경우: 화자 업데이트
    LAST_SPEAKER = mapped
    return LAST_SPEAKER

def reset_speaker_map():
    """필요할 때 speaker 매핑 & 상태 초기화."""
    global SPEAKER_MAP, NEXT_SPEAKER_LABEL, LAST_SPEAKER
    SPEAKER_MAP = {}
    NEXT_SPEAKER_LABEL = 1
    LAST_SPEAKER = None

