import 'package:dio/dio.dart';

import 'app_config.dart';
import 'secure_storage.dart';

/// Thin, self-contained failure type every service call throws on non-2xx —
/// screens catch this and show `message` rather than a raw DioException.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Single Dio instance, shared app-wide, with one interceptor that attaches
/// `Authorization: Bearer <token>` to every request that has a stored
/// session — see context/conventions.md ("API client pattern"). No screen
/// or service ever reads SecureStorageService directly to build a header;
/// they call ApiClient.instance.dio and this interceptor does it once.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await SecureStorageService.instance.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  Dio get dio => _dio;

  /// Runs [call] and rethrows any failure as an [ApiException] carrying the
  /// backend's `detail` message (FastAPI's standard error shape) when
  /// present, so every screen gets a human-readable message without
  /// re-parsing DioException itself.
  Future<T> run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String message;
      if (data is Map && data['detail'] != null) {
        message = data['detail'].toString();
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        message = 'Could not reach RozNoor. Check your connection and try again.';
      } else {
        message = e.message ?? 'Something went wrong.';
      }
      throw ApiException(status, message);
    }
  }
}
