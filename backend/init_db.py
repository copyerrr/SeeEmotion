import sys
import os

# 현재 디렉토리(backend)를 파이썬 경로에 추가하여 app 모듈을 찾을 수 있게 함
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import SessionLocal, engine
from app import models
from sqlalchemy import text, inspect

# ==========================================
# 1. 기존 데이터 백업
# ==========================================
print("💾 기존 사용자 데이터 백업 중...")
backup_data = {
    "accounts": [],
    "profiles": [],
    "caption_modes": []
}

# 테이블 삭제 전 데이터 백업을 위해 연결
with engine.connect() as conn:
    inspector = inspect(engine)
    existing_tables = inspector.get_table_names()
    # 테이블명을 대문자로 변환하여 비교 (Oracle은 기본적으로 대문자 저장)
    existing_tables_upper = [t.upper() for t in existing_tables]

    if "ACCOUNT" in existing_tables_upper:
        try:
            # 쌍따옴표 제거: account (오라클은 대소문자 구분 없이 대문자로 인식)
            result = conn.execute(text('SELECT * FROM account'))
            for row in result:
                backup_data["accounts"].append({
                    "id": row[0],
                    "user_id": row[1],
                    "email": row[2],
                    "created_at": row[3],
                    "last_login_at": row[4]
                })
            print(f"  ✓ Account 데이터 {len(backup_data['accounts'])}개 백업")
        except Exception as e:
            print(f"  ⚠️ Account 백업 오류 (무시 가능): {e}")
    
    if "PROFILE" in existing_tables_upper:
        try:
            result = conn.execute(text('SELECT * FROM profile'))
            for row in result:
                backup_data["profiles"].append({
                    "id": row[0],
                    "account_id": row[1],
                    "nickname": row[2],
                    "avatar_image": row[3],
                    "user_type": row[4],
                    "is_active": row[5],
                    "current_mode_id": row[6],
                    "created_at": row[7]
                })
            print(f"  ✓ Profile 데이터 {len(backup_data['profiles'])}개 백업")
        except Exception as e:
            print(f"  ⚠️ Profile 백업 오류 (무시 가능): {e}")
    
    if "CAPTION_MODE_CUSTOMIZING" in existing_tables_upper:
        try:
            result = conn.execute(text('SELECT * FROM caption_mode_customizing'))
            for row in result:
                backup_data["caption_modes"].append({
                    "id": row[0],
                    "profile_id": row[1],
                    "mode_name": row[2],
                    "is_empathy_on": row[3],
                    "font_size": row[4],
                    "fontSize_toggle": row[5],
                    "font_color": row[6],
                    "fontColor_toggle": row[7],
                    "font_level": row[8],
                    "color_level": row[9],
                    "speaker": row[10],
                    "bgm": row[11],
                    "effect": row[12],
                    "updated_at": row[13]
                })
            print(f"  ✓ CaptionMode 데이터 {len(backup_data['caption_modes'])}개 백업")
        except Exception as e:
            print(f"  ⚠️ CaptionMode 백업 오류 (무시 가능): {e}")

if any(backup_data.values()):
    print(f"✅ 총 {len(backup_data['accounts']) + len(backup_data['profiles']) + len(backup_data['caption_modes'])}개 레코드 백업 완료")
else:
    print("ℹ️ 백업할 기존 데이터가 없습니다.")

# ==========================================
# 2. 기존 테이블 및 객체 삭제
# ==========================================
print("\n🗑️  기존 테이블 삭제 중...")
with engine.connect() as conn:
    # 외래키 의존성을 고려하여 역순으로 삭제
    # Oracle에서는 테이블명이 대문자로 처리되므로 쌍따옴표 제거
    tables = ["caption_mode_customizing", "profile", "account"]
    for table in tables:
        try:
            conn.execute(text(f"DROP TABLE {table} CASCADE CONSTRAINTS"))
            conn.commit()
            print(f"  ✓ {table} 삭제")
        except Exception as e:
            if "ORA-00942" in str(e): # 테이블 없음
                print(f"  ℹ️ {table} 테이블 없음 (삭제 건너뜀)")
            else:
                print(f"  ⚠️ {table} 삭제 오류: {e}")
    
    # 시퀀스 삭제
    sequences = ["account_seq", "profile_seq", "caption_mode_seq"]
    for seq in sequences:
        try:
            conn.execute(text(f"DROP SEQUENCE {seq}"))
            conn.commit()
            print(f"  ✓ {seq} 시퀀스 삭제")
        except Exception:
            pass # 없으면 패스

    # 트리거 삭제
    triggers = ["account_id_trigger", "profile_id_trigger", "caption_mode_id_trigger"]
    for trigger in triggers:
        try:
            conn.execute(text(f"DROP TRIGGER {trigger}"))
            conn.commit()
            print(f"  ✓ {trigger} 트리거 삭제")
        except Exception:
            pass

print("✅ 기존 테이블 삭제 완료")

# ==========================================
# 3. 새 테이블 생성 (SQLAlchemy)
# ==========================================
print("📦 새 테이블 생성 중...")

# Oracle 11g: Primary Key는 자동으로 인덱스를 생성하므로
# index=True가 설정된 Primary Key 컬럼의 인덱스 플래그 제거
for table in models.Base.metadata.sorted_tables:
    for column in table.columns:
        if column.primary_key and column.index:
            column.index = False

try:
    models.Base.metadata.create_all(bind=engine)
    print("✅ 테이블 스키마 생성 완료")
except Exception as e:
    # 인덱스 중복 오류는 무시 (테이블은 이미 생성됨)
    if "ORA-01408" in str(e) or "already indexed" in str(e):
        print("⚠️ 일부 인덱스가 이미 존재합니다 (테이블은 생성됨)")
    else:
        print(f"❌ 테이블 생성 오류: {e}")
        raise

# ==========================================
# 4. 시퀀스 생성 (Oracle 11g - SQLAlchemy Sequence 사용)
# ==========================================
print("📦 시퀀스 생성 중...")
with engine.connect() as conn:
    # 시퀀스 생성 (SQLAlchemy Sequence가 자동으로 사용)
    sequences_sql = [
        "CREATE SEQUENCE account_seq START WITH 1 INCREMENT BY 1",
        "CREATE SEQUENCE profile_seq START WITH 1 INCREMENT BY 1",
        "CREATE SEQUENCE caption_mode_seq START WITH 1 INCREMENT BY 1"
    ]
    
    for sql in sequences_sql:
        try:
            conn.execute(text(sql))
            conn.commit()
            print(f"  ✓ 시퀀스 생성 성공")
        except Exception as e:
            if "ORA-00955" not in str(e): # 이미 존재하면 패스
                print(f"  ⚠️ 시퀀스 생성 오류: {e}")
            else:
                print(f"  ℹ️ 시퀀스 이미 존재함")

print("✅ 시퀀스 생성 완료")
print("💡 SQLAlchemy Sequence를 사용하므로 트리거가 필요 없습니다.")

# ==========================================
# 5. 데이터 초기화 및 복원
# ==========================================
def init_data(backup_data=None):
    db = SessionLocal()
    
    try:
        # --- 5-1. 백업 데이터 복원 ---
        if backup_data and any(backup_data.values()):
            print("\n📥 백업된 기존 데이터 복원 중...")
            
            # Account 복원
            account_id_map = {} 
            if backup_data.get("accounts"):
                for acc_data in backup_data["accounts"]:
                    old_id = acc_data["id"]
                    new_account = models.Account(
                        user_id=acc_data["user_id"],
                        email=acc_data["email"],
                        created_at=acc_data["created_at"],
                        last_login_at=acc_data["last_login_at"]
                    )
                    db.add(new_account)
                    db.flush() 
                    account_id_map[old_id] = new_account.id
                print(f"  ✓ Account 복원 완료")
            
            # Profile 복원
            profile_id_map = {}
            if backup_data.get("profiles"):
                for prof_data in backup_data["profiles"]:
                    old_id = prof_data["id"]
                    old_account_id = prof_data["account_id"]
                    new_account_id = account_id_map.get(old_account_id, old_account_id)
                    
                    new_profile = models.Profile(
                        account_id=new_account_id,
                        nickname=prof_data["nickname"],
                        avatar_image=prof_data["avatar_image"],
                        user_type=prof_data["user_type"],
                        is_active=bool(prof_data["is_active"]),
                        created_at=prof_data["created_at"]
                    )
                    db.add(new_profile)
                    db.flush()
                    profile_id_map[old_id] = new_profile.id
                print(f"  ✓ Profile 복원 완료")
            
            # CaptionMode 복원
            mode_id_map = {}
            if backup_data.get("caption_modes"):
                for mode_data in backup_data["caption_modes"]:
                    old_id = mode_data["id"]
                    old_profile_id = mode_data["profile_id"]
                    new_profile_id = profile_id_map.get(old_profile_id, old_profile_id)
                    
                    new_mode = models.CaptionModeCustomizing(
                        profile_id=new_profile_id,
                        mode_name=mode_data["mode_name"],
                        is_empathy_on=bool(mode_data["is_empathy_on"]),
                        font_size=mode_data["font_size"],
                        fontSize_toggle=bool(mode_data["fontSize_toggle"]),
                        font_color=mode_data["font_color"],
                        fontColor_toggle=bool(mode_data["fontColor_toggle"]),
                        font_level=mode_data["font_level"],
                        color_level=mode_data["color_level"],
                        speaker=bool(mode_data["speaker"]),
                        bgm=bool(mode_data["bgm"]),
                        effect=bool(mode_data["effect"]),
                        updated_at=mode_data["updated_at"]
                    )
                    db.add(new_mode)
                    db.flush()
                    mode_id_map[old_id] = new_mode.id
                print(f"  ✓ CaptionMode 복원 완료")

                # current_mode_id 업데이트
                if backup_data.get("profiles"):
                    for prof_data in backup_data["profiles"]:
                        if prof_data.get("current_mode_id"):
                            old_mode_id = prof_data["current_mode_id"]
                            new_mode_id = mode_id_map.get(old_mode_id)
                            new_profile_id = profile_id_map.get(prof_data["id"])
                            
                            if new_mode_id and new_profile_id:
                                profile = db.query(models.Profile).filter_by(id=new_profile_id).first()
                                if profile:
                                    profile.current_mode_id = new_mode_id
            
            db.commit()
            print("✅ 백업 데이터 복원 완료\n")
        
        # --- 5-2. 초기 테스트 데이터 생성 (백업 없을 시) ---
        if not db.query(models.Account).filter_by(user_id=1001).first():
            print("Creating Test Account...")
            test_account = models.Account(
                user_id=1001,
                email="test@lg.com"
            )
            db.add(test_account)
            db.commit()
            db.refresh(test_account)
            
            print("Creating Test Profile...")
            test_profile = models.Profile(
                account_id=test_account.id,
                nickname="User1",
                user_type="HEARING",
                avatar_image="default_avatar.png"
            )
            db.add(test_profile)
            db.commit()
            db.refresh(test_profile)

            print("Inserting Default Caption Modes...")
            
            mode_none = models.CaptionModeCustomizing(
                profile_id=test_profile.id,
                mode_name="없음",
                is_empathy_on=False,
                fontSize_toggle=False,
                fontColor_toggle=False,
                speaker=False, bgm=False, effect=False
            )
            
            mode_drama = models.CaptionModeCustomizing(
                profile_id=test_profile.id,
                mode_name="영화/드라마",
                is_empathy_on=True,
                font_size=24, fontSize_toggle=True,
                font_color="#FFFFFF", fontColor_toggle=True,
                font_level=2, color_level=2,
                speaker=True, bgm=True, effect=False
            )

            mode_news = models.CaptionModeCustomizing(
                profile_id=test_profile.id,
                mode_name="다큐멘터리",
                is_empathy_on=True,
                font_size=30, fontSize_toggle=True,
                font_color="#FFFFFF", fontColor_toggle=True,
                font_level=1, color_level=1,
                speaker=False, bgm=False, effect=False
            )

            mode_variety = models.CaptionModeCustomizing(
                profile_id=test_profile.id,
                mode_name="예능",
                is_empathy_on=True,
                font_size=28, fontSize_toggle=True,
                font_color="#FFD700", fontColor_toggle=True,
                font_level=3, color_level=3,
                speaker=True, bgm=True, effect=True
            )

            db.add_all([mode_none, mode_drama, mode_news, mode_variety])
            db.commit()

            # 기본 모드 설정
            test_profile.current_mode_id = mode_drama.id
            db.commit()
            
            print("✅ 초기 테스트 데이터 생성 완료!")
        else:
            print("ℹ️ 계정이 이미 존재하여 생성을 건너뜁니다.")
            
    except Exception as e:
        print(f"❌ 데이터 초기화 중 오류: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    # 백업 데이터 복원을 건너뛰고 깨끗하게 초기화
    # 테스트 데이터(321, 321321321, 랄헌굿라랄 등)를 제외하고 깨끗하게 시작
    init_data(backup_data=None)  # 백업 없이 깨끗하게 시작
    
    # 백업 데이터를 복원하려면 아래 주석을 해제하세요
    # init_data(backup_data)  # 백업 데이터 복원