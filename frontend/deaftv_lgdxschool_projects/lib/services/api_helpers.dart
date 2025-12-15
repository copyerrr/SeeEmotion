import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// API 호출 헬퍼 함수 (백엔드에서 모든 로직 처리)
class ApiHelpers {
  /// GET 요청
  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint').replace(
      queryParameters: query,
    );
    final response = await http.get(uri, headers: ApiConfig.headers);
    
    if (response.statusCode != 200) {
      throw Exception('GET 요청 실패 (${response.statusCode}): ${response.body}');
    }
    
    return jsonDecode(response.body);
  }

  /// POST 요청
  static Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: ApiConfig.headers,
      body: jsonEncode(body),
    );
    
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('POST 요청 실패 (${response.statusCode}): ${response.body}');
    }
    
    return jsonDecode(response.body);
  }

  /// PUT 요청
  static Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: ApiConfig.headers,
      body: jsonEncode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('PUT 요청 실패 (${response.statusCode}): ${response.body}');
    }
    
    return jsonDecode(response.body);
  }

  /// DELETE 요청
  static Future<void> delete(String endpoint) async {
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: ApiConfig.headers,
    );
    
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('DELETE 요청 실패 (${response.statusCode}): ${response.body}');
    }
  }

  /// 비디오 분석 서버 POST 요청
  static Future<dynamic> postVideoAnalyzer(
    String endpoint,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.videoAnalyzerUrl}$endpoint'),
          headers: ApiConfig.headers,
          body: jsonEncode(body),
        )
        .timeout(timeout ?? const Duration(seconds: 60));
    
    if (response.statusCode != 200) {
      throw Exception('비디오 분석 요청 실패 (${response.statusCode}): ${response.body}');
    }
    
    return jsonDecode(response.body);
  }
}

