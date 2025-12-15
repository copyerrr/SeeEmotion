from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime

# ==================== Account 스키마 ====================
class AccountBase(BaseModel):
    user_id: int
    email: EmailStr

class AccountCreate(AccountBase):
    pass

class AccountUpdate(BaseModel):
    email: Optional[EmailStr] = None
    last_login_at: Optional[datetime] = None

class AccountLogin(BaseModel):
    email: EmailStr

class AccountResponse(AccountBase):
    id: int
    created_at: datetime
    last_login_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True

# ==================== Profile 스키마 ====================
class ProfileBase(BaseModel):
    nickname: str
    avatar_image: Optional[str] = None
    user_type: str  # HEARING / SENIOR / VISION / GENERAL / FOREIGN_LEARNER / CHILD
    is_active: bool = True

class ProfileCreate(ProfileBase):
    account_id: int

class ProfileUpdate(BaseModel):
    nickname: Optional[str] = None
    avatar_image: Optional[str] = None
    user_type: Optional[str] = None
    is_active: Optional[bool] = None

class ProfileResponse(ProfileBase):
    id: int
    account_id: int
    current_mode_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True

# ==================== CaptionMode 스키마 ====================
class CaptionModeBase(BaseModel):
    mode_name: str
    is_empathy_on: bool = False
    
    font_size: Optional[int] = 20
    fontSize_toggle: bool = False
    font_color: Optional[str] = "#FFFFFF"
    fontColor_toggle: bool = False
    
    font_level: Optional[int] = 1
    color_level: Optional[int] = 1
    
    speaker: bool = False
    bgm: bool = False
    effect: bool = False

class CaptionModeCreate(CaptionModeBase):
    profile_id: Optional[int] = None  # None이면 기본 모드

class CaptionModeUpdate(BaseModel):
    """자막 모드 업데이트 스키마 (변환 로직 백엔드에서 처리)"""
    mode_name: Optional[str] = None
    is_empathy_on: Optional[bool] = None
    font_size: Optional[int] = None
    fontSize_toggle: Optional[bool] = None
    font_color: Optional[str] = None
    fontColor_toggle: Optional[bool] = None
    font_level: Optional[int] = None  # 직접 숫자로 전송 가능 (하위 호환성)
    color_level: Optional[int] = None  # 직접 숫자로 전송 가능 (하위 호환성)
    sound_pitch: Optional[str] = None  # 문자열로 전송 시 백엔드에서 변환 ('없음', '1단계', '2단계', '3단계')
    emotion_color: Optional[str] = None  # 문자열로 전송 시 백엔드에서 변환 ('없음', '빨강', '파랑', '초록')
    speaker: Optional[bool] = None
    bgm: Optional[bool] = None
    effect: Optional[bool] = None

class CaptionModeResponse(CaptionModeBase):
    id: int
    profile_id: Optional[int] = None
    updated_at: Optional[datetime] = None
    sound_pitch: Optional[str] = None  # 응답 시 변환된 값 ('없음', '1단계', '2단계', '3단계')
    emotion_color: Optional[str] = None  # 응답 시 변환된 값 ('없음', '빨강', '파랑', '초록')
    
    class Config:
        from_attributes = True
    
    @classmethod
    def from_model(cls, model):
        """모델에서 응답 스키마로 변환 (역변환 포함)"""
        data = {
            'id': model.id,
            'profile_id': model.profile_id,
            'mode_name': model.mode_name,
            'is_empathy_on': model.is_empathy_on,
            'font_size': model.font_size,
            'fontSize_toggle': model.fontSize_toggle,
            'font_color': model.font_color,
            'fontColor_toggle': model.fontColor_toggle,
            'font_level': model.font_level,
            'color_level': model.color_level,
            'speaker': model.speaker,
            'bgm': model.bgm,
            'effect': model.effect,
            'updated_at': model.updated_at,
        }
        
        # font_level → sound_pitch 역변환
        if model.fontSize_toggle and model.font_level and model.font_level > 0:
            data['sound_pitch'] = f'{model.font_level}단계'
        else:
            data['sound_pitch'] = '없음'
        
        # color_level → emotion_color 역변환 (단계 형식으로 변환)
        if model.fontColor_toggle and model.color_level and model.color_level > 0:
            data['emotion_color'] = f'{model.color_level}단계'
        else:
            data['emotion_color'] = '없음'
        
        return cls(**data)

class CaptionModeCreateCustom(BaseModel):
    """커스텀 모드 생성용 스키마 (프론트엔드 변환 로직 제거)"""
    profile_id: int
    mode_name: Optional[str] = None  # None이면 selected_mode 사용
    selected_mode: Optional[str] = None  # 'none', 'movie', 'documentary', 'variety'
    sound_pitch: Optional[str] = None  # '없음', '1단계', '2단계', '3단계'
    emotion_color: Optional[str] = None  # '없음', '빨강', '파랑', '초록'
    speaker: bool = False
    bgm: bool = False
    effect: bool = False

class CaptionSettingUpdate(BaseModel):
    """자막 설정 업데이트용 스키마 (Query Parameter → Request Body)"""
    mode_id: int
    apply_immediately: bool = True

class ModeDefaultSettingsUpdate(BaseModel):
    """모드별 기본 설정 업데이트용 스키마"""
    mode_type: str  # 'movie', 'documentary', 'variety'

# ==================== 통합 응답 스키마 ====================
class ProfileWithSettings(ProfileResponse):
    current_mode_id: Optional[int] = None
    current_mode: Optional[CaptionModeResponse] = None
    custom_modes: List[CaptionModeResponse] = []
    
    class Config:
        from_attributes = True
