import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/services/http_page_fetcher.dart';
import 'package:price_alarm/core/services/log_service.dart';
import 'package:price_alarm/core/services/page_fetcher.dart';

void main() {
  late HttpServer server;
  late HttpPageFetcher fetcher;
  late Directory tmp;
  String? lastUserAgent;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('price_alarm_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      lastUserAgent = request.headers.value('user-agent');
      final response = request.response;
      switch (request.uri.path) {
        case '/ok':
          response.headers.contentType = ContentType.html;
          response.write('<html>product</html>');
        case '/forbidden':
          response.statusCode = 403;
        case '/ratelimit':
          response.statusCode = 429;
        case '/error':
          response.statusCode = 500;
        case '/missing':
          response.statusCode = 404;
      }
      await response.close();
    });
    fetcher = HttpPageFetcher(
      dio: HttpPageFetcher.createDio(appVersion: '0.1.0+1'),
      log: LogService(File('${tmp.path}/test.log')),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  group('HttpPageFetcher.fetch', () {
    test('returns the body for 200 and identifies itself honestly', () async {
      final result = await fetcher.fetch(url('/ok'));
      expect(result, isA<PageFetched>());
      expect((result as PageFetched).html, '<html>product</html>');
      expect(lastUserAgent, 'PriceAlarm/0.1.0+1 (personal price watcher)');
    });

    test('maps 403 and 429 to blocked', () async {
      expect(await fetcher.fetch(url('/forbidden')), isA<PageBlocked>());
      expect(await fetcher.fetch(url('/ratelimit')), isA<PageBlocked>());
    });

    test('maps other non-2xx statuses to a network error', () async {
      final error = await fetcher.fetch(url('/error'));
      expect(error, isA<PageNetworkError>());
      expect((error as PageNetworkError).reason, 'HTTP 500');
      expect(await fetcher.fetch(url('/missing')), isA<PageNetworkError>());
    });

    test('maps a refused connection to a network error', () async {
      final port = server.port;
      await server.close(force: true);
      final result = await fetcher.fetch(
        Uri.parse('http://127.0.0.1:$port/ok'),
      );
      expect(result, isA<PageNetworkError>());
    });
  });
}
