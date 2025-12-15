from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, Sequence
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base

class Account(Base):
    __tablename__ = "account"
    id = Column(Integer, Sequence('account_seq', start=1), primary_key=True)  # Oracle 11g: Primary Key는 자동 인덱스 생성
    user_id = Column(Integer, unique=True, index=True) #
    email = Column(String(255))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    last_login_at = Column(DateTime(timezone=True), nullable=True)
    profiles = relationship("Profile", back_populates="account")

class Profile(Base):
    __tablename__ = "profile"
    id = Column(Integer, Sequence('profile_seq', start=1), primary_key=True)  # Oracle 11g: Primary Key는 자동 인덱스 생성
    account_id = Column(Integer, ForeignKey("account.id"))
    nickname = Column(String(50))
    avatar_image = Column(String(255))
    user_type = Column(String(30))
    is_active = Column(Boolean, default=True)
    current_mode_id = Column(Integer, ForeignKey("caption_mode_customizing.id"), nullable=True)  # 현재 선택된 모드
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    account = relationship("Account", back_populates="profiles")
    # foreign_keys를 명시하여 profile_id를 사용하는 관계임을 명확히 함
    # Profile과 CaptionModeCustomizing 사이에 두 개의 외래키 경로가 있으므로 명시 필요
    # 1. Profile.current_mode_id -> CaptionModeCustomizing.id
    # 2. CaptionModeCustomizing.profile_id -> Profile.id
    # custom_modes는 두 번째 경로를 사용해야 하므로 foreign_keys 명시
    custom_modes = relationship(
        "CaptionModeCustomizing", 
        back_populates="profile",
        primaryjoin="Profile.id == CaptionModeCustomizing.profile_id"
    )
    current_mode = relationship("CaptionModeCustomizing", foreign_keys=[current_mode_id])

class CaptionModeCustomizing(Base):
    __tablename__ = "caption_mode_customizing"
    id = Column(Integer, Sequence('caption_mode_seq', start=1), primary_key=True)  # Oracle 11g: Primary Key는 자동 인덱스 생성
    profile_id = Column(Integer, ForeignKey("profile.id"))
    mode_name = Column(String(50))
    is_empathy_on = Column(Boolean, default=False)
    
    font_size = Column(Integer)
    fontSize_toggle = Column(Boolean, default=False) # CamelCase 유지
    font_color = Column(String(10))
    fontColor_toggle = Column(Boolean, default=False)
    
    font_level = Column(Integer)
    color_level = Column(Integer)
    
    speaker = Column(Boolean, default=False)
    bgm = Column(Boolean, default=False)
    effect = Column(Boolean, default=False)
    
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    profile = relationship("Profile", back_populates="custom_modes", foreign_keys=[profile_id])
