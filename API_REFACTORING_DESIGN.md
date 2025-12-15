# API 리팩토링 설계 문서

## 목표
프론트엔드에서 처리하고 있는 비즈니스 로직과 데이터 변환을 백엔드로 이동하여, 프론트엔드는 단순히 HTTP 메서드(GET, POST, PUT, DELETE)만 호출하도록 설계합니다.

---

## 현재 상태 분석

### 프론트엔드에서 처리 중인 비즈니스 로직

#### 1. **데이터 변환 로직** (`api_service.dart`)
- **소리 높낮이 변환**: 문자열 → 숫자
  - "없음" → 0
  - "1단계" → 1
  - "2단계" → 2
  - "3단계" → 3
  
- **감정 색상 변환**: 문자열 → 숫자
  - "없음" → 0
  - "빨강" → 1
  - "파랑" → 2
  - "초록" → 3

#### 2. **모드 생성 로직** (`createCustomMode`)
- 모드 이름 기본값 설정 (빈 문자열이면 선택한 모드 타입 사용)
- 기본값 설정 (is_empathy_on, fontSize_toggle 등)

#### 3. **모드 적용 로직**
- 프로필에 모드 적용 시 추가 검증/처리

---

## 설계 원칙

### 1. **RESTful API 설계**
- **GET**: 데이터 조회 (Read)
- **POST**: 새 리소스 생성 (Create)
- **PUT**: 리소스 전체 업데이트 또는 생성 (Update/Create)
- **DELETE**: 리소스 삭제 (Delete)

### 2. **백엔드 책임**
- ✅ 모든 비즈니스 로직 처리
- ✅ 데이터 검증 및 변환
- ✅ 기본값 설정
- ✅ 관계형 데이터 처리 (Profile ↔ Mode)

### 3. **프론트엔드 책임**
- ✅ HTTP 메서드 호출만
- ✅ 요청 데이터 전송
- ✅ 응답 데이터 표시
- ❌ 데이터 변환/계산 없음

---

## API 엔드포인트 설계

### 1. Accounts (계정 관리)

#### `POST /api/accounts/`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `GET /api/accounts/{account_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `POST /api/accounts/login`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

---

### 2. Profiles (프로필 관리)

#### `GET /api/profiles/account/{account_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `GET /api/profiles/account/{account_id}/first`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `PUT /api/profiles/{profile_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

---

### 3. Caption Modes (자막 모드 관리)

#### `GET /api/caption-modes/?profile_id={profile_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `POST /api/caption-modes/` ⚠️ **변경 필요**
**현재 문제점**:
- 프론트엔드에서 `createCustomMode` 함수가 데이터 변환을 수행
- 소리 높낮이 문자열 → 숫자 변환
- 감정 색상 문자열 → 숫자 변환
- 기본값 설정

**새 설계**:
```python
# Request Body (프론트엔드는 그대로 전송)
{
    "profile_id": 1,
    "mode_name": "커스텀 모드",  # 빈 문자열이면 selected_mode 사용
    "selected_mode": "movie",  # 'none', 'movie', 'documentary', 'variety'
    "sound_pitch": "1단계",  # '없음', '1단계', '2단계', '3단계'
    "emotion_color": "빨강",  # '없음', '빨강', '파랑', '초록'
    "speaker": true,
    "bgm": true,
    "effect": true
}

# 백엔드에서 처리:
# 1. sound_pitch → font_level 변환
# 2. emotion_color → color_level 변환
# 3. mode_name이 빈 문자열이면 selected_mode 사용
# 4. 기본값 설정 (is_empathy_on, fontSize_toggle 등)
```

**변경 사항**:
- 백엔드에서 문자열 → 숫자 변환 처리
- 백엔드에서 기본값 설정
- 프론트엔드는 원본 문자열 그대로 전송

#### `PUT /api/caption-modes/{mode_id}` ⚠️ **변경 필요**
**현재**: ✅ 부분 업데이트 지원
**변경**: 없음 (이미 잘 설계됨)

#### `DELETE /api/caption-modes/{mode_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

---

### 4. Caption Settings (자막 설정)

#### `GET /api/caption-settings/profile/{profile_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `PUT /api/caption-settings/profile/{profile_id}?mode_id={mode_id}` ⚠️ **변경 필요**
**현재 문제점**:
- Query Parameter로 mode_id 전달
- 프론트엔드에서 여러 단계로 호출

**새 설계**:
```python
# Request Body로 변경 (더 명확함)
PUT /api/caption-settings/profile/{profile_id}
{
    "mode_id": 5
}

# 또는 더 확장 가능한 형태
PUT /api/caption-settings/profile/{profile_id}
{
    "mode_id": 5,
    "apply_immediately": true  # 즉시 적용 여부
}
```

**변경 사항**:
- Query Parameter → Request Body로 변경
- 프론트엔드는 단순히 mode_id만 전송

---

### 5. Subtitles (자막)

#### `GET /subtitles/profiles/{profile_id}/modes`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `PUT /subtitles/modes/{mode_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

#### `POST /subtitles/profiles/{profile_id}/apply-mode/{mode_id}`
**현재**: ✅ 이미 백엔드에서 처리
**변경**: 없음

---

## 백엔드 변경 사항 상세

### 1. `caption_modes.py` - 모드 생성 로직 개선

#### 새로운 Request Schema
```python
class CaptionModeCreateCustom(BaseModel):
    profile_id: int
    mode_name: Optional[str] = None  # None이면 selected_mode 사용
    selected_mode: Optional[str] = None  # 'none', 'movie', 'documentary', 'variety'
    sound_pitch: Optional[str] = None  # '없음', '1단계', '2단계', '3단계'
    emotion_color: Optional[str] = None  # '없음', '빨강', '파랑', '초록'
    speaker: bool = False
    bgm: bool = False
    effect: bool = False
```

#### 변환 함수 추가
```python
def convert_sound_pitch_to_font_level(sound_pitch: str) -> int:
    """소리 높낮이 문자열을 숫자로 변환"""
    mapping = {
        "없음": 0,
        "1단계": 1,
        "2단계": 2,
        "3단계": 3
    }
    return mapping.get(sound_pitch, 0)

def convert_emotion_color_to_color_level(emotion_color: str) -> int:
    """감정 색상 문자열을 숫자로 변환"""
    mapping = {
        "없음": 0,
        "빨강": 1,
        "파랑": 2,
        "초록": 3
    }
    return mapping.get(emotion_color, 0)

def get_default_mode_name(selected_mode: str) -> str:
    """선택한 모드 타입에 따른 기본 모드 이름"""
    mapping = {
        "none": "없음",
        "movie": "영화",
        "documentary": "다큐멘터리",
        "variety": "예능"
    }
    return mapping.get(selected_mode, "커스텀")
```

#### 새로운 엔드포인트 추가
```python
@router.post("/custom", response_model=schemas.CaptionModeResponse)
def create_custom_mode(
    mode_data: CaptionModeCreateCustom,
    db: Session = Depends(get_db)
):
    """커스텀 모드 생성 (프론트엔드 변환 로직 제거)"""
    # 1. 모드 이름 결정
    mode_name = mode_data.mode_name
    if not mode_name and mode_data.selected_mode:
        mode_name = get_default_mode_name(mode_data.selected_mode)
    
    # 2. 데이터 변환
    font_level = convert_sound_pitch_to_font_level(mode_data.sound_pitch) if mode_data.sound_pitch else 0
    color_level = convert_emotion_color_to_color_level(mode_data.emotion_color) if mode_data.emotion_color else 0
    
    # 3. 기본값 설정
    db_mode = models.CaptionModeCustomizing(
        profile_id=mode_data.profile_id,
        mode_name=mode_name,
        is_empathy_on=False,
        fontSize_toggle=False,
        fontColor_toggle=False,
        font_level=font_level,
        color_level=color_level,
        speaker=mode_data.speaker,
        bgm=mode_data.bgm,
        effect=mode_data.effect
    )
    
    db.add(db_mode)
    db.commit()
    db.refresh(db_mode)
    return db_mode
```

---

### 2. `caption_settings.py` - 설정 업데이트 개선

#### 새로운 Request Schema
```python
class CaptionSettingUpdate(BaseModel):
    mode_id: int
    apply_immediately: bool = True
```

#### 엔드포인트 수정
```python
@router.put("/profile/{profile_id}")
def update_caption_setting(
    profile_id: int,
    setting: CaptionSettingUpdate,  # Request Body로 변경
    db: Session = Depends(get_db)
):
    """프로필의 자막 설정 업데이트 (Request Body 사용)"""
    # 기존 로직 유지
    profile = db.query(models.Profile).filter(models.Profile.id == profile_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    mode = db.query(models.CaptionModeCustomizing).filter(
        models.CaptionModeCustomizing.id == setting.mode_id,
        models.CaptionModeCustomizing.profile_id == profile_id
    ).first()
    if not mode:
        raise HTTPException(status_code=404, detail="Caption mode not found")
    
    profile.current_mode_id = setting.mode_id
    db.commit()
    db.refresh(profile)
    
    return {
        "status": "success",
        "profile_id": profile_id,
        "current_mode_id": profile.current_mode_id
    }
```

---

## 프론트엔드 변경 사항 상세

### 1. `api_service.dart` - 변환 로직 제거

#### 변경 전 (`createCustomMode`)
```dart
static Future<Map<String, dynamic>> createCustomMode({
  required int profileId,
  required String modeName,
  required String selectedMode,
  required String soundPitch,
  required String emotionColor,
  required bool speaker,
  required bool bgm,
  required bool effect,
}) async {
  // ❌ 프론트엔드에서 변환 처리
  int fontLevel = 0;
  if (soundPitch == '1단계') fontLevel = 1;
  else if (soundPitch == '2단계') fontLevel = 2;
  else if (soundPitch == '3단계') fontLevel = 3;
  
  int colorLevel = 0;
  if (emotionColor == '빨강') colorLevel = 1;
  else if (emotionColor == '파랑') colorLevel = 2;
  else if (emotionColor == '초록') colorLevel = 3;
  
  final body = {
    'profile_id': profileId,
    'mode_name': modeName.isEmpty ? selectedMode : modeName,
    'is_empathy_on': false,
    'fontSize_toggle': false,
    'fontColor_toggle': false,
    'font_level': fontLevel,  // 변환된 값
    'color_level': colorLevel,  // 변환된 값
    'speaker': speaker,
    'bgm': bgm,
    'effect': effect,
  };
  
  final response = await http.post(uri, headers: _headers, body: jsonEncode(body));
  // ...
}
```

#### 변경 후 (`createCustomMode`)
```dart
static Future<Map<String, dynamic>> createCustomMode({
  required int profileId,
  required String modeName,
  required String selectedMode,
  required String soundPitch,
  required String emotionColor,
  required bool speaker,
  required bool bgm,
  required bool effect,
}) async {
  // ✅ 프론트엔드는 원본 데이터만 전송
  final uri = Uri.parse('$baseUrl/caption-modes/custom');
  final body = {
    'profile_id': profileId,
    'mode_name': modeName.isEmpty ? null : modeName,  // 빈 문자열은 null로
    'selected_mode': selectedMode,
    'sound_pitch': soundPitch,  // 원본 문자열 그대로
    'emotion_color': emotionColor,  // 원본 문자열 그대로
    'speaker': speaker,
    'bgm': bgm,
    'effect': effect,
  };
  
  final response = await http.post(
    uri,
    headers: _headers,
    body: jsonEncode(body),
  );
  
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Failed to create custom mode (${response.statusCode}): ${response.body}');
  }
  
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return data;
}
```

#### `updateCaptionMode` 변경
```dart
// 변경 전
static Future<void> updateCaptionMode(int profileId, int modeId) async {
  final uri = Uri.parse('$baseUrl/caption-settings/profile/$profileId').replace(
    queryParameters: {'mode_id': modeId.toString()},  // Query Parameter
  );
  final response = await http.put(uri, headers: _headers);
  // ...
}

// 변경 후
static Future<void> updateCaptionMode(int profileId, int modeId) async {
  final uri = Uri.parse('$baseUrl/caption-settings/profile/$profileId');
  final body = {
    'mode_id': modeId,
  };
  final response = await http.put(
    uri,
    headers: _headers,
    body: jsonEncode(body),  // Request Body로 변경
  );
  // ...
}
```

---

## 마이그레이션 계획

### Phase 1: 백엔드 변경
1. ✅ `caption_modes.py`에 변환 함수 추가
2. ✅ `POST /api/caption-modes/custom` 엔드포인트 추가
3. ✅ `caption_settings.py`의 `PUT` 엔드포인트 수정 (Query → Body)

### Phase 2: 프론트엔드 변경
1. ✅ `api_service.dart`의 `createCustomMode` 수정
2. ✅ `api_service.dart`의 `updateCaptionMode` 수정
3. ✅ 모든 호출부 업데이트

### Phase 3: 테스트 및 검증
1. ✅ 기존 기능 동작 확인
2. ✅ 에러 처리 확인
3. ✅ 데이터 일관성 확인

---

## API 엔드포인트 요약

### Accounts
- `POST /api/accounts/` - 계정 생성
- `GET /api/accounts/{account_id}` - 계정 조회
- `POST /api/accounts/login` - 로그인

### Profiles
- `GET /api/profiles/account/{account_id}` - 계정의 프로필 목록
- `GET /api/profiles/account/{account_id}/first` - 첫 번째 프로필 조회
- `PUT /api/profiles/{profile_id}` - 프로필 업데이트

### Caption Modes
- `GET /api/caption-modes/?profile_id={profile_id}` - 모드 목록 조회
- `POST /api/caption-modes/` - 기본 모드 생성 (기존)
- `POST /api/caption-modes/custom` - **커스텀 모드 생성 (신규)**
- `PUT /api/caption-modes/{mode_id}` - 모드 업데이트
- `DELETE /api/caption-modes/{mode_id}` - 모드 삭제

### Caption Settings
- `GET /api/caption-settings/profile/{profile_id}` - 설정 조회
- `PUT /api/caption-settings/profile/{profile_id}` - **설정 업데이트 (Body로 변경)**

### Subtitles
- `GET /subtitles/profiles/{profile_id}/modes` - 자막 모드 목록
- `PUT /subtitles/modes/{mode_id}` - 자막 모드 업데이트
- `POST /subtitles/profiles/{profile_id}/apply-mode/{mode_id}` - 모드 적용

---

## 장점

1. **관심사 분리**: 프론트엔드는 UI, 백엔드는 비즈니스 로직
2. **유지보수성**: 변환 로직이 한 곳에만 존재
3. **일관성**: 모든 클라이언트가 동일한 변환 로직 사용
4. **테스트 용이성**: 백엔드 로직만 테스트하면 됨
5. **확장성**: 다른 클라이언트 추가 시 변환 로직 재사용 가능

---

## 주의사항

1. **하위 호환성**: 기존 `POST /api/caption-modes/` 엔드포인트는 유지
2. **에러 처리**: 변환 실패 시 명확한 에러 메시지 반환
3. **데이터 검증**: 백엔드에서 모든 입력값 검증 필요
4. **문서화**: API 문서에 변환 규칙 명시

