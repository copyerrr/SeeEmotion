from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app import models, schemas
from app.database import get_db

router = APIRouter(prefix="/api/profiles", tags=["profiles"])


@router.post("/", response_model=schemas.ProfileResponse)
def create_profile(profile: schemas.ProfileCreate, db: Session = Depends(get_db)):
    """프로필 생성 및 기본 모드 자동 생성"""
    # account 존재 확인
    account = db.query(models.Account).filter(models.Account.id == profile.account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    db_profile = models.Profile(**profile.model_dump())
    db.add(db_profile)
    db.commit()
    db.refresh(db_profile)
    
    # 프로필 생성 시 기본 모드들 자동 생성
    default_modes = [
        {
            "mode_name": "없음",
            "is_empathy_on": False,
            "fontSize_toggle": False,
            "fontColor_toggle": False,
            "speaker": False,
            "bgm": False,
            "effect": False
        },
        {
            "mode_name": "일반",
            "is_empathy_on": False,
            "fontSize_toggle": False,
            "fontColor_toggle": False,
            "speaker": False,
            "bgm": False,
            "effect": False
        },
        {
            "mode_name": "청각",
            "is_empathy_on": True,
            "fontSize_toggle": True,
            "fontColor_toggle": True,
            "speaker": True,
            "bgm": True,
            "effect": True
        },
        {
            "mode_name": "시각",
            "is_empathy_on": True,
            "fontSize_toggle": True,
            "fontColor_toggle": True,
            "speaker": False,
            "bgm": True,
            "effect": True
        },
        {
            "mode_name": "아동",
            "is_empathy_on": True,
            "fontSize_toggle": True,
            "fontColor_toggle": True,
            "speaker": True,
            "bgm": True,
            "effect": True
        },
        {
            "mode_name": "시니어",
            "is_empathy_on": True,
            "fontSize_toggle": True,
            "fontColor_toggle": True,
            "speaker": True,
            "bgm": True,
            "effect": True
        }
    ]
    
    for mode_data in default_modes:
        mode = models.CaptionModeCustomizing(
            profile_id=db_profile.id,
            **mode_data
        )
        db.add(mode)
    
    db.commit()
    db.refresh(db_profile)
    return db_profile


@router.get("/", response_model=List[schemas.ProfileResponse])
def get_profiles(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """모든 프로필 조회"""
    profiles = db.query(models.Profile).offset(skip).limit(limit).all()
    return profiles


@router.get("/{profile_id}", response_model=schemas.ProfileWithSettings)
def get_profile(profile_id: int, db: Session = Depends(get_db)):
    """프로필 조회 (설정 포함) - 역변환 포함"""
    from sqlalchemy.orm import joinedload
    
    profile = db.query(models.Profile).options(
        joinedload(models.Profile.current_mode),
        joinedload(models.Profile.custom_modes)
    ).filter(
        models.Profile.id == profile_id
    ).first()
    
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    # 역변환 처리
    profile_dict = {
        'id': profile.id,
        'account_id': profile.account_id,
        'nickname': profile.nickname,
        'avatar_image': profile.avatar_image,
        'user_type': profile.user_type,
        'is_active': profile.is_active,
        'current_mode_id': profile.current_mode_id,
        'created_at': profile.created_at,
        'current_mode': schemas.CaptionModeResponse.from_model(profile.current_mode) if profile.current_mode else None,
        'custom_modes': [schemas.CaptionModeResponse.from_model(mode) for mode in profile.custom_modes] if profile.custom_modes else []
    }
    return schemas.ProfileWithSettings(**profile_dict)


@router.get("/account/{account_id}", response_model=List[schemas.ProfileResponse])
def get_profiles_by_account(account_id: int, db: Session = Depends(get_db)):
    """계정의 모든 프로필 조회"""
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        profiles = db.query(models.Profile).filter(models.Profile.account_id == account_id).all()
        logger.info(f"Found {len(profiles)} profiles for account {account_id}")
        return profiles
    except Exception as e:
        logger.error(f"Error getting profiles for account {account_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/account/{account_id}/first", response_model=schemas.ProfileWithSettings)
def get_first_profile_by_account(account_id: int, db: Session = Depends(get_db)):
    """계정의 첫 번째 프로필 조회 (설정 포함) - Flutter 앱에서 주로 사용 - 역변환 포함"""
    from sqlalchemy.orm import joinedload
    
    profile = db.query(models.Profile).options(
        joinedload(models.Profile.current_mode),
        joinedload(models.Profile.custom_modes)
    ).filter(
        models.Profile.account_id == account_id
    ).first()
    
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found for this account")
    
    # 역변환 처리
    profile_dict = {
        'id': profile.id,
        'account_id': profile.account_id,
        'nickname': profile.nickname,
        'avatar_image': profile.avatar_image,
        'user_type': profile.user_type,
        'is_active': profile.is_active,
        'current_mode_id': profile.current_mode_id,
        'created_at': profile.created_at,
        'current_mode': schemas.CaptionModeResponse.from_model(profile.current_mode) if profile.current_mode else None,
        'custom_modes': [schemas.CaptionModeResponse.from_model(mode) for mode in profile.custom_modes] if profile.custom_modes else []
    }
    return schemas.ProfileWithSettings(**profile_dict)


@router.put("/{profile_id}", response_model=schemas.ProfileResponse)
def update_profile(profile_id: int, profile_update: schemas.ProfileUpdate, db: Session = Depends(get_db)):
    """프로필 업데이트"""
    import logging
    logger = logging.getLogger(__name__)
    
    db_profile = db.query(models.Profile).filter(models.Profile.id == profile_id).first()
    if not db_profile:
        logger.error(f"Profile {profile_id} not found")
        raise HTTPException(status_code=404, detail="Profile not found")
    
    update_data = profile_update.model_dump(exclude_unset=True)
    logger.info(f"Updating profile {profile_id} with data: {update_data}")
    
    if not update_data:
        logger.warning(f"No fields to update for profile {profile_id}")
        return db_profile
    
    for field, value in update_data.items():
        if hasattr(db_profile, field):
            setattr(db_profile, field, value)
        else:
            logger.warning(f"Profile model does not have field: {field}")
    
    db.commit()
    db.refresh(db_profile)
    logger.info(f"Profile {profile_id} updated successfully. New user_type: {db_profile.user_type}")
    return db_profile


@router.delete("/{profile_id}")
def delete_profile(profile_id: int, db: Session = Depends(get_db)):
    """프로필 삭제"""
    db_profile = db.query(models.Profile).filter(models.Profile.id == profile_id).first()
    if not db_profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    db.delete(db_profile)
    db.commit()
    return {"message": "Profile deleted successfully"}

