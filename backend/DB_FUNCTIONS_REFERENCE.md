# DB 관련 함수 및 라이브러리 정리

## 📚 사용된 라이브러리 및 함수 목록

### 1. **os** (Python 표준 라이브러리)
환경 변수 및 운영체제 관련 기능

#### 라이브러리 설정:
```python
import os
```

#### 함수:
- `os.getenv(key, default=None)`
  - **용도**: 환경 변수 값 가져오기
  - **사용 예시**:
    ```python
    SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
    oracle_client_path = os.getenv("ORACLE_CLIENT_PATH", "default_path")
    ```
  - **반환값**: 
    - 환경 변수가 있으면 → **문자열** (환경 변수의 값)
    - 환경 변수가 없으면 → **None** 또는 기본값 (default 지정 시)
    - 예시: `"oracle+oracledb://user:pass@host:port"` 또는 `None`

---

### 2. **dotenv** (python-dotenv)
`.env` 파일에서 환경 변수 로드

#### 라이브러리 설정:
```python
from dotenv import load_dotenv
```

#### 함수:
- `load_dotenv(dotenv_path=None, override=False)`
  - **용도**: `.env` 파일에서 환경 변수를 로드하여 `os.getenv()`에서 사용 가능하게 함
  - **사용 예시**:
    ```python
    from dotenv import load_dotenv
    load_dotenv()  # .env 파일 로드
    ```
  - **반환값**: 
    - **None** (아무것도 반환하지 않음)
    - 환경 변수는 시스템에 자동으로 추가됨 (반환값 없이도 사용 가능)

---

### 3. **sqlalchemy**
Python ORM (Object-Relational Mapping) 라이브러리

#### 라이브러리 설정:
```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
```

#### 함수:

##### 3.1 `create_engine(database_url, **kwargs)`
- **용도**: 데이터베이스 연결 엔진 생성
- **사용 예시**:
  ```python
  from sqlalchemy import create_engine
  
  engine = create_engine(
      "oracle+oracledb://",
      connect_args={
          "user": username,
          "password": password,
          "dsn": dsn_string
      }
  )
  ```
- **반환값**: 
  - **데이터베이스 연결을 관리하는 엔진 객체**
  - 이 객체로 데이터베이스에 연결하고 쿼리를 실행할 수 있음
  - 예시: `engine.connect()`, `engine.execute()` 등 사용 가능

##### 3.2 `sessionmaker(**kwargs)`
- **용도**: 데이터베이스 세션 팩토리 생성
- **사용 예시**:
  ```python
  from sqlalchemy.orm import sessionmaker
  
  SessionLocal = sessionmaker(
      autocommit=False,
      autoflush=False,
      bind=engine
  )
  ```
- **반환값**: 
  - **데이터베이스 세션을 만드는 클래스**
  - 이 클래스를 호출하면 세션 객체가 생성됨
  - 예시: `db = SessionLocal()` → 세션 객체 생성

##### 3.3 `declarative_base()`
- **용도**: ORM 모델의 기본 클래스 생성
- **사용 예시**:
  ```python
  from sqlalchemy.ext.declarative import declarative_base
  
  Base = declarative_base()
  
  class User(Base):
      __tablename__ = "users"
      # ...
  ```
- **반환값**: 
  - **ORM 모델을 만들 때 상속받는 기본 클래스**
  - 이 클래스를 상속받아 데이터베이스 테이블을 정의함
  - 예시: `class User(Base):` → User 모델 정의

---

### 4. **urllib.parse** (Python 표준 라이브러리)
URL 파싱 및 조작

#### 라이브러리 설정:
```python
from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
```

#### 함수:

##### 4.1 `urlparse(urlstring, scheme='', allow_fragments=True)`
- **용도**: URL을 구성 요소로 파싱
- **사용 예시**:
  ```python
  from urllib.parse import urlparse
  
  parsed = urlparse("oracle+oracledb://user:pass@host:port/service_name")
  # parsed.scheme, parsed.netloc, parsed.path, parsed.query 등 접근 가능
  ```
- **반환값**: 
  - **URL을 분해한 정보를 담은 객체**
  - 속성으로 접근 가능: `parsed.scheme`, `parsed.netloc`, `parsed.path`, `parsed.query` 등
  - 예시: `parsed.scheme` → `"oracle+oracledb"`, `parsed.netloc` → `"user:pass@host:port"`

##### 4.2 `parse_qs(qs, keep_blank_values=False, strict_parsing=False, encoding='utf-8', errors='replace', max_num_fields=None)`
- **용도**: 쿼리 문자열을 딕셔너리로 파싱
- **사용 예시**:
  ```python
  from urllib.parse import parse_qs
  
  query_params = parse_qs("service_name=XE&port=1521")
  # {'service_name': ['XE'], 'port': ['1521']}
  ```
- **반환값**: 
  - **딕셔너리 형태**
  - 키는 쿼리 파라미터 이름, 값은 리스트 형태
  - 예시: `{'service_name': ['XE'], 'port': ['1521']}`
  - 주의: 값이 리스트이므로 `query_params['service_name'][0]`로 접근해야 함

##### 4.3 `urlencode(query, doseq=False, safe='', encoding=None, errors=None, quote_via=quote_plus)`
- **용도**: 딕셔너리를 쿼리 문자열로 변환
- **사용 예시**:
  ```python
  from urllib.parse import urlencode
  
  params = {"service_name": "XE"}
  query_string = urlencode(params, doseq=True)
  # "service_name=XE"
  ```
- **반환값**: 
  - **문자열 형태의 쿼리 문자열**
  - 딕셔너리를 URL 쿼리 형식으로 변환한 결과
  - 예시: `"service_name=XE"` 또는 `"service_name=XE&port=1521"`

##### 4.4 `urlunparse(components)`
- **용도**: 파싱된 URL 구성 요소를 다시 URL 문자열로 조합
- **사용 예시**:
  ```python
  from urllib.parse import urlunparse
  
  new_parsed = parsed._replace(path="", query=new_query)
  new_url = urlunparse(new_parsed)
  ```
- **반환값**: 
  - **문자열 형태의 완전한 URL**
  - 파싱된 URL 구성 요소들을 다시 하나의 URL 문자열로 합친 결과
  - 예시: `"oracle+oracledb://user:pass@host:port/?service_name=XE"`

---

### 5. **oracledb**
Oracle 데이터베이스 드라이버

#### 라이브러리 설정:
```python
import oracledb
```

#### 함수:

##### 5.1 `init_oracle_client(lib_dir=None, config_dir=None, error_url=None, driver_name=None)`
- **용도**: Oracle Instant Client 초기화 (Thick Mode)
- **사용 예시**:
  ```python
  import oracledb
  
  oracle_client_path = os.getenv("ORACLE_CLIENT_PATH")
  oracledb.init_oracle_client(lib_dir=oracle_client_path)
  ```
- **반환값**: 
  - **None** (아무것도 반환하지 않음)
  - Oracle 클라이언트만 초기화됨 (반환값 없이도 사용 가능)
- **예외**: 
  - 이미 초기화된 경우 → `Exception` 발생 가능
  - 경로가 잘못된 경우 → `Exception` 발생 가능

---

### 6. **logging** (Python 표준 라이브러리)
로깅 기능

#### 라이브러리 설정:
```python
import logging
```

#### 함수:

##### 6.1 `getLogger(name=None)`
- **용도**: 로거 인스턴스 가져오기
- **사용 예시**:
  ```python
  import logging
  
  logger = logging.getLogger(__name__)
  logger.info("Connecting to database: ...")
  ```
- **반환값**: 
  - **로그를 기록하는 로거 객체**
  - 이 객체로 로그 메시지를 출력할 수 있음
  - 예시: `logger.info("메시지")`, `logger.error("에러")` 등 사용 가능

---

## 🔧 커스텀 함수

### `get_db()`
- **용도**: FastAPI 의존성 주입을 위한 DB 세션 생성 함수
- **사용 예시**:
  ```python
  from app.database import get_db
  from fastapi import Depends
  from sqlalchemy.orm import Session
  
  @router.get("/items")
  def get_items(db: Session = Depends(get_db)):
      items = db.query(Item).all()
      return items
  ```
- **반환값**: 
  - **제너레이터 (Generator)**
  - 세션 객체를 하나씩 생성해서 반환함 (`yield` 사용)
  - 사용 예시: `db = next(get_db())` 또는 FastAPI의 `Depends(get_db)` 사용
- **특징**: 
  - 요청 종료 시 자동으로 세션 닫힘 (`finally` 블록에서 `db.close()` 실행)
  - FastAPI의 의존성 주입 패턴 사용
  - `yield`를 사용하므로 함수가 끝나도 세션이 유지됨

---

## 📋 환경 변수 목록

### 필수 환경 변수:
- `DATABASE_URL`: 데이터베이스 연결 URL
  - 형식: `oracle+oracledb://user:password@host:port/?service_name=service_name`
  
### 선택적 환경 변수:
- `ORACLE_CLIENT_PATH`: Oracle Instant Client 경로
  - 예시: `C:\oracle\instantclient_23_0` (Windows)
  - 예시: `/opt/oracle/instantclient_23_0` (Linux/Mac)

---

## 🔄 데이터베이스 연결 흐름

1. **환경 변수 로드**: `load_dotenv()` → `.env` 파일 읽기
2. **DB URL 가져오기**: `os.getenv("DATABASE_URL")`
3. **URL 파싱 및 변환**: `urlparse()`, `parse_qs()` 등으로 URL 정규화
4. **Oracle Client 초기화**: `oracledb.init_oracle_client()` (Oracle인 경우)
5. **엔진 생성**: `create_engine()` → DB 연결 엔진 생성
6. **세션 팩토리 생성**: `sessionmaker()` → 세션 클래스 생성
7. **세션 사용**: `get_db()` → API에서 세션 가져오기

---

## 📝 사용 예시 (전체 흐름)

```python
# 1. 환경 변수 로드
from dotenv import load_dotenv
load_dotenv()

# 2. DB URL 가져오기
import os
DATABASE_URL = os.getenv("DATABASE_URL")

# 3. Oracle인 경우 클라이언트 초기화
if "oracle" in DATABASE_URL:
    import oracledb
    oracle_path = os.getenv("ORACLE_CLIENT_PATH")
    oracledb.init_oracle_client(lib_dir=oracle_path)

# 4. 엔진 및 세션 생성
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)

# 5. API에서 사용
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

