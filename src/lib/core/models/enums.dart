/// How an offer's page is fetched. All enums here are persisted by name
/// (`textEnum`), so reordering values never corrupts stored data.
enum FetchMode {
  /// Plain HTTP first, WebView fallback when blocked or no price was found.
  auto,
  http,
  webview,
}

/// The transport actually used for one check.
enum FetchMethod { http, webview }

/// Outcome of one check. `blocked` and `noPrice` are deliberately distinct:
/// a refused request must never look like "page has no price".
enum CheckStatus {
  ok,
  blocked,
  noPrice,
  networkError,
  unsupported,
}
