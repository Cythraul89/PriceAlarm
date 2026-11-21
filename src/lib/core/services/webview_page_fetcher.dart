import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'log_service.dart';
import 'page_fetcher.dart';
import 'price_extractor.dart';

/// Loads a page in an invisible WebView and returns the rendered DOM, for
/// shops that reject plain HTTP clients (REQUIREMENTS 4.2).
///
/// Not unit-testable (needs a platform WebView); verified manually — see
/// REQUIREMENTS §9, risks R1/R3.
class WebViewPageFetcher implements PageFetcher {
  WebViewPageFetcher({required this.log});

  final LogService log;

  static const kPageLoadTimeout = Duration(seconds: 45);

  // After the load event, the DOM is read every [kPollInterval] until it
  // carries a price or [kSettleTimeout] passes — client-side scripts or a
  // bot check may still replace the page. Guesses, not measured values.
  static const kPollInterval = Duration(seconds: 1);
  static const kSettleTimeout = Duration(seconds: 20);

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
      final controller = webView.webViewController;
      if (controller == null) {
        return const PageNetworkError('WebView returned no content');
      }
      final deadline = DateTime.now().add(kSettleTimeout);
      String? html;
      while (true) {
        final dom = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (dom is String && dom.isNotEmpty) html = dom;
        if (html != null && PriceExtractor.extract(html) != null) break;
        if (DateTime.now().isAfter(deadline)) {
          // Diagnostics for REQUIREMENTS R3: what did the page show instead?
          log.info(
            'WebView: no price after ${kSettleTimeout.inSeconds} s on $url — '
            'title "${await controller.getTitle()}", '
            '${html?.length ?? 0} chars, '
            'challenge: ${html != null && PriceExtractor.looksLikeChallenge(html)}',
          );
          break;
        }
        await Future<void>.delayed(kPollInterval);
      }
      if (html == null) {
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
