# ai_engine/live_runner.py
# ---------------------------------------------------------
# 실시간 마이크 입력 → Deepgram STT → 감정/강도/BGM 분석 → GUI 자막
# video_runner.py 와 동일한 파이프라인, 입력만 마이크로 바뀐 버전
# ---------------------------------------------------------

import os
import queue
import threading
from pathlib import Path
import sys

import sounddevice as sd
from deepgram import DeepgramClient, LiveTranscriptionEvents, LiveOptions
from dotenv import load_dotenv

# ---------------------------------------------------------
# 🔥 0) 패키지 루트(BASE_DIR)를 sys.path 에 추가
# ---------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

# ---------------------------------------------------------
# 1) ai_engine 내부 모듈 import
# ---------------------------------------------------------
from ai_engine.config import STYLE_CONFIG, INTENSITY_FONT_RANGE
from ai_engine.text_spacing import fix_spacing
from ai_engine.audio_intensity import update_energy, get_energy, intensity_from_energy
from ai_engine.emotion_wrapper import analyze_emotion
from ai_engine.style_palette import get_palette
from ai_engine.caption_gui import run_caption_gui
import ai_engine.bgm_analyzer as bgm


# ---------------------------------------------------------
# 2) env 로딩
# ---------------------------------------------------------

load_dotenv(BASE_DIR / ".env")

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
if not DEEPGRAM_API_KEY:
    raise RuntimeError("DEEPGRAM_API_KEY missing")

# Deepgram 준비(초기화)
dg = DeepgramClient(DEEPGRAM_API_KEY)
dg_connection = dg.listen.websocket.v("1")

# 자막 데이터를 전달하는 큐
text_queue = queue.Queue()

# ---------------------------------------------------------
# 3) Deepgram STT 콜백
# ---------------------------------------------------------
def on_message(connection, result, **kwargs):

    if getattr(result, "type", None) == "SpeechStarted":
        return

    alt = result.channel.alternatives[0]
    raw_text = alt.transcript
    if not raw_text:
        return

    # 1) 띄어쓰기 보정
    text = fix_spacing(raw_text)

    # 2) 화자 ID (speaker diarization)
    speaker = None
    if getattr(alt, "words", None):
        last = alt.words[-1]
        speaker = getattr(last, "speaker", None)

    prefix = f"[인물{speaker}]" if speaker is not None else "[S?]"

    # 3) 감정 분석 + 팔레트 기반 색상
    emotion, conf, color = analyze_emotion(text)

    # 4) 오디오 음량 기반 intensity 계산 (0 ~ 1)
    rms = get_energy()
    intensity = intensity_from_energy(rms)

    # 5) BGM / sfx 라벨 -> 텍스트 매핑
    bgm_label = bgm.current_bgm_label
    sfx_label = bgm.current_sfx_label

    bgm_text = bgm.BGM_TEXT_MAP.get(bgm_label)
    sfx_text = bgm.SFX_TEXT_MAP.get(sfx_label)

    print("[DEBUG BGM RAW]", bgm_label, sfx_label)
    print("[DEBUG BGM TEXT]", bgm_text, sfx_text)

    # 6) GUI 로 넘길 payload 구성
    caption = {
        "speaker": prefix,
        "emotion": emotion,
        "text": text,
        "intensity": intensity,
        "bgm_text": bgm_text,
        "sfx_text": sfx_text,
    }

    print("[LIVE]", f"{prefix} [{emotion}] {text}")

    text_queue.put(caption)


dg_connection.on(LiveTranscriptionEvents.Transcript, on_message)

# ---------------------------------------------------------
# 4) 마이크 오디오 스트리밍 → Deepgram
# ---------------------------------------------------------
def mic_stream():
    """실시간 마이크 → Deepgram Websocket"""
    def callback(indata, frames, time, status):
        # indata 가 CFFI buffer 라 -> bytes 로 변환
        chunk = bytes(indata)

        update_energy(chunk) # 1) 소리 세기(RMS) 업데이트
        bgm.analyze_bgm_mood(chunk) # 2) BGM / SFX 분석
        dg_connection.send(chunk) # 3) Deepgram 으로 전송

    print("🎤 마이크 스트리밍 시작")
    with sd.RawInputStream(samplerate=16000, blocksize=4096,
                           dtype='int16', channels=1, callback=callback):
        threading.Event().wait()  # 메인 스레드가 종료되지 않게 유지

# ---------------------------------------------------------
# 5) 메인 실행
# ---------------------------------------------------------
if __name__ == "__main__":

    dg_connection.start(
        LiveOptions(
            model="nova-3",
            language="ko",
            encoding="linear16",
            sample_rate=16000,
            channels=1,
            diarize=True,
            vad_events=True,
            interim_results=False,
            smart_format=True,
        )
    )

    worker = threading.Thread(target=mic_stream, daemon=True)
    worker.start()

    run_caption_gui(
        text_queue,
        STYLE_CONFIG,
        INTENSITY_FONT_RANGE,
        get_palette(STYLE_CONFIG["intensity_level"])
    )





#### 🔥 실행 방법 ###
# python ai_engine/live_runner.py
# # 또는
# python -m ai_engine.live_runner : ai_engine 패키지 안에 live_runner 모듈을 실행해줘
