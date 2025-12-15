//

//현정
import 'package:flutter/material.dart';
import 'features/turn_on/turnon_page.dart';

// 파이어베이스 설정
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 흔들기 감지 서비스
import 'services/shake_detector_service.dart';

// 전역 흔들기 감지 서비스 인스턴스
final ShakeDetectorService shakeDetectorService = ShakeDetectorService();

Future<void> main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일 로드 (백엔드와 동일한 형식: KEY=value)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Warning: .env file not found. Using default values.");
  }

  // Firebase 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 흔들기 감지 시작
  shakeDetectorService.startDetecting();

  // 앱 실행
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE5574E)),
        useMaterial3: true,
      ),
      home: const TurnOnPage(),
    );
  }
}
