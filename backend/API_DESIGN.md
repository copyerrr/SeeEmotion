# API 설계 문서

## 📋 목차
1. [기본 정보](#기본-정보)
2. [Accounts API](#accounts-api)
3. [Profiles API](#profiles-api)
4. [Caption Modes API](#caption-modes-api)
5. [Caption Settings API](#caption-settings-api)
6. [데이터 모델](#데이터-모델)

---

## 기본 정보

### Base URL
```
http://localhost:8000/api
```

### 공통 사항
- 모든 API는 RESTful 방식으로 설계됨
- 요청/응답 형식: JSON
- 인증: 현재 미구현 (추후 추가 예정)

### HTTP 메서드
- `GET`: 데이터 조회
- `POST`: 데이터 생성
- `PUT`: 데이터 수정
- `DELETE`: 데이터 삭제

---

## Accounts API

### 1. 계정 생성
```http
POST /api/accounts/
```

**Request Body:**
```json
{
  "user_id": 1,
  "email": "user@example.com"
}
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "user_id": 1,
  "email": "user@example.com",
  "created_at": "2024-01-01T00:00:00",
  "last_login_at": null
}
```

**에러:**
- `400 Bad Request`: user_id가 이미 존재하는 경우

---

### 2. 모든 계정 조회
```http
GET /api/accounts/?skip=0&limit=100
```

**Query Parameters:**
- `skip` (optional): 건너뛸 개수 (기본값: 0)
- `limit` (optional): 가져올 개수 (기본값: 100)

**Response:** `200 OK`
```json
[
  {
    "id": 1,
    "user_id": 1,
    "email": "user@example.com",
    "created_at": "2024-01-01T00:00:00",
    "last_login_at": null
  }
]
```

---

### 3. 계정 조회 (ID로)
```http
GET /api/accounts/{account_id}
```

**Path Parameters:**
- `account_id`: 계정 ID

**Response:** `200 OK`
```json
{
  "id": 1,
  "user_id": 1,
  "email": "user@example.com",
  "created_at": "2024-01-01T00:00:00",
  "last_login_at": null
}
```

**에러:**
- `404 Not Found`: 계정이 없는 경우

---

### 4. 계정 조회 (user_id로)
```http
GET /api/accounts/user/{user_id}
```

**Path Parameters:**
- `user_id`: 사용자 ID

**Response:** `200 OK` (위와 동일)

**에러:**
- `404 Not Found`: 계정이 없는 경우

---

### 5. 계정 조회 (이메일로)
```http
GET /api/accounts/email/{email}
```

**Path Parameters:**
- `email`: 이메일 주소

**Response:** `200 OK` (위와 동일)

**에러:**
- `404 Not Found`: 계정이 없는 경우

---

### 6. 로그인 또는 계정 생성
```http
POST /api/accounts/login
```

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

**Response:** `200 OK`
- 기존 계정이 있으면: 계정 정보 반환 + `last_login_at` 업데이트
- 기존 계정이 없으면: 새 계정 생성 후 반환

```json
{
  "id": 1,
  "user_id": 1,
  "email": "user@example.com",
  "created_at": "2024-01-01T00:00:00",
  "last_login_at": "2024-01-01T12:00:00"
}
```

---

### 7. 계정 수정
```http
PUT /api/accounts/{account_id}
```

**Path Parameters:**
- `account_id`: 계정 ID

**Request Body:**
```json
{
  "email": "newemail@example.com",
  "last_login_at": "2024-01-01T12:00:00"
}
```
(모든 필드는 선택사항)

**Response:** `200 OK` (수정된 계정 정보)

**에러:**
- `404 Not Found`: 계정이 없는 경우

---

### 8. 계정 삭제
```http
DELETE /api/accounts/{account_id}
```

**Path Parameters:**
- `account_id`: 계정 ID

**Response:** `200 OK`
```json
{
  "message": "Account deleted successfully"
}
```

**에러:**
- `404 Not Found`: 계정이 없는 경우

---

## Profiles API

### 1. 프로필 생성
```http
POST /api/profiles/
```

**Request Body:**
```json
{
  "account_id": 1,
  "nickname": "홍길동",
  "avatar_image": "avatar.jpg",
  "user_type": "HEARING",
  "is_active": true
}
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "account_id": 1,
  "nickname": "홍길동",
  "avatar_image": "avatar.jpg",
  "user_type": "HEARING",
  "is_active": true,
  "current_mode_id": null,
  "created_at": "2024-01-01T00:00:00"
}
```

**특징:**
- 프로필 생성 시 기본 모드 6개 자동 생성:
  - 없음, 일반, 청각, 시각, 아동, 시니어

**에러:**
- `404 Not Found`: account_id에 해당하는 계정이 없는 경우

---

### 2. 모든 프로필 조회
```http
GET /api/profiles/?skip=0&limit=100
```

**Query Parameters:**
- `skip` (optional): 건너뛸 개수 (기본값: 0)
- `limit` (optional): 가져올 개수 (기본값: 100)

**Response:** `200 OK`
```json
[
  {
    "id": 1,
    "account_id": 1,
    "nickname": "홍길동",
    "avatar_image": "avatar.jpg",
    "user_type": "HEARING",
    "is_active": true,
    "current_mode_id": 1,
    "created_at": "2024-01-01T00:00:00"
  }
]
```

---

### 3. 프로필 조회 (ID로, 설정 포함)
```http
GET /api/profiles/{profile_id}
```

**Path Parameters:**
- `profile_id`: 프로필 ID

**Response:** `200 OK`
```json
{
  "id": 1,
  "account_id": 1,
  "nickname": "홍길동",
  "avatar_image": "avatar.jpg",
  "user_type": "HEARING",
  "is_active": true,
  "current_mode_id": 1,
  "created_at": "2024-01-01T00:00:00",
  "current_mode": {
    "id": 1,
    "profile_id": 1,
    "mode_name": "영화/드라마",
    "sound_pitch": "2단계",
    "emotion_color": "빨강",
    // ... 기타 필드
  },
  "custom_modes": [
    // 커스텀 모드 목록
  ]
}
```

**에러:**
- `404 Not Found`: 프로필이 없는 경우

---

### 4. 계정의 모든 프로필 조회
```http
GET /api/profiles/account/{account_id}
```

**Path Parameters:**
- `account_id`: 계정 ID

**Response:** `200 OK` (프로필 배열)

**에러:**
- `500 Internal Server Error`: 데이터베이스 오류

---

### 5. 계정의 첫 번째 프로필 조회 (설정 포함)
```http
GET /api/profiles/account/{account_id}/first
```

**Path Parameters:**
- `account_id`: 계정 ID

**Response:** `200 OK` (프로필 정보 + 설정, 위의 "프로필 조회"와 동일 형식)

**에러:**
- `404 Not Found`: 계정에 프로필이 없는 경우

---

### 6. 프로필 수정
```http
PUT /api/profiles/{profile_id}
```

**Path Parameters:**
- `profile_id`: 프로필 ID

**Request Body:**
```json
{
  "nickname": "새 닉네임",
  "user_type": "SENIOR",
  "is_active": false
}
```
(모든 필드는 선택사항)

**Response:** `200 OK` (수정된 프로필 정보)

**에러:**
- `404 Not Found`: 프로필이 없는 경우

---

### 7. 프로필 삭제
```http
DELETE /api/profiles/{profile_id}
```

**Path Parameters:**
- `profile_id`: 프로필 ID

**Response:** `200 OK`
```json
{
  "message": "Profile deleted successfully"
}
```

**에러:**
- `404 Not Found`: 프로필이 없는 경우

---

## Caption Modes API

### 1. 자막 모드 생성 (기본)
```http
POST /api/caption-modes/
```

**Request Body:**
```json
{
  "profile_id": 1,
  "mode_name": "영화/드라마",
  "is_empathy_on": true,
  "font_size": 24,
  "fontSize_toggle": true,
  "font_color": "#FFFFFF",
  "fontColor_toggle": true,
  "font_level": 2,
  "color_level": 2,
  "speaker": true,
  "bgm": true,
  "effect": true
}
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "profile_id": 1,
  "mode_name": "영화/드라마",
  "sound_pitch": "2단계",
  "emotion_color": "빨강",
  // ... 기타 필드
}
```

**에러:**
- `404 Not Found`: profile_id에 해당하는 프로필이 없는 경우

---

### 2. 커스텀 모드 생성 (권장)
```http
POST /api/caption-modes/custom
```

**Request Body:**
```json
{
  "profile_id": 1,
  "mode_name": "영화/드라마",
  "selected_mode": "movie",
  "sound_pitch": "2단계",
  "emotion_color": "빨강",
  "speaker": true,
  "bgm": true,
  "effect": true
}
```

**특징:**
- `sound_pitch`와 `emotion_color`를 문자열로 전송하면 백엔드에서 자동으로 변환
- `sound_pitch`: '없음', '1단계', '2단계', '3단계'
- `emotion_color`: '없음', '빨강', '파랑', '초록'
- `mode_name`이 없으면 `selected_mode`로 자동 생성

**Response:** `200 OK` (생성된 모드 정보)

**에러:**
- `404 Not Found`: profile_id에 해당하는 프로필이 없는 경우

---

### 3. 자막 모드 목록 조회
```http
GET /api/caption-modes/?profile_id=1&skip=0&limit=100
```

**Query Parameters:**
- `profile_id` (optional): 프로필 ID로 필터링
- `skip` (optional): 건너뛸 개수 (기본값: 0)
- `limit` (optional): 가져올 개수 (기본값: 100)

**Response:** `200 OK`
```json
[
  {
    "id": 1,
    "profile_id": 1,
    "mode_name": "영화/드라마",
    "sound_pitch": "2단계",
    "emotion_color": "빨강",
    // ... 기타 필드
  }
]
```

---

### 4. 자막 모드 조회 (ID로)
```http
GET /api/caption-modes/{mode_id}
```

**Path Parameters:**
- `mode_id`: 모드 ID

**Response:** `200 OK` (모드 정보)

**에러:**
- `404 Not Found`: 모드가 없는 경우

---

### 5. 자막 모드 수정
```http
PUT /api/caption-modes/{mode_id}
```

**Path Parameters:**
- `mode_id`: 모드 ID

**Request Body:**
```json
{
  "mode_name": "새 모드 이름",
  "sound_pitch": "3단계",
  "emotion_color": "파랑",
  "speaker": false,
  "bgm": true,
  "effect": false
}
```
(모든 필드는 선택사항)

**특징:**
- `sound_pitch`와 `emotion_color`를 문자열로 전송하면 백엔드에서 자동 변환
- `sound_pitch`가 '없음'이 아니면 `fontSize_toggle`이 자동으로 `true`로 설정
- `emotion_color`가 '없음'이 아니면 `fontColor_toggle`이 자동으로 `true`로 설정

**Response:** `200 OK` (수정된 모드 정보)

**에러:**
- `404 Not Found`: 모드가 없는 경우

---

### 6. 모드별 기본 설정 업데이트
```http
PUT /api/caption-modes/{mode_id}/default-settings
```

**Path Parameters:**
- `mode_id`: 모드 ID

**Request Body:**
```json
{
  "mode_type": "movie"
}
```

**mode_type 옵션:**
- `"movie"`: 영화/드라마 모드
  - font level 2, color level 2
  - font on, color on, 화자 on, 배경음 on, 효과음 on
- `"documentary"`: 다큐멘터리 모드
  - font off, color off, 화자 off
  - 배경음 on, 효과음 on
- `"variety"`: 예능 모드
  - font level 2, color level 2
  - font on, color on, 화자 off
  - 배경음 on, 효과음 off

**Response:** `200 OK` (업데이트된 모드 정보)

**에러:**
- `404 Not Found`: 모드가 없는 경우
- `400 Bad Request`: 잘못된 mode_type인 경우

---

### 7. 자막 모드 삭제
```http
DELETE /api/caption-modes/{mode_id}
```

**Path Parameters:**
- `mode_id`: 모드 ID

**Response:** `200 OK`
```json
{
  "message": "Caption mode deleted successfully",
  "id": 1
}
```

**특징:**
- 해당 모드를 사용 중인 프로필의 `current_mode_id`가 자동으로 `null`로 설정됨

**에러:**
- `404 Not Found`: 모드가 없는 경우
- `500 Internal Server Error`: 삭제 실패

---

## Caption Settings API

### 1. 자막 설정 업데이트 (모드 선택)
```http
PUT /api/caption-settings/profile/{profile_id}
```

**Path Parameters:**
- `profile_id`: 프로필 ID

**Request Body:**
```json
{
  "mode_id": 1,
  "apply_immediately": true
}
```

**용도:**
- 프로필의 현재 선택된 모드를 변경할 때 사용
- `profile.current_mode_id`를 업데이트함

**Response:** `200 OK`
```json
{
  "status": "success",
  "profile_id": 1,
  "current_mode_id": 1
}
```

**에러:**
- `404 Not Found`: 프로필 또는 모드가 없는 경우
- `404 Not Found`: 모드가 해당 프로필의 것이 아닌 경우

---

### 2. 자막 설정 조회
```http
GET /api/caption-settings/profile/{profile_id}
```

**Path Parameters:**
- `profile_id`: 프로필 ID

**Response:** `200 OK`
```json
{
  "profile_id": 1,
  "current_mode_id": 1,
  "mode": {
    "id": 1,
    "profile_id": 1,
    "mode_name": "영화/드라마",
    "sound_pitch": "2단계",
    "emotion_color": "빨강",
    // ... 기타 필드
  }
}
```

**모드가 선택되지 않은 경우:**
```json
{
  "profile_id": 1,
  "current_mode_id": null,
  "mode": null
}
```

**에러:**
- `404 Not Found`: 프로필이 없는 경우

---

## 데이터 모델

### Account (계정)
```json
{
  "id": 1,
  "user_id": 1,
  "email": "user@example.com",
  "created_at": "2024-01-01T00:00:00",
  "last_login_at": "2024-01-01T12:00:00"
}
```

### Profile (프로필)
```json
{
  "id": 1,
  "account_id": 1,
  "nickname": "홍길동",
  "avatar_image": "avatar.jpg",
  "user_type": "HEARING",
  "is_active": true,
  "current_mode_id": 1,
  "created_at": "2024-01-01T00:00:00"
}
```

**user_type 옵션:**
- `"HEARING"`: 청각 장애
- `"SENIOR"`: 시니어
- `"VISION"`: 시각 장애
- `"GENERAL"`: 일반
- `"FOREIGN_LEARNER"`: 외국인 학습자
- `"CHILD"`: 아동

### CaptionMode (자막 모드)
```json
{
  "id": 1,
  "profile_id": 1,
  "mode_name": "영화/드라마",
  "is_empathy_on": true,
  "font_size": 24,
  "fontSize_toggle": true,
  "font_color": "#FFFFFF",
  "fontColor_toggle": true,
  "font_level": 2,
  "color_level": 2,
  "sound_pitch": "2단계",
  "emotion_color": "빨강",
  "speaker": true,
  "bgm": true,
  "effect": true,
  "updated_at": "2024-01-01T00:00:00"
}
```

**sound_pitch 옵션:**
- `"없음"`: 0단계 (font_level: 0)
- `"1단계"`: font_level: 1
- `"2단계"`: font_level: 2
- `"3단계"`: font_level: 3

**emotion_color 옵션:**
- `"없음"`: color_level: 0
- `"빨강"`: color_level: 1
- `"파랑"`: color_level: 2
- `"초록"`: color_level: 3

---

## 🔄 데이터 변환 로직

### 프론트엔드 → 백엔드 (요청 시)
- `sound_pitch` 문자열 → `font_level` 숫자로 변환
- `emotion_color` 문자열 → `color_level` 숫자로 변환

### 백엔드 → 프론트엔드 (응답 시)
- `font_level` 숫자 → `sound_pitch` 문자열로 역변환
- `color_level` 숫자 → `emotion_color` 문자열로 역변환

**중요:** 모든 변환 로직은 백엔드에서 처리되므로, 프론트엔드는 문자열 값만 전송하면 됨.

---

## 📝 참고사항

1. **RESTful 설계 원칙 준수**
   - 리소스 중심의 URL 설계
   - 적절한 HTTP 메서드 사용
   - 명확한 요청/응답 형식

2. **에러 처리**
   - 모든 에러는 JSON 형식으로 반환
   - HTTP 상태 코드 사용 (404, 400, 500 등)

3. **데이터 변환**
   - 프론트엔드는 변환 로직 없이 문자열 값만 전송
   - 백엔드에서 모든 변환 처리

4. **자동 생성**
   - 프로필 생성 시 기본 모드 6개 자동 생성
   - 계정 로그인 시 자동 계정 생성 지원

