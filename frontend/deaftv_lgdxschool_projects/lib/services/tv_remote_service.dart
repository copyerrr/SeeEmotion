import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// TV 조종 서비스 클래스
/// Firebase Realtime Database를 사용하여 TV 명령 전송 및 상태 동기화
class TvRemoteService {
  static final TvRemoteService _instance = TvRemoteService._internal();
  factory TvRemoteService() => _instance;
  TvRemoteService._internal();

  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  FirebaseMessaging? _messaging;
  FirebaseRemoteConfig? _remoteConfig;

  // 리모컨 앱과 동일한 tvId 사용 (Firestore)
  static const String tvId = 'demo_tv_01';
  static DocumentReference<Map<String, dynamic>> get _firestoreDoc =>
      FirebaseFirestore.instance.collection('tvs').doc(tvId);

  // 인스턴스용 firestoreDoc (기존 코드 호환성)
  DocumentReference<Map<String, dynamic>> get firestoreDoc => _firestoreDoc;

  /// Firebase 초기화
  Future<void> initialize() async {
    try {
      // Firebase Realtime Database 연결 확인 (선택적 - 실패해도 계속 진행)
      // 리모컨 앱은 Firestore를 사용하므로 Realtime Database는 선택적입니다.
      try {
        // databaseURL이 설정되어 있는지 확인
        final dbUrl = FirebaseDatabase.instance.databaseURL;
        if (dbUrl != null && dbUrl.isNotEmpty) {
          final testRef = _databaseRef.child('test');
          await testRef.set({'test': DateTime.now().millisecondsSinceEpoch});
          await testRef.remove();
        }
      } catch (e) {
        // Realtime Database 실패해도 계속 진행 (Firestore 사용)
      }

      // Firebase Messaging 초기화 (웹 환경에서는 선택적)
      if (!kIsWeb) {
        try {
          _messaging = FirebaseMessaging.instance;

          // 알림 권한 요청 (iOS용)
          await _messaging?.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );

          // FCM 토큰 가져오기
          await _messaging?.getToken();

          // 토큰 갱신 리스너
          _messaging?.onTokenRefresh.listen((newToken) {
            _saveTokenToDatabase(newToken);
          });
        } catch (e) {
          // Firebase Messaging 초기화 실패 (선택적 기능)
        }
      }

      // Firestore 연결 확인 (리모컨 앱과 연결)
      try {
        final testDoc = _firestoreDoc;
        await testDoc.set({
          'test': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      } catch (e) {
        // Firestore 연결 실패 (에러 무시)
      }

      // Remote Config 초기화
      try {
        _remoteConfig = FirebaseRemoteConfig.instance;
        await _remoteConfig?.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ));
        await _remoteConfig?.fetchAndActivate();
      } catch (e) {
        // Remote Config 초기화 실패 (선택적 기능)
      }
    } catch (e) {
      // TV Remote Service 초기화 실패 (에러 무시)
    }
  }

  /// FCM 토큰을 데이터베이스에 저장
  Future<void> _saveTokenToDatabase(String token) async {
    try {
      await _databaseRef.child('devices').child(token).set({
        'token': token,
        'lastUpdated': ServerValue.timestamp,
        'platform': 'web',
      });
    } catch (e) {
      // 토큰 저장 실패 (에러 무시)
    }
  }

  /// TV에 명령 전송 (Realtime Database 사용 - 선택적)
  /// [command] 명령 타입 (예: 'power', 'volumeUp', 'volumeDown', 'channelUp', 'channelDown', 'mute', 'input')
  /// [value] 추가 값 (예: 채널 번호, 볼륨 레벨 등)
  /// 주의: 리모컨 앱과의 연결은 Firestore를 사용합니다.
  Future<bool> sendCommand(String command,
      {Map<String, dynamic>? value}) async {
    try {
      final commandData = {
        'command': command,
        'timestamp': ServerValue.timestamp,
        'value': value ?? {},
        'sender': kIsWeb ? 'web' : 'mobile',
        'sentAt': DateTime.now().toIso8601String(),
      };

      // TV 명령 노드에 전송
      final commandRef = _databaseRef.child('tv/commands').push();
      await commandRef.set(commandData);

      return true;
    } catch (e) {
      // Realtime Database 실패해도 false 반환 (Firestore는 별도로 작동)
      return false;
    }
  }

  /// TV 전원 켜기/끄기
  Future<bool> togglePower() async {
    return await sendCommand('power');
  }

  /// 볼륨 증가
  Future<bool> volumeUp() async {
    return await sendCommand('volumeUp');
  }

  /// 볼륨 감소
  Future<bool> volumeDown() async {
    return await sendCommand('volumeDown');
  }

  /// 음소거
  Future<bool> toggleMute() async {
    return await sendCommand('mute');
  }

  /// 채널 증가
  Future<bool> channelUp() async {
    return await sendCommand('channelUp');
  }

  /// 채널 감소
  Future<bool> channelDown() async {
    return await sendCommand('channelDown');
  }

  /// 특정 채널로 이동
  Future<bool> changeChannel(int channelNumber) async {
    return await sendCommand('changeChannel',
        value: {'channel': channelNumber});
  }

  /// 입력 소스 변경
  /// [input] 입력 소스 (예: 'HDMI1', 'HDMI2', 'USB', 'TV')
  Future<bool> changeInput(String input) async {
    return await sendCommand('input', value: {'source': input});
  }

  /// TV 상태 구독 (Firestore - 리모컨 앱과 연결)
  /// 리모컨 앱에서 보낸 TV 상태를 실시간으로 구독
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getTvStateStream() {
    return _firestoreDoc.snapshots();
  }

  /// TV 상태 구독 (Realtime Database - 기존 방식)
  /// [onStatusChanged] 상태 변경 콜백
  Stream<Map<String, dynamic>?> subscribeToTvStatus(
      Function(Map<String, dynamic>) onStatusChanged) {
    return _databaseRef.child('tv/status').onValue.map((event) {
      if (event.snapshot.value != null) {
        final status = Map<String, dynamic>.from(event.snapshot.value as Map);
        onStatusChanged(status);
        return status;
      }
      return null;
    });
  }

  /// TV 상태 가져오기 (Firestore)
  Future<DocumentSnapshot<Map<String, dynamic>>> getTvState() async {
    return await _firestoreDoc.get();
  }

  /// TV 상태 가져오기 (Realtime Database - 기존 방식)
  Future<Map<String, dynamic>?> getTvStatus() async {
    try {
      final snapshot = await _databaseRef.child('tv/status').get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Remote Config 값 가져오기
  String getRemoteConfigValue(String key, {String defaultValue = ''}) {
    return _remoteConfig?.getString(key) ?? defaultValue;
  }

  /// Remote Config 새로고침
  Future<void> refreshRemoteConfig() async {
    try {
      await _remoteConfig?.fetchAndActivate();
    } catch (e) {
      // Remote Config 새로고침 실패 (에러 무시)
    }
  }

  /// 클릭 좌표 초기화 (클릭 처리 후 호출하여 중복 처리 방지)
  static Future<void> clearClickCoordinates() async {
    try {
      await _firestoreDoc.set({
        'clickX': null,
        'clickY': null,
        'clickUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // 클릭 좌표 초기화 실패 (에러 무시)
    }
  }

  /// FCM 메시지 수신 리스너 설정
  void setupMessageHandler() {
    // 웹 환경에서는 Messaging을 사용하지 않음
    if (kIsWeb) {
      return;
    }

    try {
      // 포그라운드 메시지 핸들러
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // 여기에 알림 표시 로직 추가 가능
      });

      // 백그라운드 메시지 핸들러 (앱이 종료된 상태)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // 여기에 네비게이션 로직 추가 가능
      });
    } catch (e) {
      // 메시지 핸들러 설정 실패 (에러 무시)
    }
  }
}
