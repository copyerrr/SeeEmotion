# ai_engine/caption_gui.py
# ---------------------------------------------------------
# Caption GUI Renderer (실시간 감정 + 소리 강도 기반 자막 시각화)
# ---------------------------------------------------------
# 이 모듈은 tkinter 기반으로
# "실시간 STT + 감정(emotion) + 소리 강도(intensity)" 정보를
# 시각적으로 보여주는 자막 미리보기 GUI를 제공한다.
#
# 주요 역할:
#   1) 상단 영역: BGM/효과음 표시
#   2) 하단 영역: 감정 컬러 + 말의 세기(폰트 크기) + 스피커 이름을 포함한 자막 렌더링
#   3) 외부 엔진(ver1, ver2 등)에서 전달한 text_queue를 폴링하여 실시간 출력
#
# text_queue 예:
#   { speaker, emotion, text, intensity, bgm_text, sfx_text }
#
# STYLE_CONFIG: intensity_level 등 스타일 설정
# INTENSITY_FONT_RANGE: intensity → 폰트 크기 범위
# EMOTION_COLORS: 감정별 컬러 매핑
# ---------------------------------------------------------

import tkinter as tk
import tkinter.font as tkfont
from ai_engine.kluebert_emotion import EMOTION_ICON


def run_caption_gui(text_queue, STYLE_CONFIG, INTENSITY_FONT_RANGE,
                    EMOTION_COLORS, bgm_state_provider=None):
    """
    text_queue: 실시간 자막 데이터가 들어오는 Queue (dict 형태)
    bgm_state_provider: (선택) 외부에서 BGM 상태를 가져오는 콜백 함수
    """

    # =======================
    # 1) GUI 기본 창 세팅
    # =======================
    root = tk.Tk()
    root.title("실시간 STT + Emotion + Intensity")
    root.geometry("1000x200")
    root.configure(bg="black")

    # =======================
    # 2) 상단: BGM/효과음 영역
    # =======================
    bgm_label = tk.Label(
        root,
        text="",
        bg="black",
        fg="#80CBC4",
        font=("맑은 고딕", 16, "bold"),
        anchor="w",   # 왼쪽 정렬
    )
    bgm_label.pack(fill="x")    # 위쪽에 가로로만 차지

    # 🔹 마지막 BGM/효과음 텍스트를 GUI 쪽에서 기억해두기
    current_bgm_header = ""
    current_sfx_header = ""

    # =======================
    # 3) 아래쪽: 자막 Text 영역
    # =======================
    caption_widget = tk.Text(
        root,
        wrap="word",
        bg="black",
        fg="white",
        bd=0,
        highlightthickness=0
    )
    caption_widget.pack(fill="both", expand=True)

    # 베이스 자막 스타일 (공통)
    base_font = tkfont.Font(family="맑은 고딕", size=20, weight="bold")
    caption_widget.tag_config(
        "caption_base",
        font=base_font,
        foreground="white",
        background="#333333",
        spacing1=6,
        spacing3=6,
        lmargin1=20,
        lmargin2=20,
        rmargin=20,
    )

    # =======================
    # 4) 소리 강도(intensity) → 폰트 크기 맵핑
    # =======================
    NUM_BUCKETS = 5

    def build_font_buckets():
        """
        intensity_level 기반 intensity 범위에서
        폰트 사이즈를 여러 단계로 나눠 태그 생성
        """
        level = STYLE_CONFIG["intensity_level"]   # 옛날: pitch_level
        min_s, max_s = INTENSITY_FONT_RANGE[level]

        buckets = {}
        for i in range(NUM_BUCKETS):
            # intensity 0~1 → bucket_index → 폰트 크기 매핑
            ratio = i / (NUM_BUCKETS - 1)  # 0.0 ~ 1.0
            size = int(min_s + (max_s - min_s) * ratio)

            font_obj = tkfont.Font(family="맑은 고딕", size=size, weight="bold")
            tag_name = f"size_bucket_{i}"
            caption_widget.tag_config(tag_name, font=font_obj)
            buckets[i] = tag_name

        return buckets

    FONT_BUCKET_TAGS = build_font_buckets()

    # =======================
    # 5) 감정 컬러 태그 생성
    # =======================
    for emo, col in EMOTION_COLORS.items():
        caption_widget.tag_config(emo, foreground=col)

    SPEAKER_COLORS = "#FFFFFF"
    caption_widget.tag_config("speaker_tag", foreground=SPEAKER_COLORS) 

    def poll_queue():
        nonlocal current_bgm_header, current_sfx_header

        while not text_queue.empty():
            cap = text_queue.get()

            cap_type = cap.get("type", "SPEECH")

            # ===========================================
            # 6-A) BGM / SFX 전용 이벤트 처리
            # ===========================================
            if cap_type == "BGM_SFX":
                # 이벤트 안에 있는 키만 업데이트 (없는 건 이전 값 유지)
                if "bgm_text" in cap:
                    current_bgm_header = cap.get("bgm_text") or ""
                if "sfx_text" in cap:
                    current_sfx_header = cap.get("sfx_text") or ""

                header_parts = []
                if current_bgm_header:
                    header_parts.append(f"🎵 [BGM: {current_bgm_header}]")
                if current_sfx_header:
                    header_parts.append(f"🎧 [효과음: {current_sfx_header}]")

                header_str = "   ".join(header_parts)
                bgm_label.config(text=header_str)
                # 상단만 갱신하고, 자막 본문은 건드리지 않고 다음 cap 으로
                continue

            # ===========================================
            # 6-B) 일반 STT 자막 처리
            # ===========================================
            speaker   = cap["speaker"]
            emotion   = cap["emotion"]   # 예: "fear", "joy" ...
            text      = cap["text"]
            intensity = cap.get("intensity", 0.0)
<<<<<<< Updated upstream
            bgm_text  = cap.get("bgm_text")
            sfx_text  = cap.get("sfx_text")

            # ---- 6-A) 상단 BGM/효과음 표시 ----
            top_text = bgm_text or ""
            if sfx_text:
                if top_text:
                    top_text += " / "
                top_text += sfx_text
            bgm_label.config(text=top_text)

            ########### before 기존 자막 렌더링 방식 ###########
            # ---- 6-B) 자막 본문 렌더링 ---- 
            # line = f"{speaker} [{emotion}] {text}\n"

            # # intensity(0~1) → bucket index 변환
            # bucket_idx = int(round(intensity * (NUM_BUCKETS - 1)))
            # bucket_idx = max(0, min(NUM_BUCKETS - 1, bucket_idx))  # 안전 클램핑
            # bucket_tag = FONT_BUCKET_TAGS[bucket_idx]

            # # 감정 태그 없으면 neutral 사용
            # emo_tag = emotion if emotion in EMOTION_COLORS else "neutral"

            # tags = ("caption_base", emo_tag, bucket_tag)
            # caption_widget.insert(tk.END, line, tags)
            # caption_widget.see(tk.END)
            ###############################################
            #             
=======

>>>>>>> Stashed changes
            bucket_idx = int(round(intensity * (NUM_BUCKETS - 1)))
            bucket_tag = FONT_BUCKET_TAGS[bucket_idx]

            # 이모지 (화면 표시용)
            display_emo = EMOTION_ICON.get(emotion, "")  # 예: "😨"

            # 색상 태깅용 감정 키
            emo_tag = emotion if emotion in EMOTION_COLORS else "neutral"

            # 1) 화자 prefix: [인물1]  → speaker_tag 색만 적용
            speaker_prefix = f"{speaker} "
            caption_widget.insert(
                tk.END,
                speaker_prefix,
                ("caption_base", "speaker_tag", bucket_tag),
            )

<<<<<<< Updated upstream
            # # 2) 감정 표시: [sadness]
            # emo_prefix = f"[{emotion}] "
            # caption_widget.insert(
            #     tk.END,
            #     emo_prefix,
            #     ("caption_base", emo_tag, bucket_tag),
            # )

            # 3) 실제 대사 텍스트
            main_text = f"{text}\n"
=======
            # 대사 부분: 이모지 + 텍스트
            main_text = f"({display_emo}) {text}\n"
>>>>>>> Stashed changes
            caption_widget.insert(
                tk.END,
                main_text,
                ("caption_base", emo_tag, bucket_tag),
            )

            caption_widget.see(tk.END)

        root.after(100, poll_queue)



    # 폴링 시작
    poll_queue()

    # =======================
    # 7) GUI 실행 루프
    # =======================
    root.mainloop()
