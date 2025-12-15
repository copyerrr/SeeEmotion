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
  } catch (e) {
    print("Warning: .env file not found. Using default values.");
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
