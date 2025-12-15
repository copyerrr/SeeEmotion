from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session
from typing import List, Optional
from app import models, schemas
from app.database import get_db

router = APIRouter(prefix="/api/caption-modes", tags=["caption-modes"])


# ==================== 변환 함수 ====================
def convert_sound_pitch_to_font_level(sound_pitch: Optional[str]) -> int:
    """소리 높낮이 문자열을 숫자로 변환"""
    if not sound_pitch:
        return 0
    mapping = {
        "없음": 0,
        "1단계": 1,
        "2단계": 2,
        "3단계": 3
    }
    return mapping.get(sound_pitch, 0)


def convert_emotion_color_to_color_level(emotion_color: Optional[str]) -> int:
    """감정 색상 문자열을 숫자로 변환"""
    if not emotion_color:
        return 0
    mapping = {
        "없음": 0,
        "빨강": 1,
        "파랑": 2,
        "초록": 3
    }
    return mapping.get(emotion_color, 0)


def get_default_mode_name(selected_mode: Optional[str]) -> str:
    """선택한 모드 타입에 따른 기본 모드 이름"""
    if not selected_mode:
        return "커스텀"
    mapping = {
        "none": "없음",
        "movie": "영화",
        "documentary": "다큐멘터리",
        "variety": "예능"
    }
    return mapping.get(selected_mode, "커스텀")


# ==================== 엔드포인트 ====================
@router.post("/", response_model=schemas.CaptionModeResponse)
def create_caption_mode(mode: schemas.CaptionModeCreate, db: Session = Depends(get_db)):
    """자막 모드 생성 (기본 엔드포인트 - 하위 호환성 유지)"""
    # profile_id가 있으면 존재 확인
    if mode.profile_id:
        profile = db.query(models.Profile).filter(models.Profile.id == mode.profile_id).first()
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
    
    db_mode = models.CaptionModeCustomizing(**mode.model_dump())
    db.add(db_mode)
    db.commit()
    db.refresh(db_mode)
    return schemas.CaptionModeResponse.from_model(db_mode)


@router.post("/custom", response_model=schemas.CaptionModeResponse)
def create_custom_mode(
    mode_data: schemas.CaptionModeCreateCustom,
    db: Session = Depends(get_db)
):
    """커스텀 모드 생성 (프론트엔드 변환 로직 제거 - 백엔드에서 처리)"""
    import logging
    logger = logging.getLogger(__name__)
    
    # 1. Profile 존재 확인
    profile = db.query(models.Profile).filter(models.Profile.id == mode_data.profile_id).first()
    if not profile:
        logger.error(f"Profile {mode_data.profile_id} not found")
        raise HTTPException(status_code=404, detail="Profile not found")
    
    # 2. 모드 이름 결정
    mode_name = mode_data.mode_name
    if not mode_name or mode_name.strip() == "":
        if mode_data.selected_mode:
            mode_name = get_default_mode_name(mode_data.selected_mode)
        else:
            mode_name = "커스텀"
    
    # 3. 데이터 변환 (프론트엔드에서 처리하던 로직을 백엔드로 이동)
    font_level = convert_sound_pitch_to_font_level(mode_data.sound_pitch)
    color_level = convert_emotion_color_to_color_level(mode_data.emotion_color)
    
    logger.info(f"Creating custom mode: profile_id={mode_data.profile_id}, mode_name={mode_name}, "
                f"sound_pitch={mode_data.sound_pitch}→font_level={font_level}, "
                f"emotion_color={mode_data.emotion_color}→color_level={color_level}")
    
    # 4. 기본값 설정 및 모드 생성
    db_mode = models.CaptionModeCustomizing(
        profile_id=mode_data.profile_id,
        mode_name=mode_name,
        is_empathy_on=False,
        fontSize_toggle=False,
        fontColor_toggle=False,
        font_level=font_level,
        color_level=color_level,
        speaker=mode_data.speaker,
        bgm=mode_data.bgm,
        effect=mode_data.effect
    )
    
    db.add(db_mode)
    db.commit()
    db.refresh(db_mode)
    logger.info(f"Custom mode created successfully: mode_id={db_mode.id}")
    return schemas.CaptionModeResponse.from_model(db_mode)


@router.get("/", response_model=List[schemas.CaptionModeResponse])
def get_caption_modes(
    profile_id: Optional[int] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """자막 모드 조회 (프로필별 필터링 지원)"""
    import logging
    logger = logging.getLogger(__name__)
    
    query = db.query(models.CaptionModeCustomizing)
    
    if profile_id:
        query = query.filter(models.CaptionModeCustomizing.profile_id == profile_id)
        logger.info(f"Fetching modes for profile_id: {profile_id}")
    
    modes = query.offset(skip).limit(limit).all()
    logger.info(f"Found {len(modes)} modes")
    # 역변환하여 응답
    return [schemas.CaptionModeResponse.from_model(mode) for mode in modes]


@router.get("/{mode_id}", response_model=schemas.CaptionModeResponse)
def get_caption_mode(mode_id: int, db: Session = Depends(get_db)):
    """자막 모드 조회 - 역변환 포함"""
    mode = db.query(models.CaptionModeCustomizing).filter(models.CaptionModeCustomizing.id == mode_id).first()
    if not mode:
        raise HTTPException(status_code=404, detail="Caption mode not found")
    return schemas.CaptionModeResponse.from_model(mode)


@router.put("/{mode_id}", response_model=schemas.CaptionModeResponse)
def update_caption_mode(mode_id: int, mode_update: schemas.CaptionModeUpdate, db: Session = Depends(get_db)):
    """자막 모드 업데이트 (변환 로직 백엔드에서 처리)"""
    import logging
    logger = logging.getLogger(__name__)
    
    db_mode = db.query(models.CaptionModeCustomizing).filter(models.CaptionModeCustomizing.id == mode_id).first()
    if not db_mode:
        raise HTTPException(status_code=404, detail="Caption mode not found")
    
    update_data = mode_update.model_dump(exclude_unset=True)
    
    # sound_pitch가 있으면 font_level로 변환
    if 'sound_pitch' in update_data:
        sound_pitch = update_data.pop('sound_pitch')
        font_level = convert_sound_pitch_to_font_level(sound_pitch)
        update_data['font_level'] = font_level
        # sound_pitch가 '없음'이 아니면 fontSize_toggle도 True로 설정
        if sound_pitch and sound_pitch != '없음':
            update_data['fontSize_toggle'] = True
        logger.info(f"sound_pitch '{sound_pitch}' → font_level {font_level}")
    
    # emotion_color가 있으면 color_level로 변환
    if 'emotion_color' in update_data:
        emotion_color = update_data.pop('emotion_color')
        color_level = convert_emotion_color_to_color_level(emotion_color)
        update_data['color_level'] = color_level
        # emotion_color가 '없음'이 아니면 fontColor_toggle도 True로 설정
        if emotion_color and emotion_color != '없음':
            update_data['fontColor_toggle'] = True
        logger.info(f"emotion_color '{emotion_color}' → color_level {color_level}")
    
    # 나머지 필드 업데이트
    for field, value in update_data.items():
        if hasattr(db_mode, field):
            setattr(db_mode, field, value)
        else:
            logger.warning(f"Field '{field}' not found in CaptionModeCustomizing model")
    
    db.commit()
    db.refresh(db_mode)
    logger.info(f"Mode {mode_id} updated successfully")
    return schemas.CaptionModeResponse.from_model(db_mode)


@router.put("/{mode_id}/default-settings")
def update_mode_default_settings(
    mode_id: int,
    settings: schemas.ModeDefaultSettingsUpdate,
    db: Session = Depends(get_db)
):
    """모드별 기본 설정 업데이트 (프론트엔드 변환 로직 제거)"""
    import logging
    logger = logging.getLogger(__name__)
    
    db_mode = db.query(models.CaptionModeCustomizing).filter(models.CaptionModeCustomizing.id == mode_id).first()
    if not db_mode:
        raise HTTPException(status_code=404, detail="Caption mode not found")
    
    # 모드별 기본 설정 (백엔드에서 처리)
    mode_type = settings.mode_type
    if mode_type == 'movie':
        # 드라마/영화: font level 2, color level 2, font on, color on, 화자 on, 배경음 on, 효과음 on
        db_mode.fontSize_toggle = True
        db_mode.fontColor_toggle = True
        db_mode.speaker = True
        db_mode.bgm = True
        db_mode.effect = True
        db_mode.font_level = 2
        db_mode.color_level = 2
    elif mode_type == 'documentary':
        # 다큐: font off, color off, 화자 off, 배경음 on, 효과음 on
        db_mode.fontSize_toggle = False
        db_mode.fontColor_toggle = False
        db_mode.speaker = False
        db_mode.bgm = True
        db_mode.effect = True
        db_mode.font_level = 0
        db_mode.color_level = 0
    elif mode_type == 'variety':
        # 예능: font level 2, color level 2, font on, color on, 화자 off, 배경음 on, 효과음 off
        db_mode.fontSize_toggle = True
        db_mode.fontColor_toggle = True
        db_mode.speaker = False
        db_mode.bgm = True
        db_mode.effect = False
        db_mode.font_level = 2
        db_mode.color_level = 2
    else:
        raise HTTPException(status_code=400, detail=f"Invalid mode_type: {mode_type}")
    
    db.commit()
    db.refresh(db_mode)
    logger.info(f"Mode {mode_id} default settings updated for {mode_type}")
    return schemas.CaptionModeResponse.from_model(db_mode)


@router.delete("/{mode_id}")
def delete_caption_mode(mode_id: int, db: Session = Depends(get_db), response: Response = Response()):
    """자막 모드 삭제"""
    try:
        db_mode = db.query(models.CaptionModeCustomizing).filter(models.CaptionModeCustomizing.id == mode_id).first()
        if not db_mode:
            # CORS 헤더 추가
            response.headers["Access-Control-Allow-Origin"] = "*"
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "*"
            raise HTTPException(status_code=404, detail="Caption mode not found")
        
        # 해당 모드를 참조하는 Profile의 current_mode_id를 None으로 설정
        profiles_using_mode = db.query(models.Profile).filter(models.Profile.current_mode_id == mode_id).all()
        for profile in profiles_using_mode:
            profile.current_mode_id = None
        
        # Profile 업데이트를 먼저 커밋
        if profiles_using_mode:
            db.commit()
        
        db.delete(db_mode)
        db.commit()
        
        # CORS 헤더 명시적 추가
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "*"
        
        return {"message": "Caption mode deleted successfully", "id": mode_id}
    except HTTPException:
        # HTTPException은 그대로 전달 (이미 CORS 헤더 설정됨)
        raise
    except Exception as e:
        db.rollback()
        # CORS 헤더 추가
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "*"
        raise HTTPException(status_code=500, detail=f"Failed to delete caption mode: {str(e)}")

