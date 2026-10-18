import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/secure_storage.dart';
import '../errors/app_exception.dart';
import 'endpoints.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._internal();

  final Dio dio;
  final SecureStorageService storage;
  bool _isRefreshing = false;
  static bool _hasSyncedRemoteConfig = false;

  factory ApiClient({Dio? dioClient, SecureStorageService? storageService}) {
    if (dioClient != null || storageService != null) {
      return ApiClient._internal(dioClient: dioClient, storageService: storageService);
    }
    return _instance ??= ApiClient._internal();
  }

  ApiClient._internal({Dio? dioClient, SecureStorageService? storageService})
      : dio = dioClient ?? Dio(),
        storage = storageService ?? SecureStorageService() {
    dio.options.baseUrl = Endpoints.defaultBaseUrl;
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Attach Interceptors
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Automatic background dynamic sync on first run
          if (!_hasSyncedRemoteConfig) {
            _hasSyncedRemoteConfig = true;
            await _syncRemoteConfig(options);
          }

          // 2. Check if custom base url stored
          final customBaseUrl = await storage.getBaseUrl();
          if (customBaseUrl != null && customBaseUrl.isNotEmpty) {
            // Clean up obsolete temporary dead tunnel URLs
            if (customBaseUrl.contains('dancing-behavioral-residential-test.trycloudflare.com')) {
              await storage.deleteBaseUrl();
              options.baseUrl = Endpoints.defaultBaseUrl;
            } else {
              options.baseUrl = customBaseUrl;
            }
          }

          // 3. Attach Access Token if available
          final token = await storage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // If error is 401 and not already refreshing and not from login/refresh endpoint
          final isAuthEndpoint = error.requestOptions.path.contains('/v1/auth/login') ||
              error.requestOptions.path.contains('/v1/auth/refresh');

          if (error.response?.statusCode == 401 && !isAuthEndpoint && !_isRefreshing) {
            _isRefreshing = true;
            try {
              final refreshToken = await storage.getRefreshToken();
              if (refreshToken != null) {
                // Attempt token refresh
                final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
                final response = await refreshDio.post(
                  Endpoints.refresh,
                  data: {'refreshToken': refreshToken},
                );

                if (response.statusCode == 200 && response.data != null) {
                  final newAccessToken = response.data['accessToken'] as String;
                  final newRefreshToken = response.data['refreshToken'] as String;

                  await storage.saveTokens(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken,
                  );

                  // Update header and retry failed request
                  error.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  _isRefreshing = false;

                  final retryResponse = await dio.fetch(error.requestOptions);
                  return handler.resolve(retryResponse);
                }
              }
            } catch (refreshErr) {
              // Refresh failed or revoked: clear tokens
              await storage.clearAll();
            } finally {
              _isRefreshing = false;
            }
          }

          // Handle Cloudflare transient tunnel 530/502/503 reconnection blips
          final statusCode = error.response?.statusCode;
          final retryCount = (error.requestOptions.extra['retry_count'] as int?) ?? 0;
          if ((statusCode == 530 || statusCode == 502 || statusCode == 503) && retryCount < 2) {
            error.requestOptions.extra['retry_count'] = retryCount + 1;
            await Future.delayed(const Duration(milliseconds: 1200));
            try {
              final retryRes = await dio.fetch(error.requestOptions);
              return handler.resolve(retryRes);
            } catch (_) {}
          }

          // Format to AppException
          final responseData = error.response?.data;
          String code = 'NETWORK_ERROR';
          String message = error.message ?? 'An unexpected network error occurred';
          dynamic details;

          if (statusCode == 530 || statusCode == 502 || statusCode == 503) {
            code = 'TUNNEL_RECONNECTING';
            message = 'Connection was momentarily interrupted while joining. Please tap "Try Again".';
          } else if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout) {
            code = 'CONNECTION_TIMEOUT';
            message = 'Connection timed out. Server response took too long. Please try again.';
          } else if (error.type == DioExceptionType.connectionError) {
            code = 'CONNECTION_FAILED';
            message = 'Could not connect to server. Please check your internet connection.';
          }

          if (responseData is Map<String, dynamic>) {
            code = responseData['code']?.toString() ?? code;
            message = responseData['message']?.toString() ?? message;
            details = responseData['details'];
          }

          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              error: AppException(
                code: code,
                message: message,
                statusCode: error.response?.statusCode,
                details: details,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Automatically fetches the latest active API server URL from cloud remote config
  Future<void> _syncRemoteConfig(RequestOptions options) async {
    try {
      final syncDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final response = await syncDio.get(Endpoints.remoteConfigUrl);
      dynamic configData = response.data;
      if (configData is String) {
        configData = jsonDecode(configData);
      }
      if (configData is Map && configData['apiUrl'] is String) {
        final remoteUrl = configData['apiUrl'] as String;
        if (remoteUrl.startsWith('http')) {
          dio.options.baseUrl = remoteUrl;
          options.baseUrl = remoteUrl;
          await storage.saveBaseUrl(remoteUrl);
        }
      }
    } catch (_) {
      // Offline, timeout, or repo unavailable: smoothly continue with baked-in defaultBaseUrl
    }
  }

  /// Reset sync flag (for testing or manual force-refresh)
  static void resetSyncFlag() {
    _hasSyncedRemoteConfig = false;
  }

  /// Mark synced (for testing or manual override)
  static void markRemoteConfigSynced() {
    _hasSyncedRemoteConfig = true;
  }

  /// Reset singleton instance (for testing)
  static void resetForTesting() {
    _instance = null;
    _hasSyncedRemoteConfig = false;
  }
}
