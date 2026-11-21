/// Display name derived from a shop URL: `https://www.galaxus.ch/…` →
/// `Galaxus`. Returns an empty string for an unparsable URL.
String shopNameFromUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return '';
  final labels = host.split('.')..removeWhere((l) => l == 'www');
  // Second-level label: galaxus.ch → galaxus, shop.example.co.uk → example
  // is not handled specially; the user can edit the name.
  final name = labels.length >= 2 ? labels[labels.length - 2] : labels.first;
  return name.isEmpty ? '' : name[0].toUpperCase() + name.substring(1);
}

/// Validation message for an offer URL, or `null` when valid.
String? validateOfferUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'Enter a full URL';
  }
  if (uri.scheme != 'https') return 'Only https:// URLs are supported';
  return null;
}
