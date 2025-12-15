from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app import models, schemas
from app.database import get_db

router = APIRouter(prefix="/api/caption-settings", tags=["caption-settings"])


@router.put("/profile/{profile_id}")
def update_caption_setting(
    profile_id: int,
    setting: schemas.CaptionSettingUpdate,  # Request Body로 변경
    db: Session = Depends(get_db)
):
    """프로필의 자막 설정 업데이트 (모드 선택 시 사용)
    
    Request Body:
    - mode_id: 선택할 모드의 ID (필수)
    - apply_immediately: 즉시 적용 여부 (기본값: True)
    """
    import logging
    
    logger = logging.getLogger(__name__)
    logger.info(f"update_caption_setting 호출: profile_id={profile_id}, mode_id={setting.mode_id}")
    
    # profile 존재 확인
    profile = db.query(models.Profile).filter(models.Profile.id == profile_id).first()
    if not profile:
        logger.error(f"Profile {profile_id} not found")
        raise HTTPException(status_code=404, detail="Profile not found")
    
    # mode 존재 확인 (해당 profile의 mode인지 확인)
    mode = db.query(models.CaptionModeCustomizing).filter(
        models.CaptionModeCustomizing.id == setting.mode_id,
        models.CaptionModeCustomizing.profile_id == profile_id
    ).first()
    if not mode:
        logger.error(f"Mode {setting.mode_id} not found for profile {profile_id}")
        raise HTTPException(status_code=404, detail="Caption mode not found for this profile")
    
    logger.info(f"Mode found: {mode.mode_name} (ID: {mode.id})")
    
    # profile의 current_mode_id 업데이트
    old_mode_id = profile.current_mode_id
    profile.current_mode_id = setting.mode_id
    logger.info(f"Profile updated: profile_id={profile_id}, current_mode_id {old_mode_id} -> {setting.mode_id}")
    
    db.commit()
    db.refresh(profile)
    logger.info(f"Setting saved successfully: profile_id={profile_id}, current_mode_id={profile.current_mode_id}")
    
    return {
        "status": "success",
        "profile_id": profile_id,
        "current_mode_id": profile.current_mode_id
    }


@router.get("/profile/{profile_id}")
def get_caption_setting(profile_id: int, db: Session = Depends(get_db)):
    """프로필의 자막 설정 조회"""
    from sqlalchemy.orm import joinedload
    
    profile = db.query(models.Profile).options(
        joinedload(models.Profile.current_mode)
    ).filter(
        models.Profile.id == profile_id
    ).first()
    
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    if not profile.current_mode_id:
        return {
            "profile_id": profile_id,
            "current_mode_id": None,
            "mode": None
        }
    
    return {
        "profile_id": profile_id,
        "current_mode_id": profile.current_mode_id,
        "mode": schemas.CaptionModeResponse.from_model(profile.current_mode) if profile.current_mode else None
    }

