import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

class ApiConstants {
  ApiConstants._();

  /// Absolute URL used by native builds, which have no page origin to inherit.
  //
  // Pointed at the LAN dev server (beellz@192.168.1.222), which runs the
  // dockerized backend on port 8080 behind nginx.
  static const String _nativeBaseUrl = 'http://192.168.1.222:8080/api/v1'; // dev server
  //static const String _nativeBaseUrl = 'http://3.108.194.79:8080/api/v1'; // production

  /// Build-time override, for pointing any target at a different backend:
  ///   flutter build web --dart-define=API_BASE_URL=https://example.com/api/v1
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// On web the app is served by CloudFront, which routes `/api/*` to the
  /// backend origin. Deriving the base URL from the page origin keeps API
  /// calls same-origin, which matters for two reasons:
  ///
  ///  - The page is served over HTTPS, and a browser blocks an HTTPS page from
  ///    calling a plain `http://` endpoint (mixed content). The hardcoded
  ///    `_nativeBaseUrl` above is exactly such an endpoint, so using it on web
  ///    would fail every request.
  ///  - Same-origin requests are not subject to CORS at all.
  ///
  /// Native builds are unaffected and keep using the absolute URL.
  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) return _overrideBaseUrl;
    if (kIsWeb) return '${Uri.base.origin}/api/v1';
    return _nativeBaseUrl;
  }

  static const connectTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 600);

  // Storage keys
  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'refresh_token';
  static const userIdKey = 'user_id';
  static const userEmailKey = 'user_email';
  static const userRoleKey = 'user_role';
}

// ─── API Exception ────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  @override
  String toString() => message;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode != null && statusCode! >= 500;
  bool get isNetworkError => statusCode == null;
}

// ─── Token Storage (web-safe) ─────────────────────────────────────────────────

class TokenStorage {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  static Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      return _secure.read(key: key);
    }
  }

  static Future<void> _deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secure.deleteAll();
    }
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _write(ApiConstants.accessTokenKey, accessToken),
      _write(ApiConstants.refreshTokenKey, refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() =>
      _read(ApiConstants.accessTokenKey);

  static Future<String?> getRefreshToken() =>
      _read(ApiConstants.refreshTokenKey);

  static Future<void> saveUserInfo({
    required String userId,
    required String email,
    required String role,
  }) async {
    await Future.wait([
      _write(ApiConstants.userIdKey, userId),
      _write(ApiConstants.userEmailKey, email),
      _write(ApiConstants.userRoleKey, role),
    ]);
  }

  static Future<Map<String, String?>> getUserInfo() async {
    final results = await Future.wait([
      _read(ApiConstants.userIdKey),
      _read(ApiConstants.userEmailKey),
      _read(ApiConstants.userRoleKey),
    ]);
    return {
      'userId': results[0],
      'email': results[1],
      'role': results[2],
    };
  }

  static Future<void> clearAll() => _deleteAll();

  static Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

// ─── Auth Interceptor ─────────────────────────────────────────────────────────

class AuthInterceptor extends Interceptor {
  final Dio _dio;
  // Separate, interceptor-free Dio for the refresh call itself — reusing
  // _dio here would re-enter this same interceptor if the refresh token is
  // also invalid (its own 401 would trigger onError again), and that
  // request would then hang forever since it's dropped instead of resolved.
  final Dio _refreshDio;
  bool _isRefreshing = false;
  Completer<void>? _refreshCompleter;

  AuthInterceptor(this._dio)
      : _refreshDio = Dio(BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: ApiConstants.connectTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ));

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/forgot-password') ||
        path.contains('/auth/reset-password')) {
      return handler.next(options);
    }

    final token = await TokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // A refresh is already in flight for another request — wait for it
    // instead of dropping this request, then retry with the new token.
    if (_isRefreshing) {
      try {
        await _refreshCompleter?.future;
        final token = await TokenStorage.getAccessToken();
        if (token == null) return handler.next(err);
        final retryResponse = await _dio.fetch(
          err.requestOptions..headers['Authorization'] = 'Bearer $token',
        );
        return handler.resolve(retryResponse);
      } catch (_) {
        return handler.next(err);
      }
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<void>();

    try {
      final refreshToken = await TokenStorage.getRefreshToken();
      if (refreshToken == null) {
        await TokenStorage.clearAll();
        return handler.next(err);
      }

      final response = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        await TokenStorage.saveTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
        );

        final retryResponse = await _dio.fetch(err.requestOptions
          ..headers['Authorization'] = 'Bearer ${data['access_token']}');
        return handler.resolve(retryResponse);
      }

      await TokenStorage.clearAll();
      return handler.next(err);
    } catch (_) {
      await TokenStorage.clearAll();
      return handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
  }
}

// ─── Dio Client Factory ───────────────────────────────────────────────────────

class DioClient {
  static Dio? _instance;

  static Dio get instance {
    _instance ??= _createDio();
    return _instance!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // Only 2xx counts as success — 401 must reach onError below so the
        // AuthInterceptor can silently refresh the token and retry.
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    dio.interceptors.add(AuthInterceptor(dio));

    assert(() {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: false,
          requestBody: false,
          // Document responses can carry hundreds of KB of raw OCR text.
          // Logging that on every request (especially during the 3s status
          // polling while a large file processes) blocks the UI thread and
          // makes the app *look* stuck loading — the bigger the file, the
          // worse it gets. Keep response logging off; use a debugger /
          // network inspector instead if you need to see a payload.
          responseBody: false,
          responseHeader: false,
          error: true,
          compact: true,
        ),
      );
      return true;
    }());

    return dio;
  }

  static Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParams,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await instance.get(path, queryParameters: queryParams);
      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static Future<T> post<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await instance.post(path, data: data);
      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static Future<T> put<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await instance.put(path, data: data);
      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static Future<T> patch<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await instance.patch(path, data: data);
      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static Future<T> delete<T>(
    String path, {
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await instance.delete(path);
      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static Future<Response> uploadFile(
    String path,
    FormData formData, {
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      return await instance.post(
        path,
        data: formData,
        onSendProgress: onSendProgress,
        options: Options(contentType: 'multipart/form-data'),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  static T _handleResponse<T>(
    Response response,
    T Function(dynamic)? fromJson,
  ) {
    final body = response.data;
    final isSuccess = response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300;

    if (isSuccess) {
      if (fromJson != null && body is Map && body['data'] != null) {
        return fromJson(body['data']);
      }
      return body as T;
    }

    // body may be a String (HTML error page) or Map — guard both
    final message = body is Map
        ? ((body['message'] ?? body['error'] ?? 'Request failed').toString())
        : 'Request failed (status ${response.statusCode})';
    final code = body is Map ? body['code']?.toString() : null;

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      code: code,
    );
  }

  static ApiException _handleDioError(DioException e) {
    if (e.response != null) {
      final body = e.response!.data;
      return ApiException(
        message: body is Map
            ? (body['message'] ?? 'Request failed')
            : 'Request failed',
        statusCode: e.response!.statusCode,
        code: body is Map ? body['code']?.toString() : null,
      );
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          message: 'Connection timed out. Please try again.',
          statusCode: null,
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          message: 'Unable to reach the server. Check your internet connection.',
          statusCode: null,
        );
      default:
        return ApiException(
          message: e.message ?? 'Something went wrong.',
          statusCode: null,
        );
    }
  }
}

// ─── Riverpod Provider ────────────────────────────────────────────────────────

final dioClientProvider = Provider<Dio>((ref) => DioClient.instance);