# FastAPI 프레임워크 완전 정리

## 🎯 FastAPI란?

**FastAPI = Python으로 웹 서버를 빠르고 쉽게 만드는 프레임워크**

- **프레임워크**: 개발을 쉽게 해주는 도구 모음
- **웹 서버**: HTTP 요청을 받아서 처리하는 프로그램
- **Python**: 프로그래밍 언어

---

## 🔧 프레임워크란?

### 도구 비유
- **프레임워크 없이**: 맨손으로 집 짓기 (매우 어려움)
- **프레임워크 사용**: 공구함과 설계도 제공받아 집 짓기 (쉬움)

### 코드 비유
```python
# 프레임워크 없이 (매우 복잡)
# HTTP 요청 파싱, 라우팅, JSON 변환 등 모든 걸 직접 구현해야 함

# FastAPI 사용 (간단)
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def hello():
    return {"message": "Hello"}
```

---

## 🚀 FastAPI의 특징

### 1. 빠름 (Fast)
- **비동기 처리** 지원 (async/await)
- 여러 요청을 동시에 처리 가능
- Node.js나 Go와 비슷한 성능

### 2. 쉬움 (Easy)
- **타입 힌트** 자동 검증
- **자동 문서 생성** (Swagger UI)
- **직관적인 문법**

### 3. 현대적 (Modern)
- Python 3.6+ 기능 활용
- Pydantic으로 데이터 검증
- OpenAPI 표준 준수

---

## 🏗️ FastAPI 구조

### 핵심 구성 요소

#### 1. FastAPI 앱 객체
```python
from fastapi import FastAPI

app = FastAPI(title="My API")
```
- **역할**: 웹 서버의 핵심
- **기능**: 요청을 받고 응답을 보냄

#### 2. 라우터 (Router)
```python
from fastapi import APIRouter

router = APIRouter(prefix="/api/profiles")
```
- **역할**: 관련된 엔드포인트를 그룹화
- **장점**: 코드 정리, 재사용 가능

#### 3. 엔드포인트 (Endpoint)
```python
@router.get("/{id}")
def get_profile(id: int):
    return {"id": id}
```
- **역할**: 특정 URL과 함수를 연결
- **데코레이터**: `@router.get()` 등

#### 4. 의존성 주입 (Dependency Injection)
```python
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/")
def get_profiles(db: Session = Depends(get_db)):
    return db.query(Profile).all()
```
- **역할**: 공통 기능을 재사용
- **예시**: DB 세션, 인증 등

---

## 🔄 FastAPI 작동 원리

### 요청 처리 흐름

```
1. 클라이언트 요청
   ↓
2. FastAPI가 요청 받음
   ↓
3. URL 경로 매칭 (라우팅)
   ↓
4. 타입 검증 (Pydantic)
   ↓
5. 함수 실행
   ↓
6. 응답 반환 (자동 JSON 변환)
```

### 실제 예시
```python
# 클라이언트 요청
GET /api/profiles/1

# FastAPI 처리
@router.get("/{profile_id}")  # 경로 매칭
def get_profile(profile_id: int):  # 타입 검증 (int인지 확인)
    # 함수 실행
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    return profile  # 자동으로 JSON 변환
```

---

## 💡 FastAPI의 핵심 기능

### 1. 자동 타입 검증
```python
@router.get("/{profile_id}")
def get_profile(profile_id: int):  # int가 아니면 자동으로 에러
    pass

# 요청: /api/profiles/abc
# 응답: 422 Validation Error (자동!)
```

### 2. 자동 문서 생성
```python
# 코드만 작성하면
@router.post("/profiles/")
def create_profile(profile: ProfileCreate):
    pass

# 자동으로 /docs에 문서 생성됨!
```

### 3. 자동 JSON 변환
```python
def get_profile():
    return {"id": 1, "name": "홍길동"}
    # 자동으로 JSON으로 변환되어 응답
```

### 4. 비동기 지원
```python
@app.get("/")
async def read_data():
    data = await fetch_from_database()  # 다른 작업 가능
    return data
```

---

## 🆚 다른 프레임워크와 비교

### Flask
```python
# Flask
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return {"message": "Hello"}
```
- **장점**: 간단함, 유연함
- **단점**: 타입 검증 수동, 문서 수동 작성

### Django
```python
# Django (더 복잡)
# settings.py, urls.py, views.py 등 여러 파일 필요
```
- **장점**: 기능 많음, 관리자 페이지
- **단점**: 무거움, 학습 곡선 높음

### FastAPI
```python
# FastAPI
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def hello():
    return {"message": "Hello"}
```
- **장점**: 빠름, 타입 검증 자동, 문서 자동
- **단점**: 비교적 새로운 프레임워크

---

## 🎓 FastAPI 사용 패턴

### 패턴 1: 기본 사용
```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"Hello": "World"}
```

### 패턴 2: 라우터 분리
```python
# main.py
from fastapi import FastAPI
from app.routers import profiles

app = FastAPI()
app.include_router(profiles.router)

# routers/profiles.py
from fastapi import APIRouter
router = APIRouter(prefix="/api/profiles")

@router.get("/")
def get_profiles():
    pass
```

### 패턴 3: 의존성 주입
```python
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/")
def get_profiles(db: Session = Depends(get_db)):
    return db.query(Profile).all()
```

---

## 🔍 FastAPI 내부 동작

### 1. 요청 받기
- **ASGI 서버** (Uvicorn 등)가 HTTP 요청 받음
- FastAPI로 전달

### 2. 라우팅
- URL 경로와 HTTP 메서드로 매칭
- 해당 함수 찾기

### 3. 검증
- **Pydantic**으로 타입 검증
- 잘못된 요청이면 자동 에러 반환

### 4. 실행
- 함수 실행
- 결과 반환

### 5. 응답
- 자동으로 JSON 변환
- HTTP 응답 생성

---

## 📚 FastAPI의 핵심 개념

### 1. 데코레이터 (Decorator)
```python
@router.get("/")
def function():
    pass
```
- **역할**: 함수를 꾸며서 기능 추가
- **예시**: `@router.get()` = GET 요청 처리 기능 추가

### 2. 타입 힌트 (Type Hints)
```python
def get_profile(profile_id: int) -> dict:
    pass
```
- **역할**: 변수 타입 명시
- **효과**: 자동 검증, 자동 완성

### 3. Pydantic 모델
```python
class ProfileCreate(BaseModel):
    name: str
    age: int
```
- **역할**: 데이터 구조 정의
- **효과**: 자동 검증, 자동 문서화

### 4. 의존성 주입
```python
def get_db():
    yield db

def function(db: Session = Depends(get_db)):
    pass
```
- **역할**: 공통 기능 재사용
- **효과**: 코드 중복 제거

---

## 🛠️ FastAPI로 할 수 있는 것

### 1. REST API 만들기
```python
@router.get("/items/{id}")
@router.post("/items/")
@router.put("/items/{id}")
@router.delete("/items/{id}")
```

### 2. WebSocket 사용
```python
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    await websocket.send_json({"message": "Hello"})
```

### 3. 파일 업로드
```python
@app.post("/upload")
async def upload_file(file: UploadFile):
    return {"filename": file.filename}
```

### 4. 인증/권한
```python
def verify_token(token: str = Header()):
    # 토큰 검증 로직
    return user

@app.get("/protected")
def protected_route(user = Depends(verify_token)):
    return {"user": user}
```

---

## 🎯 FastAPI를 사용하는 이유

### 1. 개발 속도
- 자동 문서 생성으로 시간 절약
- 타입 검증 자동으로 버그 감소

### 2. 성능
- 비동기 처리로 빠른 응답
- 높은 동시 처리 능력

### 3. 유지보수
- 타입 힌트로 코드 이해 쉬움
- 자동 문서로 API 이해 쉬움

### 4. 현대적
- Python 최신 기능 활용
- 표준 준수 (OpenAPI)

---

## 📖 요약

### FastAPI란?
- Python 웹 서버 프레임워크
- 빠르고, 쉽고, 현대적

### 핵심 기능
- 자동 타입 검증
- 자동 문서 생성
- 자동 JSON 변환
- 비동기 지원

### 사용 이유
- 개발 빠름
- 성능 좋음
- 유지보수 쉬움

### 작동 원리
1. 요청 받기
2. 라우팅
3. 검증
4. 실행
5. 응답

**결론**: FastAPI는 웹 서버를 쉽고 빠르게 만들 수 있게 해주는 도구입니다.

