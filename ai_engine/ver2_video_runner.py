# ai_engine/ver2_video_runner.py
# ---------------------------------------------------------
# Video → STT → Emotion → Intensity → BGM/SFX → Caption GUI (ver2)
#   - ffmpeg 로 mp4에서 오디오 추출
#   - Deepgram 실시간 STT
#   - 띄어쓰기 보정, 감정 분석, 음량 기반 강도, BGM/효과음 태깅
#   - 최종 결과는 caption_gui.run_caption_gui 에게 전달
# ---------------------------------------------------------

import os
import sys
import threading
import queue
import subprocess
from pathlib import Path

from deepgram import DeepgramClient, LiveTranscriptionEvents, LiveOptions
from dotenv import load_dotenv

# =====================================================================
# 0) 프로젝트 루트 경로를 sys.path 에 추가
#    (DX_project_ai-engine/ 가 import 검색 경로에 들어가도록)
# =====================================================================
BASE_DIR = Path(__file__).resolve().parent.parent  # .../DX_project_ai-engine
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

# =====================================================================
# 1) ai_engine 내부 모듈 import
# =====================================================================
from ai_engine.config import STYLE_CONFIG, INTENSITY_FONT_RANGE
from ai_engine.style_palette import PALETTES
from ai_engine.text_spacing import fix_spacing
from ai_engine.audio_intensity import (
    update_energy,
    get_energy,
    intensity_from_energy,
)
from ai_engine.emotion_wrapper import analyze_emotion
# from ai_engine.bgm_analyzer import (
#     analyze_bgm_mood,
#     BGM_TEXT_MAP,
#     SFX_TEXT_MAP,
#     current_bgm_label,
#     current_sfx_label,
# )

from ai_engine.speaker_diarization import get_major_speaker, map_speaker_id, stabilize_speaker
from ai_engine.caption_gui import run_caption_gui
# from ai_engine import panns_bgm_analyzer

# =====================================================================
# 2) Deepgram 설정
# =====================================================================
load_dotenv(BASE_DIR / ".env")

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
if not DEEPGRAM_API_KEY:
    raise RuntimeError("DEEPGRAM_API_KEY 가 .env 에 없습니다.")

dg = DeepgramClient(DEEPGRAM_API_KEY)
dg_connection = dg.listen.websocket.v("1")

# GUI 스레드로 메시지를 넘길 큐
text_queue: "queue.Queue[dict]" = queue.Queue()

# 팔레트 선택 (1/2/3)
PALETTE_LEVEL = STYLE_CONFIG.get("palette_level", 2)
EMOTION_COLORS = PALETTES[PALETTE_LEVEL]


# =====================================================================
# 3) Deepgram Transcript 콜백
# =====================================================================
def on_message(connection, result, **kwargs):
    """Deepgram 에서 Transcript 이벤트가 올 때마다 호출되는 콜백"""

    # 말 시작 이벤트는 그냥 무시
    if getattr(result, "type", None) == "SpeechStarted":
        return

    alt = result.channel.alternatives[0]
    raw_text = alt.transcript
    if not raw_text:
        return

    # -----------------------------------------------------------------
    # (1) 띄어쓰기 보정
    # -----------------------------------------------------------------
    text = fix_spacing(raw_text)

    # -----------------------------------------------------------------
    # (2) 화자 ID (speaker diarization)
    # -----------------------------------------------------------------
    # 2-1) 화자: 해당 segment 내에서 가장 많이 등장한 speaker id
    raw_speaker_id = get_major_speaker(alt)      # ex) 0, 1, 2, ...
    # 2-2) 텍스트 길이, 이전 화자 고려해서 안정화된 화자 번호 리턴
    mapped_speaker = stabilize_speaker(raw_speaker_id, text)  # ex) 1, 2, 3, ...
    

    # 화면에 보여줄 prefix 적용 여부
    show_speaker = STYLE_CONFIG.get("show_speaker_prefix", True)

    if show_speaker and mapped_speaker is not None:
        prefix = f"[인물{mapped_speaker}]"
    else:
        prefix = ""   # 기본은 안 보이게


    # -----------------------------------------------------------------
    # (3) 감정 분석 + 팔레트 기반 색상
    #     - emotion_wrapper.analyze_emotion(text, palette_level)
    #     - return: (emotion_label, confidence, hex_color)
    # -----------------------------------------------------------------
    palette_level = STYLE_CONFIG.get("palette_level", 2)
    emotion_on = STYLE_CONFIG.get("emotion_on", True)

    if emotion_on:
        # 감정 기반 팔레트 적용
        emotion, conf, color_hex = analyze_emotion(text, palette_level)
    else:
        # 감정 색 끈 모드 (다큐/뉴스용)
        emotion = "neutral"
        conf = 1.0
        color_hex = "#FFFFFF"  # ✅ 눈에 확 보이는 노란색
    

    # -----------------------------------------------------------------
    # (4) 오디오 음량 기반 intensity 계산 (0 ~ 1)
    # -----------------------------------------------------------------
    rms = get_energy()
    intensity = intensity_from_energy(rms)

    # # -----------------------------------------------------------------
    # # (5) BGM / 효과음 텍스트 (PANNs 결과 그대로 사용)
    # # -----------------------------------------------------------------
    # bgm_text = panns_bgm_analyzer.current_bgm_text
    # sfx_text = panns_bgm_analyzer.current_sfx_text

    # print("[DEBUG BGM TEXT]", bgm_text, sfx_text)
    

    # -----------------------------------------------------------------
    # (6) GUI 로 넘길 payload 구성
    # -----------------------------------------------------------------
    cap = {
        "speaker": prefix,
        "emotion": emotion,
        "color": color_hex,
        "text": text,
        "intensity": intensity,
        # "bgm_text": bgm_text,
        # "sfx_text": sfx_text,
    }

    # 디버깅용 로그
    print(
        "[LIVE]",
        f"{prefix} [{emotion}] {text} "
        f"(conf={conf:.3f}, int={intensity:.2f})",
    )


    # GUI 스레드에 전달
    text_queue.put(cap)


# 콜백 등록
dg_connection.on(LiveTranscriptionEvents.Transcript, on_message)


# =====================================================================
# 4) FFmpeg: Video → PCM streaming + 에너지/BGM 분석
# =====================================================================
VIDEO_PATH = os.path.join("data_samples", "인사이드아웃.mp4")


def video_stream():
    """ffmpeg 로 mp4 → 16kHz mono PCM 을 뽑아서
    - audio_intensity.update_energy
    - bgm_analyzer.analyze_bgm_mood
    - Deepgram 으로 전송
    을 동시에 수행한다.
    """
    if not os.path.exists(VIDEO_PATH):
        raise FileNotFoundError(f"VIDEO_PATH 를 찾을 수 없음: {VIDEO_PATH}")

    cmd = [
        "ffmpeg",
        "-re",
        "-i",
        VIDEO_PATH,
        "-vn",
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-ar",
        "16000",
        "-ac",
        "1",
        "pipe:1",
    ]

    print("🎬 ffmpeg 시작:", " ".join(cmd))

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=4096,
    )

    try:
        while True:
            chunk = proc.stdout.read(4096)
            if not chunk:
                break

            # 1) 강도(RMS) 업데이트
            update_energy(chunk)

            # 2) BGM / SFX 분석 (PANNs 기반) + 이벤트 수신
            event = panns_bgm_analyzer.analyze_bgm_chunk(chunk, in_sr=16000)

            if event is not None:
                # BGM/SFX 전용 캡션 payload
                cap = {"type": "BGM_SFX"}
                # 키가 있을 때만 넣기 (bgm/sfx 각각 ON/OFF 이벤트 포함)
                if "bgm_text" in event:
                    cap["bgm_text"] = event["bgm_text"]
                if "sfx_text" in event:
                    cap["sfx_text"] = event["sfx_text"]

                # 디버깅용
                print("[BGM_SFX_EVENT]", cap)

                text_queue.put(cap)


            # 3) Deepgram 으로 전송
            dg_connection.send(chunk)

    finally:
        proc.terminate()
        proc.wait()
        dg_connection.finish()
        print("⛔ 오디오 스트리밍 종료")


# =====================================================================
# 5) 메인 실행부
# =====================================================================
if __name__ == "__main__":
    # 1) Deepgram 세션 시작
    print("[DEBUG] ver2_video_runner main 시작")

    # 여기서 import 하면 전역으로 잡혀서 video_stream에서도 사용 가능
    from ai_engine import panns_bgm_analyzer
    print("[DEBUG] panns_bgm_analyzer import 완료")

    dg_connection.start(
        LiveOptions(
            model="nova-3",
            language="ko",
            encoding="linear16",
            sample_rate=16000,
            channels=1,
            smart_format=True,
            interim_results=False,
            vad_events=True,
            endpointing= 100,        # 무음 or 말 멈춤 이후 몇 ms 뒤를 한 문장의 끝으로 볼지 정하는 값
            diarize=True,            # 화자 구분 on
            # num_speakers=2
            # utterance_end_ms=1000,  # 속삭임 강화
            # vad_turnoff_silence_ms=300,
            # vad_threshold=0.2,     # default는 0.5쯤 / 낮출수록 작은 소리도 잡힘
        )
    )

    # 2) ffmpeg 스트리밍 스레드 시작
    worker = threading.Thread(target=video_stream, daemon=True)
    worker.start()

    # 3) 캡션 GUI 실행 (메인 스레드)
    run_caption_gui(text_queue, STYLE_CONFIG, INTENSITY_FONT_RANGE, EMOTION_COLORS)
