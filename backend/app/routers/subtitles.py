from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/subtitles", tags=["subtitles"])

# 1. 자막 모드 리스트 조회 (GET)
@router.get("/profiles/{profile_id}/modes", response_model=List[schemas.CaptionModeResponse])
def get_subtitle_modes(profile_id: int, db: Session = Depends(get_db)):
    modes = db.query(models.CaptionModeCustomizing).filter(
        models.CaptionModeCustomizing.profile_id == profile_id
    ).all()
    return modes

# 2. 자막 모드 설정값 수정 (PUT) - 커스터마이징
@router.put("/modes/{mode_id}", response_model=schemas.CaptionModeResponse)
def update_custom_mode(mode_id: int, mode_data: schemas.CaptionModeUpdate, db: Session = Depends(get_db)):
    mode = db.query(models.CaptionModeCustomizing).filter(models.CaptionModeCustomizing.id == mode_id).first()
    
    if not mode:
        raise HTTPException(status_code=404, detail="Mode not found")
    
    # 요청 들어온 데이터만 부분 업데이트
    update_data = mode_data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(mode, key, value)
    
    db.commit()
    db.refresh(mode)
    return mode

# 3. [중요] 자막 모드 적용하기 (POST) - 퀵 패널에서 클릭 시
@router.post("/profiles/{profile_id}/apply-mode/{mode_id}")
def apply_subtitle_mode(profile_id: int, mode_id: int, db: Session = Depends(get_db)):
    # profile 존재 확인
    profile = db.query(models.Profile).filter(models.Profile.id == profile_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    # mode 존재 확인
    mode = db.query(models.CaptionModeCustomizing).filter(
        models.CaptionModeCustomizing.id == mode_id,
        models.CaptionModeCustomizing.profile_id == profile_id
    ).first()
    if not mode:
        raise HTTPException(status_code=404, detail="Mode not found for this profile")
    
    # profile의 current_mode_id 업데이트
    profile.current_mode_id = mode_id
    db.commit()
    
    return {"status": "success", "message": f"Mode {mode_id} applied", "current_mode_id": mode_id}