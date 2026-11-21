import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'log_service.dart';
import 'page_fetcher.dart';

/// Loads a page in an invisible WebView and returns the rendered DOM, for
/// shops that reject plain HTTP clients (REQUIREMENTS 4.2).
///
/// Not unit-testable (needs a platform WebView); verified manually — see
/// REQUIREMENTS §9, risks R1/R3.
class WebViewPageFetcher implements PageFetcher {
  WebViewPageFetcher({required this.log});

  final LogService log;

  static const kPageLoadTimeout = Duration(seconds: 45);

  // Time for client-side scripts to insert structured data after the load
  // event. A guess, not a measured value — adjust from real observations.
  static const kSettleDelay = Duration(seconds: 2);

  /// `flutter_inappwebview` 6.1.x ships headless implementations for these
  /// platforms only; there is no Linux implementation in the stable line.
  static bool get isSupportedPlatform =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  Future<PageFetchResult> fetch(Uri url) async {
    if (!isSupportedPlatform) {
      return const PageUnsupported('WebView not available on this platform');
    }
    final loaded = Completer<PageFetchResult?>();
    HeadlessInAppWebView? webView;
    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(url)),
      onReceivedHttpError: (controller, request, response) {
        if (request.isForMainFrame != true || loaded.isCompleted) return;
        final status = response.statusCode ?? 0;
        loaded.complete(
          status == 403 || status == 429
              ? PageBlocked('HTTP $status (WebView)')
              : PageNetworkError('HTTP $status (WebView)'),
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true || loaded.isCompleted) return;
        loaded.complete(PageNetworkError(error.description));
      },
      onLoadStop: (controller, _) {
        if (!loaded.isCompleted) loaded.complete(null);
      },
    );
    try {
      await webView.run();
      final failure = await loaded.future.timeout(kPageLoadTimeout);
      if (failure != null) return failure;
      await Future<void>.delayed(kSettleDelay);
      final html = await webView.webViewController?.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (html is! String || html.isEmpty) {
        return const PageNetworkError('WebView returned no content');
      }
      return PageFetched(html);
    } on TimeoutException {
      return const PageNetworkError('Page load timed out (WebView)');
    } catch (e, st) {
      log.error('WebViewPageFetcher: $url failed', e, st);
      return PageNetworkError('WebView error: $e');
    } finally {
      await webView.dispose();
    }
  }
}
