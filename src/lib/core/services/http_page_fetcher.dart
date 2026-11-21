import 'package:dio/dio.dart';

import 'log_service.dart';
import 'page_fetcher.dart';

/// Plain HTTPS GET. Identifies itself honestly (no browser impersonation —
/// REQUIREMENTS 4.2.3).
class HttpPageFetcher implements PageFetcher {
  HttpPageFetcher({required this.dio, required this.log});

  final Dio dio;
  final LogService log;

  static Dio createDio({required String appVersion}) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      // Every status is mapped explicitly below instead of via exceptions.
      validateStatus: (_) => true,
      headers: {
        'User-Agent': 'PriceAlarm/$appVersion (personal price watcher)',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'de-CH,de;q=0.9,en;q=0.8',
      },
    ),
  );

  @override
  Future<PageFetchResult> fetch(Uri url) async {
    try {
      final response = await dio.getUri<String>(url);
      final status = response.statusCode ?? 0;
      if (status == 403 || status == 429) {
        return PageBlocked('HTTP $status');
      }
      if (status < 200 || status >= 300) {
        return PageNetworkError('HTTP $status');
      }
      return PageFetched(response.data ?? '');
    } on DioException catch (e) {
      log.warn('HttpPageFetcher: $url failed', '${e.type}: ${e.message}');
      return PageNetworkError(_describe(e));
    }
  }

  static String _describe(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout => 'Connection timed out',
    DioExceptionType.receiveTimeout => 'Server did not respond in time',
    DioExceptionType.sendTimeout => 'Request timed out',
    DioExceptionType.connectionError => 'No connection',
    DioExceptionType.badCertificate => 'Invalid TLS certificate',
    DioExceptionType.cancel => 'Cancelled',
    // Dio adds enum values over time; everything else is a generic failure.
    _ => e.message ?? 'Network error',
  };
}
