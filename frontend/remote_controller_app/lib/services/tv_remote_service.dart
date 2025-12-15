// import 'package:cloud_firestore/cloud_firestore.dart';

// class TvRemoteService {
//   // 지금은 테스트용으로 고정 tvId
//   static const String tvId = 'demo_tv_01';

//   static DocumentReference<Map<String, dynamic>> get _doc =>
//       FirebaseFirestore.instance.collection('tvs').doc(tvId);

//   /// 자막 모드 변경 (예: DRAMA, NEWS, ENTERTAIN)
//   static Future<void> setCaptionMode(String mode) async {
//     await _doc.set({
//       'mode': mode,
//       'updatedAt': FieldValue.serverTimestamp(),
//     }, SetOptions(merge: true));
//   }

//   /// 볼륨 변경 예시 (delta: +1, -1 같은 값)
//   static Future<void> changeVolume(int delta) async {
//     await FirebaseFirestore.instance.runTransaction((tx) async {
//       final snap = await tx.get(_doc);
//       final current = (snap.data()?['volume'] ?? 10) as int;
//       final updated = (current + delta).clamp(0, 100);
//       tx.set(_doc, {
//         'volume': updated,
//         'updatedAt': FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true));
//     });
//   }
// }

//현정
import 'package:cloud_firestore/cloud_firestore.dart';

class TvRemoteService {
  // 지금은 테스트용으로 고정 tvId
  static const String tvId = 'demo_tv_01';

  /// 'tvs/{tvId}' 문서에 접근하는 DocumentReference
  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('tvs').doc(tvId);

  // --------------------------------------------------------------------------
  // 1. 상태 구독 (GET) - 실시간으로 TV 상태를 감시
  // --------------------------------------------------------------------------

  /// Firestore 문서의 스냅샷 변화를 스트림으로 제공합니다.
  /// (UI에서 TV의 현재 상태를 실시간으로 표시하는 데 사용)
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getTvStateStream() {
    return _doc.snapshots();
  }

  // --------------------------------------------------------------------------
  // 2. 명령어 전송 (SET) - TV 상태 변경
  // --------------------------------------------------------------------------

  /// 자막 모드 변경 (예: DRAMA, NEWS, ENTERTAIN)
  static Future<void> setCaptionMode(String mode) async {
    await _doc.set({
      'mode': mode,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 볼륨 변경 예시 (delta: +1, -1 같은 값)
  /// 트랜잭션을 사용하여 현재 볼륨 값을 읽고 업데이트하여 동시 쓰기 문제를 방지합니다.
  static Future<void> changeVolume(int delta) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      // 현재 볼륨을 읽어옵니다. 값이 없으면 기본값 10을 사용합니다.
      final current = (snap.data()?['volume'] ?? 10) as int;
      // 볼륨을 0-100 범위로 제한합니다.
      final updated = (current + delta).clamp(0, 100);
      tx.set(_doc, {
        'volume': updated,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// 볼륨을 특정 값으로 설정 (음소거/복원용)
  static Future<void> setVolume(int volume) async {
    await _doc.set({
      'volume': volume.clamp(0, 100),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 채널 변경 예시 (delta: +1, -1 같은 값, 혹은 특정 채널 번호)
  /// 볼륨 변경과 마찬가지로 트랜잭션을 사용하여 현재 채널 값을 읽고 업데이트합니다.
  static Future<void> changeChannel({int? delta, int? channel}) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      // 현재 채널을 읽어옵니다. 값이 없으면 기본값 1을 사용합니다.
      var currentChannel = (snap.data()?['channel'] ?? 1) as int;
      // 채널 번호를 1~3 범위로 정규화 (4→1, 5→2, 6→3...)
      currentChannel = currentChannel <= 0 ? 3 : ((currentChannel - 1) % 3) + 1;
      int updatedChannel;

      if (channel != null) {
        // 특정 채널 번호로 변경 - 1~3 범위로 정규화
        updatedChannel = channel <= 0 ? 3 : ((channel - 1) % 3) + 1;
      } else if (delta != null) {
        // delta 값으로 채널 변경 (+1 또는 -1)
        updatedChannel = currentChannel + delta;

        // 채널 번호 범위를 벗어날 경우 1~3 범위로 순환
        if (updatedChannel < 1) {
          updatedChannel = 3;
        } else if (updatedChannel > 3) {
          updatedChannel = 1;
        }
      } else {
        // delta나 channel 값이 모두 없으면 변경하지 않습니다.
        return;
      }

      tx.set(_doc, {
        'channel': updatedChannel,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// 퀵모드 패널 토글 (흔들기로 제어)
  /// true: 열기, false: 닫기
  static Future<void> toggleQuickMode() async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      final currentState = snap.data()?['quickModeOpen'] ?? false;
      final newState = !currentState;

      tx.set(_doc, {
        'quickModeOpen': newState,
        'quickModeUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// 터치 포인터 좌표 전송 (0.0 ~ 1.0 범위의 정규화된 좌표)
  /// [x] x 좌표 (0.0 = 왼쪽, 1.0 = 오른쪽)
  /// [y] y 좌표 (0.0 = 위쪽, 1.0 = 아래쪽)
  static Future<void> sendTouchPosition(double x, double y) async {
    await _doc.set({
      'touchX': x.clamp(0.0, 1.0),
      'touchY': y.clamp(0.0, 1.0),
      'touchUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 뒤로가기 버튼 명령 전송
  static Future<void> sendBackButton() async {
    await _doc.set({
      'backButtonPressed': true,
      'backButtonUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 클릭 이벤트 전송 (터치패드에서 드래그 후 떼고 다시 탭했을 때)
  /// [x] x 좌표 (0.0 ~ 1.0 범위의 정규화된 좌표)
  /// [y] y 좌표 (0.0 ~ 1.0 범위의 정규화된 좌표)
  static Future<void> sendClick(double x, double y) async {
    await _doc.set({
      'clickX': x.clamp(0.0, 1.0),
      'clickY': y.clamp(0.0, 1.0),
      'clickUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 설정 페이지 열기 명령 전송
  static Future<void> openSettingsPage() async {
    await _doc.set({
      'openSettingsPage': true,
      'openSettingsPageUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 자막 모드 토글 상태 전송
  /// [isOn] 자막 모드 켜짐(true) / 꺼짐(false)
  static Future<void> setSubtitleMode(bool isOn) async {
    await _doc.set({
      'subtitleModeOn': isOn,
      'subtitleModeUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
