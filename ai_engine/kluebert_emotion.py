import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

# ---------------------------------------------------------
# 1) KLUE-BERT 기반 한국어 감정 분석 모델을 불러옴
#    - HuggingFace 모델 허브에 업로드된 fine-tuned 모델
#    - 7가지 감정(fear, surprise, anger, sadness, neutral, joy, disgust) 분류
# ---------------------------------------------------------
MODEL_NAME = "dlckdfuf141/korean-emotion-kluebert-v2"

# 문장을 토큰 ID로 변환하는 tokenizer
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

# 감정 분류 모델 자체 (KLUE-BERT 기반)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)

# ---------------------------------------------------------
# 2) 감정 ID → 감정명 매핑 테이블
#    - BERT 모델은 0~6 숫자를 출력하므로 사람이 읽을 수 있게 매핑 필요
# ---------------------------------------------------------
ID2EMOTION = {
    0: "fear",      # 공포
    1: "surprise",  # 놀람
    2: "anger",     # 분노
    3: "sadness",   # 슬픔
    4: "neutral",   # 중립
    5: "joy",       # 행복
    6: "disgust",   # 혐오
}

EMOTION_ICON = {
    "fear": "😱",
    "surprise": "😲",
    "anger": "😡",
    "sadness": "😢",
    "neutral": "🙂",
    "joy": "😊",
    "disgust": "🤢",
}
 

# ---------------------------------------------------------
# 3) 메인 함수: 텍스트 → (감정, confidence) 반환
#    - 입력된 문장을 토큰화 → 모델 입력 → softmax 확률 계산
#    - 가장 높은 확률의 감정을 예측하여 반환
# ---------------------------------------------------------
def kluebert_emotion(text: str):
    """문장을 입력하면 (감정이름, confidence 확률) 형태로 반환"""

    # 빈 문자열(ex: "   ")이 들어오면 감정 분석할 수 없으므로 중립 반환
    if not text.strip():
        return "neutral", 0.0

    # 문장을 토큰화하여 BERT 모델 입력 형태로 변환 (PyTorch tensor)
    inputs = tokenizer(text, return_tensors="pt", truncation=True)

    # 모델 추론: gradient 계산을 하지 않음 (속도↑, 메모리 사용↓)
    with torch.no_grad():
        logits = model(**inputs).logits       # (1, 7) 형태의 raw scores
        probs = torch.softmax(logits, dim=1)  # softmax → 0~1 확률값으로 변환

        # 가장 확률이 높은 감정 ID 선택
        pred_id = torch.argmax(probs, dim=1).item()

        # 선택된 감정의 확신 정도(확률)
        confidence = float(probs[0][pred_id])

    # 숫자 ID → 감정명 변환
    emotion = ID2EMOTION.get(pred_id, "neutral")

    # 디버깅용 로그 출력
    print(f"[EMO_DEBUG] pred_id={pred_id}, emotion={emotion}, conf={confidence:.3f}")

    # 최종 결과 반환
    return emotion, confidence
