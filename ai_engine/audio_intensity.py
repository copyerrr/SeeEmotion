# ai_engine/audio_intensity.py
# ---------------------------------------------------------
# Audio Intensity Engine (볼륨 기반 말의 세기 계산 모듈) 소리 강도 
# ---------------------------------------------------------
# 이 모듈은 실시간 오디오 PCM 데이터를 받아서 "말의 세기(Intensity)"를
# 0~1 범위로 계산하는 기능을 제공한다.
#
# 주요 기능:
#   1) 오디오 청크(chunk)에서 RMS(Root Mean Square) 에너지 계산
#   2) 최근 RMS 값들을 버퍼에 저장하여 평균 기반 smoothing 수행
#      → 갑작스러운 피크(예: 박수/폭소) 때문에 자막 폰트가 튀는 것을 방지
#   3) 가장 큰 RMS(max_energy)를 기준으로 정규화하여 0~1 intensity 생성
#   4) intensity는 caption_gui 등에서 폰트 크기 조절에 사용됨
#
# 이 파일은 오직 "볼륨 기반 말의 세기"만을 계산하며,
# Pitch(음 높낮이)는 계산하지 않는다.
#
# 전체 처리 흐름 예:
#   update_energy(chunk)        # 오디오 → RMS
#   rms = get_energy()          # smoothing 된 RMS
#   intensity = intensity_from_energy(rms)
#   → intensity(0~1)를 자막 엔진이 사용
#
# 이 모듈은 GUI나 STT와 직접 연결되지 않으며,
# intensity 값만 외부로 전달되거나 text_queue 입력에 포함된다.
# ---------------------------------------------------------

import numpy as np
from collections import deque
import threading

# ====== 오디오 강도(RMS) 계산용 ======

# 최근 RMS 에너지를 저장하는 링버퍼(최대 50개 저장)
# → 순간적인 피크 때문에 흔들리지 않도록 평균 기반으로 안정적인 강도 산출
energy_buffer = deque(maxlen=50)

# 쓰레드 환경에서 여러 곳에서 update_energy를 호출하므로 동시 접근 보호
energy_lock = threading.Lock()

# 지금까지 관측된 RMS 값 중 가장 큰 값 (정규화 기준치)
# → 처음엔 매우 작은 값으로 초기화되어 점차 업데이트됨
max_energy = 1e-6

def update_energy(chunk: bytes):
    """
    오디오 청크에서 RMS 에너지 계산
    마이크 또는 영상 오디오에서 받은 오디오 chunk(PCM bytes)로부터
    RMS 에너지 값을 계산하고 버퍼에 저장함.
    또한 가장 높은 RMS(max_energy)를 갱신하여 정규화 기준을 업데이트함.
    """

    global max_energy
    if not chunk:
        return

    samples = np.frombuffer(chunk, dtype=np.int16).astype(np.float32)

    if samples.size == 0:
        return

    rms = float(np.sqrt(np.mean(samples ** 2))) # 오디오 청크의 RMS 에너지 계산

    # 최대 에너지 갱신 → 이후 intensity 계산 시 정규화 기준
    if rms > max_energy:
        max_energy = rms
    
    # 버퍼에 RMS 저장 (동시 접근 안전)
    with energy_lock:
        energy_buffer.append(rms)

def get_energy() -> float:
    """최근 RMS 평균 리턴
    (말소리의 순간 피크를 제거하고 부드러운 강도 값을 얻기 위한 smoothing 역할)
    """
    with energy_lock:
        if not energy_buffer:
            return 0.0
        return float(np.mean(energy_buffer))

def intensity_from_energy(rms: float) -> float:
    """rms(0~max_energy)를 0~1 범위로 정규화"""
    global max_energy
    if max_energy <= 0:
        return 0.0
    norm = rms / max_energy  # RMS 정규화: 0~1 사이
    norm = norm ** 0.5  # sqrt 적용으로 강도 변화가 더 자연스럽게 보이도록 조정
    return float(max(0.0, min(1.0, norm)))
