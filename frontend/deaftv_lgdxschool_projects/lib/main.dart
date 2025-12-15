// lib/main.dart
import 'package:flutter/material.dart';

// 각 화면 import
import 'features/auth/login_page.dart';
import 'features/auth/loading_page.dart';
import 'features/auth/loading_id_page.dart';
import 'features/mode/type_select_page.dart';
import 'features/mode/mode_select_page.dart';
import 'features/screens/home/home_page.dart';

// 파이어베이스 설정
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'tv_debug_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 🔹 Firebase 초기화까지 마친 후에 앱 실행
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일 로드 (백엔드와 동일한 형식: KEY=value)
  try {
    await dotenv.load(fileName: ".env");
    // 로드 확인 (deaftv는 공통 변수 FIREBASE_* 사용)
    final testKey =
        dotenv.env['FIREBASE_WEB_API_KEY'] ?? dotenv.env['FIREBASE_API_KEY'];
    if (testKey == null || testKey.isEmpty) {
      throw Exception(
          '.env 파일이 로드되었지만 FIREBASE_API_KEY 또는 FIREBASE_WEB_API_KEY를 찾을 수 없습니다.');
    }
    print("✅ .env 파일 로드 성공: FIREBASE_API_KEY=${testKey.substring(0, 10)}...");
  } catch (e) {
    print("❌ .env 파일 로드 실패: $e");
    print("💡 해결 방법:");
    print("   1. flutter clean 실행");
    print("   2. flutter run -d chrome 다시 실행");
    print("   3. .env 파일이 frontend/deaftv_lgdxschool_projects/.env 경로에 있는지 확인");
    rethrow; // 에러를 다시 던져서 앱이 시작되지 않도록
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

// 전역 네비게이션 키 (어떤 페이지에서든 홈으로 이동 가능)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 👉 앱 전체 설정 + 라우팅만 담당
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LG_TV MVP',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // 전역 네비게이션 키 설정
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/loading': (context) => const LoadingPage(),
        '/login-select': (context) => const LoginSelectPage(),
        '/type-select': (context) => const TypeSelectPage(),
        '/mode-select': (context) => const ModeSelectPage(),
        '/home': (context) => const HomePage(),
      },
    );
  }
}

// void main() {
//   runApp(const MyApp());
// }

// // 👉 앱 전체 설정 + 라우팅만 담당
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'LG_TV MVP',
//       debugShowCheckedModeBanner: false,
//       initialRoute: '/',
//       routes: {
//         '/': (context) => const LoginPage(),
//         '/loading': (context) => const LoadingPage(),
//         '/login-select': (context) => const LoginSelectPage(),
//         '/type-select': (context) => const TypeSelectPage(),
//         '/mode-select': (context) => const ModeSelectPage(),
//         '/home': (context) => const HomePage(),
//       },
//     );
//   }
// }
