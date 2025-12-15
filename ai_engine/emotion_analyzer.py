"""
감정분석 모델 로드 및 추론 클래스
"""
import torch
import numpy as np
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from typing import Dict, Optional
import os


class EmotionAnalyzer:
    """Electra 기반 감정분석 모델"""
    
    # 감정별 색상 매핑 (ANSI 색상 코드)
    EMOTION_COLORS = {
        "Anxiety": "\033[93m",      # 노란색
        "Joy": "\033[92m",           # 초록색
        "Sadness": "\033[94m",       # 파란색
        "Fear": "\033[95m",          # 자홍색
        "Anger": "\033[91m",         # 빨간색
        "Neutral": "\033[97m",       # 흰색
    }
    
    # 감정별 한글 이름
    EMOTION_NAMES_KO = {
        "Anxiety": "불안",
        "Joy": "기쁨",
        "Sadness": "슬픔",
        "Fear": "공포",
        "Anger": "분노",
        "Neutral": "중립",
    }
    
    RESET_COLOR = "\033[0m"  # 색상 리셋
    
    def __init__(self, model_path: str, device: Optional[str] = None):
        """
        Args:
            model_path: 모델이 있는 디렉토리 경로
            device: 'cuda' 또는 'cpu' (None이면 자동 선택)
        """
        self.model_path = model_path
        self.device = device if device else ("cuda" if torch.cuda.is_available() else "cpu")
        
        print(f"📦 감정분석 모델 로딩 중... ({self.device})")
        
        # 토크나이저 로드
        self.tokenizer = AutoTokenizer.from_pretrained(model_path)
        
        # 모델 로드
        self.model = AutoModelForSequenceClassification.from_pretrained(model_path)
        self.model.to(self.device)
        self.model.eval()
        
        # 레이블 매핑 (config.json에서 가져옴)
        self.id2label = {
            0: "Anxiety",
            1: "Joy",
            2: "Sadness",
            3: "Fear",
            4: "Anger",
            5: "Neutral"
        }
        
        print("✅ 감정분석 모델 로드 완료")
    
    def predict(self, text: str) -> Dict:
        """
        텍스트에 대한 감정 예측
        
        Args:
            text: 분석할 텍스트
            
        Returns:
            {
                'emotion': 감정 이름,
                'emotion_ko': 감정 한글 이름,
                'color': ANSI 색상 코드,
                'confidence': 확률
            }
        """
        if not text or not text.strip():
            return {
                'emotion': 'Neutral',
                'emotion_ko': '중립',
                'color': self.EMOTION_COLORS['Neutral'],
                'confidence': 1.0
            }
        
        # 토크나이징
        encoded = self.tokenizer(
            text,
            max_length=512,
            padding=True,
            truncation=True,
            return_tensors='pt'
        )
        
        input_ids = encoded['input_ids'].to(self.device)
        attention_mask = encoded['attention_mask'].to(self.device)
        
        # 예측
        with torch.no_grad():
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            logits = outputs.logits
            probs = torch.softmax(logits, dim=-1)
            prediction = torch.argmax(logits, dim=-1).item()
            confidence = probs[0][prediction].item()
        
        emotion = self.id2label.get(prediction, "Neutral")
        
        return {
            'emotion': emotion,
            'emotion_ko': self.EMOTION_NAMES_KO.get(emotion, "중립"),
            'color': self.EMOTION_COLORS.get(emotion, self.EMOTION_COLORS['Neutral']),
            'confidence': confidence
        }
    
    def format_text_with_emotion(self, text: str, emotion_result: Dict) -> str:
        """
        감정에 따른 색상이 적용된 텍스트 반환
        
        Args:
            text: 원본 텍스트
            emotion_result: predict() 메서드의 반환값
            
        Returns:
            색상이 적용된 텍스트
        """
        color = emotion_result['color']
        return f"{color}{text}{self.RESET_COLOR}"

