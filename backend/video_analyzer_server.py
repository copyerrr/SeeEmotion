"""
비디오 오디오 분석 → 자막 + 스타일링 → WebSocket 전송 (실시간)
"""
import os
import asyncio
import numpy as np
from pathlib import Path
from typing import Dict, List, Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
from dotenv import load_dotenv

from speaker_diarization import get_major_speaker, stabilize_speaker, reset_speaker_map

# PANNs BGM/SFX 분석 모듈 import
try:
    import sys
    ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
    if os.path.exists(ai_engine_path):
        sys.path.insert(0, os.path.dirname(ai_engine_path))
        from ai_engine.panns_bgm_analyzer import analyze_bgm_chunk
        import ai_engine.panns_bgm_analyzer as panns_module
        USE_PANNS_BGM = True
        print("[Video Analyzer] ✅ PANNs BGM/SFX 분석 모듈 로드 성공")
    else:
        USE_PANNS_BGM = False
        print("[Video Analyzer] ⚠️ ai_engine 경로를 찾을 수 없습니다. PANNs BGM/SFX 분석 비활성화")
except ImportError as e:
    USE_PANNS_BGM = False
    print(f"[Video Analyzer] ⚠️ PANNs BGM/SFX 분석 모듈 로드 실패: {e}. BGM/SFX 분석 비활성화")

# DX_Project_2 방식: ai_engine 감정 분석 사용
try:
    import sys
    import os
    # ai_engine 경로 추가
    ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
    if os.path.exists(ai_engine_path):
        sys.path.insert(0, os.path.dirname(ai_engine_path))
        from ai_engine.emotion_wrapper import analyze_emotion
        from ai_engine.kluebert_emotion import EMOTION_ICON
        print("[Video Analyzer] ✅ ai_engine 감정 분석 모듈 로드 성공")
        USE_AI_ENGINE_EMOTION = True
    else:
        print("[Video Analyzer] ⚠️ ai_engine 경로를 찾을 수 없습니다. 기본 감정 분석 사용")
        USE_AI_ENGINE_EMOTION = False
        EMOTION_ICON = {}
        # ai_engine 경로를 추가한 후 import
        ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
        sys.path.insert(0, os.path.dirname(ai_engine_path))
        from ai_engine.emotion_analyzer import EmotionAnalyzer
except ImportError as e:
    print(f"[Video Analyzer] ⚠️ ai_engine 모듈 로드 실패: {e}. 기본 감정 분석 사용")
    USE_AI_ENGINE_EMOTION = False
    EMOTION_ICON = {}
    # ai_engine 경로를 추가한 후 import
    ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
    sys.path.insert(0, os.path.dirname(ai_engine_path))
    from ai_engine.emotion_analyzer import EmotionAnalyzer
from deepgram import AsyncDeepgramClient
from deepgram.core.events import EventType

load_dotenv()
DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_models()
    yield

app = FastAPI(title="Video Analyzer Server", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# 전역 변수
connected_clients: set[WebSocket] = set()
video_streams: Dict[str, Dict] = {}  # {video_name: {websocket, connection, audio_data, ...}}
analyzing: set[str] = set()

emotion_analyzer = None
deepgram_client = None
# DX_Project_2 방식: 팔레트 레벨 (기본값 2)
palette_level = 2

def _ansi_to_hex(ansi_color: str) -> str:
    """ANSI 색상 코드를 HEX 색상으로 변환"""
    color_map = {
        "\033[93m": "#FFFF00",  # 노란색
        "\033[92m": "#00FF00",  # 초록색
        "\033[94m": "#0000FF",  # 파란색
        "\033[95m": "#FF00FF",  # 자홍색
        "\033[91m": "#FF0000",  # 빨간색
        "\033[97m": "#FFFFFF",  # 흰색
    }
    return color_map.get(ansi_color, "#FFFFFF")

def _correct_common_errors(text: str) -> str:
    """자주 잘못 인식되는 단어 교정: 지혁 → 지옥"""
    return text.replace("지혁", "지옥")

def _is_sentence_complete(text: str) -> bool:
    """문장이 완성되었는지 확인 (문장 부호로 끝나는지)"""
    if not text or len(text.strip()) < 3:  # 최소 3글자 이상
        return False
    
    # 문장 종료 부호로 끝나는지 확인
    sentence_endings = ['.', '!', '?', '…', '。', '！', '？']
    text_stripped = text.strip()
    
    # 마지막 문자가 문장 종료 부호인지 확인
    if text_stripped[-1] in sentence_endings:
        return True
    
    # 한글 문장의 경우 "~다", "~요", "~네" 등으로 끝나는 경우도 완성으로 간주
    korean_endings = ['다', '요', '네', '죠', '까', '래', '게', '야', '어', '아']
    if len(text_stripped) >= 5:  # 충분히 긴 문장인 경우
        if text_stripped[-1] in korean_endings:
            # 문장 부호가 없어도 특정 어미로 끝나면 완성으로 간주
            return True
    
    return False

class SentenceBuffer:
    """문장 버퍼링을 위한 클래스"""
    def __init__(self, max_wait_time: float = 2.0, min_length: int = 3):
        self.text = ""
        self.speaker_label = None
        self.start_time = None
        self.end_time = None
        self.last_update_time = None
        self.segments = []  # 각 세그먼트 정보 저장
        self.max_wait_time = max_wait_time  # 최대 대기 시간 (초)
        self.min_length = min_length  # 최소 문장 길이
        self.is_flushing = False  # 플러시 중인지 여부
    
    def add_segment(self, transcript: str, speaker_label: str, start: float, end: float):
        """새 세그먼트를 버퍼에 추가"""
        current_time = asyncio.get_event_loop().time()
        
        # 화자가 바뀌면 기존 버퍼 플러시 필요
        if self.speaker_label is not None and self.speaker_label != speaker_label:
            self.is_flushing = True
        
        # 버퍼가 비어있으면 시작 시간 설정
        if self.start_time is None:
            self.start_time = start
            self.speaker_label = speaker_label
        
        # 텍스트 누적
        if self.text:
            self.text += " " + transcript
        else:
            self.text = transcript
        
        # 시간 업데이트
        self.end_time = end
        self.last_update_time = current_time
        
        # 세그먼트 정보 저장
        self.segments.append({
            'transcript': transcript,
            'speaker_label': speaker_label,
            'start': start,
            'end': end
        })
    
    def should_flush(self) -> bool:
        """버퍼를 플러시해야 하는지 확인"""
        if not self.text:
            return False
        
        # 화자가 바뀌면 즉시 플러시
        if self.is_flushing:
            return True
        
        # 문장이 완성되었으면 플러시
        if _is_sentence_complete(self.text):
            return True
        
        # 최소 길이를 넘고 타임아웃되었으면 플러시
        if len(self.text.strip()) >= self.min_length and self.last_update_time:
            current_time = asyncio.get_event_loop().time()
            if current_time - self.last_update_time >= self.max_wait_time:
                return True
        
        return False
    
    def flush(self) -> Optional[Dict]:
        """버퍼를 플러시하고 문장 데이터 반환"""
        if not self.text or len(self.text.strip()) < self.min_length:
            self.reset()
            return None
        
        result = {
            'text': self.text.strip(),
            'speaker_label': self.speaker_label,
            'start': self.start_time,
            'end': self.end_time,
            'segments': self.segments.copy()
        }
        
        self.reset()
        return result
    
    def reset(self):
        """버퍼 초기화"""
        self.text = ""
        self.speaker_label = None
        self.start_time = None
        self.end_time = None
        self.last_update_time = None
        self.segments = []
        self.is_flushing = False

async def update_emotion_styling(
    transcript: str, 
    display_text: str, 
    intensity: float, 
    bgm_text: str, 
    sfx_text: str, 
    start: float, 
    end: float, 
    websocket: WebSocket
):
    """감정 분석 및 스타일링 업데이트 (DX_Project_2 방식: ai_engine 사용)"""
    global palette_level
    
    try:
        loop = asyncio.get_event_loop()
        
        if USE_AI_ENGINE_EMOTION:
            # DX_Project_2 방식: ai_engine.emotion_wrapper 사용
            emotion, conf, color_hex = await loop.run_in_executor(
                None,
                analyze_emotion,
                transcript,
                palette_level
            )
            # 감정 이름을 한글로 변환
            emotion_ko_map = {
                "joy": "기쁨",
                "sadness": "슬픔",
                "anger": "분노",
                "fear": "공포",
                "surprise": "놀람",
                "disgust": "혐오",
                "neutral": "중립"
            }
            emotion_val = emotion_ko_map.get(emotion, "중립")
            color_val = color_hex
        else:
            # 기본 방식: EmotionAnalyzer 사용
            global emotion_analyzer
            if not emotion_analyzer:
                return
            emotion_result = await loop.run_in_executor(
                None, 
                emotion_analyzer.predict, 
                transcript
            )
            emotion_val = emotion_result.get("emotion_ko", "중립")
            ansi_color = emotion_result.get("color", "\033[97m")
            color_val = _ansi_to_hex(ansi_color)
        
        # 결과를 WebSocket으로 전송 (업데이트)
        try:
            # 감정 이모지 가져오기 (USE_AI_ENGINE_EMOTION일 때만)
            emotion_icon = ""
            if USE_AI_ENGINE_EMOTION:
                # emotion_val이 한글이므로 영어 감정명으로 역변환 필요
                emotion_en_map = {
                    "기쁨": "joy",
                    "슬픔": "sadness",
                    "분노": "anger",
                    "공포": "fear",
                    "놀람": "surprise",
                    "혐오": "disgust",
                    "중립": "neutral"
                }
                emotion_en = emotion_en_map.get(emotion_val, "neutral")
                emotion_icon = EMOTION_ICON.get(emotion_en, "")
            
            update_response = {
                "text": display_text,
                "emotion": emotion_val,
                "emotion_icon": emotion_icon,  # 이모지 추가
                "color": color_val,
                "intensity": float(intensity),
                "pitch": 0.5,
                "bgm": bgm_text,
                "sfx": sfx_text,
                "start": float(start),
                "end": float(end),
            }
            await websocket.send_json(update_response)
            print(f"[Video Analyzer] 🎨 감정 분석 완료: {emotion_val} {emotion_icon} ({color_val})")
        except (RuntimeError, Exception) as send_error:
            # WebSocket이 닫혔거나 연결이 끊어진 경우 무시
            if "close" in str(send_error).lower() or "disconnect" in str(send_error).lower():
                return
            raise  # 다른 예외는 다시 발생시킴
    except Exception as e:
        # WebSocket 연결 오류는 무시 (연결이 끊어진 경우)
        if "close" in str(e).lower() or "disconnect" in str(e).lower():
            return
        print(f"[Video Analyzer] 감정 분석 오류: {e}")
        import traceback
        traceback.print_exc()

# 변환 로직 제거 - WAV 파일은 이미 16kHz mono 16-bit로 준비되어 있어야 함

def init_models():
    global emotion_analyzer, deepgram_client
    try:
        # DX_Project_2 방식: ai_engine을 사용하면 EmotionAnalyzer 초기화 불필요
        if not USE_AI_ENGINE_EMOTION:
            emotion_analyzer = EmotionAnalyzer(r"C:\Users\155\Downloads\My_Emotion_Model")
        if DEEPGRAM_API_KEY:
            deepgram_client = AsyncDeepgramClient(api_key=DEEPGRAM_API_KEY)
        print("[Video Analyzer] ✅ 모델 초기화 완료")
    except Exception as e:
        print(f"[Video Analyzer] ❌ 모델 초기화 실패: {e}")

class VideoAnalysisRequest(BaseModel):
    video_path: str
    video_name: str


async def start_realtime_analysis(audio_path: str, audio_name: str, websocket: WebSocket, audio_start_time: float = 0.0):
    """오디오 파일을 실시간으로 스트리밍하여 분석 (librosa 직접 읽기)"""
    global deepgram_client, emotion_analyzer
    
    if not deepgram_client:
        await websocket.send_json({"error": "Deepgram 클라이언트가 초기화되지 않았습니다."})
        return
    
    reset_speaker_map()
    
    connection_opened = asyncio.Event()
    stream_start_time = None
    audio_playback_start_time = audio_start_time  # 오디오 재생 시작 시간 (초)
    last_message_time = None  # 마지막 메시지 수신 시간 (외부 스코프에서 업데이트)
    
    # 중복 전송 방지: (start, end, transcript) 조합을 추적
    sent_captions = set()
    
    # 문장 버퍼링: 완전한 문장을 만들기 위한 버퍼
    sentence_buffer = SentenceBuffer(max_wait_time=2.0, min_length=5)
    buffer_flush_task = None  # 버퍼 플러시 태스크
    
    # 오디오 강도 추적 (시간대별 RMS 저장)
    audio_intensity_buffer = {}  # {timestamp: rms_value}
    
    # BGM/SFX 버퍼 (시간대별 BGM/SFX 정보 저장)
    bgm_sfx_buffer = {}  # {timestamp: {'bgm': bgm_text, 'sfx': sfx_text}}
    
    # 연결 상태 플래그 (연결이 끊어졌는지 추적)
    connection_closed = False
    
    # 비디오 파일명에 따라 PANNs 모드 설정
    if USE_PANNS_BGM:
        video_basename = os.path.basename(audio_name).lower()
        if '환승연애' in video_basename or '예능' in video_basename or 'enter_web' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'ENTERTAINMENT'
            print("[Video Analyzer] 🎬 PANNs 모드: ENTERTAINMENT (예능)")
        elif '친애하는' in video_basename or '드라마' in video_basename or '영화' in video_basename or 'drama' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'DRAMA'
            print("[Video Analyzer] 🎬 PANNs 모드: DRAMA (드라마/영화)")
        elif '펭귄' in video_basename or '다큐' in video_basename or 'dacu' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'DOCUMENTARY'
            print("[Video Analyzer] 🎬 PANNs 모드: DOCUMENTARY (다큐멘터리)")
        else:
            os.environ['CAPTION_CONTENT_MODE'] = 'DOCUMENTARY'  # 기본값
            print("[Video Analyzer] 🎬 PANNs 모드: DOCUMENTARY (기본값)")
    
    async def flush_buffer_if_ready():
        """버퍼가 준비되었으면 플러시하고 전송"""
        nonlocal sentence_buffer, sent_captions, audio_intensity_buffer, bgm_sfx_buffer, connection_closed
        
        # 연결이 끊어진 경우 즉시 반환
        if connection_closed:
            return
        
        # WebSocket 연결 상태 확인
        try:
            # WebSocket이 닫혔는지 확인
            if hasattr(websocket, 'client_state'):
                if websocket.client_state.name != "CONNECTED":
                    connection_closed = True
                    return
        except (AttributeError, RuntimeError, Exception):
            # 연결이 끊어진 경우
            connection_closed = True
            return
        
        if sentence_buffer.should_flush():
            buffer_data = sentence_buffer.flush()
            if buffer_data:
                transcript = buffer_data['text']
                speaker_label = buffer_data['speaker_label']
                start = buffer_data['start']
                end = buffer_data['end']
                
                # 중복 체크
                caption_key = (round(start, 2), round(end, 2), transcript)
                if caption_key in sent_captions:
                    return
                
                sent_captions.add(caption_key)
                
                # 화자 정보 포함
                if speaker_label:
                    display_text = f"[인물{speaker_label}] {transcript}"
                else:
                    display_text = transcript
                
                # 기본값 설정
                emotion = "중립"
                color = "#FFFFFF"
                bgm_text = None
                sfx_text = None
                
                # 실제 오디오 강도 계산 (시간대별 RMS 사용)
                # 자막 시간 범위의 평균 강도 계산
                intensity_samples = []
                for t in np.arange(start, end, 0.1):  # 0.1초 간격으로 샘플링
                    t_rounded = round(t, 2)
                    if t_rounded in audio_intensity_buffer:
                        intensity_samples.append(audio_intensity_buffer[t_rounded])
                
                if intensity_samples:
                    # 평균 강도 계산
                    intensity = float(np.mean(intensity_samples))
                else:
                    # 강도 데이터가 없으면 기본값 (0.5)
                    intensity = 0.5
                
                # BGM/SFX 정보 가져오기 (자막 시간 범위의 평균값 사용)
                if USE_PANNS_BGM and bgm_sfx_buffer:
                    bgm_samples = []
                    sfx_samples = []
                    for t in np.arange(start, end, 0.1):  # 0.1초 간격으로 샘플링
                        t_rounded = round(t, 2)
                        if t_rounded in bgm_sfx_buffer:
                            bgm_data = bgm_sfx_buffer[t_rounded]
                            if bgm_data.get('bgm'):
                                bgm_samples.append(bgm_data['bgm'])
                            if bgm_data.get('sfx'):
                                sfx_samples.append(bgm_data['sfx'])
                    
                    # 가장 많이 나타난 BGM/SFX 선택 (또는 가장 최근 값)
                    if bgm_samples:
                        bgm_text = max(set(bgm_samples), key=bgm_samples.count) if bgm_samples else None
                    if sfx_samples:
                        sfx_text = max(set(sfx_samples), key=sfx_samples.count) if sfx_samples else None
                    
                    # 디버깅 로그
                    if bgm_text or sfx_text:
                        print(f"[Video Analyzer] 🎵 자막에 BGM/SFX 포함: [{start:.1f}-{end:.1f}s] BGM={bgm_text}, SFX={sfx_text}")
                
                # 즉시 전송 (예외 처리 추가)
                try:
                    # 연결 상태 재확인
                    if connection_closed:
                        return
                    
                    # 초기 응답에도 이모지 포함 (기본값으로 빈 문자열)
                    initial_response = {
                        "text": display_text,
                        "emotion": emotion,
                        "emotion_icon": "",  # 초기에는 이모지 없음 (감정 분석 후 업데이트됨)
                        "color": color,
                        "intensity": float(intensity),
                        "pitch": 0.5,
                        "bgm": bgm_text,
                        "sfx": sfx_text,
                        "start": float(start),
                        "end": float(end),
                    }
                    await websocket.send_json(initial_response)
                    print(f"[Video Analyzer] 📤 [{start:.1f}s] {display_text[:80]}... (완성된 문장 전송)")
                    
                    # 감정 분석 후 업데이트
                    await update_emotion_styling(
                        transcript, display_text, intensity, bgm_text, sfx_text, start, end, websocket
                    )
                except (RuntimeError, Exception) as e:
                    # WebSocket이 닫혔거나 연결이 끊어진 경우
                    error_str = str(e).lower()
                    error_type = type(e).__name__
                    if any(keyword in error_str for keyword in ["close", "disconnect", "1006", "1000", "connection"]):
                        connection_closed = True
                        print(f"[Video Analyzer] 🔌 연결 끊김 감지: {error_type}")
                        return
                    # 다른 예외는 로그만 출력
                    print(f"[Video Analyzer] ⚠️ 자막 전송 실패: {error_type}: {e}")
                    return
    
    async def buffer_timeout_monitor():
        """버퍼 타임아웃 모니터링 (주기적으로 버퍼 체크 및 플러시)"""
        nonlocal connection_closed
        try:
            while not connection_closed:
                await asyncio.sleep(0.5)  # 0.5초마다 체크
                try:
                    await flush_buffer_if_ready()
                except (RuntimeError, Exception) as e:
                    # WebSocket 연결이 끊어진 경우 루프 종료
                    error_str = str(e).lower()
                    if any(keyword in error_str for keyword in ["close", "disconnect", "1006", "1000", "connection"]):
                        connection_closed = True
                        print(f"[Video Analyzer] 🔌 버퍼 모니터 종료 (연결 끊김)")
                        break
                    # 다른 예외는 무시하고 계속
        except asyncio.CancelledError:
            # 태스크 취소 시 남은 버퍼 플러시 (연결 상태 확인 후)
            try:
                if not connection_closed:
                    await flush_buffer_if_ready()
            except:
                pass  # 연결이 끊어진 경우 무시
            raise
    
    def on_open(event):
        connection_opened.set()
        print(f"[Video Analyzer] ✅ Deepgram 연결 완료: {audio_name}")
    
    def on_message(message):
        nonlocal stream_start_time, last_message_time, sentence_buffer
        
        last_message_time = asyncio.get_event_loop().time()
        try:
            if hasattr(message, "channel") and message.channel:
                channel = message.channel[0] if isinstance(message.channel, list) else message.channel
                if hasattr(channel, "alternatives") and channel.alternatives:
                    alt = channel.alternatives[0]
                    transcript = getattr(alt, "transcript", "")
                    # 후처리: 지혁 → 지옥 교정
                    transcript = _correct_common_errors(transcript)
                    
                    if not transcript or not transcript.strip():
                        return
                    
                    # 화자 구분 (실시간)
                    speaker_id = get_major_speaker(alt)
                    speaker_label = stabilize_speaker(speaker_id, transcript)
                    
                    # 시간 정보 추출 (스트리밍 시작 시간 기준 상대 시간)
                    if hasattr(alt, "words") and alt.words:
                        deepgram_start = float(alt.words[0].start if hasattr(alt.words[0], "start") else 0.0)
                        deepgram_end = float(alt.words[-1].end if hasattr(alt.words[-1], "end") else deepgram_start + 1.0)
                    else:
                        deepgram_start = 0.0
                        deepgram_end = deepgram_start + 1.0
                    
                    # 오디오 재생 시간으로 변환 (Deepgram 타임스탬프 + 오디오 재생 시작 시간)
                    start = deepgram_start + audio_playback_start_time
                    end = deepgram_end + audio_playback_start_time
                    
                    # 버퍼에 세그먼트 추가 (화자 변경 시 기존 버퍼 플러시)
                    if sentence_buffer.speaker_label is not None and sentence_buffer.speaker_label != speaker_label:
                        # 화자가 바뀌면 기존 버퍼 플러시
                        asyncio.create_task(flush_buffer_if_ready())
                    
                    sentence_buffer.add_segment(transcript, speaker_label, start, end)
                    
                    # 문장이 완성되었는지 확인
                    if sentence_buffer.should_flush():
                        asyncio.create_task(flush_buffer_if_ready())
                        
        except Exception as e:
            print(f"[Video Analyzer] 메시지 처리 오류: {e}")
            import traceback
            traceback.print_exc()
    
    try:
        async with deepgram_client.listen.v1.connect(
            model="nova-2",
            language="ko-KR",
            encoding="linear16",
            sample_rate="16000",
            smart_format="true",
            punctuate=True,  # 문장 부호 추가 (정확도 향상)
            endpointing=300,  # 발화 종료 대기 시간 (ms) - 짧은 끊김 방지
            diarize=True,  # 화자 구분 활성화
            vad_events=True,  # Voice Activity Detection 활성화 (작은 소리도 감지)
        ) as connection:
            connection.on(EventType.OPEN, on_open)
            connection.on(EventType.MESSAGE, on_message)
            
            listen_task = asyncio.create_task(connection.start_listening())
            await asyncio.wait_for(connection_opened.wait(), timeout=15.0)
            
            # 버퍼 타임아웃 모니터링 시작
            buffer_flush_task = asyncio.create_task(buffer_timeout_monitor())
            
            # 오디오 파일을 librosa로 직접 읽어서 Deepgram으로 전송
            print(f"[Video Analyzer] ✅ 오디오 스트리밍 시작: {audio_path}")
            
            async def send_audio_stream():
                nonlocal stream_start_time, audio_path
                try:
                    stream_start_time = asyncio.get_event_loop().time()
                    
                    # 오디오 파일 확장자 확인
                    file_ext = os.path.splitext(audio_path)[1].lower()
                    print(f"[Video Analyzer] 🎵 오디오 파일 스트리밍: {file_ext}")
                    
                    # MP4는 비디오 파일이므로 오디오 파일(WAV 등)을 사용해야 함
                    if file_ext in ['.mp4', '.mov', '.avi', '.mkv', '.flv', '.webm']:
                        # 비디오 파일이면 WAV 파일을 찾아서 사용
                        video_name = os.path.splitext(os.path.basename(audio_path))[0]
                        wav_path = os.path.join(os.path.dirname(audio_path), f"{video_name}.wav")
                        
                        if not os.path.exists(wav_path):
                            # WAV 파일이 없으면 오류
                            error_msg = f"비디오 파일({file_ext})은 지원하지 않습니다. 오디오 파일(.wav)을 사용하세요. WAV 파일을 찾을 수 없습니다: {wav_path}"
                            print(f"[Video Analyzer] ❌ {error_msg}")
                            await websocket.send_json({"error": error_msg})
                            return
                        
                        # WAV 파일 사용
                        audio_path = wav_path
                        file_ext = '.wav'
                        print(f"[Video Analyzer] 🔄 WAV 파일로 변경: {wav_path}")
                    
                    # PyAudio처럼: WAV 파일을 직접 읽어서 Deepgram으로 전송 (변환 없이)
                    # WAV 파일은 이미 16kHz mono 16-bit로 준비되어 있어야 함
                    import wave
                    
                    with wave.open(audio_path, 'rb') as wav_file:
                        # WAV 파일 정보 확인
                        sample_rate = wav_file.getframerate()
                        channels = wav_file.getnchannels()
                        sample_width = wav_file.getsampwidth()
                        frames = wav_file.getnframes()
                        
                        print(f"[Video Analyzer] 🎵 WAV 파일 정보: {sample_rate}Hz, {channels}ch, {sample_width*8}-bit, {frames} frames")
                        
                        # 형식 확인 (16kHz mono 16-bit)
                        if sample_rate != 16000 or channels != 1 or sample_width != 2:
                            error_msg = f"WAV 파일 형식이 맞지 않습니다. 16kHz mono 16-bit가 필요합니다. (현재: {sample_rate}Hz, {channels}ch, {sample_width*8}-bit)"
                            print(f"[Video Analyzer] ❌ {error_msg}")
                            await websocket.send_json({"error": error_msg})
                            return
                        
                        # DX_Project_2 PyAudio와 동일한 설정
                        # PyAudio: frames_per_buffer=1024 (bytes)
                        # 1024 bytes = 512 samples (16-bit = 2 bytes per sample)
                        chunk_bytes_size = 1024  # DX_Project_2와 동일
                        chunk_frames = chunk_bytes_size // 2  # 512 frames
                        
                        # 오디오 재생 시작 시간에 맞춰서 건너뛰기
                        if audio_playback_start_time > 0:
                            skip_frames = int(audio_playback_start_time * 16000)
                            wav_file.setpos(skip_frames)
                            print(f"[Video Analyzer] ⏩ {skip_frames} frames 건너뛰기 ({audio_playback_start_time:.2f}초)")
                        else:
                            print(f"[Video Analyzer] 🎵 오디오 스트리밍 처음부터 시작 (audio_start_time=0.0)")
                        
                        print(f"[Video Analyzer] 🎵 WAV 파일 직접 스트리밍 시작 (DX_Project_2와 동일)")
                        print(f"[Video Analyzer] 📡 즉시 오디오 스트리밍 시작 → Deepgram 자막 생성 중...")
                        
                        # DX_Project_2 PyAudio와 동일한 방식: 1024 bytes 읽기 → 즉시 전송 → 0.01초 딜레이
                        file_ended = False
                        
                        # 오디오 강도 추적용 변수
                        nonlocal audio_intensity_buffer, bgm_sfx_buffer
                        chunk_index = 0  # 청크 인덱스 (시간 계산용)
                        
                        try:
                            while True:
                                # 청크 읽기 (1024 bytes = 512 frames, DX_Project_2와 동일)
                                chunk_bytes = wav_file.readframes(chunk_frames)
                                
                                if len(chunk_bytes) == 0:
                                    # 파일 끝 - 무음을 보내서 연결 유지 (비디오가 끝날 때까지)
                                    if not file_ended:
                                        print("[Video Analyzer] ✅ WAV 파일 스트리밍 완료 (연결 유지 중)")
                                        file_ended = True
                                    # 무음 청크 생성 (1024 bytes = 512 frames of silence)
                                    chunk_bytes = b'\x00' * chunk_bytes_size
                                
                                # 현재 시간 계산 (강도 추적용)
                                current_time = chunk_index * (chunk_frames / 16000.0) + audio_playback_start_time
                                
                                # 오디오 강도 계산 (자막에 사용)
                                if len(chunk_bytes) > 0:
                                    try:
                                        # 16-bit PCM 데이터를 numpy 배열로 변환
                                        audio_array = np.frombuffer(chunk_bytes, dtype=np.int16).astype(np.float32)
                                        # 정규화 (-1.0 ~ 1.0 범위)
                                        audio_normalized = audio_array / 32768.0
                                        # RMS 계산
                                        current_rms = np.sqrt(np.mean(audio_normalized ** 2))
                                        # RMS를 0.0~1.0 범위로 정규화하여 intensity로 사용
                                        intensity_value = min(1.0, current_rms * 2.0)  # 0.0~1.0 범위
                                        audio_intensity_buffer[round(current_time, 2)] = intensity_value
                                        
                                        # PANNs BGM/SFX 분석 (비동기로 실행하여 블로킹 방지)
                                        if USE_PANNS_BGM:
                                            try:
                                                # analyze_bgm_chunk 호출 (내부 상태 업데이트)
                                                analyze_bgm_chunk(chunk_bytes, in_sr=16000)
                                                
                                                # 전역 변수에서 현재 BGM/SFX 값 읽기 (변경이 없어도 최신 값 유지)
                                                current_bgm = getattr(panns_module, 'current_bgm_text', '')
                                                current_sfx = getattr(panns_module, 'current_sfx_text', '')
                                                
                                                # BGM/SFX가 있으면 버퍼에 저장 (항상 최신 값 유지)
                                                if current_bgm or current_sfx:
                                                    bgm_sfx_buffer[round(current_time, 2)] = {
                                                        'bgm': current_bgm if current_bgm else None,
                                                        'sfx': current_sfx if current_sfx else None
                                                    }
                                                    # 디버깅 로그 (주기적으로만 출력)
                                                    if chunk_index % 100 == 0:  # 100번째 청크마다 로그
                                                        print(f"[Video Analyzer] 🎵 BGM/SFX 분석: 시간={round(current_time, 2)}s, BGM={current_bgm}, SFX={current_sfx}")
                                            except Exception as bgm_error:
                                                # BGM 분석 실패 시 로그 출력
                                                if chunk_index % 100 == 0:  # 에러도 주기적으로만 출력
                                                    print(f"[Video Analyzer] ⚠️ BGM 분석 실패: {bgm_error}")
                                                pass
                                    except Exception:
                                        # 오류 발생 시 기본값 사용
                                        audio_intensity_buffer[round(current_time, 2)] = 0.5
                                
                                chunk_index += 1
                                
                                # 오래된 강도 데이터 정리 (메모리 절약)
                                if len(audio_intensity_buffer) > 1000:
                                    # 가장 오래된 500개 제거
                                    sorted_keys = sorted(audio_intensity_buffer.keys())
                                    for key in sorted_keys[:500]:
                                        del audio_intensity_buffer[key]
                                
                                # 오래된 BGM/SFX 데이터 정리 (메모리 절약)
                                if len(bgm_sfx_buffer) > 1000:
                                    # 가장 오래된 500개 제거
                                    sorted_keys = sorted(bgm_sfx_buffer.keys())
                                    for key in sorted_keys[:500]:
                                        del bgm_sfx_buffer[key]
                                
                                # DX_Project_2와 동일: Deepgram으로 즉시 전송
                                if len(chunk_bytes) > 0:
                                    try:
                                        await connection.send_media(chunk_bytes)
                                    except Exception as send_error:
                                        # 연결이 닫혔으면 정상 종료
                                        if "1000" in str(send_error) or "ConnectionClosed" in str(type(send_error).__name__):
                                            print("[Video Analyzer] ✅ Deepgram 연결 정상 종료")
                                            break
                                        raise
                                
                                # DX_Project_2 PyAudio와 동일한 딜레이 (0.01초)
                                await asyncio.sleep(0.01)
                        except Exception as stream_error:
                            # 연결 종료는 정상적인 경우이므로 무시
                            if "1000" in str(stream_error) or "ConnectionClosed" in str(type(stream_error).__name__):
                                print("[Video Analyzer] ✅ 오디오 스트리밍 정상 종료")
                            else:
                                print(f"[Video Analyzer] ❌ 스트리밍 오류: {stream_error}")
                                import traceback
                                traceback.print_exc()
                                raise
                    
                except Exception as e:
                    print(f"[Video Analyzer] 오디오 스트리밍 오류: {e}")
                    import traceback
                    traceback.print_exc()
            
            # 오디오 스트리밍을 백그라운드 태스크로 실행 (블로킹 방지, 즉시 시작)
            stream_task = asyncio.create_task(send_audio_stream())
            
            # 메시지 수신 대기 (오디오 스트리밍과 병렬로 실행)
            # WAV 파일 길이 계산 (초 단위)
            import wave
            try:
                with wave.open(audio_path, 'rb') as wav_check:
                    wav_duration = wav_check.getnframes() / wav_check.getframerate()
                    print(f"[Video Analyzer] ⏱️ WAV 파일 길이: {wav_duration:.2f}초")
            except:
                wav_duration = 300.0  # 기본값 5분
            
            wait_start = asyncio.get_event_loop().time()
            file_ended_time = None
            
            while True:
                await asyncio.sleep(0.1)
                
                # 스트리밍 태스크가 완료되었는지 확인
                if stream_task.done():
                    if file_ended_time is None:
                        file_ended_time = asyncio.get_event_loop().time()
                        print(f"[Video Analyzer] ✅ WAV 파일 스트리밍 완료, 연결 유지 중...")
                    
                    # 파일이 끝난 후에도 최소 5초 더 대기 (비디오가 끝날 때까지)
                    if asyncio.get_event_loop().time() - file_ended_time > 5.0:
                        # 마지막 메시지가 3초 이상 전이면 종료
                        if last_message_time:
                            if asyncio.get_event_loop().time() - last_message_time > 3.0:
                                print("[Video Analyzer] ✅ 메시지 수신 종료 (3초 이상 메시지 없음)")
                                break
                        # 파일이 끝난 후 10초 이상 지나면 종료
                        if asyncio.get_event_loop().time() - file_ended_time > 10.0:
                            print("[Video Analyzer] ✅ 타임아웃 종료 (파일 종료 후 10초)")
                            break
                else:
                    # 스트리밍 중일 때는 메시지 타임아웃만 체크 (더 긴 타임아웃)
                    if last_message_time:
                        if asyncio.get_event_loop().time() - last_message_time > 10.0:
                            print("[Video Analyzer] ⚠️ 메시지 수신 타임아웃 (10초 이상 메시지 없음)")
                            break
                
                # 전체 타임아웃 (WAV 파일 길이 + 여유 시간 20초)
                max_wait_time = wav_duration + 20.0
                if asyncio.get_event_loop().time() - wait_start > max_wait_time:
                    print(f"[Video Analyzer] ✅ 전체 타임아웃 종료 ({max_wait_time:.1f}초)")
                    break
            
            # 버퍼 플러시 태스크 종료
            if buffer_flush_task and not buffer_flush_task.done():
                buffer_flush_task.cancel()
                try:
                    await buffer_flush_task
                except asyncio.CancelledError:
                    pass
            
            # 남은 버퍼 내용 전송
            if sentence_buffer.text:
                await flush_buffer_if_ready()
            
            listen_task.cancel()
            if not stream_task.done():
                stream_task.cancel()
            
    except Exception as e:
        print(f"[Video Analyzer] STT 오류: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if audio_name in video_streams:
            del video_streams[audio_name]

@app.post("/api/analyze-video")
async def analyze_video_endpoint(request: VideoAnalysisRequest):
    """비디오 분석 시작 (실시간 스트리밍)"""
    video_path = request.video_path
    if not os.path.isabs(video_path):
        backend_dir = Path(__file__).parent
        project_root = backend_dir.parent
        video_path = str(project_root / video_path)
    
    if not os.path.exists(video_path):
        return {"error": f"비디오 파일을 찾을 수 없습니다: {video_path}"}
    
    analyzing.add(request.video_name)
    
    return {
        "status": "started",
        "video_name": request.video_name,
        "message": "비디오 분석이 시작되었습니다. WebSocket으로 연결하세요."
    }

@app.websocket("/ws/video-captions")
async def video_captions_ws(websocket: WebSocket):
    """비디오 자막 WebSocket (실시간 스트리밍)"""
    await websocket.accept()
    connected_clients.add(websocket)
    
    # audio_name을 함수 시작 부분에서 초기화 (예외 처리에서 접근 가능하도록)
    audio_name = None
    
    try:
        # 초기 메시지: 오디오 파일 이름과 시작 신호
        # 타임아웃 없이 즉시 받기 (비디오 재생 전에도 자막 수집)
        try:
            init_data = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        except asyncio.TimeoutError:
            # 타임아웃 시 기본값 사용 (연결만으로도 시작 가능)
            print("[Video Analyzer] ⚠️ 초기 메시지 타임아웃, 기본값 사용")
            init_data = {}
        
        audio_name = init_data.get("audio_name") or init_data.get("video_name")  # 하위 호환성
        action = init_data.get("action", "start")
        
        if not audio_name:
            # audio_name이 없으면 연결만 유지 (나중에 메시지로 받을 수 있음)
            print("[Video Analyzer] ⚠️ audio_name이 없습니다. 연결 유지 중...")
            # 메시지 대기 루프
            while True:
                try:
                    msg = await asyncio.wait_for(websocket.receive_json(), timeout=30.0)
                    audio_name = msg.get("audio_name") or msg.get("video_name")
                    if audio_name:
                        init_data = msg
                        action = msg.get("action", "start")
                        break
                except asyncio.TimeoutError:
                    continue
        
        if action == "start":
            # 오디오 파일 경로 찾기
            backend_dir = Path(__file__).parent
            project_root = backend_dir.parent
            
            # MP4 파일명이 들어오면 해당하는 WAV 파일 사용 (오디오는 WAV 파일만 사용)
            if audio_name.endswith('.mp4') or audio_name.endswith('.MP4'):
                # MP4 파일명에서 확장자 제거하고 .wav 추가
                wav_name = audio_name.rsplit('.', 1)[0] + '.wav'
                audio_path = str(project_root / f"frontend/deaftv_lgdxschool_projects/assets/{wav_name}")
                audio_name = wav_name
                print(f"[Video Analyzer] 🔄 MP4 파일명 감지, {wav_name} 사용")
            else:
                audio_path = str(project_root / f"frontend/deaftv_lgdxschool_projects/assets/{audio_name}")
            
            if not os.path.exists(audio_path):
                await websocket.send_json({"error": f"오디오 파일을 찾을 수 없습니다: {audio_path}"})
                return
            
            # 오디오 재생 시작 시간 받기 (초 단위, 기본값 0.0)
            audio_start_time = float(init_data.get("audio_start_time") or init_data.get("video_start_time", 0.0))
            print(f"[Video Analyzer] 🚀 즉시 오디오 스트리밍 시작: {audio_name} (시작 시간: {audio_start_time:.2f}초)")
            
            # 실시간 분석 시작 (즉시 오디오 스트리밍 시작)
            video_streams[audio_name] = {"websocket": websocket}
            await start_realtime_analysis(audio_path, audio_name, websocket, audio_start_time)
        
    except WebSocketDisconnect:
        connected_clients.discard(websocket)
        if audio_name and audio_name in video_streams:
            del video_streams[audio_name]
    except Exception as e:
        print(f"[Video Analyzer] WebSocket 오류: {e}")
        import traceback
        traceback.print_exc()
        connected_clients.discard(websocket)
        if audio_name and audio_name in video_streams:
            del video_streams[audio_name]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)

# DX_Project_2 방식: ai_engine 감정 분석 사용
try:
    import sys
    import os
    # ai_engine 경로 추가
    ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
    if os.path.exists(ai_engine_path):
        sys.path.insert(0, os.path.dirname(ai_engine_path))
        from ai_engine.emotion_wrapper import analyze_emotion
        from ai_engine.kluebert_emotion import EMOTION_ICON
        print("[Video Analyzer] ✅ ai_engine 감정 분석 모듈 로드 성공")
        USE_AI_ENGINE_EMOTION = True
    else:
        print("[Video Analyzer] ⚠️ ai_engine 경로를 찾을 수 없습니다. 기본 감정 분석 사용")
        USE_AI_ENGINE_EMOTION = False
        EMOTION_ICON = {}
        # ai_engine 경로를 추가한 후 import
        ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
        sys.path.insert(0, os.path.dirname(ai_engine_path))
        from ai_engine.emotion_analyzer import EmotionAnalyzer
except ImportError as e:
    print(f"[Video Analyzer] ⚠️ ai_engine 모듈 로드 실패: {e}. 기본 감정 분석 사용")
    USE_AI_ENGINE_EMOTION = False
    EMOTION_ICON = {}
    # ai_engine 경로를 추가한 후 import
    ai_engine_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'ai_engine')
    sys.path.insert(0, os.path.dirname(ai_engine_path))
    from ai_engine.emotion_analyzer import EmotionAnalyzer
from deepgram import AsyncDeepgramClient
from deepgram.core.events import EventType

load_dotenv()
DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_models()
    yield

app = FastAPI(title="Video Analyzer Server", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# 전역 변수
connected_clients: set[WebSocket] = set()
video_streams: Dict[str, Dict] = {}  # {video_name: {websocket, connection, audio_data, ...}}
analyzing: set[str] = set()

emotion_analyzer = None
deepgram_client = None
# DX_Project_2 방식: 팔레트 레벨 (기본값 2)
palette_level = 2

def _ansi_to_hex(ansi_color: str) -> str:
    """ANSI 색상 코드를 HEX 색상으로 변환"""
    color_map = {
        "\033[93m": "#FFFF00",  # 노란색
        "\033[92m": "#00FF00",  # 초록색
        "\033[94m": "#0000FF",  # 파란색
        "\033[95m": "#FF00FF",  # 자홍색
        "\033[91m": "#FF0000",  # 빨간색
        "\033[97m": "#FFFFFF",  # 흰색
    }
    return color_map.get(ansi_color, "#FFFFFF")

def _correct_common_errors(text: str) -> str:
    """자주 잘못 인식되는 단어 교정: 지혁 → 지옥"""
    return text.replace("지혁", "지옥")

def _is_sentence_complete(text: str) -> bool:
    """문장이 완성되었는지 확인 (문장 부호로 끝나는지)"""
    if not text or len(text.strip()) < 3:  # 최소 3글자 이상
        return False
    
    # 문장 종료 부호로 끝나는지 확인
    sentence_endings = ['.', '!', '?', '…', '。', '！', '？']
    text_stripped = text.strip()
    
    # 마지막 문자가 문장 종료 부호인지 확인
    if text_stripped[-1] in sentence_endings:
        return True
    
    # 한글 문장의 경우 "~다", "~요", "~네" 등으로 끝나는 경우도 완성으로 간주
    korean_endings = ['다', '요', '네', '죠', '까', '래', '게', '야', '어', '아']
    if len(text_stripped) >= 5:  # 충분히 긴 문장인 경우
        if text_stripped[-1] in korean_endings:
            # 문장 부호가 없어도 특정 어미로 끝나면 완성으로 간주
            return True
    
    return False

class SentenceBuffer:
    """문장 버퍼링을 위한 클래스"""
    def __init__(self, max_wait_time: float = 2.0, min_length: int = 3):
        self.text = ""
        self.speaker_label = None
        self.start_time = None
        self.end_time = None
        self.last_update_time = None
        self.segments = []  # 각 세그먼트 정보 저장
        self.max_wait_time = max_wait_time  # 최대 대기 시간 (초)
        self.min_length = min_length  # 최소 문장 길이
        self.is_flushing = False  # 플러시 중인지 여부
    
    def add_segment(self, transcript: str, speaker_label: str, start: float, end: float):
        """새 세그먼트를 버퍼에 추가"""
        current_time = asyncio.get_event_loop().time()
        
        # 화자가 바뀌면 기존 버퍼 플러시 필요
        if self.speaker_label is not None and self.speaker_label != speaker_label:
            self.is_flushing = True
        
        # 버퍼가 비어있으면 시작 시간 설정
        if self.start_time is None:
            self.start_time = start
            self.speaker_label = speaker_label
        
        # 텍스트 누적
        if self.text:
            self.text += " " + transcript
        else:
            self.text = transcript
        
        # 시간 업데이트
        self.end_time = end
        self.last_update_time = current_time
        
        # 세그먼트 정보 저장
        self.segments.append({
            'transcript': transcript,
            'speaker_label': speaker_label,
            'start': start,
            'end': end
        })
    
    def should_flush(self) -> bool:
        """버퍼를 플러시해야 하는지 확인"""
        if not self.text:
            return False
        
        # 화자가 바뀌면 즉시 플러시
        if self.is_flushing:
            return True
        
        # 문장이 완성되었으면 플러시
        if _is_sentence_complete(self.text):
            return True
        
        # 최소 길이를 넘고 타임아웃되었으면 플러시
        if len(self.text.strip()) >= self.min_length and self.last_update_time:
            current_time = asyncio.get_event_loop().time()
            if current_time - self.last_update_time >= self.max_wait_time:
                return True
        
        return False
    
    def flush(self) -> Optional[Dict]:
        """버퍼를 플러시하고 문장 데이터 반환"""
        if not self.text or len(self.text.strip()) < self.min_length:
            self.reset()
            return None
        
        result = {
            'text': self.text.strip(),
            'speaker_label': self.speaker_label,
            'start': self.start_time,
            'end': self.end_time,
            'segments': self.segments.copy()
        }
        
        self.reset()
        return result
    
    def reset(self):
        """버퍼 초기화"""
        self.text = ""
        self.speaker_label = None
        self.start_time = None
        self.end_time = None
        self.last_update_time = None
        self.segments = []
        self.is_flushing = False

async def update_emotion_styling(
    transcript: str, 
    display_text: str, 
    intensity: float, 
    bgm_text: str, 
    sfx_text: str, 
    start: float, 
    end: float, 
    websocket: WebSocket
):
    """감정 분석 및 스타일링 업데이트 (DX_Project_2 방식: ai_engine 사용)"""
    global palette_level
    
    try:
        loop = asyncio.get_event_loop()
        
        if USE_AI_ENGINE_EMOTION:
            # DX_Project_2 방식: ai_engine.emotion_wrapper 사용
            emotion, conf, color_hex = await loop.run_in_executor(
                None,
                analyze_emotion,
                transcript,
                palette_level
            )
            # 감정 이름을 한글로 변환
            emotion_ko_map = {
                "joy": "기쁨",
                "sadness": "슬픔",
                "anger": "분노",
                "fear": "공포",
                "surprise": "놀람",
                "disgust": "혐오",
                "neutral": "중립"
            }
            emotion_val = emotion_ko_map.get(emotion, "중립")
            color_val = color_hex
        else:
            # 기본 방식: EmotionAnalyzer 사용
            global emotion_analyzer
            if not emotion_analyzer:
                return
            emotion_result = await loop.run_in_executor(
                None, 
                emotion_analyzer.predict, 
                transcript
            )
            emotion_val = emotion_result.get("emotion_ko", "중립")
            ansi_color = emotion_result.get("color", "\033[97m")
            color_val = _ansi_to_hex(ansi_color)
        
        # 결과를 WebSocket으로 전송 (업데이트)
        try:
            # 감정 이모지 가져오기 (USE_AI_ENGINE_EMOTION일 때만)
            emotion_icon = ""
            if USE_AI_ENGINE_EMOTION:
                # emotion_val이 한글이므로 영어 감정명으로 역변환 필요
                emotion_en_map = {
                    "기쁨": "joy",
                    "슬픔": "sadness",
                    "분노": "anger",
                    "공포": "fear",
                    "놀람": "surprise",
                    "혐오": "disgust",
                    "중립": "neutral"
                }
                emotion_en = emotion_en_map.get(emotion_val, "neutral")
                emotion_icon = EMOTION_ICON.get(emotion_en, "")
            
            update_response = {
                "text": display_text,
                "emotion": emotion_val,
                "emotion_icon": emotion_icon,  # 이모지 추가
                "color": color_val,
                "intensity": float(intensity),
                "pitch": 0.5,
                "bgm": bgm_text,
                "sfx": sfx_text,
                "start": float(start),
                "end": float(end),
            }
            await websocket.send_json(update_response)
            print(f"[Video Analyzer] 🎨 감정 분석 완료: {emotion_val} {emotion_icon} ({color_val})")
        except (RuntimeError, Exception) as send_error:
            # WebSocket이 닫혔거나 연결이 끊어진 경우 무시
            if "close" in str(send_error).lower() or "disconnect" in str(send_error).lower():
                return
            raise  # 다른 예외는 다시 발생시킴
    except Exception as e:
        # WebSocket 연결 오류는 무시 (연결이 끊어진 경우)
        if "close" in str(e).lower() or "disconnect" in str(e).lower():
            return
        print(f"[Video Analyzer] 감정 분석 오류: {e}")
        import traceback
        traceback.print_exc()

# 변환 로직 제거 - WAV 파일은 이미 16kHz mono 16-bit로 준비되어 있어야 함

def init_models():
    global emotion_analyzer, deepgram_client
    try:
        # DX_Project_2 방식: ai_engine을 사용하면 EmotionAnalyzer 초기화 불필요
        if not USE_AI_ENGINE_EMOTION:
            emotion_analyzer = EmotionAnalyzer(r"C:\Users\155\Downloads\My_Emotion_Model")
        if DEEPGRAM_API_KEY:
            deepgram_client = AsyncDeepgramClient(api_key=DEEPGRAM_API_KEY)
        print("[Video Analyzer] ✅ 모델 초기화 완료")
    except Exception as e:
        print(f"[Video Analyzer] ❌ 모델 초기화 실패: {e}")

class VideoAnalysisRequest(BaseModel):
    video_path: str
    video_name: str


async def start_realtime_analysis(audio_path: str, audio_name: str, websocket: WebSocket, audio_start_time: float = 0.0):
    """오디오 파일을 실시간으로 스트리밍하여 분석 (librosa 직접 읽기)"""
    global deepgram_client, emotion_analyzer
    
    if not deepgram_client:
        await websocket.send_json({"error": "Deepgram 클라이언트가 초기화되지 않았습니다."})
        return
    
    reset_speaker_map()
    
    connection_opened = asyncio.Event()
    stream_start_time = None
    audio_playback_start_time = audio_start_time  # 오디오 재생 시작 시간 (초)
    last_message_time = None  # 마지막 메시지 수신 시간 (외부 스코프에서 업데이트)
    
    # 중복 전송 방지: (start, end, transcript) 조합을 추적
    sent_captions = set()
    
    # 문장 버퍼링: 완전한 문장을 만들기 위한 버퍼
    sentence_buffer = SentenceBuffer(max_wait_time=2.0, min_length=5)
    buffer_flush_task = None  # 버퍼 플러시 태스크
    
    # 오디오 강도 추적 (시간대별 RMS 저장)
    audio_intensity_buffer = {}  # {timestamp: rms_value}
    
    # BGM/SFX 버퍼 (시간대별 BGM/SFX 정보 저장)
    bgm_sfx_buffer = {}  # {timestamp: {'bgm': bgm_text, 'sfx': sfx_text}}
    
    # 연결 상태 플래그 (연결이 끊어졌는지 추적)
    connection_closed = False
    
    # 비디오 파일명에 따라 PANNs 모드 설정
    if USE_PANNS_BGM:
        video_basename = os.path.basename(audio_name).lower()
        if '환승연애' in video_basename or '예능' in video_basename or 'enter_web' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'ENTERTAINMENT'
            print("[Video Analyzer] 🎬 PANNs 모드: ENTERTAINMENT (예능)")
        elif '친애하는' in video_basename or '드라마' in video_basename or '영화' in video_basename or 'drama' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'DRAMA'
            print("[Video Analyzer] 🎬 PANNs 모드: DRAMA (드라마/영화)")
        elif '펭귄' in video_basename or '다큐' in video_basename or 'dacu' in video_basename:
            os.environ['CAPTION_CONTENT_MODE'] = 'DOCUMENTARY'
            print("[Video Analyzer] 🎬 PANNs 모드: DOCUMENTARY (다큐멘터리)")
        else:
            os.environ['CAPTION_CONTENT_MODE'] = 'DOCUMENTARY'  # 기본값
            print("[Video Analyzer] 🎬 PANNs 모드: DOCUMENTARY (기본값)")
    
    async def flush_buffer_if_ready():
        """버퍼가 준비되었으면 플러시하고 전송"""
        nonlocal sentence_buffer, sent_captions, audio_intensity_buffer, bgm_sfx_buffer, connection_closed
        
        # 연결이 끊어진 경우 즉시 반환
        if connection_closed:
            return
        
        # WebSocket 연결 상태 확인
        try:
            # WebSocket이 닫혔는지 확인
            if hasattr(websocket, 'client_state'):
                if websocket.client_state.name != "CONNECTED":
                    connection_closed = True
                    return
        except (AttributeError, RuntimeError, Exception):
            # 연결이 끊어진 경우
            connection_closed = True
            return
        
        if sentence_buffer.should_flush():
            buffer_data = sentence_buffer.flush()
            if buffer_data:
                transcript = buffer_data['text']
                speaker_label = buffer_data['speaker_label']
                start = buffer_data['start']
                end = buffer_data['end']
                
                # 중복 체크
                caption_key = (round(start, 2), round(end, 2), transcript)
                if caption_key in sent_captions:
                    return
                
                sent_captions.add(caption_key)
                
                # 화자 정보 포함
                if speaker_label:
                    display_text = f"[인물{speaker_label}] {transcript}"
                else:
                    display_text = transcript
                
                # 기본값 설정
                emotion = "중립"
                color = "#FFFFFF"
                bgm_text = None
                sfx_text = None
                
                # 실제 오디오 강도 계산 (시간대별 RMS 사용)
                # 자막 시간 범위의 평균 강도 계산
                intensity_samples = []
                for t in np.arange(start, end, 0.1):  # 0.1초 간격으로 샘플링
                    t_rounded = round(t, 2)
                    if t_rounded in audio_intensity_buffer:
                        intensity_samples.append(audio_intensity_buffer[t_rounded])
                
                if intensity_samples:
                    # 평균 강도 계산
                    intensity = float(np.mean(intensity_samples))
                else:
                    # 강도 데이터가 없으면 기본값 (0.5)
                    intensity = 0.5
                
                # BGM/SFX 정보 가져오기 (자막 시간 범위의 평균값 사용)
                if USE_PANNS_BGM and bgm_sfx_buffer:
                    bgm_samples = []
                    sfx_samples = []
                    for t in np.arange(start, end, 0.1):  # 0.1초 간격으로 샘플링
                        t_rounded = round(t, 2)
                        if t_rounded in bgm_sfx_buffer:
                            bgm_data = bgm_sfx_buffer[t_rounded]
                            if bgm_data.get('bgm'):
                                bgm_samples.append(bgm_data['bgm'])
                            if bgm_data.get('sfx'):
                                sfx_samples.append(bgm_data['sfx'])
                    
                    # 가장 많이 나타난 BGM/SFX 선택 (또는 가장 최근 값)
                    if bgm_samples:
                        bgm_text = max(set(bgm_samples), key=bgm_samples.count) if bgm_samples else None
                    if sfx_samples:
                        sfx_text = max(set(sfx_samples), key=sfx_samples.count) if sfx_samples else None
                    
                    # 디버깅 로그
                    if bgm_text or sfx_text:
                        print(f"[Video Analyzer] 🎵 자막에 BGM/SFX 포함: [{start:.1f}-{end:.1f}s] BGM={bgm_text}, SFX={sfx_text}")
                
                # 즉시 전송 (예외 처리 추가)
                try:
                    # 연결 상태 재확인
                    if connection_closed:
                        return
                    
                    # 초기 응답에도 이모지 포함 (기본값으로 빈 문자열)
                    initial_response = {
                        "text": display_text,
                        "emotion": emotion,
                        "emotion_icon": "",  # 초기에는 이모지 없음 (감정 분석 후 업데이트됨)
                        "color": color,
                        "intensity": float(intensity),
                        "pitch": 0.5,
                        "bgm": bgm_text,
                        "sfx": sfx_text,
                        "start": float(start),
                        "end": float(end),
                    }
                    await websocket.send_json(initial_response)
                    print(f"[Video Analyzer] 📤 [{start:.1f}s] {display_text[:80]}... (완성된 문장 전송)")
                    
                    # 감정 분석 후 업데이트
                    await update_emotion_styling(
                        transcript, display_text, intensity, bgm_text, sfx_text, start, end, websocket
                    )
                except (RuntimeError, Exception) as e:
                    # WebSocket이 닫혔거나 연결이 끊어진 경우
                    error_str = str(e).lower()
                    error_type = type(e).__name__
                    if any(keyword in error_str for keyword in ["close", "disconnect", "1006", "1000", "connection"]):
                        connection_closed = True
                        print(f"[Video Analyzer] 🔌 연결 끊김 감지: {error_type}")
                        return
                    # 다른 예외는 로그만 출력
                    print(f"[Video Analyzer] ⚠️ 자막 전송 실패: {error_type}: {e}")
                    return
    
    async def buffer_timeout_monitor():
        """버퍼 타임아웃 모니터링 (주기적으로 버퍼 체크 및 플러시)"""
        nonlocal connection_closed
        try:
            while not connection_closed:
                await asyncio.sleep(0.5)  # 0.5초마다 체크
                try:
                    await flush_buffer_if_ready()
                except (RuntimeError, Exception) as e:
                    # WebSocket 연결이 끊어진 경우 루프 종료
                    error_str = str(e).lower()
                    if any(keyword in error_str for keyword in ["close", "disconnect", "1006", "1000", "connection"]):
                        connection_closed = True
                        print(f"[Video Analyzer] 🔌 버퍼 모니터 종료 (연결 끊김)")
                        break
                    # 다른 예외는 무시하고 계속
        except asyncio.CancelledError:
            # 태스크 취소 시 남은 버퍼 플러시 (연결 상태 확인 후)
            try:
                if not connection_closed:
                    await flush_buffer_if_ready()
            except:
                pass  # 연결이 끊어진 경우 무시
            raise
    
    def on_open(event):
        connection_opened.set()
        print(f"[Video Analyzer] ✅ Deepgram 연결 완료: {audio_name}")
    
    def on_message(message):
        nonlocal stream_start_time, last_message_time, sentence_buffer
        
        last_message_time = asyncio.get_event_loop().time()
        try:
            if hasattr(message, "channel") and message.channel:
                channel = message.channel[0] if isinstance(message.channel, list) else message.channel
                if hasattr(channel, "alternatives") and channel.alternatives:
                    alt = channel.alternatives[0]
                    transcript = getattr(alt, "transcript", "")
                    # 후처리: 지혁 → 지옥 교정
                    transcript = _correct_common_errors(transcript)
                    
                    if not transcript or not transcript.strip():
                        return
                    
                    # 화자 구분 (실시간)
                    speaker_id = get_major_speaker(alt)
                    speaker_label = stabilize_speaker(speaker_id, transcript)
                    
                    # 시간 정보 추출 (스트리밍 시작 시간 기준 상대 시간)
                    if hasattr(alt, "words") and alt.words:
                        deepgram_start = float(alt.words[0].start if hasattr(alt.words[0], "start") else 0.0)
                        deepgram_end = float(alt.words[-1].end if hasattr(alt.words[-1], "end") else deepgram_start + 1.0)
                    else:
                        deepgram_start = 0.0
                        deepgram_end = deepgram_start + 1.0
                    
                    # 오디오 재생 시간으로 변환 (Deepgram 타임스탬프 + 오디오 재생 시작 시간)
                    start = deepgram_start + audio_playback_start_time
                    end = deepgram_end + audio_playback_start_time
                    
                    # 버퍼에 세그먼트 추가 (화자 변경 시 기존 버퍼 플러시)
                    if sentence_buffer.speaker_label is not None and sentence_buffer.speaker_label != speaker_label:
                        # 화자가 바뀌면 기존 버퍼 플러시
                        asyncio.create_task(flush_buffer_if_ready())
                    
                    sentence_buffer.add_segment(transcript, speaker_label, start, end)
                    
                    # 문장이 완성되었는지 확인
                    if sentence_buffer.should_flush():
                        asyncio.create_task(flush_buffer_if_ready())
                        
        except Exception as e:
            print(f"[Video Analyzer] 메시지 처리 오류: {e}")
            import traceback
            traceback.print_exc()
    
    try:
        async with deepgram_client.listen.v1.connect(
            model="nova-2",
            language="ko-KR",
            encoding="linear16",
            sample_rate="16000",
            smart_format="true",
            punctuate=True,  # 문장 부호 추가 (정확도 향상)
            endpointing=300,  # 발화 종료 대기 시간 (ms) - 짧은 끊김 방지
            diarize=True,  # 화자 구분 활성화
            vad_events=True,  # Voice Activity Detection 활성화 (작은 소리도 감지)
        ) as connection:
            connection.on(EventType.OPEN, on_open)
            connection.on(EventType.MESSAGE, on_message)
            
            listen_task = asyncio.create_task(connection.start_listening())
            await asyncio.wait_for(connection_opened.wait(), timeout=15.0)
            
            # 버퍼 타임아웃 모니터링 시작
            buffer_flush_task = asyncio.create_task(buffer_timeout_monitor())
            
            # 오디오 파일을 librosa로 직접 읽어서 Deepgram으로 전송
            print(f"[Video Analyzer] ✅ 오디오 스트리밍 시작: {audio_path}")
            
            async def send_audio_stream():
                nonlocal stream_start_time, audio_path
                try:
                    stream_start_time = asyncio.get_event_loop().time()
                    
                    # 오디오 파일 확장자 확인
                    file_ext = os.path.splitext(audio_path)[1].lower()
                    print(f"[Video Analyzer] 🎵 오디오 파일 스트리밍: {file_ext}")
                    
                    # MP4는 비디오 파일이므로 오디오 파일(WAV 등)을 사용해야 함
                    if file_ext in ['.mp4', '.mov', '.avi', '.mkv', '.flv', '.webm']:
                        # 비디오 파일이면 WAV 파일을 찾아서 사용
                        video_name = os.path.splitext(os.path.basename(audio_path))[0]
                        wav_path = os.path.join(os.path.dirname(audio_path), f"{video_name}.wav")
                        
                        if not os.path.exists(wav_path):
                            # WAV 파일이 없으면 오류
                            error_msg = f"비디오 파일({file_ext})은 지원하지 않습니다. 오디오 파일(.wav)을 사용하세요. WAV 파일을 찾을 수 없습니다: {wav_path}"
                            print(f"[Video Analyzer] ❌ {error_msg}")
                            await websocket.send_json({"error": error_msg})
                            return
                        
                        # WAV 파일 사용
                        audio_path = wav_path
                        file_ext = '.wav'
                        print(f"[Video Analyzer] 🔄 WAV 파일로 변경: {wav_path}")
                    
                    # PyAudio처럼: WAV 파일을 직접 읽어서 Deepgram으로 전송 (변환 없이)
                    # WAV 파일은 이미 16kHz mono 16-bit로 준비되어 있어야 함
                    import wave
                    
                    with wave.open(audio_path, 'rb') as wav_file:
                        # WAV 파일 정보 확인
                        sample_rate = wav_file.getframerate()
                        channels = wav_file.getnchannels()
                        sample_width = wav_file.getsampwidth()
                        frames = wav_file.getnframes()
                        
                        print(f"[Video Analyzer] 🎵 WAV 파일 정보: {sample_rate}Hz, {channels}ch, {sample_width*8}-bit, {frames} frames")
                        
                        # 형식 확인 (16kHz mono 16-bit)
                        if sample_rate != 16000 or channels != 1 or sample_width != 2:
                            error_msg = f"WAV 파일 형식이 맞지 않습니다. 16kHz mono 16-bit가 필요합니다. (현재: {sample_rate}Hz, {channels}ch, {sample_width*8}-bit)"
                            print(f"[Video Analyzer] ❌ {error_msg}")
                            await websocket.send_json({"error": error_msg})
                            return
                        
                        # DX_Project_2 PyAudio와 동일한 설정
                        # PyAudio: frames_per_buffer=1024 (bytes)
                        # 1024 bytes = 512 samples (16-bit = 2 bytes per sample)
                        chunk_bytes_size = 1024  # DX_Project_2와 동일
                        chunk_frames = chunk_bytes_size // 2  # 512 frames
                        
                        # 오디오 재생 시작 시간에 맞춰서 건너뛰기
                        if audio_playback_start_time > 0:
                            skip_frames = int(audio_playback_start_time * 16000)
                            wav_file.setpos(skip_frames)
                            print(f"[Video Analyzer] ⏩ {skip_frames} frames 건너뛰기 ({audio_playback_start_time:.2f}초)")
                        else:
                            print(f"[Video Analyzer] 🎵 오디오 스트리밍 처음부터 시작 (audio_start_time=0.0)")
                        
                        print(f"[Video Analyzer] 🎵 WAV 파일 직접 스트리밍 시작 (DX_Project_2와 동일)")
                        print(f"[Video Analyzer] 📡 즉시 오디오 스트리밍 시작 → Deepgram 자막 생성 중...")
                        
                        # DX_Project_2 PyAudio와 동일한 방식: 1024 bytes 읽기 → 즉시 전송 → 0.01초 딜레이
                        file_ended = False
                        
                        # 오디오 강도 추적용 변수
                        nonlocal audio_intensity_buffer, bgm_sfx_buffer
                        chunk_index = 0  # 청크 인덱스 (시간 계산용)
                        
                        try:
                            while True:
                                # 청크 읽기 (1024 bytes = 512 frames, DX_Project_2와 동일)
                                chunk_bytes = wav_file.readframes(chunk_frames)
                                
                                if len(chunk_bytes) == 0:
                                    # 파일 끝 - 무음을 보내서 연결 유지 (비디오가 끝날 때까지)
                                    if not file_ended:
                                        print("[Video Analyzer] ✅ WAV 파일 스트리밍 완료 (연결 유지 중)")
                                        file_ended = True
                                    # 무음 청크 생성 (1024 bytes = 512 frames of silence)
                                    chunk_bytes = b'\x00' * chunk_bytes_size
                                
                                # 현재 시간 계산 (강도 추적용)
                                current_time = chunk_index * (chunk_frames / 16000.0) + audio_playback_start_time
                                
                                # 오디오 강도 계산 (자막에 사용)
                                if len(chunk_bytes) > 0:
                                    try:
                                        # 16-bit PCM 데이터를 numpy 배열로 변환
                                        audio_array = np.frombuffer(chunk_bytes, dtype=np.int16).astype(np.float32)
                                        # 정규화 (-1.0 ~ 1.0 범위)
                                        audio_normalized = audio_array / 32768.0
                                        # RMS 계산
                                        current_rms = np.sqrt(np.mean(audio_normalized ** 2))
                                        # RMS를 0.0~1.0 범위로 정규화하여 intensity로 사용
                                        intensity_value = min(1.0, current_rms * 2.0)  # 0.0~1.0 범위
                                        audio_intensity_buffer[round(current_time, 2)] = intensity_value
                                        
                                        # PANNs BGM/SFX 분석 (비동기로 실행하여 블로킹 방지)
                                        if USE_PANNS_BGM:
                                            try:
                                                # analyze_bgm_chunk 호출 (내부 상태 업데이트)
                                                analyze_bgm_chunk(chunk_bytes, in_sr=16000)
                                                
                                                # 전역 변수에서 현재 BGM/SFX 값 읽기 (변경이 없어도 최신 값 유지)
                                                current_bgm = getattr(panns_module, 'current_bgm_text', '')
                                                current_sfx = getattr(panns_module, 'current_sfx_text', '')
                                                
                                                # BGM/SFX가 있으면 버퍼에 저장 (항상 최신 값 유지)
                                                if current_bgm or current_sfx:
                                                    bgm_sfx_buffer[round(current_time, 2)] = {
                                                        'bgm': current_bgm if current_bgm else None,
                                                        'sfx': current_sfx if current_sfx else None
                                                    }
                                                    # 디버깅 로그 (주기적으로만 출력)
                                                    if chunk_index % 100 == 0:  # 100번째 청크마다 로그
                                                        print(f"[Video Analyzer] 🎵 BGM/SFX 분석: 시간={round(current_time, 2)}s, BGM={current_bgm}, SFX={current_sfx}")
                                            except Exception as bgm_error:
                                                # BGM 분석 실패 시 로그 출력
                                                if chunk_index % 100 == 0:  # 에러도 주기적으로만 출력
                                                    print(f"[Video Analyzer] ⚠️ BGM 분석 실패: {bgm_error}")
                                                pass
                                    except Exception:
                                        # 오류 발생 시 기본값 사용
                                        audio_intensity_buffer[round(current_time, 2)] = 0.5
                                
                                chunk_index += 1
                                
                                # 오래된 강도 데이터 정리 (메모리 절약)
                                if len(audio_intensity_buffer) > 1000:
                                    # 가장 오래된 500개 제거
                                    sorted_keys = sorted(audio_intensity_buffer.keys())
                                    for key in sorted_keys[:500]:
                                        del audio_intensity_buffer[key]
                                
                                # 오래된 BGM/SFX 데이터 정리 (메모리 절약)
                                if len(bgm_sfx_buffer) > 1000:
                                    # 가장 오래된 500개 제거
                                    sorted_keys = sorted(bgm_sfx_buffer.keys())
                                    for key in sorted_keys[:500]:
                                        del bgm_sfx_buffer[key]
                                
                                # DX_Project_2와 동일: Deepgram으로 즉시 전송
                                if len(chunk_bytes) > 0:
                                    try:
                                        await connection.send_media(chunk_bytes)
                                    except Exception as send_error:
                                        # 연결이 닫혔으면 정상 종료
                                        if "1000" in str(send_error) or "ConnectionClosed" in str(type(send_error).__name__):
                                            print("[Video Analyzer] ✅ Deepgram 연결 정상 종료")
                                            break
                                        raise
                                
                                # DX_Project_2 PyAudio와 동일한 딜레이 (0.01초)
                                await asyncio.sleep(0.01)
                        except Exception as stream_error:
                            # 연결 종료는 정상적인 경우이므로 무시
                            if "1000" in str(stream_error) or "ConnectionClosed" in str(type(stream_error).__name__):
                                print("[Video Analyzer] ✅ 오디오 스트리밍 정상 종료")
                            else:
                                print(f"[Video Analyzer] ❌ 스트리밍 오류: {stream_error}")
                                import traceback
                                traceback.print_exc()
                                raise
                    
                except Exception as e:
                    print(f"[Video Analyzer] 오디오 스트리밍 오류: {e}")
                    import traceback
                    traceback.print_exc()
            
            # 오디오 스트리밍을 백그라운드 태스크로 실행 (블로킹 방지, 즉시 시작)
            stream_task = asyncio.create_task(send_audio_stream())
            
            # 메시지 수신 대기 (오디오 스트리밍과 병렬로 실행)
            # WAV 파일 길이 계산 (초 단위)
            import wave
            try:
                with wave.open(audio_path, 'rb') as wav_check:
                    wav_duration = wav_check.getnframes() / wav_check.getframerate()
                    print(f"[Video Analyzer] ⏱️ WAV 파일 길이: {wav_duration:.2f}초")
            except:
                wav_duration = 300.0  # 기본값 5분
            
            wait_start = asyncio.get_event_loop().time()
            file_ended_time = None
            
            while True:
                await asyncio.sleep(0.1)
                
                # 스트리밍 태스크가 완료되었는지 확인
                if stream_task.done():
                    if file_ended_time is None:
                        file_ended_time = asyncio.get_event_loop().time()
                        print(f"[Video Analyzer] ✅ WAV 파일 스트리밍 완료, 연결 유지 중...")
                    
                    # 파일이 끝난 후에도 최소 5초 더 대기 (비디오가 끝날 때까지)
                    if asyncio.get_event_loop().time() - file_ended_time > 5.0:
                        # 마지막 메시지가 3초 이상 전이면 종료
                        if last_message_time:
                            if asyncio.get_event_loop().time() - last_message_time > 3.0:
                                print("[Video Analyzer] ✅ 메시지 수신 종료 (3초 이상 메시지 없음)")
                                break
                        # 파일이 끝난 후 10초 이상 지나면 종료
                        if asyncio.get_event_loop().time() - file_ended_time > 10.0:
                            print("[Video Analyzer] ✅ 타임아웃 종료 (파일 종료 후 10초)")
                            break
                else:
                    # 스트리밍 중일 때는 메시지 타임아웃만 체크 (더 긴 타임아웃)
                    if last_message_time:
                        if asyncio.get_event_loop().time() - last_message_time > 10.0:
                            print("[Video Analyzer] ⚠️ 메시지 수신 타임아웃 (10초 이상 메시지 없음)")
                            break
                
                # 전체 타임아웃 (WAV 파일 길이 + 여유 시간 20초)
                max_wait_time = wav_duration + 20.0
                if asyncio.get_event_loop().time() - wait_start > max_wait_time:
                    print(f"[Video Analyzer] ✅ 전체 타임아웃 종료 ({max_wait_time:.1f}초)")
                    break
            
            # 버퍼 플러시 태스크 종료
            if buffer_flush_task and not buffer_flush_task.done():
                buffer_flush_task.cancel()
                try:
                    await buffer_flush_task
                except asyncio.CancelledError:
                    pass
            
            # 남은 버퍼 내용 전송
            if sentence_buffer.text:
                await flush_buffer_if_ready()
            
            listen_task.cancel()
            if not stream_task.done():
                stream_task.cancel()
            
    except Exception as e:
        print(f"[Video Analyzer] STT 오류: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if audio_name in video_streams:
            del video_streams[audio_name]
