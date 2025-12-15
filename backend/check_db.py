"""
DB 연결 확인 스크립트
"""
import sys
import os

# 현재 디렉토리를 파이썬 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import engine, SessionLocal
from sqlalchemy import text, inspect

def check_database_connection():
    """DB 연결 확인"""
    print("=" * 60)
    print("🔍 DB 연결 확인 중...")
    print("=" * 60)
    
    try:
        # 1. 엔진 연결 테스트
        print("\n1️⃣ 엔진 연결 테스트...")
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1 FROM DUAL"))
            row = result.fetchone()
            if row and row[0] == 1:
                print("   ✅ 엔진 연결 성공!")
            else:
                print("   ❌ 엔진 연결 실패")
                return False
        
        # 2. 테이블 목록 확인
        print("\n2️⃣ 테이블 목록 확인...")
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        if tables:
            print(f"   ✅ 발견된 테이블: {len(tables)}개")
            for table in tables:
                print(f"      - {table}")
        else:
            print("   ⚠️ 테이블이 없습니다.")
        
        # 3. 각 테이블의 데이터 개수 확인 (DB 전체 테이블)
        print("\n3️⃣ 테이블별 데이터 개수 확인 (DB 전체)...")
        with engine.connect() as conn:
            # 모든 테이블 확인
            for table_name in tables:
                try:
                    result = conn.execute(text(f"SELECT COUNT(*) FROM {table_name}"))
                    count = result.fetchone()[0]
                    print(f"   ✅ {table_name}: {count}개 레코드")
                except Exception as e:
                    if "ORA-00942" in str(e):  # 테이블 없음
                        print(f"   ⚠️ {table_name}: 테이블 없음")
                    else:
                        print(f"   ❌ {table_name}: 오류 - {e}")
        
        # 4. 샘플 데이터 조회 (Account)
        print("\n4️⃣ 샘플 데이터 조회 (Account)...")
        with engine.connect() as conn:
            try:
                result = conn.execute(text("SELECT id, user_id, email FROM account WHERE ROWNUM <= 5"))
                rows = result.fetchall()
                if rows:
                    print("   ✅ Account 데이터:")
                    for row in rows:
                        print(f"      - ID: {row[0]}, User ID: {row[1]}, Email: {row[2]}")
                else:
                    print("   ℹ️ Account 테이블에 데이터가 없습니다.")
            except Exception as e:
                print(f"   ⚠️ Account 조회 오류: {e}")
        
        # 5. 샘플 데이터 조회 (Profile)
        print("\n5️⃣ 샘플 데이터 조회 (Profile)...")
        with engine.connect() as conn:
            try:
                result = conn.execute(text("""
                    SELECT p.id, p.account_id, p.nickname, p.user_type, p.current_mode_id, 
                           c.mode_name
                    FROM profile p
                    LEFT JOIN caption_mode_customizing c ON p.current_mode_id = c.id
                    WHERE ROWNUM <= 5
                """))
                rows = result.fetchall()
                if rows:
                    print("   ✅ Profile 데이터:")
                    for row in rows:
                        profile_id = row[0]
                        account_id = row[1]
                        nickname = row[2]
                        user_type = row[3]
                        current_mode_id = row[4]
                        mode_name = row[5]
                        mode_info = f"현재 모드: {mode_name} (ID: {current_mode_id})" if mode_name else "현재 모드: 없음"
                        print(f"      - ID: {profile_id}, Account ID: {account_id}, Nickname: {nickname}, Type: {user_type}")
                        print(f"        {mode_info}")
                else:
                    print("   ℹ️ Profile 테이블에 데이터가 없습니다.")
            except Exception as e:
                print(f"   ⚠️ Profile 조회 오류: {e}")
        
        # 6. 현재 선택된 모드 확인 (Profile별)
        print("\n6️⃣ 현재 선택된 모드 확인 (Profile별)...")
        with engine.connect() as conn:
            try:
                result = conn.execute(text("""
                    SELECT p.id, p.nickname, p.current_mode_id, c.mode_name,
                           c.speaker, c.bgm, c.effect, c.font_level, c.color_level
                    FROM profile p
                    LEFT JOIN caption_mode_customizing c ON p.current_mode_id = c.id
                    WHERE p.current_mode_id IS NOT NULL
                    ORDER BY p.id
                """))
                rows = result.fetchall()
                if rows:
                    print("   ✅ 현재 선택된 모드:")
                    for row in rows:
                        profile_id = row[0]
                        nickname = row[1]
                        current_mode_id = row[2]
                        mode_name = row[3]
                        speaker = row[4]
                        bgm = row[5]
                        effect = row[6]
                        font_level = row[7]
                        color_level = row[8]
                        print(f"      📌 Profile ID: {profile_id} ({nickname})")
                        print(f"         → 모드: {mode_name} (ID: {current_mode_id})")
                        print(f"         → 폰트 레벨: {font_level}, 색상 레벨: {color_level}")
                        print(f"         → 토글: 화자={speaker}, 배경음={bgm}, 효과음={effect}")
                else:
                    print("   ℹ️ 현재 선택된 모드가 없습니다.")
            except Exception as e:
                print(f"   ⚠️ 현재 선택된 모드 조회 오류: {e}")
        
        # 7. 샘플 데이터 조회 (CaptionMode)
        print("\n7️⃣ 샘플 데이터 조회 (CaptionMode)...")
        with engine.connect() as conn:
            try:
                result = conn.execute(text("SELECT id, profile_id, mode_name, font_level, color_level, speaker, bgm, effect FROM caption_mode_customizing WHERE ROWNUM <= 5"))
                rows = result.fetchall()
                if rows:
                    print("   ✅ CaptionMode 데이터:")
                    for row in rows:
                        print(f"      - ID: {row[0]}, Profile ID: {row[1]}, Mode: {row[2]}, Font Level: {row[3]}, Color Level: {row[4]}")
                        print(f"        토글: 화자={row[5]}, 배경음={row[6]}, 효과음={row[7]}")
                else:
                    print("   ℹ️ CaptionMode 테이블에 데이터가 없습니다.")
            except Exception as e:
                print(f"   ⚠️ CaptionMode 조회 오류: {e}")
        
        # 8. DB 버전 확인
        print("\n8️⃣ Oracle DB 버전 확인...")
        with engine.connect() as conn:
            try:
                result = conn.execute(text("SELECT * FROM v$version WHERE banner LIKE 'Oracle%'"))
                version = result.fetchone()
                if version:
                    print(f"   ✅ {version[0]}")
            except Exception as e:
                print(f"   ⚠️ 버전 확인 오류: {e}")
        return True
        
    except Exception as e:
        print(f"\n❌ DB 연결 실패: {e}")
        print("\n💡 확인 사항:")
        print("   1. .env 파일에 DATABASE_URL이 올바르게 설정되어 있는지 확인")
        print("   2. Oracle Instant Client가 설치되어 있는지 확인")
        print("   3. 네트워크 연결이 정상인지 확인")
        print("   4. DB 서버가 실행 중인지 확인")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    check_database_connection()
