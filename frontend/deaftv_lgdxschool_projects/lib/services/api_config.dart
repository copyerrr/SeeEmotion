/// API 설정 상수 (백엔드로 모든 로직 이동)
class ApiConfig {
  // 로컬 개발용 백엔드 API 기본 URL
  static const String baseUrl = 'http://localhost:8000/api';
  // 비디오 분석 서버 URL
  static const String videoAnalyzerUrl = 'http://localhost:8002/api';

  // 공통 HTTP 헤더
  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        'User-Agent': 'FlutterApp/1.0',
      };
}

