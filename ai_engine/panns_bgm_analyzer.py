# ai_engine/panns_bgm_analyzer.py
"""
PANNs 기반 BGM / 효과음 분석 모듈 (DRAMA / DOCUMENTARY / ENTERTAINMENT 모드 지원)

[DOCUMENTARY 모드 특징]
- 자연/환경음(파도, 물, 바람, 동물 등)이 강하면 BGM은 강제 OFF
- BGM 은 진짜 Music 계열이 확실할 때만 ON
- 자연/환경 효과음은 임팩트 없이도 점수만 되면 표시

[DRAMA 모드 특징]
- 동물/자연 계열 라벨은 SFX 후보에서 아예 제거 (동물 소리, 파도, 비 등 안 나옴)
- BGM 은 다큐보다 느슨하게 감지 (OST, 배경 음악 잘 잡기 위함)
- 효과음은 말소리와 함께 섞여도 어느 정도 잡히도록 임팩트 기준 완화

[ENTERTAINMENT(예능) 모드 특징]
- 자연/환경음은 효과음 후보에서 제외 (비, 파도, 바람 등 안 나옴)
- 리액션/효과음(웃음, 박수, 환호, 띵동 등)만 화이트리스트로 엄선
- BGM 은 다큐보다 쉽게 잡고, ON/OFF 반응도 더 빠르게
"""

import os
import sys
import ssl
import urllib.request
import time
from pathlib import Path
from contextlib import contextmanager

import numpy as np
import torch
import librosa

# ==========================================
# 0) 모드 설정 (DRAMA / DOCUMENTARY / ENTERTAINMENT)
# ==========================================
#   - dacu2 (다큐멘터리): "DOCUMENTARY"
#   - drama (드라마): "DRAMA"
#   - enter_web (예능): "ENTERTAINMENT"
MODE = os.getenv("CAPTION_CONTENT_MODE", "DOCUMENTARY").upper()
if MODE not in ("DRAMA", "DOCUMENTARY", "ENTERTAINMENT"):
    MODE = "DOCUMENTARY"  # 기본값을 DOCUMENTARY로 설정 (dacu 채널이 기본)


# ==========================================
# 1) 경로 / PANNs 설정
# ==========================================
BASE_DIR = Path(__file__).resolve().parent.parent  # DX_project_ai-engine/
PANNS_DATA = BASE_DIR / "panns_data"

CSV_PATH = PANNS_DATA / "class_labels_indices.csv"
MODEL_PATH = PANNS_DATA / "Cnn14_mAP=0.431.pth"

# panns_inference 기본 경로 override
from panns_inference import config as panns_config

panns_config.labels_csv_path = str(CSV_PATH)
panns_config.model_path = str(MODEL_PATH)

from panns_inference import AudioTagging


# ==========================================
# 2) stderr 억제 (PANNs 로딩 시 쓸데없는 로그 숨김)
# ==========================================
@contextmanager
def suppress_stderr():
    with open(os.devnull, "w") as devnull:
        old_stderr = sys.stderr
        sys.stderr = devnull
        try:
            try:
                fd_stderr = 2
                fd_dup = os.dup(fd_stderr)
                os.dup2(devnull.fileno(), fd_stderr)
                yield
            except Exception:
                yield
            finally:
                try:
                    os.dup2(fd_dup, fd_stderr)
                    os.close(fd_dup)
                except Exception:
                    pass
        finally:
            sys.stderr = old_stderr


# ==========================================
# 3) PANNs 모델 파일 존재 체크 (프로젝트 폴더 기준)
# ==========================================
def check_panns_setup():
    """필요시 모델 .pth 다운로드 / CSV 존재 여부 확인"""
    ssl._create_default_https_context = ssl._create_unverified_context

    PANNS_DATA.mkdir(parents=True, exist_ok=True)

    model_url = (
        "https://zenodo.org/record/3987831/files/"
        "Cnn14_mAP%3D0.431.pth?download=1"
    )

    if not MODEL_PATH.exists():
        print("[PANNs] 모델 다운로드 중...")
        urllib.request.urlretrieve(model_url, MODEL_PATH)

    if not CSV_PATH.exists():
        # CSV 는 사용자가 GitHub 에서 받아서 넣어둔다고 가정
        print(f"[PANNs] 경고: {CSV_PATH} 가 없습니다. "
              f"class_labels_indices.csv 를 여기에 두세요.")


check_panns_setup()


# ==========================================
# 4) 기본 설정
# ==========================================
SAMPLE_RATE = 32000           # PANNs 기본 샘플링 레이트
VOLUME_BOOST = 4.0            # 분석용 볼륨 보정 (너무 크면 clip됨)
ANALYSIS_INTERVAL = 0.25      # 최소 분석 간격(초) - 초당 4회 정도만 분석
BGM_HOLD_TIME = 1.0           # BGM 감지 끊겨도 최소 유지 시간(초)

# "화면 표시"를 위한 BGM 게이트
if MODE == "DOCUMENTARY":
    MUSIC_ON_MIN = 2.0        # 연속 2초 이상 음악이 있을 때만 켜기
    MUSIC_OFF_MIN = 1.2       # 연속 1.2초 이상 음악이 없으면 끄기
elif MODE == "ENTERTAINMENT":
    MUSIC_ON_MIN = 1.0        # 예능: BGM 자주 바뀌니까 조금 더 빠르게 ON
    MUSIC_OFF_MIN = 0.8       # 너무 오래 남지 않게 OFF도 살짝 빠르게
else:  # DRAMA
    MUSIC_ON_MIN = 1.2
    MUSIC_OFF_MIN = 1.0


# BGM 안정화: 같은 문구가 몇 번 연속 나왔을 때만 최종 확정
_BGM_STABLE_COUNT = 3

_device = "cuda" if torch.cuda.is_available() else "cpu"


# ==========================================
# 5) 라벨 → 한국어 문구 매핑
# ==========================================

# --- BGM 후보 (음악/악기 위주) ---
BGM_LABEL_TEXT = {
    "Music": "배경 음악이 흐른다",
    "Background music": "배경음악이 깔린다",
    "Dramatic music": "웅장한 음악이 흐른다",
    "Film score": "영화 같은 음악이 흐른다",
    "Soundtrack music": "테마 음악이 흐른다",
    "Theme music": "주제곡이 나온다",
    "Sad music": "슬픈 음악이 흐른다",
    "Happy music": "경쾌한 음악이 흐른다",
    "Exciting music": "박진감 넘치는 음악이 흐른다",
    "Scary music": "긴장감이 감도는 음악이 흐른다",
    "Suspense": "서스펜스 음악이 흐른다",
    "Lullaby": "잔잔한 음악이 흐른다",
    "Orchestra": "오케스트라 음악이 흐른다",
    "Choir": "합창 음악이 울려 퍼진다",

    "Electronic music": "전자음 느낌의 음악이 흐른다",
    "Video game music": "게임 같은 음악이 흐른다",
    "Musical instrument": "악기 연주가 배경으로 들린다",

    # ===== 예능에서 자주 나오는 BGM 강화 =====
    "Techno": "강한 비트의 테크노 음악이 흐른다",
    "Electronica": "일렉트로닉 사운드의 음악이 흐른다",
    "House music": "리듬감 있는 하우스 음악이 흐른다",
    "Dubstep": "강한 베이스의 덥스텝 음악이 흐른다",

    "Guitar": "기타 연주가 배경으로 깔린다",
    "Plucked string instrument": "현을 튕기는 악기 소리가 배경으로 들린다",
    "Drum": "드럼 비트가 강조된 음악이 흐른다",
    "Drum kit": "드럼 세트 연주가 배경으로 들린다",
    "Piano": "피아노 연주가 배경으로 들린다",

    "Synthesizer": "신시사이저 소리가 배경으로 깔린다",
    "Beatboxing": "입으로 비트를 만드는 비트박스 소리가 들린다",
    "New-age music": "잔잔한 뉴에이지 음악이 흐른다",
    "Singing": "노래 소리가 배경으로 들린다",
    "Mantra": "읊조리는 듯한 목소리가 배경으로 들린다",
    "Strum": "기타를 튕기는 소리가 배경으로 들린다",
}
BGM_LABELS = set(BGM_LABEL_TEXT.keys())  # 중복 없는 집합 (set) 형태로 지정한다.

# --- SFX 후보 (드라마/예능/다큐에서 자주 나올 법한 것만) ---
SFX_LABEL_TEXT = {
    # ───── 사람/실내 생활음 ─────
    "Footsteps": "발자국 소리가 들린다",
    "Door": "문이 열리거나 닫히는 소리가 난다",
    "Knock": "누군가 문을 두드린다",
    "Clapping": "손뼉을 치는 소리가 난다",
    "Applause": "박수 소리가 터져 나온다",
    "Laughter": "웃음 소리가 들린다",
    "Crying, sobbing": "흐느끼는 소리가 들린다",
    "Screaming": "비명 소리가 들린다",

    # ───── 액션/강한 소리 ─────
    "Punch": "주먹으로 때리는 둔탁한 소리가 난다",
    "Thump, thud": "쿵 하는 소리가 난다",
    "Slap, smack": "짝! 하는 소리가 난다",
    "Whoosh, swoosh, swish": "무언가 휙 지나가는 소리가 난다",
    "Explosion": "폭발음이 들린다",
    "Gunshot, gunfire": "총성이 울린다",
    "Glass": "유리가 부딪히는 소리가 난다",
    "Shatter": "유리가 깨지는 소리가 난다",
    "Smash, crash": "무언가 부서지는 소리가 난다",

    # ───── 자연/환경음 ─────
    "Rain": "물소리가 들린다",
    "Thunder": "북치는 소리가 울린다",
    "Wind": "바람 소리가 난다",
    "Water": "물이 흐르거나 튀는 소리가 난다",
    "Waves, surf": "파도 소리가 들린다",
    "Fire": "불이 타오르는 소리가 난다",

    # 동물/자연음 (범용)
    "Animal": "동물 소리가 들린다",
    "Bird": "새소리가 들린다",
    "Insect": "벌레 소리가 들린다",

    # ====== 🔔 알림/벨소리/전자음 추가 ======
    "Ding-dong": "딩동 하는 알림음이 울린다",
    "Ringtone": "휴대폰 벨소리가 울린다",
    "Telephone dialing, DTMF": "전화 키패드 소리가 난다",
    "Beep, bleep": "삐 소리가 난다",
    "Ping": "짧은 알림음이 울린다",
    "Jingle, tinkle": "맑은 벨소리가 울린다",
    "Chime": "차임벨 소리가 울린다",
    "Glockenspiel": "맑은 금속성 벨소리가 울린다",
    "Wind chime": "풍경 소리가 들린다",
    "Jingle bell": "방울 소리가 들린다",
    "Alarm": "알람이 울린다",
    "Siren": "사이렌 소리가 울린다",
    "Telephone": "전화 벨소리가 울린다",

    # # ===== 교통 / 이동 =====
    # "Vehicle": "차량이 지나가는 소리가 들린다",
    # "Car": "자동차가 움직이는 소리가 들린다",
    # "Engine": "엔진이 윙 하고 돌아가는 소리가 들린다",
    # "Boat, Water vehicle": "배가 물 위를 가르는 소리가 들린다",
    # "Train": "기차가 지나가는 소리가 들린다",

    # ===== 긴장감 / 심장 박동 =====
    "Heart sounds, heartbeat": "심장 박동 소리가 크게 들린다",
    "Heart murmur": "불규칙한 심장 박동 소리가 들린다",
    "Throbbing": "쿵쿵 울리는 맥박 같은 소리가 들린다",

    # ===== 물 / 액체 =====
    "Liquid": "액체가 출렁이는 소리가 들린다",
    "Drip": "물방울이 또르르 떨어지는 소리가 들린다",
    "Pour": "물이 쏟아지는 소리가 들린다",

    # ===== 동물 / 발자국 =====
    "Horse": "말이 달리는 소리가 들린다",
    "Clip-clop": "단단한 바닥을 구르는 발굽 소리가 들린다",
    "Domestic animals, pets": "애완동물 소리가 들린다",
    "Dog": "개 짖는 소리가 들린다",
    "Run": "누군가 급하게 뛰어가는 발소리가 들린다",

    # ===== 환경 / 기타 =====
    "Hum": "윙- 하는 기계 소리가 은은하게 들린다",
    "Rattle": "달그락거리는 소리가 들린다",
    "Patter": "후두두 떨어지는 작은 타격음이 들린다",
    "Squish": "물컹거리는 소리가 들린다",

    # ===== 시계 / 리듬 =====
    "Tick": "작게 딱딱거리는 소리가 들린다",
    "Tick-tock": "시계 초침이 째깍거리는 소리가 들린다",

    # (선택) 속삭임도 효과음처럼 보여주고 싶으면:
    "Whispering": "누군가 속삭이는 소리가 들린다",
}
SFX_LABELS = set(SFX_LABEL_TEXT.keys())

# 예능(ENTERTAINMENT) 모드에서 화면에 보여줄 효과음만 엄선
ENTERTAINMENT_SFX_WHITELIST = {
    "Laughter",   # 웃음
    "Applause",   # 박수
    "Clapping",   # 손뼉
    "Cheering",   # 환호성
    "Yell",       # 큰 외침
    "Chant",      # 구호 외침
    "Ding-dong",  # 예능식 띵동 효과음
}

# 모드별로 막고 싶은 SFX 라벨
IGNORE_SFX_DRAMA = {
    "Animal",   # 동물 소리
    # 필요하면 "Bird", "Insect" 도 여기 추가 가능
}
IGNORE_SFX_DOCUMENTARY = set()  # 다큐에선 동물 소리 살릴 거라 비워둠

# 🎉 ENTERTAINMENT(예능) 모드에서 추가로 제외할 효과음 (화이트리스트와 중복 방어용)
IGNORE_SFX_ENTER = {
    "Car",
    "Vehicle",
    "Boat, Water vehicle",
    "Animal",
}

# 🌊 자연/환경 효과음만 따로 묶기 (다큐에서 BGM보다 우선)
ENV_SFX_LABELS = {
    "Rain",
    "Thunder",
    "Wind",
    "Water",
    "Waves, surf",
    "Fire",
    "Bird",
    "Insect",
}

# DRAMA / ENTERTAINMENT 모드에서 '완전히 제외'할 자연 계열 라벨
NATURAL_LABELS = set(ENV_SFX_LABELS)

# 무시할 라벨 (환경/노이즈/스피치 등)
IGNORE_LABELS = {
    "Silence",
    "Speech",
    "Male speech, man speaking",
    "Female speech, woman speaking",
    "Child speech, kid speaking",
    "Conversation",
    "Narration, monologue",
    "Babbling",
    "Inside, small room",
    "Inside, large room or hall",
    "Outside, urban or manmade",
    "Noise",
    "Static",
    "White noise",
    "Pink noise",
    "Ambience",
}


# ==========================================
# 6) 모델 로딩
# ==========================================
with suppress_stderr():
    _model = AudioTagging(checkpoint_path=None, device=_device)

_labels = _model.labels  # index → label string


# ==========================================
# 7) 상태 (실시간용)
# ==========================================
_audio_buffer = np.zeros(0, dtype=np.float32)
_prev_rms = 0.0
_last_pred_time = 0.0
_bgm_last_detected_time = 0.0
_last_detected_bgm_text = ""

_start_time = time.time()

# 외부에서 읽어갈 현재 표시용 텍스트
current_bgm_text: str = ""
current_sfx_text: str = ""

# 게이트용 상태
_display_bgm_text: str = ""
_music_started_at = None
_music_stopped_at = None

# 이벤트/안정화용 상태
_last_event_bgm = ""
_last_event_sfx = ""
_bgm_recent: list[str] = []    # 최근 BGM 후보 히스토리

_sfx_last_time = 0.0
_SFX_HOLD_TIME = 1.2  # ★ 효과음 유지시간 (초)

# 모드별 SFX 유지 시간 튜닝
if MODE == "DRAMA":
    _SFX_HOLD_TIME = 1.0        # 드라마는 살짝 짧게 툭툭
elif MODE == "ENTERTAINMENT":
    _SFX_HOLD_TIME = 1.6        # 예능은 리액션/효과음 조금 더 길게
# DOCUMENTARY 는 1.2 그대로 사용


# ==========================================
# 8) 메인 분석 함수 (chunk 단위)
# ==========================================
def analyze_bgm_chunk(chunk: bytes, in_sr: int = 16000):
    """
    16kHz mono PCM bytes(chunk) → 내부 버퍼에 쌓고
    일정 주기(ANALYSIS_INTERVAL)마다 PANNs로 BGM / SFX 추정.

    반환값:
        - 변경 사항이 있을 때만 dict 리턴 (bgm_text / sfx_text 키 포함)
        - 아무 변화 없으면 None
    """
    global _audio_buffer, _prev_rms, _last_pred_time
    global _bgm_last_detected_time, _last_detected_bgm_text
    global current_bgm_text, current_sfx_text
    global _music_started_at, _music_stopped_at, _display_bgm_text
    global _last_event_bgm, _last_event_sfx, _bgm_recent
    global _sfx_last_time, _SFX_HOLD_TIME

    if _model is None:
        return None
    if not chunk:
        return None

    # 1) bytes -> float32 (-1 ~ 1 근사)
    samples16 = np.frombuffer(chunk, dtype=np.int16).astype(np.float32)
    if samples16.size == 0:
        return None
    samples16 /= 32768.0

    # 2) 16k -> 32k resample
    samples32 = librosa.resample(samples16, orig_sr=in_sr, target_sr=SAMPLE_RATE)
    samples32 *= VOLUME_BOOST

    # 3) 내부 버퍼에 이어 붙이고, 너무 길어지면 최근 2초만 유지
    _audio_buffer = np.concatenate([_audio_buffer, samples32])
    max_len = int(SAMPLE_RATE * 2.0)
    if _audio_buffer.size > max_len:
        _audio_buffer = _audio_buffer[-max_len:]

    now = time.time()
    elapsed = now - _start_time

    # 너무 자주 분석하지 않도록 인터벌 체크
    if elapsed - _last_pred_time < ANALYSIS_INTERVAL:
        return None

    short_window = int(SAMPLE_RATE * 0.3)  # 0.3초 구간
    if _audio_buffer.size < short_window:
        return None

    waveform_seg = _audio_buffer[-short_window:]

    # ==========================================
    # 1) RMS 및 임팩트(효과음 후보) 계산
    # ==========================================
    rms = float(np.sqrt(np.mean(waveform_seg ** 2)))

    # 기본 임팩트 기준
    is_impact = (rms > _prev_rms * 1.5) or (rms > 0.05)

    # DRAMA 모드는 임팩트 기준을 조금 더 까다롭게
    if MODE == "DRAMA":
        is_impact = (rms > _prev_rms * 2.0) or (rms > 0.08)

    _prev_rms = rms

    # ==========================================
    # 2) PANNs 입력 준비 (1초 길이로 타일링)
    # ==========================================
    target_len = SAMPLE_RATE  # 1초
    repeats = (target_len // waveform_seg.shape[0]) + 1
    tiled_seg = np.tile(waveform_seg, repeats)[:target_len]

    with torch.no_grad():
        output, _ = _model.inference(tiled_seg[None, :])

    scores = output[0]
    top_idx = np.argsort(scores)[::-1]

    best_bgm_label = None
    best_bgm_score = 0.0
    best_sfx_label = None
    best_sfx_score = 0.0

    music_cands = []           # 자막용 BGM 후보 (label, score)
    max_music_score = 0.0      # Music 포함 전체 음악 중 최대 점수

    # 상위 몇 개만 살펴본다
    for i in top_idx[:10]:
        label = _labels[i]
        score = float(scores[i])

        if label in IGNORE_LABELS:
            continue

        # DRAMA / ENTERTAINMENT 모드에서는 자연/동물 계열 라벨은 아예 후보에서 제외
        if MODE in ("DRAMA", "ENTERTAINMENT") and label in NATURAL_LABELS:
            continue

        # BGM 후보 → 리스트에 모으고, 최대 음악 점수 갱신
        if label in BGM_LABELS:
            music_cands.append((label, score))
            if score > max_music_score:
                max_music_score = score

        # SFX 후보
        if label in SFX_LABELS:

            # DRAMA: 자연/동물 소리 제외
            if MODE == "DRAMA" and label in IGNORE_SFX_DRAMA:
                continue

            # DOCUMENTARY: (현재는 별도 exclude 없음)
            if MODE == "DOCUMENTARY" and label in IGNORE_SFX_DOCUMENTARY:
                continue

            # ENTERTAINMENT: 화이트리스트만 허용 (+ 추가적으로 막을 라벨)
            if MODE == "ENTERTAINMENT":
                if label not in ENTERTAINMENT_SFX_WHITELIST:
                    continue
                if label in IGNORE_SFX_ENTER:
                    continue

            # 여기까지 통과했다면 진짜 후보
            if score > best_sfx_score:
                best_sfx_score = score
                best_sfx_label = label

    # 🎯 "표시용 BGM 라벨" 결정 (Music 제외 로직)
    caption_label = None
    if music_cands:
        labels_only = [lab for lab, _ in music_cands]

        if "Music" in labels_only and len(music_cands) > 1:
            music_cands_no_music = [(lab, sc) for lab, sc in music_cands if lab != "Music"]
            if music_cands_no_music:
                caption_label, _ = max(music_cands_no_music, key=lambda x: x[1])
            else:
                caption_label, _ = max(music_cands, key=lambda x: x[1])
        else:
            caption_label, _ = max(music_cands, key=lambda x: x[1])

    best_bgm_label = caption_label
    best_bgm_score = max_music_score

    # 최상위 라벨 (자연음 우선 판단용 - 주로 다큐에서 사용)
    top1_label = _labels[top_idx[0]]
    top1_score = float(scores[top_idx[0]])

    # ==========================================
    # 🔍 디버그 로그
    # ==========================================
    DEBUG_PANNS_RAW = True  # 필요 없으면 False 로 변경

    LOG_DIR = BASE_DIR / "logs"
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    RAW_LOG_PATH = LOG_DIR / "환승연애5_raw_log.txt"

    if DEBUG_PANNS_RAW:
        with open(RAW_LOG_PATH, "a") as f:
            f.write(f"MODE={MODE}, elapsed={elapsed:.2f}, rms={rms:.4f}\n")
            f.write("----- [RAW TOP-5] ----------------\n")
            for i in top_idx[:5]:
                label = _labels[i]
                score = float(scores[i])
                f.write(f"  {label:30s}  score={score:.3f}\n")
            f.write("------------------------------------\n")
            f.write(f"[SFX_DEBUG] best_sfx_label={best_sfx_label}, "
                    f"score={best_sfx_score:.3f}, is_impact={is_impact}\n")
            f.write("------------------------------------\n\n")

    # ==========================================
    # 모드별 threshold 설정
    # ==========================================
    if MODE == "DRAMA":
        MUSIC_MIN_SCORE = 0.12
        SFX_MIN_SCORE = 0.22
        STRONG_SFX_SCORE = 0.35
        ENV_SFX_MIN_SCORE = 0.30
        SUPPRESS_BGM_BY_SFX = False

    elif MODE == "ENTERTAINMENT":
        MUSIC_MIN_SCORE = 0.20
        SFX_MIN_SCORE = 0.18
        STRONG_SFX_SCORE = 0.30
        ENV_SFX_MIN_SCORE = 0.28
        SUPPRESS_BGM_BY_SFX = False

    else:  # DOCUMENTARY
        MUSIC_MIN_SCORE = 0.45
        SFX_MIN_SCORE = 0.18
        STRONG_SFX_SCORE = 0.40
        ENV_SFX_MIN_SCORE = 0.22
        SUPPRESS_BGM_BY_SFX = True

    # ==========================================
    # 🎯 DOCUMENTARY 모드용 BGM 필터링
    # ==========================================
    if MODE == "DOCUMENTARY":
        # 자연/환경음이 top1 이고 점수가 꽤 높으면 → BGM 강제 OFF
        if top1_label in ENV_SFX_LABELS and top1_score >= 0.30:
            best_bgm_label = None
            best_bgm_score = 0.0

        # 자연 SFX 가 BGM 보다 훨씬 강하면 BGM OFF
        if SUPPRESS_BGM_BY_SFX:
            if best_sfx_label in ENV_SFX_LABELS and best_sfx_score >= best_bgm_score * 0.8:
                best_bgm_label = None
                best_bgm_score = 0.0

    # Music 계열 자체가 약하면 BGM OFF
    if best_bgm_score < MUSIC_MIN_SCORE:
        best_bgm_label = None
        best_bgm_score = 0.0

    # ==========================================
    # 9) BGM 문구 안정화 로직
    # ==========================================
    temp_bgm_raw = ""

    if best_bgm_label and best_bgm_score >= MUSIC_MIN_SCORE:
        temp_bgm_raw = BGM_LABEL_TEXT.get(best_bgm_label, "")
        if temp_bgm_raw:
            _bgm_last_detected_time = elapsed
            _last_detected_bgm_text = temp_bgm_raw

    # 최근 히스토리 업데이트
    if temp_bgm_raw:
        _bgm_recent.append(temp_bgm_raw)
        if len(_bgm_recent) > _BGM_STABLE_COUNT:
            _bgm_recent.pop(0)
    else:
        _bgm_recent.clear()

    # N번 연속 같은 값일 때만 안정된 BGM 으로 사용
    temp_bgm = ""
    if _bgm_recent:
        if len(_bgm_recent) == _BGM_STABLE_COUNT and len(set(_bgm_recent)) == 1:
            temp_bgm = _bgm_recent[0]

    # 감지가 끊겨도 BGM_HOLD_TIME 만큼은 유지
    if not temp_bgm:
        if elapsed - _bgm_last_detected_time < BGM_HOLD_TIME:
            temp_bgm = _last_detected_bgm_text
        else:
            temp_bgm = ""

    # ==========================================
    # 10) 화면 표시용 BGM 게이트 (ON / OFF 딜레이)
    # ==========================================
    if temp_bgm:
        _music_stopped_at = None
        if _music_started_at is None:
            _music_started_at = elapsed

        if elapsed - _music_started_at >= MUSIC_ON_MIN:
            _display_bgm_text = temp_bgm
    else:
        _music_started_at = None
        if _music_stopped_at is None:
            _music_stopped_at = elapsed

        if elapsed - _music_stopped_at >= MUSIC_OFF_MIN:
            _display_bgm_text = ""

    current_bgm_text = _display_bgm_text

    # ==========================================
    # 11) 효과음(SFX) 최종 선택 (자연/환경음은 모드에 따라 처리)
    # ==========================================
    new_sfx = ""  # 이번 프레임에서 새로 감지된 효과음 문구

    if best_sfx_label:
        is_env_sfx = best_sfx_label in ENV_SFX_LABELS

        # ------------------------
        # DOCUMENTARY 모드
        # ------------------------
        if MODE == "DOCUMENTARY":
            if is_env_sfx:
                # 자연/환경 소리: 임팩트 없어도 점수만 되면 표시
                if best_sfx_score >= ENV_SFX_MIN_SCORE:
                    new_sfx = SFX_LABEL_TEXT.get(best_sfx_label, "")
            else:
                # 일반 효과음: 임팩트 or 높은 점수
                if best_sfx_score >= SFX_MIN_SCORE:
                    if is_impact or best_sfx_score >= STRONG_SFX_SCORE:
                        new_sfx = SFX_LABEL_TEXT.get(best_sfx_label, "")

        # ------------------------
        # ENTERTAINMENT (예능) 모드
        # ------------------------
        elif MODE == "ENTERTAINMENT":

            # 1) 자연음/환경음 절대 금지
            if is_env_sfx:
                new_sfx = ""

            # 2) 엔터용 별도 ignore 리스트도 절대 금지
            elif best_sfx_label in IGNORE_SFX_ENTER:
                new_sfx = ""

            # 3) 그 외 라벨만 점수 기반으로 허용
            else:
                if best_sfx_score >= SFX_MIN_SCORE:
                    if is_impact or best_sfx_score >= STRONG_SFX_SCORE:
                        new_sfx = SFX_LABEL_TEXT.get(best_sfx_label, "")

        # ------------------------
        # DRAMA 모드
        # ------------------------
        else:  # MODE == "DRAMA"
            # DRAMA 모드는 대부분 자연음이 앞단에서 컷됨
            if best_sfx_score >= SFX_MIN_SCORE:
                if is_impact or best_sfx_score >= STRONG_SFX_SCORE:
                    new_sfx = SFX_LABEL_TEXT.get(best_sfx_label, "")

    # ==========================================
    # 12) SFX 표시 + HOLD TIME 적용
    # ==========================================
    if new_sfx:
        current_sfx_text = new_sfx
        _sfx_last_time = elapsed
    else:
        if elapsed - _sfx_last_time >= _SFX_HOLD_TIME:
            current_sfx_text = ""

    # ==========================================
    # 13) 이벤트 딕셔너리 생성 (변경 있을 때만)
    # ==========================================
    event = {}

    if current_bgm_text != _last_event_bgm:
        event["bgm_text"] = current_bgm_text
        _last_event_bgm = current_bgm_text

    if current_sfx_text != _last_event_sfx:
        event["sfx_text"] = current_sfx_text
        _last_event_sfx = current_sfx_text

    _last_pred_time = elapsed

    return event or None
