/// Failure contract shared by both fetch paths (ARCHITECTURE 5.1).
///
/// "Could not load" ([PageBlocked], [PageNetworkError], [PageUnsupported])
/// is kept strictly apart from "loaded" ([PageFetched]) so an outage can
/// never be read as "page has no price".
sealed class PageFetchResult {
  const PageFetchResult();
}

final class PageFetched extends PageFetchResult {
  const PageFetched(this.html);
  final String html;
}

/// HTTP 403/429 or a recognised bot-challenge page.
final class PageBlocked extends PageFetchResult {
  const PageBlocked(this.reason);
  final String reason;
}

/// DNS, TLS, timeout, other non-2xx responses.
final class PageNetworkError extends PageFetchResult {
  const PageNetworkError(this.reason);
  final String reason;
}

/// The transport is not available on this platform / isolate.
final class PageUnsupported extends PageFetchResult {
  const PageUnsupported(this.reason);
  final String reason;
}

abstract interface class PageFetcher {
  Future<PageFetchResult> fetch(Uri url);
}
