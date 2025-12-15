from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from datetime import datetime
from app import models, schemas
from app.database import get_db

router = APIRouter(prefix="/api/accounts", tags=["accounts"])


@router.post("/", response_model=schemas.AccountResponse)
def create_account(account: schemas.AccountCreate, db: Session = Depends(get_db)):
    """계정 생성"""
    # user_id 중복 체크
    existing = db.query(models.Account).filter(models.Account.user_id == account.user_id).first()
    if existing:
        raise HTTPException(status_code=400, detail="User ID already exists")
    
    db_account = models.Account(**account.model_dump())
    db.add(db_account)
    db.commit()
    db.refresh(db_account)
    return db_account


@router.get("/", response_model=List[schemas.AccountResponse])
def get_accounts(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """모든 계정 조회"""
    accounts = db.query(models.Account).offset(skip).limit(limit).all()
    return accounts


@router.get("/{account_id}", response_model=schemas.AccountResponse)
def get_account(account_id: int, db: Session = Depends(get_db)):
    """계정 조회"""
    account = db.query(models.Account).filter(models.Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.get("/user/{user_id}", response_model=schemas.AccountResponse)
def get_account_by_user_id(user_id: int, db: Session = Depends(get_db)):
    """user_id로 계정 조회"""
    account = db.query(models.Account).filter(models.Account.user_id == user_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.get("/email/{email}", response_model=schemas.AccountResponse)
def get_account_by_email(email: str, db: Session = Depends(get_db)):
    """이메일로 계정 조회 (로그인용)"""
    account = db.query(models.Account).filter(models.Account.email == email).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.post("/login", response_model=schemas.AccountResponse)
def login_or_create_account(login_data: schemas.AccountLogin, db: Session = Depends(get_db)):
    """이메일로 로그인 또는 계정 생성 (이메일이 없으면 생성, 있으면 반환)"""
    account = db.query(models.Account).filter(models.Account.email == login_data.email).first()
    
    if account:
        # 기존 계정이면 last_login_at 업데이트
        account.last_login_at = datetime.now()
        db.commit()
        db.refresh(account)
        return account
    else:
        # 새 계정 생성 (user_id는 자동 생성)
        max_user_id = db.query(func.max(models.Account.user_id)).scalar()
        user_id = (max_user_id or 0) + 1
        
        new_account = models.Account(
            user_id=user_id,
            email=login_data.email
        )
        db.add(new_account)
        db.commit()
        db.refresh(new_account)
        return new_account


@router.put("/{account_id}", response_model=schemas.AccountResponse)
def update_account(account_id: int, account_update: schemas.AccountUpdate, db: Session = Depends(get_db)):
    """계정 업데이트"""
    db_account = db.query(models.Account).filter(models.Account.id == account_id).first()
    if not db_account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    update_data = account_update.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_account, field, value)
    
    db.commit()
    db.refresh(db_account)
    return db_account


@router.delete("/{account_id}")
def delete_account(account_id: int, db: Session = Depends(get_db)):
    """계정 삭제"""
    db_account = db.query(models.Account).filter(models.Account.id == account_id).first()
    if not db_account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    db.delete(db_account)
    db.commit()
    return {"message": "Account deleted successfully"}

