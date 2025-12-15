import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from dotenv import load_dotenv

# .env 파일 로드
load_dotenv()

# 환경 변수에서 주소 가져오기
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

# .env 파일에 "DATABASE_URL="가 값에 포함된 경우 제거 (SQL 쿼리 결과를 그대로 복사한 경우)
if SQLALCHEMY_DATABASE_URL and SQLALCHEMY_DATABASE_URL.startswith("DATABASE_URL="):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace("DATABASE_URL=", "", 1)

# cx_oracle 대신 oracledb 사용하도록 변경 (oracle+cx_oracle:// -> oracle+oracledb://)
if SQLALCHEMY_DATABASE_URL and SQLALCHEMY_DATABASE_URL.startswith("oracle+cx_oracle://"):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace("oracle+cx_oracle://", "oracle+oracledb://")

# Oracle Service Name을 쿼리 파라미터 형식으로 변환
# 형식: oracle+oracledb://user:pass@host:port/service_name 
# -> oracle+oracledb://user:pass@host:port/?service_name=service_name
if SQLALCHEMY_DATABASE_URL and "oracle" in SQLALCHEMY_DATABASE_URL:
    # 이미 service_name 또는 sid 파라미터가 있으면 건너뛰기
    if "?service_name=" not in SQLALCHEMY_DATABASE_URL and "?sid=" not in SQLALCHEMY_DATABASE_URL:
        # URL을 파싱하여 service_name 추출
        from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
        parsed = urlparse(SQLALCHEMY_DATABASE_URL)
        
        # 경로에서 service_name 추출 (마지막 / 뒤의 부분)
        if parsed.path and parsed.path != "/" and "?" not in parsed.path:
            identifier = parsed.path.lstrip("/")
            # 포트 번호가 아닌 경우 (숫자가 아닌 경우)
            if not identifier.isdigit():
                # 새로운 경로는 빈 문자열로 설정하고 service_name을 쿼리 파라미터로 추가
                query_params = parse_qs(parsed.query)
                query_params["service_name"] = [identifier]
                new_query = urlencode(query_params, doseq=True)
                new_parsed = parsed._replace(path="", query=new_query)
                SQLALCHEMY_DATABASE_URL = urlunparse(new_parsed)
        elif parsed.path == "/":
            # 경로가 "/"만 있는 경우 제거 (SQLAlchemy가 인식하지 못할 수 있음)
            new_parsed = parsed._replace(path="")
            SQLALCHEMY_DATABASE_URL = urlunparse(new_parsed)

# SQLAlchemy Oracle URL 형식에 맞게 조정
# oracle+oracledb:// 형식은 호스트:포트 뒤에 경로가 없어야 함
# 디버깅용: 최종 URL 출력 (비밀번호는 마스킹)
if SQLALCHEMY_DATABASE_URL:
    import logging
    logger = logging.getLogger(__name__)
    # 비밀번호 마스킹
    masked_url = SQLALCHEMY_DATABASE_URL
    if "@" in masked_url and ":" in masked_url.split("@")[0]:
        user_pass = masked_url.split("@")[0]
        if ":" in user_pass:
            user, _ = user_pass.split(":", 1)
            masked_url = masked_url.replace(user_pass, f"{user}:***")
    logger.info(f"Connecting to database: {masked_url}")

# oracledb.makedsn()을 사용하여 DSN 생성 및 connect_args 설정
# 이 방법이 DPY-4027 오류를 방지하는 가장 확실한 방법입니다
connect_args = {}
dsn = None

if SQLALCHEMY_DATABASE_URL and "oracle" in SQLALCHEMY_DATABASE_URL:
    # URL에서 호스트, 포트, 사용자명, 비밀번호 추출
    from urllib.parse import urlparse, parse_qs
    import oracledb
    
    # Oracle Instant Client 초기화 (Thick Mode)
    # .env 파일에 ORACLE_CLIENT_PATH를 설정하거나, 아래 경로를 수정하세요
    oracle_client_path = os.getenv("ORACLE_CLIENT_PATH", r"C:\Users\155\Downloads\instantclient-basic-windows.x64-23.26.0.0.0\instantclient_23_0")
    
    try:
        oracledb.init_oracle_client(lib_dir=oracle_client_path)
        print("✅ Oracle Client 로드 성공 (Thick Mode)")
    except Exception as e:
        # 이미 초기화되었거나 다른 경로에 있는 경우
        if "Oracle Client library has already been initialized" not in str(e):
            print(f"⚠️ Oracle Client 초기화 경고: {e}")
            print("💡 Oracle Instant Client 경로를 확인하거나 .env에 ORACLE_CLIENT_PATH를 설정하세요.")
    
    parsed = urlparse(SQLALCHEMY_DATABASE_URL)
    if parsed.netloc:
        # netloc 형식: user:pass@host:port
        if "@" in parsed.netloc:
            auth, host_port = parsed.netloc.split("@", 1)
            if ":" in auth:
                username, password = auth.split(":", 1)
            else:
                username = auth
                password = None
            
            if ":" in host_port:
                host, port = host_port.split(":", 1)
            else:
                host = host_port
                port = "1521"
            
            # Service Name 또는 SID 추출
            service_name = None
            sid = None
            if parsed.query:
                query_params = parse_qs(parsed.query)
                if "service_name" in query_params:
                    service_name = query_params["service_name"][0]
                elif "sid" in query_params:
                    sid = query_params["sid"][0]
            
            # Service Name과 SID가 모두 없는 경우 기본값으로 'XE' 사용
            if not service_name and not sid:
                service_name = "XE"
                print(f"⚠️ Service Name이 지정되지 않아 기본값 'XE'를 사용합니다.")
            
            # DSN 문자열 생성 (사용자가 성공한 형식: "host:port/service_name")
            if service_name:
                dsn_string = f"{host}:{port}/{service_name}"
            elif sid:
                dsn_string = f"{host}:{port}/{sid}"
            else:
                dsn_string = f"{host}:{port}"
            
            print(f"✅ DSN 생성: {dsn_string}")
            
            # connect_args 설정 (사용자가 성공한 방식)
            connect_args = {
                "user": username,
                "password": password,
                "dsn": dsn_string,
            }

# connect_args가 있으면 DSN을 사용하여 연결, 없으면 기본 URL 사용
if connect_args and "dsn" in connect_args:
    # 사용자가 성공한 방식: oracledb.connect(user=..., password=..., dsn=...)
    # SQLAlchemy는 connect_args를 사용하여 연결
    engine = create_engine(
        f"oracle+oracledb://",
        connect_args=connect_args
    )
else:
    engine = create_engine(SQLALCHEMY_DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# DB 세션 의존성 함수 (API에서 사용)
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()